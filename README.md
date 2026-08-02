# FoodHub Analytics — SQL + Power BI Portfolio Project

An end-to-end analytics project on a synthetic **food-delivery platform**:
schema design → realistic (deliberately messy) data → PostgreSQL load & cleaning
→ an analytical SQL library (window functions, CTEs, cohorts, RFM, operational
KPIs) → a Power BI star-schema model with ready-to-paste DAX.

> **Domain:** B2C food delivery (customers, restaurants, riders, orders, reviews).
> The analytical patterns — cohort retention, RFM segmentation, churn, delivery
> SLAs — are the same ones used across e-commerce, subscriptions, and marketplaces.

---

## Problem statement
A food-delivery marketplace needs to understand **where revenue comes from, which
customers to retain, and where operations break down.** This project builds the
full data stack to answer those questions: a clean dimensional model over messy
operational data, a library of analytical SQL, and a BI layer for self-serve
dashboards.

## Why this project (skills demonstrated)
- **Data modeling** — normalized 3NF schema with PK/FK/CHECK constraints; a
  star-schema BI layer built as SQL views.
- **Data cleaning / ETL** — staging-then-transform pipeline that absorbs dirty
  source data (bad date formats, duplicates, out-of-range values) without
  breaking the load. See [`docs/data_quality_notes.md`](docs/data_quality_notes.md).
- **Advanced SQL** — window functions, ranking, percentiles, multi-step and
  **recursive** CTEs, cohort/retention math, RFM segmentation.
- **Query performance** — `EXPLAIN ANALYZE` before/after indexing, with a written
  rationale ([`sql/queries/07_optimization`](sql/queries/07_optimization)).
- **BI / visualization** — Power BI dimensional model, DAX time-intelligence,
  dashboard design across 4 pages.

## Architecture / tech stack
```
Faker (Python)  ->  CSVs  ->  Postgres staging (TEXT)  ->  clean/cast  ->  3NF tables
                                                                              |
                                                            SQL views (star schema)
                                                                              |
                                                                    Power BI (Import)
```
| Layer | Tech |
|---|---|
| Data generation | Python 3.13, Faker |
| Database | PostgreSQL 17 |
| Transformation | SQL (staging + `plpgsql` date parser) |
| Analytics | SQL (window fns, CTEs, cohort/RFM) |
| BI | Power BI Desktop (DAX, star schema) |
| Tooling | Git, psql |

## Repository layout
```
foodhub-analytics/
├── data/
│   ├── generate_data.py         # Faker generator (seed 42)
│   └── csv/                     # generated CSVs
├── sql/
│   ├── 01_schema.sql            # 3NF DDL + constraints
│   ├── 02_load_data.sql         # staging -> clean -> load
│   ├── 03_indexes.sql           # indexes justified by query patterns
│   ├── 04_powerbi_views.sql     # star-schema views (fact + dims)
│   ├── 05_key_findings.sql      # headline-number queries
│   └── queries/                 # analytical SQL library (01..07)
├── powerbi/
│   ├── dax_measures.md          # ready-to-paste DAX
│   └── build_guide.md           # step-by-step manual build
├── docs/
│   ├── erd.md                   # Mermaid ERD
│   ├── data_quality_notes.md    # what dirty data was injected & how it's cleaned
│   ├── optimization_results.md  # EXPLAIN ANALYZE before/after
│   └── case-study.md            # portfolio write-up
├── scripts/
│   ├── run_all.ps1 / run_all.sh # one-command pipeline
└── PROGRESS.md
```

## How to reproduce

**Prerequisites:** PostgreSQL 17 (service running), Python 3.13, `psql` on PATH.

```powershell
# 1. Generate data (writes data/csv/*.csv)
python data\generate_data.py

# 2. Load everything in one shot (creates db, schema, load, indexes, views, findings)
$env:PGPASSWORD = '<your-postgres-password>'
powershell -File scripts\run_all.ps1
```
or step-by-step:
```powershell
createdb -U postgres foodhub
psql -U postgres -d foodhub -f sql\01_schema.sql
psql -U postgres -d foodhub -v csvdir="$PWD\data\csv" -f sql\02_load_data.sql
psql -U postgres -d foodhub -f sql\03_indexes.sql
psql -U postgres -d foodhub -f sql\04_powerbi_views.sql
```

**Power BI:** follow [`powerbi/build_guide.md`](powerbi/build_guide.md) to build the
dashboard (connect to the `foodhub` DB → import the views → paste the DAX → lay
out 4 pages).

## Dataset at a glance
| Table | Rows |
|---|---|
| customers | ~500 (8 duplicate signups injected) |
| restaurants | 120 |
| menu_items | 3,000 |
| riders | 150 |
| orders | 25,000 |
| order_items | ~75,000 |
| reviews | 12,000 |

Data spans **Jan 2024 – Jun 2026** to support cohort, retention, and YoY analysis.

## Key findings
<!-- KEY_FINDINGS_START -->
_All figures below are from a live run of the Phase 4 queries against the seed-42
dataset (`sql/05_key_findings.sql`) — real numbers, not placeholders. Currency is
the synthetic platform's local unit (₹)._

1. **₹4.95 crore GMV across 20,587 delivered orders**, at an average order value of
   **₹2,405**. Of 25,000 total orders, 82.3% were delivered, 10.0% cancelled, and
   4.8% refunded.

2. **Revenue is heavily repeat-driven — 92.8% of GMV comes from returning
   customers** (orders after a customer's first month). With only ~500 customers,
   retention, not acquisition, is the growth lever. The 90-day churn rate is a low
   **1.0%** (5 customers), reflecting a highly engaged, dense-ordering base.

3. **RFM segmentation concentrates value: 78 "Champions" (15.6% of customers)
   drive 18.6% of revenue**, while 100 "Hibernating / Lost" customers still
   account for 16.8% — a clear win-back opportunity worth targeting.

4. **Delivery SLA is the biggest operational gap: only 55.3% of deliveries beat
   the 45-minute promise**, with an average delivery time of **42.5 minutes**.
   Half of all deliveries are close to or over the SLA line — the clearest lever
   for improving customer experience.

5. **Kolkata is the top market (₹68.4 L), followed by Kochi, Bengaluru, Mumbai and
   Pune** — the top 5 cities are within ~22% of each other, so demand is broad
   rather than concentrated in one hub.

6. **South Indian is the highest-grossing cuisine (₹76.9 L)**, ahead of Beverages,
   Fast Food, Italian and Desserts — useful for menu and partner-acquisition focus.

7. **Strong YoY growth:** delivered revenue rose from ₹76.6 L (2024, 3,193 orders)
   to ₹1.99 Cr (2025, 8,284) to ₹2.20 Cr in 2026 through June alone (9,110 orders)
   — the platform is scaling, with H1-2026 already exceeding all of 2025.

_See [`docs/optimization_results.md`](docs/optimization_results.md) for the query
performance study (EXPLAIN ANALYZE before/after, incl. a 14× index win)._
<!-- KEY_FINDINGS_END -->

## License
Synthetic data; free to use for learning/portfolio purposes.
