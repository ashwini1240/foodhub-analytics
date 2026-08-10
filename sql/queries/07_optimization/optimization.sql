-- ============================================================================
-- 07 — Query optimization: EXPLAIN ANALYZE before/after
-- Three heavy queries from the library, each shown with a plan before and after
-- an index (or rewrite). Run this file top-to-bottom; the accompanying findings
-- are written up in optimization_results.md (captured from a real seed-42 run).
--
-- Reset to a clean baseline first so "before" plans are honest.
-- ============================================================================

-- Make plans reproducible-ish (still shows real timings).
SET max_parallel_workers_per_gather = 0;

-- ----------------------------------------------------------------------------
-- CASE 1 — Revenue by city (filter status='delivered', join restaurants)
-- Hypothesis: a partial index on delivered orders avoids a full seq scan+filter.
-- ----------------------------------------------------------------------------
DROP INDEX IF EXISTS idx_orders_delivered;
DROP INDEX IF EXISTS idx_orders_status_ts;

\echo '--- CASE 1 BEFORE (no status index) ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT r.city, COUNT(*) AS orders, SUM(o.total_amount) AS revenue
FROM orders o
JOIN restaurants r ON r.restaurant_id = o.restaurant_id
WHERE o.status = 'delivered'
GROUP BY r.city;

CREATE INDEX idx_orders_delivered ON orders (order_timestamp) WHERE status = 'delivered';
ANALYZE orders;

\echo '--- CASE 1 AFTER (partial index on delivered) ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT r.city, COUNT(*) AS orders, SUM(o.total_amount) AS revenue
FROM orders o
JOIN restaurants r ON r.restaurant_id = o.restaurant_id
WHERE o.status = 'delivered'
GROUP BY r.city;

-- ----------------------------------------------------------------------------
-- CASE 2 — Top-3 items per restaurant (order_items -> menu_items -> orders)
-- Hypothesis: an index on order_items(item_id) speeds the join to menu_items,
-- and order_items(order_id) speeds the join back to orders.
-- ----------------------------------------------------------------------------
DROP INDEX IF EXISTS idx_order_items_item;
DROP INDEX IF EXISTS idx_order_items_order;

\echo '--- CASE 2 BEFORE (no order_items FK indexes) ---'
EXPLAIN (ANALYZE, BUFFERS)
WITH item_sales AS (
    SELECT mi.restaurant_id, mi.item_id, SUM(oi.quantity) AS units
    FROM order_items oi
    JOIN orders o      ON o.order_id = oi.order_id AND o.status = 'delivered'
    JOIN menu_items mi ON mi.item_id = oi.item_id
    GROUP BY mi.restaurant_id, mi.item_id
)
SELECT restaurant_id, item_id, units,
       ROW_NUMBER() OVER (PARTITION BY restaurant_id ORDER BY units DESC) AS rn
FROM item_sales;

CREATE INDEX idx_order_items_item  ON order_items (item_id);
CREATE INDEX idx_order_items_order ON order_items (order_id);
ANALYZE order_items;

\echo '--- CASE 2 AFTER (FK indexes on order_items) ---'
EXPLAIN (ANALYZE, BUFFERS)
WITH item_sales AS (
    SELECT mi.restaurant_id, mi.item_id, SUM(oi.quantity) AS units
    FROM order_items oi
    JOIN orders o      ON o.order_id = oi.order_id AND o.status = 'delivered'
    JOIN menu_items mi ON mi.item_id = oi.item_id
    GROUP BY mi.restaurant_id, mi.item_id
)
SELECT restaurant_id, item_id, units,
       ROW_NUMBER() OVER (PARTITION BY restaurant_id ORDER BY units DESC) AS rn
FROM item_sales;

-- ----------------------------------------------------------------------------
-- CASE 3 — Churn scan (MAX(order_timestamp) per customer)
-- Hypothesis: a composite index on orders(customer_id, order_timestamp) lets
-- the aggregate be served from the index (no heap sort of the whole table).
-- ----------------------------------------------------------------------------
DROP INDEX IF EXISTS idx_orders_cust_ts;
DROP INDEX IF EXISTS idx_orders_customer;

\echo '--- CASE 3 BEFORE (no customer index) ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT customer_id, MAX(order_timestamp) AS last_order
FROM orders
WHERE status = 'delivered'
GROUP BY customer_id;

CREATE INDEX idx_orders_cust_ts ON orders (customer_id, order_timestamp);
ANALYZE orders;

\echo '--- CASE 3 AFTER (composite customer_id, order_timestamp) ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT customer_id, MAX(order_timestamp) AS last_order
FROM orders
WHERE status = 'delivered'
GROUP BY customer_id;

-- ----------------------------------------------------------------------------
-- CASE 4 — SELECTIVE lookup: delivered orders for ONE restaurant.
-- Hypothesis: unlike the full-table aggregates above, a selective predicate
-- (one of 120 restaurants ~ 0.6% of rows) SHOULD flip Seq Scan -> Index Scan.
-- This is the case where indexing genuinely pays off.
-- ----------------------------------------------------------------------------
DROP INDEX IF EXISTS idx_orders_restaurant;

\echo '--- CASE 4 BEFORE (no restaurant index) ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT order_id, total_amount FROM orders
WHERE restaurant_id = 42 AND status = 'delivered';

CREATE INDEX idx_orders_restaurant ON orders (restaurant_id);
ANALYZE orders;

\echo '--- CASE 4 AFTER (index on restaurant_id) ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT order_id, total_amount FROM orders
WHERE restaurant_id = 42 AND status = 'delivered';

-- ----------------------------------------------------------------------------
-- Restore the full index set for normal operation.
-- ----------------------------------------------------------------------------
\i sql/03_indexes.sql
SET max_parallel_workers_per_gather TO DEFAULT;
