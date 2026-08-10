# Data Quality Notes

The synthetic dataset (`data/generate_data.py`, seed `42`) **deliberately injects
realistic data-quality issues** so the loading/cleaning layer can demonstrate
data-cleaning skills. The load pipeline (`sql/02_load_data.sql`) loads every CSV
into an all-`TEXT` **staging** table first, then cleans and casts into the typed
final tables — the standard pattern for handling dirty source files.

Exact counts below are from the seed-42 run and are reproducible.

## Injected issues by table

### `customers` (508 raw rows for 500 real customers)
| Issue | Where | Count | Cleaning applied |
|---|---|---|---|
| **Duplicate signups** — same person, new `customer_id`, near-identical name/city/date | end of file (ids 501–508) | 8 | Flagged via `ROW_NUMBER()` over (name, city); kept lowest id, dupes excluded from load. |
| **Non-ISO `signup_date`** — `DD/MM/YYYY`, `MM-DD-YYYY`, `DD-Mon-YYYY` | 3 of the duplicate rows | 3 | Multi-format parse in cleaning step; unparseable → `NULL`. |
| **NULL city** | random ~4% | ~20 | Loaded as `NULL`; left as-is (legitimately unknown). |
| **City casing / trailing whitespace** — `mumbai`, `MUMBAI`, `Mumbai ` | random ~3% | ~15 | `INITCAP(TRIM(city))` standardisation on load. |

### `restaurants`
| Issue | Count | Cleaning |
|---|---|---|
| **NULL `avg_rating`** | 6 | Loaded as `NULL`; excluded from rating aggregates via `WHERE ... IS NOT NULL`. |

### `orders`
| Issue | Count | Cleaning |
|---|---|---|
| **Negative `delivery_time_minutes`** (delivered orders) | 98 | Treated as invalid → set `NULL` and excluded from delivery-time KPIs. |
| **Outlier `delivery_time_minutes`** 300–600 min | 124 | Retained but flagged; excluded from SLA averages via a sane-range filter (`0 < t <= 180`). |
| **NULL `delivery_time_minutes`** on delivered orders | 111 | Left `NULL`; excluded from delivery KPIs. |
| **Orphaned rider link** — cancelled orders have `NULL rider_id` + `NULL delivery_time` | all cancelled (~10%) | Expected business rule (no rider assigned); handled by nullable FK. |
| **Zeroed `total_amount`** on ~50% of cancelled orders | ~half of cancelled | Revenue queries exclude non-`delivered` statuses. |

### `reviews`
| Issue | Count | Cleaning |
|---|---|---|
| **NULL `rating`** | 594 | Loaded as `NULL`; excluded from average-rating and rating-distribution queries. |
| **Non-ISO `review_date`** — `DD/MM/YYYY`, `MM/DD/YYYY` | 180 | Multi-format parse; unparseable → `NULL`. |

## Cleaning strategy summary
1. **Stage as TEXT** — every column loaded as text so no malformed value blocks the import.
2. **Parse dates defensively** — a helper (`try_parse_date`) attempts ISO first, then
   `DD/MM/YYYY`, `MM-DD-YYYY`, `DD-Mon-YYYY`, `MM/DD/YYYY`; failures become `NULL`.
3. **Standardise text** — `INITCAP(TRIM(...))` on city names.
4. **De-duplicate** — window function over natural key, keep first occurrence.
5. **Range-guard numerics** — negative/out-of-range delivery times excluded from
   operational KPIs rather than deleted (kept for a "data quality" callout).
6. **Reconcile totals** — `total_amount` is trusted only for `delivered` orders.
