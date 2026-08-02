# FoodHub Analytics — Case Study

> Portfolio write-up. Ready to paste into a portfolio site (e.g. `ash-analytics`).
> All metrics are from a real run of the project's SQL against the generated dataset.

## Summary
Designed and built an **end-to-end analytics stack for a food-delivery
marketplace** — from database schema and a deliberately-messy synthetic dataset,
through a PostgreSQL cleaning/ETL pipeline and a library of advanced analytical
SQL, to a Power BI dimensional model with ready-to-use DAX. The project answers
the three questions every marketplace cares about: **where revenue comes from,
which customers to keep, and where operations break down.**

**Tech stack:** `PostgreSQL 17` · `SQL (window functions, CTEs, cohorts, RFM)` ·
`Python / Faker` · `Power BI (DAX, star schema)` · `Git`

## Headline numbers
| Metric | Value |
|---|---|
| GMV analysed | **₹4.95 Cr** across 20,587 delivered orders |
| Revenue from returning customers | **92.8%** |
| On-time delivery rate (45-min SLA) | **55.3%** |
| Top RFM segment | **78 "Champions" → 18.6% of revenue** |

## Problem
A food-delivery platform generates high-volume operational data (orders, riders,
restaurants, reviews) but that raw data is **messy and non-analytical**:
inconsistent date formats, duplicate signups, out-of-range delivery times, and no
dimensional structure for BI. The business needs trustworthy answers to:
- Which cities, cuisines, and restaurants drive revenue?
- Who are our most valuable customers, and who is at risk of churning?
- Are we meeting delivery SLAs, and where do operations fail?

## Approach
1. **Modeled a normalized (3NF) schema** — 7 tables with PK/FK/CHECK constraints
   for customers, restaurants, menu items, riders, orders, order items, reviews.
2. **Generated 25,000 orders of realistic synthetic data** with Python/Faker, and
   **deliberately injected data-quality issues** (NULL ratings, duplicate
   customers, non-ISO dates, negative/300-600-min delivery times, orphaned rider
   links) to build a real cleaning problem.
3. **Built a staging-then-transform ETL pipeline in SQL** — load everything as
   TEXT so no bad row breaks the import, then clean and cast: a tolerant
   multi-format date parser, de-duplication via window functions, text
   standardization, and range-guarding of numeric outliers.
4. **Wrote an analytical SQL library** covering joins/aggregation, window
   functions (running totals, ranking, NTILE/percentiles, top-N per group),
   multi-step and **recursive** CTEs, **cohort retention**, **RFM segmentation**,
   and **operational KPIs** (SLA, cancellation, speed by city/rider/vehicle).
5. **Tuned queries with `EXPLAIN ANALYZE`** — measured before/after indexing on
   four cases, demonstrating both when indexes help and when they correctly don't.
6. **Delivered a Power BI-ready star schema** — one fact + five dimension views,
   ~30 documented DAX measures, and a step-by-step 4-page dashboard build guide.

## Impact / insights
- **Retention is the growth lever, not acquisition** — 92.8% of revenue comes from
  returning customers and 90-day churn is just 1.0%, so investment should protect
  the engaged base.
- **A win-back opportunity is quantified** — 100 "Hibernating / Lost" customers
  still represent 16.8% of historical revenue, a concrete re-engagement target.
- **The clearest operational fix is delivery speed** — only 55.3% of orders beat
  the 45-minute SLA (avg 42.5 min), pinpointing the biggest CX lever.
- **Demand is broad-based** — the top 5 cities sit within ~22% of each other and
  South Indian leads cuisines (₹76.9 L), informing partner and menu strategy.
- **The business is scaling** — delivered revenue grew ₹76.6 L → ₹1.99 Cr → ₹2.20 Cr
  (2024 → 2025 → H1-2026), with the first half of 2026 already beating all of 2025.

## Skills demonstrated
Data modeling · ETL & data cleaning · advanced SQL (windows, recursive CTEs,
cohort/RFM analysis) · query performance tuning · dimensional modeling · DAX ·
dashboard design · reproducible pipelines.

## Links
- Repo: `foodhub-analytics`
- Key files: `sql/queries/` (analysis), `docs/optimization_results.md` (tuning),
  `powerbi/build_guide.md` (dashboard), `docs/data_quality_notes.md` (cleaning).
