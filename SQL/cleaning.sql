-- =====================================================================================
-- POSTGRESQL DATA QUALITY AUDIT SCRIPT
-- Schema: E-commerce (customers, orders, order_items, order_payments, order_reviews,
--         products, sellers, product_category_name_translation)
-- Purpose: Read-only SELECT-based audit covering structural issues (Phase 2) and
--          value-level issues (Phase 3). No data is modified.
-- Note: Every query is independent and can be executed standalone.
-- =====================================================================================


-- #####################################################################################
-- TABLE: customers
-- #####################################################################################

-- -------------------------------------------------------------------------------------
-- [customers] Rule 5: NULL check per column
-- customer_id, customer_unique_id, customer_zip_code_prefix, customer_city,
-- customer_state are all NOT NULL by schema -> NULLs here indicate constraint
-- violation / data load error, not legitimate missingness. Included as a safety net.
-- -------------------------------------------------------------------------------------
SELECT
    COUNT(*) FILTER (WHERE customer_id IS NULL)              AS null_customer_id,
    COUNT(*) FILTER (WHERE customer_unique_id IS NULL)       AS null_customer_unique_id,
    COUNT(*) FILTER (WHERE customer_zip_code_prefix IS NULL) AS null_zip_code_prefix,
    COUNT(*) FILTER (WHERE customer_city IS NULL)            AS null_customer_city,
    COUNT(*) FILTER (WHERE customer_state IS NULL)           AS null_customer_state
FROM customers;

-- -------------------------------------------------------------------------------------
-- [customers] Rule 6: Disguised missing values in text columns
-- Checks customer_city and customer_state for placeholder strings pretending to be data.
-- -------------------------------------------------------------------------------------
SELECT
    'customer_city' AS column_name,
    customer_city   AS suspect_value,
    COUNT(*)        AS occurrence_count
FROM customers
WHERE TRIM(customer_city) = ''
   OR LOWER(TRIM(customer_city)) IN ('n/a','na','null','none','-','unknown','999','0000-00-00')
GROUP BY customer_city

UNION ALL

SELECT
    'customer_state' AS column_name,
    customer_state    AS suspect_value,
    COUNT(*)          AS occurrence_count
FROM customers
WHERE TRIM(customer_state) = ''
   OR LOWER(TRIM(customer_state)) IN ('n/a','na','null','none','-','unknown','99')
GROUP BY customer_state
ORDER BY column_name, occurrence_count DESC;

-- -------------------------------------------------------------------------------------
-- [customers] Rule 8: Exact full-row duplicates
-- -------------------------------------------------------------------------------------
SELECT customer_id, customer_unique_id, customer_zip_code_prefix, customer_city,
       customer_state, COUNT(*) AS duplicate_count
FROM customers
GROUP BY customer_id, customer_unique_id, customer_zip_code_prefix, customer_city, customer_state
HAVING COUNT(*) > 1;

-- -------------------------------------------------------------------------------------
-- [customers] Rule 8/9: Business-key duplicates
-- customer_unique_id represents the real-world person; multiple customer_id rows can
-- legitimately map to the same customer_unique_id (repeat customer), but flag counts
-- for review, and separately confirm customer_id (PK) uniqueness.
-- -------------------------------------------------------------------------------------
SELECT customer_unique_id, COUNT(*) AS linked_customer_id_count
FROM customers
GROUP BY customer_unique_id
HAVING COUNT(*) > 1
ORDER BY linked_customer_id_count DESC
LIMIT 50;

-- -------------------------------------------------------------------------------------
-- [customers] Rule 9: Primary key integrity check (customer_id)
-- Since customer_id is PK, Postgres enforces uniqueness; this validates it explicitly
-- (useful if run against a view/copy without the constraint).
-- -------------------------------------------------------------------------------------
SELECT customer_id, COUNT(*) AS occurrence_count
FROM customers
GROUP BY customer_id
HAVING COUNT(*) > 1;

-- -------------------------------------------------------------------------------------
-- [customers] Rule 10: Range/format check on customer_zip_code_prefix
-- Brazilian zip prefixes should be positive and within a plausible 5-digit range (0-99999).
-- -------------------------------------------------------------------------------------
SELECT
    MIN(customer_zip_code_prefix) AS min_zip,
    MAX(customer_zip_code_prefix) AS max_zip,
    AVG(customer_zip_code_prefix)::NUMERIC(10,2) AS avg_zip,
    STDDEV(customer_zip_code_prefix)::NUMERIC(10,2) AS stddev_zip,
    COUNT(*) FILTER (WHERE customer_zip_code_prefix < 0 OR customer_zip_code_prefix > 99999) AS out_of_range_count
FROM customers;

SELECT customer_id, customer_zip_code_prefix
FROM customers
WHERE customer_zip_code_prefix < 0 OR customer_zip_code_prefix > 99999
LIMIT 20;

-- -------------------------------------------------------------------------------------
-- [customers] Rule 11: Categorical consistency on customer_state
-- Brazilian states must be a 2-letter uppercase code from a known set of 27 values.
-- Lists distinct values actually present to spot casing/typo issues.
-- -------------------------------------------------------------------------------------
SELECT customer_state, COUNT(*) AS row_count
FROM customers
GROUP BY customer_state
ORDER BY customer_state;

-- Flag values that are not valid uppercase Brazilian state codes
SELECT customer_id, customer_state
FROM customers
WHERE customer_state !~ '^[A-Z]{2}$'
   OR customer_state NOT IN (
        'AC','AL','AP','AM','BA','CE','DF','ES','GO','MA','MT','MS','MG','PA','PB',
        'PR','PE','PI','RJ','RN','RS','RO','RR','SC','SP','SE','TO'
   )
LIMIT 50;

-- -------------------------------------------------------------------------------------
-- [customers] Rule 12: Text formatting consistency (customer_city)
-- Leading/trailing whitespace and inconsistent capitalization.
-- -------------------------------------------------------------------------------------
SELECT customer_id, customer_city
FROM customers
WHERE customer_city <> TRIM(customer_city)
LIMIT 50;

SELECT customer_city, COUNT(*) AS variant_count
FROM customers
GROUP BY customer_city
HAVING customer_city <> LOWER(customer_city) AND customer_city <> INITCAP(customer_city)
ORDER BY variant_count DESC
LIMIT 50;

-- Detect potential mojibake / non-ASCII encoding artifacts in city names
SELECT customer_id, customer_city
FROM customers
WHERE customer_city ~ '[ÃÂ]{1}[^a-zA-Z0-9\s]'
LIMIT 50;


-- #####################################################################################
-- TABLE: orders
-- #####################################################################################

-- -------------------------------------------------------------------------------------
-- [orders] Rule 5: NULL check per column with per-column NULL policy
-- order_approved_at, order_delivered_carrier_date, order_delivered_customer_date are
-- nullable by schema and NULL is EXPECTED/meaningful (order not yet approved/shipped/
-- delivered) -- these are "not applicable yet" NULLs, not errors, EXCEPT when
-- order_status implies the milestone should have occurred (checked in Rule 16).
-- -------------------------------------------------------------------------------------
SELECT
    COUNT(*) FILTER (WHERE order_id IS NULL)                        AS null_order_id,
    COUNT(*) FILTER (WHERE customer_id IS NULL)                     AS null_customer_id,
    COUNT(*) FILTER (WHERE order_status IS NULL)                    AS null_order_status,
    COUNT(*) FILTER (WHERE order_purchase_timestamp IS NULL)        AS null_purchase_ts,
    COUNT(*) FILTER (WHERE order_approved_at IS NULL)                AS null_approved_at,
    COUNT(*) FILTER (WHERE order_delivered_carrier_date IS NULL)     AS null_delivered_carrier,
    COUNT(*) FILTER (WHERE order_delivered_customer_date IS NULL)    AS null_delivered_customer,
    COUNT(*) FILTER (WHERE order_estimated_delivery_date IS NULL)    AS null_estimated_delivery
FROM orders;

-- -------------------------------------------------------------------------------------
-- [orders] Rule 6: Disguised missing values in order_status
-- -------------------------------------------------------------------------------------
SELECT order_status, COUNT(*) AS occurrence_count
FROM orders
WHERE TRIM(order_status) = ''
   OR LOWER(TRIM(order_status)) IN ('n/a','na','null','none','-','unknown')
GROUP BY order_status;

-- -------------------------------------------------------------------------------------
-- [orders] Rule 8: Exact full-row duplicates
-- -------------------------------------------------------------------------------------
SELECT order_id, customer_id, order_status, order_purchase_timestamp, order_approved_at,
       order_delivered_carrier_date, order_delivered_customer_date, order_estimated_delivery_date,
       COUNT(*) AS duplicate_count
FROM orders
GROUP BY order_id, customer_id, order_status, order_purchase_timestamp, order_approved_at,
         order_delivered_carrier_date, order_delivered_customer_date, order_estimated_delivery_date
HAVING COUNT(*) > 1;

-- -------------------------------------------------------------------------------------
-- [orders] Rule 9: Primary key integrity (order_id) and orphaned foreign key (customer_id)
-- -------------------------------------------------------------------------------------
SELECT order_id, COUNT(*) AS occurrence_count
FROM orders
GROUP BY order_id
HAVING COUNT(*) > 1;

SELECT o.order_id, o.customer_id
FROM orders o
LEFT JOIN customers c ON o.customer_id = c.customer_id
WHERE c.customer_id IS NULL
LIMIT 50;

SELECT COUNT(*) AS orphaned_customer_fk_count
FROM orders o
LEFT JOIN customers c ON o.customer_id = c.customer_id
WHERE c.customer_id IS NULL;

-- -------------------------------------------------------------------------------------
-- [orders] Rule 11: Categorical consistency on order_status
-- Expected canonical values from the domain: created, approved, invoiced, processing,
-- shipped, delivered, unavailable, canceled. Flags casing/spacing/typo variants.
-- -------------------------------------------------------------------------------------
SELECT order_status, COUNT(*) AS row_count
FROM orders
GROUP BY order_status
ORDER BY row_count DESC;

SELECT order_id, order_status
FROM orders
WHERE order_status <> LOWER(TRIM(order_status))
   OR LOWER(TRIM(order_status)) NOT IN
      ('created','approved','invoiced','processing','shipped','delivered','unavailable','canceled')
LIMIT 50;

-- -------------------------------------------------------------------------------------
-- [orders] Rule 13: Date/time logical order consistency
-- Checks that timestamps occur in the expected chronological sequence:
-- purchase <= approved <= delivered_carrier <= delivered_customer,
-- and delivered_customer vs estimated_delivery for lateness insight.
-- -------------------------------------------------------------------------------------
SELECT order_id, order_purchase_timestamp, order_approved_at
FROM orders
WHERE order_approved_at IS NOT NULL
  AND order_approved_at < order_purchase_timestamp
LIMIT 50;

SELECT order_id, order_approved_at, order_delivered_carrier_date
FROM orders
WHERE order_delivered_carrier_date IS NOT NULL
  AND order_approved_at IS NOT NULL
  AND order_delivered_carrier_date < order_approved_at
LIMIT 50;

SELECT order_id, order_delivered_carrier_date, order_delivered_customer_date
FROM orders
WHERE order_delivered_customer_date IS NOT NULL
  AND order_delivered_carrier_date IS NOT NULL
  AND order_delivered_customer_date < order_delivered_carrier_date
LIMIT 50;

SELECT order_id, order_purchase_timestamp, order_delivered_customer_date
FROM orders
WHERE order_delivered_customer_date IS NOT NULL
  AND order_delivered_customer_date < order_purchase_timestamp
LIMIT 50;

-- Count of orders delivered later than the estimated delivery date (late deliveries)
SELECT COUNT(*) AS late_delivery_count
FROM orders
WHERE order_delivered_customer_date IS NOT NULL
  AND order_delivered_customer_date > order_estimated_delivery_date;

-- -------------------------------------------------------------------------------------
-- [orders] Rule 14: Outlier check on delivery duration (purchase -> delivered_customer)
-- Flags orders whose fulfillment time is statistically far from the mean.
-- -------------------------------------------------------------------------------------
WITH durations AS (
    SELECT order_id,
           EXTRACT(EPOCH FROM (order_delivered_customer_date - order_purchase_timestamp)) / 86400.0 AS delivery_days
    FROM orders
    WHERE order_delivered_customer_date IS NOT NULL
),
stats AS (
    SELECT AVG(delivery_days) AS mean_days, STDDEV(delivery_days) AS stddev_days
    FROM durations
)
SELECT d.order_id, ROUND(d.delivery_days::NUMERIC, 2) AS delivery_days,
       ROUND(s.mean_days::NUMERIC, 2) AS mean_days,
       ROUND(s.stddev_days::NUMERIC, 2) AS stddev_days
FROM durations d, stats s
WHERE ABS(d.delivery_days - s.mean_days) > 3 * s.stddev_days
ORDER BY delivery_days DESC
LIMIT 50;

-- -------------------------------------------------------------------------------------
-- [orders] Rule 16: Business-rule consistency
-- A canceled order should not have a delivered_customer_date.
-- An "unavailable" order should not have a delivered_carrier_date.
-- A delivered order (status = 'delivered') should have a delivered_customer_date.
-- -------------------------------------------------------------------------------------
SELECT order_id, order_status, order_delivered_customer_date
FROM orders
WHERE LOWER(order_status) = 'canceled'
  AND order_delivered_customer_date IS NOT NULL
LIMIT 50;

SELECT order_id, order_status, order_delivered_carrier_date
FROM orders
WHERE LOWER(order_status) = 'unavailable'
  AND order_delivered_carrier_date IS NOT NULL
LIMIT 50;

SELECT COUNT(*) AS delivered_missing_delivery_date_count
FROM orders
WHERE LOWER(order_status) = 'delivered'
  AND order_delivered_customer_date IS NULL;

SELECT order_id, order_status, order_delivered_customer_date
FROM orders
WHERE LOWER(order_status) = 'delivered'
  AND order_delivered_customer_date IS NULL
LIMIT 50;


-- #####################################################################################
-- TABLE: order_items
-- #####################################################################################

-- -------------------------------------------------------------------------------------
-- [order_items] Rule 5: NULL check per column
-- All columns are NOT NULL by schema; this checks for constraint-bypass anomalies.
-- -------------------------------------------------------------------------------------
SELECT
    COUNT(*) FILTER (WHERE order_id IS NULL)             AS null_order_id,
    COUNT(*) FILTER (WHERE order_item_id IS NULL)        AS null_order_item_id,
    COUNT(*) FILTER (WHERE product_id IS NULL)           AS null_product_id,
    COUNT(*) FILTER (WHERE seller_id IS NULL)             AS null_seller_id,
    COUNT(*) FILTER (WHERE shipping_limit_date IS NULL)   AS null_shipping_limit_date,
    COUNT(*) FILTER (WHERE price IS NULL)                 AS null_price,
    COUNT(*) FILTER (WHERE freight_value IS NULL)         AS null_freight_value
FROM order_items;

-- -------------------------------------------------------------------------------------
-- [order_items] Rule 8: Exact full-row duplicates
-- -------------------------------------------------------------------------------------
SELECT order_id, order_item_id, product_id, seller_id, shipping_limit_date, price,
       freight_value, COUNT(*) AS duplicate_count
FROM order_items
GROUP BY order_id, order_item_id, product_id, seller_id, shipping_limit_date, price, freight_value
HAVING COUNT(*) > 1;

-- -------------------------------------------------------------------------------------
-- [order_items] Rule 9: Composite PK integrity + orphaned foreign keys
-- Verifies (order_id, order_item_id) uniqueness and that order_id, product_id, seller_id
-- all reference existing parent rows.
-- -------------------------------------------------------------------------------------
SELECT order_id, order_item_id, COUNT(*) AS occurrence_count
FROM order_items
GROUP BY order_id, order_item_id
HAVING COUNT(*) > 1;

SELECT oi.order_id, oi.order_item_id
FROM order_items oi
LEFT JOIN orders o ON oi.order_id = o.order_id
WHERE o.order_id IS NULL
LIMIT 50;

SELECT oi.order_id, oi.order_item_id, oi.product_id
FROM order_items oi
LEFT JOIN products p ON oi.product_id = p.product_id
WHERE p.product_id IS NULL
LIMIT 50;

SELECT oi.order_id, oi.order_item_id, oi.seller_id
FROM order_items oi
LEFT JOIN sellers s ON oi.seller_id = s.seller_id
WHERE s.seller_id IS NULL
LIMIT 50;

SELECT
    (SELECT COUNT(*) FROM order_items oi LEFT JOIN orders o ON oi.order_id = o.order_id WHERE o.order_id IS NULL) AS orphaned_order_fk,
    (SELECT COUNT(*) FROM order_items oi LEFT JOIN products p ON oi.product_id = p.product_id WHERE p.product_id IS NULL) AS orphaned_product_fk,
    (SELECT COUNT(*) FROM order_items oi LEFT JOIN sellers s ON oi.seller_id = s.seller_id WHERE s.seller_id IS NULL) AS orphaned_seller_fk;

-- -------------------------------------------------------------------------------------
-- [order_items] Rule 10: Range/bounds check on price, freight_value, order_item_id
-- Prices and freight should be positive; zero or negative values are impossible.
-- -------------------------------------------------------------------------------------
SELECT
    MIN(price) AS min_price, MAX(price) AS max_price,
    AVG(price)::NUMERIC(10,2) AS avg_price, STDDEV(price)::NUMERIC(10,2) AS stddev_price,
    MIN(freight_value) AS min_freight, MAX(freight_value) AS max_freight,
    AVG(freight_value)::NUMERIC(10,2) AS avg_freight, STDDEV(freight_value)::NUMERIC(10,2) AS stddev_freight,
    COUNT(*) FILTER (WHERE price <= 0) AS non_positive_price_count,
    COUNT(*) FILTER (WHERE freight_value < 0) AS negative_freight_count
FROM order_items;

SELECT order_id, order_item_id, price
FROM order_items
WHERE price <= 0
LIMIT 50;

SELECT order_id, order_item_id, freight_value
FROM order_items
WHERE freight_value < 0
LIMIT 50;

-- order_item_id should be a positive sequential counter starting at 1 per order
SELECT order_id, order_item_id
FROM order_items
WHERE order_item_id <= 0
LIMIT 50;

-- -------------------------------------------------------------------------------------
-- [order_items] Rule 13: shipping_limit_date should not precede the order's purchase date
-- -------------------------------------------------------------------------------------
SELECT oi.order_id, oi.order_item_id, oi.shipping_limit_date, o.order_purchase_timestamp
FROM order_items oi
JOIN orders o ON oi.order_id = o.order_id
WHERE oi.shipping_limit_date < o.order_purchase_timestamp
LIMIT 50;

-- -------------------------------------------------------------------------------------
-- [order_items] Rule 14: Outlier detection on price and freight_value
-- -------------------------------------------------------------------------------------
WITH stats AS (
    SELECT AVG(price) AS mean_price, STDDEV(price) AS stddev_price,
           AVG(freight_value) AS mean_freight, STDDEV(freight_value) AS stddev_freight
    FROM order_items
)
SELECT oi.order_id, oi.order_item_id, oi.price, oi.freight_value
FROM order_items oi, stats s
WHERE ABS(oi.price - s.mean_price) > 3 * s.stddev_price
   OR ABS(oi.freight_value - s.mean_freight) > 3 * s.stddev_freight
ORDER BY oi.price DESC
LIMIT 50;

-- -------------------------------------------------------------------------------------
-- [order_items] Rule 16: Business rule - freight_value should not exceed price by an
-- extreme multiple (e.g., freight > 5x price is a red flag worth reviewing).
-- -------------------------------------------------------------------------------------
SELECT order_id, order_item_id, price, freight_value,
       ROUND((freight_value / NULLIF(price,0))::NUMERIC, 2) AS freight_to_price_ratio
FROM order_items
WHERE freight_value > 5 * price
ORDER BY freight_to_price_ratio DESC
LIMIT 50;


-- #####################################################################################
-- TABLE: order_payments
-- #####################################################################################

-- -------------------------------------------------------------------------------------
-- [order_payments] Rule 5: NULL check per column (all NOT NULL by schema)
-- -------------------------------------------------------------------------------------
SELECT
    COUNT(*) FILTER (WHERE order_id IS NULL)              AS null_order_id,
    COUNT(*) FILTER (WHERE payment_sequential IS NULL)    AS null_payment_sequential,
    COUNT(*) FILTER (WHERE payment_type IS NULL)          AS null_payment_type,
    COUNT(*) FILTER (WHERE payment_installments IS NULL)  AS null_payment_installments,
    COUNT(*) FILTER (WHERE payment_value IS NULL)         AS null_payment_value
FROM order_payments;

-- -------------------------------------------------------------------------------------
-- [order_payments] Rule 6: Disguised missing values in payment_type
-- -------------------------------------------------------------------------------------
SELECT payment_type, COUNT(*) AS occurrence_count
FROM order_payments
WHERE TRIM(payment_type) = ''
   OR LOWER(TRIM(payment_type)) IN ('n/a','na','null','none','-','unknown')
GROUP BY payment_type;

-- -------------------------------------------------------------------------------------
-- [order_payments] Rule 8: Exact full-row duplicates
-- -------------------------------------------------------------------------------------
SELECT order_id, payment_sequential, payment_type, payment_installments, payment_value,
       COUNT(*) AS duplicate_count
FROM order_payments
GROUP BY order_id, payment_sequential, payment_type, payment_installments, payment_value
HAVING COUNT(*) > 1;

-- -------------------------------------------------------------------------------------
-- [order_payments] Rule 9: Composite PK integrity + orphaned FK to orders
-- -------------------------------------------------------------------------------------
SELECT order_id, payment_sequential, COUNT(*) AS occurrence_count
FROM order_payments
GROUP BY order_id, payment_sequential
HAVING COUNT(*) > 1;

SELECT op.order_id, op.payment_sequential
FROM order_payments op
LEFT JOIN orders o ON op.order_id = o.order_id
WHERE o.order_id IS NULL
LIMIT 50;

SELECT COUNT(*) AS orphaned_order_fk_count
FROM order_payments op
LEFT JOIN orders o ON op.order_id = o.order_id
WHERE o.order_id IS NULL;

-- -------------------------------------------------------------------------------------
-- [order_payments] Rule 10: Range/bounds on payment_installments and payment_value
-- Installments should be >= 1 (or >=0 for non-installment types); payment_value should
-- be non-negative (0 is plausible for full-voucher-covered orders, but flagged for review).
-- -------------------------------------------------------------------------------------
SELECT
    MIN(payment_installments) AS min_installments, MAX(payment_installments) AS max_installments,
    AVG(payment_installments)::NUMERIC(10,2) AS avg_installments,
    MIN(payment_value) AS min_payment_value, MAX(payment_value) AS max_payment_value,
    AVG(payment_value)::NUMERIC(10,2) AS avg_payment_value,
    STDDEV(payment_value)::NUMERIC(10,2) AS stddev_payment_value,
    COUNT(*) FILTER (WHERE payment_installments < 1) AS invalid_installments_count,
    COUNT(*) FILTER (WHERE payment_value < 0) AS negative_payment_value_count
FROM order_payments;

SELECT order_id, payment_sequential, payment_installments
FROM order_payments
WHERE payment_installments < 1
LIMIT 50;

SELECT order_id, payment_sequential, payment_value
FROM order_payments
WHERE payment_value < 0
LIMIT 50;

-- -------------------------------------------------------------------------------------
-- [order_payments] Rule 11: Categorical consistency on payment_type
-- Expected canonical values: credit_card, boleto, voucher, debit_card, not_defined
-- -------------------------------------------------------------------------------------
SELECT payment_type, COUNT(*) AS row_count
FROM order_payments
GROUP BY payment_type
ORDER BY row_count DESC;

SELECT order_id, payment_sequential, payment_type
FROM order_payments
WHERE payment_type <> LOWER(TRIM(payment_type))
   OR LOWER(TRIM(payment_type)) NOT IN ('credit_card','boleto','voucher','debit_card','not_defined')
LIMIT 50;

-- -------------------------------------------------------------------------------------
-- [order_payments] Rule 14: Outlier detection on payment_value
-- -------------------------------------------------------------------------------------
WITH stats AS (
    SELECT AVG(payment_value) AS mean_value, STDDEV(payment_value) AS stddev_value
    FROM order_payments
)
SELECT op.order_id, op.payment_sequential, op.payment_value
FROM order_payments op, stats s
WHERE ABS(op.payment_value - s.mean_value) > 3 * s.stddev_value
ORDER BY op.payment_value DESC
LIMIT 50;

-- -------------------------------------------------------------------------------------
-- [order_payments] Rule 15/16: Cross-column / cross-table consistency
-- Sum of payment_value per order should approximately equal sum of (price + freight_value)
-- from order_items for that order. Flags orders where totals diverge meaningfully.
-- -------------------------------------------------------------------------------------
WITH payment_totals AS (
    SELECT order_id, SUM(payment_value) AS total_paid
    FROM order_payments
    GROUP BY order_id
),
item_totals AS (
    SELECT order_id, SUM(price + freight_value) AS total_owed
    FROM order_items
    GROUP BY order_id
)
SELECT
    COALESCE(p.order_id, i.order_id) AS order_id,
    p.total_paid,
    i.total_owed,
    ROUND((p.total_paid - i.total_owed)::NUMERIC, 2) AS difference
FROM payment_totals p
FULL OUTER JOIN item_totals i ON p.order_id = i.order_id
WHERE ABS(COALESCE(p.total_paid,0) - COALESCE(i.total_owed,0)) > 0.01
ORDER BY ABS(COALESCE(p.total_paid,0) - COALESCE(i.total_owed,0)) DESC
LIMIT 50;

SELECT COUNT(*) AS mismatched_order_total_count
FROM (
    WITH payment_totals AS (
        SELECT order_id, SUM(payment_value) AS total_paid
        FROM order_payments
        GROUP BY order_id
    ),
    item_totals AS (
        SELECT order_id, SUM(price + freight_value) AS total_owed
        FROM order_items
        GROUP BY order_id
    )
    SELECT COALESCE(p.order_id, i.order_id) AS order_id
    FROM payment_totals p
    FULL OUTER JOIN item_totals i ON p.order_id = i.order_id
    WHERE ABS(COALESCE(p.total_paid,0) - COALESCE(i.total_owed,0)) > 0.01
) AS mismatches;


-- #####################################################################################
-- TABLE: order_reviews
-- #####################################################################################

-- -------------------------------------------------------------------------------------
-- [order_reviews] Rule 5: NULL check per column
-- review_comment_title and review_comment_message are nullable and NULL legitimately
-- means "customer left no written comment" -- not an error. Other columns are NOT NULL.
-- -------------------------------------------------------------------------------------
SELECT
    COUNT(*) FILTER (WHERE review_id IS NULL)                AS null_review_id,
    COUNT(*) FILTER (WHERE order_id IS NULL)                 AS null_order_id,
    COUNT(*) FILTER (WHERE review_score IS NULL)             AS null_review_score,
    COUNT(*) FILTER (WHERE review_comment_title IS NULL)     AS null_comment_title_expected_ok,
    COUNT(*) FILTER (WHERE review_comment_message IS NULL)   AS null_comment_message_expected_ok,
    COUNT(*) FILTER (WHERE review_creation_date IS NULL)     AS null_creation_date,
    COUNT(*) FILTER (WHERE review_answer_timestamp IS NULL)  AS null_answer_timestamp
FROM order_reviews;

-- -------------------------------------------------------------------------------------
-- [order_reviews] Rule 6: Disguised missing values in free-text comment columns
-- -------------------------------------------------------------------------------------
SELECT 'review_comment_title' AS column_name, review_comment_title AS suspect_value, COUNT(*) AS occurrence_count
FROM order_reviews
WHERE review_comment_title IS NOT NULL
  AND (TRIM(review_comment_title) = ''
       OR LOWER(TRIM(review_comment_title)) IN ('n/a','na','null','none','-','unknown'))
GROUP BY review_comment_title

UNION ALL

SELECT 'review_comment_message' AS column_name, review_comment_message AS suspect_value, COUNT(*) AS occurrence_count
FROM order_reviews
WHERE review_comment_message IS NOT NULL
  AND (TRIM(review_comment_message) = ''
       OR LOWER(TRIM(review_comment_message)) IN ('n/a','na','null','none','-','unknown'))
GROUP BY review_comment_message
ORDER BY column_name, occurrence_count DESC
LIMIT 50;

-- -------------------------------------------------------------------------------------
-- [order_reviews] Rule 8: Exact full-row duplicates
-- -------------------------------------------------------------------------------------
SELECT review_id, order_id, review_score, review_comment_title, review_comment_message,
       review_creation_date, review_answer_timestamp, COUNT(*) AS duplicate_count
FROM order_reviews
GROUP BY review_id, order_id, review_score, review_comment_title, review_comment_message,
         review_creation_date, review_answer_timestamp
HAVING COUNT(*) > 1;

-- -------------------------------------------------------------------------------------
-- [order_reviews] Rule 9: PK integrity (review_id) + orphaned FK to orders
-- Note: order_id has no UNIQUE constraint here, so multiple reviews per order are
-- structurally allowed but worth flagging as a business-key duplicate (Rule 8).
-- -------------------------------------------------------------------------------------
SELECT review_id, COUNT(*) AS occurrence_count
FROM order_reviews
GROUP BY review_id
HAVING COUNT(*) > 1;

SELECT ord.review_id, ord.order_id
FROM order_reviews ord
LEFT JOIN orders o ON ord.order_id = o.order_id
WHERE o.order_id IS NULL
LIMIT 50;

SELECT order_id, COUNT(*) AS review_count_per_order
FROM order_reviews
GROUP BY order_id
HAVING COUNT(*) > 1
ORDER BY review_count_per_order DESC
LIMIT 50;

-- -------------------------------------------------------------------------------------
-- [order_reviews] Rule 10: Range/bounds check on review_score
-- Standard review scale is 1-5; anything outside that range is invalid.
-- -------------------------------------------------------------------------------------
SELECT
    MIN(review_score) AS min_score, MAX(review_score) AS max_score,
    AVG(review_score)::NUMERIC(10,2) AS avg_score, STDDEV(review_score)::NUMERIC(10,2) AS stddev_score,
    COUNT(*) FILTER (WHERE review_score < 1 OR review_score > 5) AS out_of_range_count
FROM order_reviews;

SELECT review_id, review_score
FROM order_reviews
WHERE review_score < 1 OR review_score > 5
LIMIT 50;

-- -------------------------------------------------------------------------------------
-- [order_reviews] Rule 13: Date/time logical order
-- review_answer_timestamp should not precede review_creation_date.
-- review_creation_date should not precede the related order's purchase timestamp.
-- -------------------------------------------------------------------------------------
SELECT review_id, review_creation_date, review_answer_timestamp
FROM order_reviews
WHERE review_answer_timestamp < review_creation_date
LIMIT 50;

SELECT r.review_id, r.order_id, r.review_creation_date, o.order_purchase_timestamp
FROM order_reviews r
JOIN orders o ON r.order_id = o.order_id
WHERE r.review_creation_date < o.order_purchase_timestamp
LIMIT 50;

-- -------------------------------------------------------------------------------------
-- [order_reviews] Rule 12: Text formatting consistency in comment fields
-- Leading/trailing whitespace check.
-- -------------------------------------------------------------------------------------
SELECT review_id, review_comment_title
FROM order_reviews
WHERE review_comment_title IS NOT NULL
  AND review_comment_title <> TRIM(review_comment_title)
LIMIT 50;

SELECT review_id, review_comment_message
FROM order_reviews
WHERE review_comment_message IS NOT NULL
  AND review_comment_message <> TRIM(review_comment_message)
LIMIT 50;

-- -------------------------------------------------------------------------------------
-- [order_reviews] Rule 16: Business rule consistency
-- Low review scores (1-2) with no comment message at all may indicate silent
-- dissatisfaction worth flagging for review-quality auditing (not strictly an "error").
-- -------------------------------------------------------------------------------------
SELECT COUNT(*) AS low_score_no_comment_count
FROM order_reviews
WHERE review_score <= 2
  AND (review_comment_message IS NULL OR TRIM(review_comment_message) = '');


-- #####################################################################################
-- TABLE: products
-- #####################################################################################

-- -------------------------------------------------------------------------------------
-- [products] Rule 5: NULL check per column
-- Only product_id is NOT NULL by schema. All other columns are nullable; for this
-- catalog table, NULL in dimension/weight/category fields typically means "not yet
-- catalogued" (unknown), not "not applicable" -- flagged for data-completeness review.
-- -------------------------------------------------------------------------------------
SELECT
    COUNT(*) FILTER (WHERE product_id IS NULL)                     AS null_product_id,
    COUNT(*) FILTER (WHERE product_category_name IS NULL)          AS null_category_name,
    COUNT(*) FILTER (WHERE product_name_lenght IS NULL)            AS null_name_length,
    COUNT(*) FILTER (WHERE product_description_lenght IS NULL)     AS null_description_length,
    COUNT(*) FILTER (WHERE product_photos_qty IS NULL)             AS null_photos_qty,
    COUNT(*) FILTER (WHERE product_weight_g IS NULL)               AS null_weight_g,
    COUNT(*) FILTER (WHERE product_length_cm IS NULL)              AS null_length_cm,
    COUNT(*) FILTER (WHERE product_height_cm IS NULL)              AS null_height_cm,
    COUNT(*) FILTER (WHERE product_width_cm IS NULL)               AS null_width_cm
FROM products;

-- -------------------------------------------------------------------------------------
-- [products] Rule 6: Disguised missing values in product_category_name
-- -------------------------------------------------------------------------------------
SELECT product_category_name, COUNT(*) AS occurrence_count
FROM products
WHERE product_category_name IS NOT NULL
  AND (TRIM(product_category_name) = ''
       OR LOWER(TRIM(product_category_name)) IN ('n/a','na','null','none','-','unknown'))
GROUP BY product_category_name;

-- -------------------------------------------------------------------------------------
-- [products] Rule 8: Exact full-row duplicates (excluding PK, since product_id is
-- expected unique -- checks whether non-key attributes fully match another row,
-- which could indicate a duplicated catalog entry under a different ID).
-- -------------------------------------------------------------------------------------
SELECT product_category_name, product_name_lenght, product_description_lenght,
       product_photos_qty, product_weight_g, product_length_cm, product_height_cm,
       product_width_cm, COUNT(*) AS duplicate_count, ARRAY_AGG(product_id) AS product_ids
FROM products
GROUP BY product_category_name, product_name_lenght, product_description_lenght,
         product_photos_qty, product_weight_g, product_length_cm, product_height_cm, product_width_cm
HAVING COUNT(*) > 1
ORDER BY duplicate_count DESC
LIMIT 50;

-- -------------------------------------------------------------------------------------
-- [products] Rule 9: PK integrity check
-- -------------------------------------------------------------------------------------
SELECT product_id, COUNT(*) AS occurrence_count
FROM products
GROUP BY product_id
HAVING COUNT(*) > 1;

-- -------------------------------------------------------------------------------------
-- [products] Rule 9 (referential): Orphaned category -- product_category_name not
-- present in product_category_name_translation lookup table.
-- -------------------------------------------------------------------------------------
SELECT p.product_id, p.product_category_name
FROM products p
LEFT JOIN product_category_name_translation t
    ON p.product_category_name = t.product_category_name
WHERE p.product_category_name IS NOT NULL
  AND t.product_category_name IS NULL
LIMIT 50;

SELECT COUNT(*) AS unmapped_category_count
FROM products p
LEFT JOIN product_category_name_translation t
    ON p.product_category_name = t.product_category_name
WHERE p.product_category_name IS NOT NULL
  AND t.product_category_name IS NULL;

-- -------------------------------------------------------------------------------------
-- [products] Rule 10: Range/bounds check on numeric dimension and count columns
-- All of these should be positive; zero/negative is physically impossible for a
-- real product, and NULLs are handled separately under Rule 5.
-- -------------------------------------------------------------------------------------
SELECT
    MIN(product_name_lenght) AS min_name_len, MAX(product_name_lenght) AS max_name_len,
    MIN(product_description_lenght) AS min_desc_len, MAX(product_description_lenght) AS max_desc_len,
    MIN(product_photos_qty) AS min_photos, MAX(product_photos_qty) AS max_photos,
    MIN(product_weight_g) AS min_weight_g, MAX(product_weight_g) AS max_weight_g,
    AVG(product_weight_g)::NUMERIC(10,2) AS avg_weight_g, STDDEV(product_weight_g)::NUMERIC(10,2) AS stddev_weight_g,
    MIN(product_length_cm) AS min_length_cm, MAX(product_length_cm) AS max_length_cm,
    MIN(product_height_cm) AS min_height_cm, MAX(product_height_cm) AS max_height_cm,
    MIN(product_width_cm) AS min_width_cm, MAX(product_width_cm) AS max_width_cm,
    COUNT(*) FILTER (WHERE product_weight_g <= 0) AS non_positive_weight_count,
    COUNT(*) FILTER (WHERE product_length_cm <= 0) AS non_positive_length_count,
    COUNT(*) FILTER (WHERE product_height_cm <= 0) AS non_positive_height_count,
    COUNT(*) FILTER (WHERE product_width_cm <= 0) AS non_positive_width_count,
    COUNT(*) FILTER (WHERE product_photos_qty < 0) AS negative_photos_qty_count
FROM products;

SELECT product_id, product_weight_g, product_length_cm, product_height_cm, product_width_cm
FROM products
WHERE product_weight_g <= 0 OR product_length_cm <= 0 OR product_height_cm <= 0 OR product_width_cm <= 0
LIMIT 50;

-- -------------------------------------------------------------------------------------
-- [products] Rule 14: Outlier detection on product_weight_g (dimension outliers can
-- indicate data-entry errors, e.g., grams entered as kilograms).
-- -------------------------------------------------------------------------------------
WITH stats AS (
    SELECT AVG(product_weight_g) AS mean_weight, STDDEV(product_weight_g) AS stddev_weight
    FROM products
    WHERE product_weight_g IS NOT NULL
)
SELECT p.product_id, p.product_weight_g
FROM products p, stats s
WHERE p.product_weight_g IS NOT NULL
  AND ABS(p.product_weight_g - s.mean_weight) > 3 * s.stddev_weight
ORDER BY p.product_weight_g DESC
LIMIT 50;

-- -------------------------------------------------------------------------------------
-- [products] Rule 12: Text formatting consistency on product_category_name
-- (raw category names in this dataset are typically snake_case; flags mixed casing).
-- -------------------------------------------------------------------------------------
SELECT product_category_name, COUNT(*) AS row_count
FROM products
WHERE product_category_name IS NOT NULL
  AND product_category_name <> LOWER(product_category_name)
GROUP BY product_category_name
ORDER BY row_count DESC
LIMIT 50;

SELECT product_id, product_category_name
FROM products
WHERE product_category_name IS NOT NULL
  AND product_category_name <> TRIM(product_category_name)
LIMIT 50;


-- #####################################################################################
-- TABLE: sellers
-- #####################################################################################

-- -------------------------------------------------------------------------------------
-- [sellers] Rule 5: NULL check per column (all NOT NULL by schema)
-- -------------------------------------------------------------------------------------
SELECT
    COUNT(*) FILTER (WHERE seller_id IS NULL)               AS null_seller_id,
    COUNT(*) FILTER (WHERE seller_zip_code_prefix IS NULL)  AS null_zip_code_prefix,
    COUNT(*) FILTER (WHERE seller_city IS NULL)             AS null_seller_city,
    COUNT(*) FILTER (WHERE seller_state IS NULL)            AS null_seller_state
FROM sellers;

-- -------------------------------------------------------------------------------------
-- [sellers] Rule 6: Disguised missing values in seller_city / seller_state
-- -------------------------------------------------------------------------------------
SELECT 'seller_city' AS column_name, seller_city AS suspect_value, COUNT(*) AS occurrence_count
FROM sellers
WHERE TRIM(seller_city) = ''
   OR LOWER(TRIM(seller_city)) IN ('n/a','na','null','none','-','unknown','999')
GROUP BY seller_city

UNION ALL

SELECT 'seller_state' AS column_name, seller_state AS suspect_value, COUNT(*) AS occurrence_count
FROM sellers
WHERE TRIM(seller_state) = ''
   OR LOWER(TRIM(seller_state)) IN ('n/a','na','null','none','-','unknown','99')
GROUP BY seller_state
ORDER BY column_name, occurrence_count DESC;

-- -------------------------------------------------------------------------------------
-- [sellers] Rule 8: Exact full-row duplicates
-- -------------------------------------------------------------------------------------
SELECT seller_id, seller_zip_code_prefix, seller_city, seller_state, COUNT(*) AS duplicate_count
FROM sellers
GROUP BY seller_id, seller_zip_code_prefix, seller_city, seller_state
HAVING COUNT(*) > 1;

-- -------------------------------------------------------------------------------------
-- [sellers] Rule 9: PK integrity check (seller_id)
-- -------------------------------------------------------------------------------------
SELECT seller_id, COUNT(*) AS occurrence_count
FROM sellers
GROUP BY seller_id
HAVING COUNT(*) > 1;

-- -------------------------------------------------------------------------------------
-- [sellers] Rule 10: Range check on seller_zip_code_prefix
-- -------------------------------------------------------------------------------------
SELECT
    MIN(seller_zip_code_prefix) AS min_zip,
    MAX(seller_zip_code_prefix) AS max_zip,
    AVG(seller_zip_code_prefix)::NUMERIC(10,2) AS avg_zip,
    STDDEV(seller_zip_code_prefix)::NUMERIC(10,2) AS stddev_zip,
    COUNT(*) FILTER (WHERE seller_zip_code_prefix < 0 OR seller_zip_code_prefix > 99999) AS out_of_range_count
FROM sellers;

SELECT seller_id, seller_zip_code_prefix
FROM sellers
WHERE seller_zip_code_prefix < 0 OR seller_zip_code_prefix > 99999
LIMIT 20;

-- -------------------------------------------------------------------------------------
-- [sellers] Rule 11: Categorical consistency on seller_state
-- -------------------------------------------------------------------------------------
SELECT seller_state, COUNT(*) AS row_count
FROM sellers
GROUP BY seller_state
ORDER BY seller_state;

SELECT seller_id, seller_state
FROM sellers
WHERE seller_state !~ '^[A-Z]{2}$'
   OR seller_state NOT IN (
        'AC','AL','AP','AM','BA','CE','DF','ES','GO','MA','MT','MS','MG','PA','PB',
        'PR','PE','PI','RJ','RN','RS','RO','RR','SC','SP','SE','TO'
   )
LIMIT 50;

-- -------------------------------------------------------------------------------------
-- [sellers] Rule 12: Text formatting consistency on seller_city
-- -------------------------------------------------------------------------------------
SELECT seller_id, seller_city
FROM sellers
WHERE seller_city <> TRIM(seller_city)
LIMIT 50;

SELECT seller_city, COUNT(*) AS variant_count
FROM sellers
GROUP BY seller_city
HAVING seller_city <> LOWER(seller_city) AND seller_city <> INITCAP(seller_city)
ORDER BY variant_count DESC
LIMIT 50;

-- -------------------------------------------------------------------------------------
-- [sellers] Rule 15: Cross-column consistency between seller_city and seller_state
-- Flags city/state combinations that appear only once in the dataset as potential
-- typos (a legitimate city/state pair for a marketplace this size should recur).
-- -------------------------------------------------------------------------------------
SELECT seller_city, seller_state, COUNT(*) AS row_count
FROM sellers
GROUP BY seller_city, seller_state
HAVING COUNT(*) = 1
ORDER BY seller_city
LIMIT 50;


-- #####################################################################################
-- TABLE: product_category_name_translation
-- #####################################################################################

-- -------------------------------------------------------------------------------------
-- [product_category_name_translation] Rule 5: NULL check per column (all NOT NULL)
-- -------------------------------------------------------------------------------------
SELECT
    COUNT(*) FILTER (WHERE product_category_name IS NULL)          AS null_category_name,
    COUNT(*) FILTER (WHERE product_category_name_english IS NULL)  AS null_category_name_english
FROM product_category_name_translation;

-- -------------------------------------------------------------------------------------
-- [product_category_name_translation] Rule 6: Disguised missing values
-- -------------------------------------------------------------------------------------
SELECT product_category_name_english, COUNT(*) AS occurrence_count
FROM product_category_name_translation
WHERE TRIM(product_category_name_english) = ''
   OR LOWER(TRIM(product_category_name_english)) IN ('n/a','na','null','none','-','unknown')
GROUP BY product_category_name_english;

-- -------------------------------------------------------------------------------------
-- [product_category_name_translation] Rule 9: PK integrity check
-- -------------------------------------------------------------------------------------
SELECT product_category_name, COUNT(*) AS occurrence_count
FROM product_category_name_translation
GROUP BY product_category_name
HAVING COUNT(*) > 1;

-- -------------------------------------------------------------------------------------
-- [product_category_name_translation] Rule 8: Duplicate English translations mapped
-- from different Portuguese category names (may be legitimate synonyms, but worth
-- reviewing for consolidation opportunities).
-- -------------------------------------------------------------------------------------
SELECT product_category_name_english, COUNT(*) AS mapped_count,
       ARRAY_AGG(product_category_name) AS source_category_names
FROM product_category_name_translation
GROUP BY product_category_name_english
HAVING COUNT(*) > 1
ORDER BY mapped_count DESC;

-- -------------------------------------------------------------------------------------
-- [product_category_name_translation] Rule 12: Text formatting consistency
-- -------------------------------------------------------------------------------------
SELECT product_category_name, product_category_name_english
FROM product_category_name_translation
WHERE product_category_name <> TRIM(product_category_name)
   OR product_category_name_english <> TRIM(product_category_name_english)
LIMIT 50;

SELECT product_category_name
FROM product_category_name_translation
WHERE product_category_name <> LOWER(product_category_name)
LIMIT 50;

-- -------------------------------------------------------------------------------------
-- [product_category_name_translation] Rule 9 (reverse referential check):
-- Category names present in products.product_category_name but missing from this
-- translation lookup (complements the earlier products-side orphan check).
-- -------------------------------------------------------------------------------------
SELECT DISTINCT p.product_category_name
FROM products p
LEFT JOIN product_category_name_translation t
    ON p.product_category_name = t.product_category_name
WHERE p.product_category_name IS NOT NULL
  AND t.product_category_name IS NULL
LIMIT 50;

-- =====================================================================================
-- END OF AUDIT SCRIPT
-- =====================================================================================