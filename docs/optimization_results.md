# Query Optimization — EXPLAIN ANALYZE, before / after

All figures below are from a **real run** against the seed-42 dataset
(25,000 orders / 75,211 order_items) on PostgreSQL 17, with
`max_parallel_workers_per_gather = 0` for stable, comparable plans.
Reproduce with `sql/queries/07_optimization/optimization.sql`.

**Headline lesson:** indexes are not free wins. For queries that read a *large
fraction* of a *small* table, a sequential scan is already optimal and the
planner correctly ignores an index. Indexes pay off on **selective** predicates.
Cases 1–3 demonstrate the first point; Case 4 demonstrates the second.

---

## Case 1 — Revenue by city (`status = 'delivered'`, join restaurants)
A partial index on delivered orders was hypothesized to help.

| | Plan | Execution time |
|---|---|---|
| **Before** | Seq Scan on orders (20,587 rows) → HashAggregate | **11.36 ms** |
| **After** (`idx_orders_delivered` partial) | **Unchanged** — Seq Scan → HashAggregate | 10.41 ms |

**Why no change:** `delivered` is ~82% of all orders. Reading 82% of a 585-page
table via an index (random I/O + heap fetches) is more expensive than a straight
sequential scan, so the planner keeps the Seq Scan. Correct decision.

## Case 2 — Top-3 items per restaurant (order_items → orders → menu_items)
FK indexes on `order_items(item_id)` and `order_items(order_id)` were added.

| | Plan | Execution time |
|---|---|---|
| **Before** | Seq Scans + HashAggregate + Sort | **41.7 ms** |
| **After** (FK indexes) | **Unchanged** — hash joins over full scans | 44.5 ms |

**Why no change:** the query aggregates *every* delivered line item, so it must
read the whole `order_items` table regardless. A hash join over sequential scans
is the right plan for a full-table join; nested-loop index lookups would be slower
here. The indexes remain valuable for *point* lookups (see Case 4), just not for
this full aggregation.

## Case 3 — Last order per customer (`MAX(order_timestamp)` grouped)
A composite `orders(customer_id, order_timestamp)` index was hypothesized to
enable an index-only aggregate.

| | Plan | Execution time |
|---|---|---|
| **Before** | Seq Scan → HashAggregate (500 groups) | **5.91 ms** |
| **After** (composite index) | **Unchanged** — Seq Scan → HashAggregate | 5.48 ms |

**Why no change:** with only 500 distinct customers across 20,587 delivered rows,
a hash aggregate over a sequential scan is cheap and the planner sees no benefit
in an index scan. (On a table with millions of customers and a covering index,
this would flip to an index-only scan — the pattern still matters at scale.)

---

## Case 4 — Selective lookup: delivered orders for ONE restaurant ✅ index wins
`WHERE restaurant_id = 42 AND status = 'delivered'` — ~0.6% of rows.

| | Plan | Rows removed by filter | Execution time |
|---|---|---|---|
| **Before** (no index) | **Seq Scan on orders** | 24,847 | **2.75 ms** |
| **After** (`idx_orders_restaurant`) | **Bitmap Index Scan → Bitmap Heap Scan** | 40 | **0.19 ms** |

**Result: ~14× faster (2.75 ms → 0.19 ms).** The selective predicate matches
only 153 of 25,000 rows, so the index lets Postgres jump straight to the ~193
candidate rows instead of scanning and discarding 24,847. This is the textbook
case where an index earns its keep.

---

## Takeaways
1. **Selectivity decides everything.** Index a column when queries filter it down
   to a small fraction of rows (Case 4), not when they scan most of the table
   (Cases 1–3).
2. **Small tables hide index benefits.** At 25k rows the whole `orders` table is
   ~585 pages — trivial to scan. The same queries on millions of rows would
   behave very differently; the indexes in `sql/03_indexes.sql` are sized for that
   growth (FK joins, status+time filtering, per-city ranking).
3. **Trust the planner, but verify with `EXPLAIN ANALYZE`.** Adding an index and
   assuming a speedup is a common mistake — three of four hypotheses here were
   "wrong" in a useful way.
