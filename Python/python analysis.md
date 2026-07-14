# 🌟 Olist E-Commerce Dataset — Executive Insights
### *Automated Exploratory Data Analysis (EDA) Summary*

<div

![Status](https://img.shields.io/badge/Analysis-Completed-22c55e?style=for-the-badge)
![Tables](https://img.shields.io/badge/Tables-8-3b82f6?style=for-the-badge)
![Rows](https://img.shields.io/badge/Rows-450K+-8b5cf6?style=for-the-badge)
![Relationships](https://img.shields.io/badge/Integrity-97%25+-f59e0b?style=for-the-badge)

</div>

---

# 📊 Dataset Overview

| 📦 Metric | 📈 Value |
|-----------|---------:|
| Database Tables | **8** |
| Total Records | **≈ 450,000+** |
| Primary Relationships Tested | **7** |
| Referential Integrity | **97–100%** |
| Overall Data Quality | **High** |

---

# 🟢 Major Business Insights

---

## 🚚 1. Delivery Speed Directly Impacts Customer Satisfaction

> ⭐ **The earlier an order arrives, the better the review score.**

| Review Score | Average Delivery Difference |
|--------------|---------------------------:|
| ⭐ | -5.22 Days |
| ⭐⭐ | -7.37 Days |
| ⭐⭐⭐ | -10.57 Days |
| ⭐⭐⭐⭐ | -12.55 Days |
| ⭐⭐⭐⭐⭐ | **-13.11 Days** |

### 💡 Insight

Customers consistently reward faster-than-promised deliveries with higher ratings.

---

## 💳 2. Credit Cards Dominate Payments

```text
Credit Card     ████████████████████████████████ 73.9%
Boleto          ████████
Voucher         ██
Debit Card      ▌
Others          ▏
```

### 💡 Business Takeaway

- Credit Card is the dominant payment method.
- Installment-based purchases are extremely common.
- Payment optimization should focus primarily on credit card users.

---

## 📦 3. Orders are Successfully Delivered

| Status | Percentage |
|---------|-----------:|
| ✅ Delivered | **97%** |
| Other Statuses Combined | 3% |

### 💡 Business Takeaway

The fulfillment pipeline is highly efficient.

---

# 🌍 Geographic Insights

## Customer Concentration

🏆 São Paulo dominates customer volume.

Top customer region:

```
SP ███████████████████████████████
RJ ███████
MG ██████
PR ████
RS ███
```

### Business Opportunity

- Regional marketing
- Local warehouses
- Same-day delivery expansion

---

# 🏪 Seller Distribution

Most sellers are also concentrated in **São Paulo**, indicating:

- Strong marketplace concentration
- Better logistics around Southeast Brazil

---

# 📈 Product Insights

## Most Popular Categories

🥇 Bed, Bath & Table

🥈 Sports & Leisure

🥉 Furniture & Home Decor

These categories generate the largest share of marketplace activity.

---

# 💰 Revenue Characteristics

Revenue distribution is **heavily right-skewed**.

Most products are inexpensive.

A very small number of premium products contribute disproportionately to total revenue.

---

# 📦 Freight Insights

Average Freight

> **≈ 20 BRL**

Freight costs also exhibit heavy skew, suggesting:

- Premium shipping
- Large products
- Long-distance deliveries

---

# ⭐ Review Insights

Average Review Score

# ⭐⭐⭐⭐☆ (4.13 / 5)

Customer sentiment is overwhelmingly positive.

---

# 🔗 Database Relationship Quality

| Relationship | Status |
|--------------|--------|
| Customer ↔ Orders | ✅ Perfect |
| Orders ↔ Order Items | ✅ Perfect |
| Orders ↔ Payments | ✅ Perfect |
| Orders ↔ Reviews | ✅ Perfect |
| Seller ↔ Items | ✅ Perfect |
| Product ↔ Items | ✅ Perfect |
| Category Translation | ⚠️ Minor Issue |

---

# ⚠️ Data Quality Findings

## Minor Issues

### 🟠 Missing Product Categories

- 13 products have categories without translation.
- Only 2 orphan category values exist.

---

### 🟠 Zero Values

Found in:

- Product Weight
- Payment Value
- Freight Value


---

### 🔴 Shipping Date Anomaly

One of the largest findings.

Some shipping limit dates extend into **2020**, while almost the entire dataset ends in **2018**.

This strongly suggests:

- ETL issue
- Data entry issue
- Incorrect timestamp

---

### 🟡 Review Dataset Limitation

Reviews contain only

> **2,872 rows**

while Orders contain

> **99,441 rows**

Meaning review-based insights represent only a subset of the marketplace.

---

# 📊 Statistical Characteristics

| Metric | Observation |
|---------|------------|
| Price | Highly Right Skewed |
| Freight | Highly Right Skewed |
| Payment Value | Highly Right Skewed |
| Product Weight | Highly Right Skewed |
| Review Score | Left Skewed (mostly positive) |

---

# 🧠 Key Business Opportunities

## 🚀 Logistics

✔ Deliver earlier than promised

✔ Optimize freight costs

✔ Expand warehouses near high-demand regions

---

## 💳 Payments

✔ Improve credit-card experience

✔ Optimize installment offers

---

## 📦 Products

✔ Focus inventory on best-selling categories

✔ Investigate premium-product pricing

---

## ⭐ Customer Experience

✔ Delivery speed drives reviews

✔ Maintain high fulfillment performance

✔ Improve experience for delayed deliveries

---

# 🔍 Technical Observations

✅ Strong relational integrity

✅ Clean primary keys

✅ Very few duplicates

✅ Minimal missing data

⚠ Some quality checks should be improved to detect:

- Zero-value anomalies
- Historical date inconsistencies
- Placeholder categories

---

# 🎯 Executive Summary

> ## 🟢 Overall Dataset Health

| Category | Rating |
|----------|---------|
| Data Completeness | 🟢 Excellent |
| Referential Integrity | 🟢 Excellent |
| Missing Data | 🟢 Low |
| Business Readiness | 🟢 High |
| Statistical Quality | 🟢 Good |
| Data Quality Issues | 🟡 Minor |
| ETL Health | 🟡 Needs Review |

---