-- ============================================================================
-- FoodHub Analytics — Indexes
-- PostgreSQL 17
--
-- Each index is justified by a concrete query pattern in sql/queries/.
-- PK indexes are created automatically; these target the JOIN/FILTER/ORDER
-- columns exercised by the analytical library.
-- ============================================================================

-- FK join columns on the central fact table (orders is joined from every dir).
-- Used by: 01_basic_joins, 02_window_functions, 04_cohort, 05_rfm, 06_kpis.
CREATE INDEX IF NOT EXISTS idx_orders_customer     ON orders (customer_id);
CREATE INDEX IF NOT EXISTS idx_orders_restaurant   ON orders (restaurant_id);
CREATE INDEX IF NOT EXISTS idx_orders_rider        ON orders (rider_id);

-- Time-series slicing (cohorts, running totals, MoM/YoY, KPIs by month).
-- Used by: 02_window_functions (running revenue), 04_cohort_and_retention.
CREATE INDEX IF NOT EXISTS idx_orders_timestamp    ON orders (order_timestamp);

-- Status filtering: nearly every revenue/KPI query filters status='delivered'.
-- Partial + composite so the planner can serve "delivered orders in a window".
-- Used by: 06_operational_kpis, 05_rfm, revenue queries.
CREATE INDEX IF NOT EXISTS idx_orders_status_ts    ON orders (status, order_timestamp);
CREATE INDEX IF NOT EXISTS idx_orders_delivered    ON orders (order_timestamp)
    WHERE status = 'delivered';

-- order_items -> orders/menu_items joins and per-item aggregation.
-- Used by: top-N items per restaurant, basket/revenue rollups.
CREATE INDEX IF NOT EXISTS idx_order_items_order   ON order_items (order_id);
CREATE INDEX IF NOT EXISTS idx_order_items_item    ON order_items (item_id);

-- menu_items by restaurant (top-N items per restaurant, menu rollups).
CREATE INDEX IF NOT EXISTS idx_menu_items_rest     ON menu_items (restaurant_id);

-- reviews by order (join to orders) and rating aggregation.
CREATE INDEX IF NOT EXISTS idx_reviews_order       ON reviews (order_id);

-- restaurant / rider "by city" ranking queries (window fns partitioned by city).
CREATE INDEX IF NOT EXISTS idx_restaurants_city    ON restaurants (city);
CREATE INDEX IF NOT EXISTS idx_riders_city         ON riders (city);

ANALYZE;
