# PROGRESS

Build log for the FoodHub Analytics portfolio project. Updated per phase.

## Status snapshot — ALL PHASES COMPLETE ✅
| Phase | Description | Status |
|---|---|---|
| 1 | Schema design | ✅ Done |
| 2 | Synthetic data generation | ✅ Done |
| 3 | Load into PostgreSQL | ✅ Done — DB `foodhub` loaded, counts verified |
| 4 | Analytical SQL library | ✅ Done — all files validated error-free vs live DB |
| 5 | Power BI prep (views, DAX, build guide) | ✅ Done — **build_guide ready for manual step** |
| 6 | Documentation (README + real key findings) | ✅ Done |
| 7 | Portfolio case study | ✅ Done |

**Only remaining manual step (yours): build the .pbix in Power BI Desktop via
`powerbi/build_guide.md`.** The `foodhub` database is loaded and the star-schema
views are ready to import.

### Verified load (seed 42)
customers 500 (8 dupes removed), restaurants 120, menu_items 3000, riders 150,
orders 25000, order_items 75211, reviews 12000.

### Real headline numbers (from sql/05_key_findings.sql)
GMV ₹4.95 Cr / 20,587 delivered · AOV ₹2,405 · cancel 10.0% · on-time 55.3%
(avg 42.5 min) · 92.8% revenue from returning customers · churn 1.0% ·
Champions 78 cust = 18.6% rev · top city Kolkata · top cuisine South Indian ·
YoY ₹76.6L→₹1.99Cr→₹2.20Cr (2024→2025→H1-2026).

### Optimization study (docs/optimization_results.md)
4 EXPLAIN ANALYZE cases: Cases 1-3 show indexes correctly ignored on
large-fraction scans; Case 4 shows a ~14× win (2.75ms→0.19ms) on a selective
predicate. Honest, interview-worthy result.

### Fixes made during validation
- `02_load_data.sql`: `\copy` can't concat a quoted path variable → switched to
  `\cd :csvdir` + bare filenames.
- `02_window_functions`: `ROUND(double, int)` → cast `PERCENT_RANK()` to numeric.
- `02_window_functions`: removed an illustrative `QUALIFY` (not valid in Postgres).

## Environment notes / decisions made on your behalf
- **Project folder:** `D:\Projects\foodhub-analytics`, fresh git repo (`git init`).
- **psycopg2 is blocked** by a Windows Application Control policy on this machine
  (native DLL load denied). Decision: **load via `psql \copy`** (a signed binary
  that works), not a Python DB driver. The Python script only generates CSVs.
- **Postgres service** was stopped and needs admin to start — you started it. 👍
- **Cleaning strategy:** CSVs load into all-TEXT **staging** tables first, then a
  clean/cast step populates the typed final tables. This is what lets us inject
  dirty data (bad date formats, dupes) without breaking the import, and showcases
  cleaning skill. See `docs/data_quality_notes.md`.
- **Recursive CTE:** the schema has no stored hierarchy (flat `category` column),
  so `03_ctes` demonstrates recursion two honest ways — an inline
  category→department taxonomy roll-up and a recursive month spine — with a note
  explaining the schema has no self-referencing tree. (Requirement said "skip and
  note why if no natural hierarchy"; we did better and demonstrated it anyway.)

## Phase 1 — Schema ✅
- `sql/01_schema.sql`: 7 tables, PK/FK constraints, CHECK constraints, nullable
  `rider_id` for cancelled orders. `delivery_time_minutes` intentionally
  unconstrained so dirty outliers can live in staging.
- `docs/erd.md`: Mermaid ERD + relationship notes.

## Phase 2 — Data generation ✅
- `data/generate_data.py` (Faker, seed 42). Generated:
  customers 508 (500 + 8 dupes), restaurants 120, menu_items 3000, riders 150,
  orders 25000, order_items 75211, reviews 12000.
- Dirty data injected + documented in `docs/data_quality_notes.md`
  (NULL ratings, dupe signups, non-ISO dates, negative/300-600min delivery times,
  orphaned rider links on cancels, city casing/whitespace).

## Phase 3 — Load ⏳
- `sql/02_load_data.sql`: staging + `try_parse_date()` + clean/cast + row-count
  verification. Ready to run; **needs the Postgres password**.
- `sql/03_indexes.sql`: indexes justified against Phase 4 query patterns.

## Phase 4 — SQL library ✅ (written; to be executed once DB is up)
- `01_basic_joins/` — 7 queries (revenue by city, top restaurants, cuisine,
  payment mix, zero-order customers, popular items, sentiment).
- `02_window_functions/` — running totals + MoM, city ranking, rider percentiles
  (NTILE/PERCENT_RANK), top-N items per restaurant, reorder gap.
- `03_ctes/` — multi-step CTEs (AOV vs city, new/returning split) + 2 recursive.
- `04_cohort_and_retention/` — cohort sizes, retention matrix, pooled curve,
  churn flag (90-day), churn rate.
- `05_rfm_segmentation/` — RFM quintile scores, segment labels, segment roll-up.
- `06_operational_kpis/` — on-time rate (ROLLUP), speed p50/p90 by city, rider
  leaderboard, cancel/refund rate, vehicle perf, peak hours.
- `07_optimization/` — 3 EXPLAIN ANALYZE before/after cases (results pending run).

## Phase 5 — Power BI prep ✅
- `sql/04_powerbi_views.sql`: `fact_orders`, `fact_reviews`, `dim_customers`,
  `dim_restaurants`, `dim_riders`, `dim_menu_items`, `dim_date`.
- `powerbi/dax_measures.md`: ~30 measures (revenue, YoY/MoM, retention, RFM, SLAs).
- `powerbi/build_guide.md`: **step-by-step manual build (the one thing you do).**

## Remaining / next
1. Get Postgres password → create DB, run load, verify counts (Phase 3).
2. Run Phase 4 queries → capture real numbers.
3. Fill `07_optimization` results into `optimization_results.md`.
4. Write `README.md` key-findings + `docs/case-study.md` with real numbers.

## Cut / deferred (if time runs short)
- Actual `.pbix` is manual (by design — can't be scripted).
- Screenshots for README/case study depend on you building the .pbix.
