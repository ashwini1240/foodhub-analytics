-- ============================================================================
-- FoodHub Analytics — Load & Clean pipeline
-- PostgreSQL 17
--
-- Pattern: load raw CSVs into all-TEXT staging tables (so no malformed value
-- can block the import), then CLEAN + CAST into the typed final tables defined
-- in 01_schema.sql. See docs/data_quality_notes.md for what gets cleaned.
--
-- Run from the project root with psql, e.g.:
--   psql -U postgres -h localhost -d foodhub -v csvdir='D:/Projects/foodhub-analytics/data/csv' -f sql/02_load_data.sql
--
-- (The DB itself is created by the runner; see README / run_pipeline notes.)
-- ============================================================================

\set ON_ERROR_STOP on

-- ----------------------------------------------------------------------------
-- 0. Helper: tolerant multi-format date parser.
-- Tries ISO, then DD/MM/YYYY, MM-DD-YYYY, DD-Mon-YYYY, MM/DD/YYYY.
-- Returns NULL on anything unparseable (rather than erroring the load).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION try_parse_date(s TEXT)
RETURNS DATE AS $$
DECLARE
    fmts TEXT[] := ARRAY['YYYY-MM-DD','DD/MM/YYYY','MM-DD-YYYY','DD-Mon-YYYY','MM/DD/YYYY'];
    f TEXT;
    d DATE;
BEGIN
    IF s IS NULL OR btrim(s) = '' THEN
        RETURN NULL;
    END IF;
    -- Fast path: native ISO / timestamp casts.
    BEGIN
        RETURN s::date;
    EXCEPTION WHEN others THEN
        NULL;
    END;
    FOREACH f IN ARRAY fmts LOOP
        BEGIN
            d := to_date(s, f);
            RETURN d;
        EXCEPTION WHEN others THEN
            CONTINUE;
        END;
    END LOOP;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- ----------------------------------------------------------------------------
-- 1. Staging tables (all TEXT)
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS stg_customers, stg_restaurants, stg_menu_items,
                     stg_riders, stg_orders, stg_order_items, stg_reviews CASCADE;

CREATE TABLE stg_customers   (customer_id TEXT, name TEXT, city TEXT, signup_date TEXT, segment TEXT);
CREATE TABLE stg_restaurants (restaurant_id TEXT, name TEXT, cuisine_type TEXT, city TEXT, active_since TEXT, avg_rating TEXT);
CREATE TABLE stg_menu_items  (item_id TEXT, restaurant_id TEXT, name TEXT, category TEXT, price TEXT);
CREATE TABLE stg_riders      (rider_id TEXT, name TEXT, city TEXT, join_date TEXT, vehicle_type TEXT);
CREATE TABLE stg_orders      (order_id TEXT, customer_id TEXT, restaurant_id TEXT, rider_id TEXT,
                              order_timestamp TEXT, status TEXT, payment_method TEXT,
                              total_amount TEXT, delivery_time_minutes TEXT, discount_applied TEXT);
CREATE TABLE stg_order_items (order_item_id TEXT, order_id TEXT, item_id TEXT, quantity TEXT, unit_price TEXT);
CREATE TABLE stg_reviews     (review_id TEXT, order_id TEXT, rating TEXT, review_text TEXT, review_date TEXT);

-- ----------------------------------------------------------------------------
-- 2. Raw load via \copy (client-side; works without server file access).
-- psql cannot concatenate a quoted variable with a suffix in \copy, so we
-- \cd into the CSV directory and use bare filenames. Pass -v csvdir=<abs path>.
-- ----------------------------------------------------------------------------
\cd :csvdir
\copy stg_customers   FROM 'customers.csv'    WITH (FORMAT csv, HEADER true)
\copy stg_restaurants FROM 'restaurants.csv'  WITH (FORMAT csv, HEADER true)
\copy stg_menu_items  FROM 'menu_items.csv'   WITH (FORMAT csv, HEADER true)
\copy stg_riders      FROM 'riders.csv'       WITH (FORMAT csv, HEADER true)
\copy stg_orders      FROM 'orders.csv'       WITH (FORMAT csv, HEADER true)
\copy stg_order_items FROM 'order_items.csv'  WITH (FORMAT csv, HEADER true)
\copy stg_reviews     FROM 'reviews.csv'      WITH (FORMAT csv, HEADER true)

-- ----------------------------------------------------------------------------
-- 3. Clean + cast into final tables
-- ----------------------------------------------------------------------------
TRUNCATE reviews, order_items, orders, menu_items, riders, restaurants, customers RESTART IDENTITY CASCADE;

-- customers: standardise city, parse dates tolerantly, DE-DUPLICATE by (name,city).
INSERT INTO customers (customer_id, name, city, signup_date, segment)
SELECT customer_id, name, city, signup_date, segment
FROM (
    SELECT
        customer_id::int                                       AS customer_id,
        name,
        NULLIF(INITCAP(TRIM(city)), '')                        AS city,
        try_parse_date(signup_date)                            AS signup_date,
        NULLIF(TRIM(segment), '')                              AS segment,
        ROW_NUMBER() OVER (PARTITION BY LOWER(TRIM(name)),
                                        LOWER(TRIM(COALESCE(city,'')))
                           ORDER BY customer_id::int)          AS rn
    FROM stg_customers
) c
WHERE rn = 1;   -- drop duplicate signups, keep the earliest customer_id

-- restaurants
INSERT INTO restaurants (restaurant_id, name, cuisine_type, city, active_since, avg_rating)
SELECT restaurant_id::int, name, NULLIF(TRIM(cuisine_type),''),
       NULLIF(INITCAP(TRIM(city)),''), try_parse_date(active_since),
       NULLIF(avg_rating,'')::numeric
FROM stg_restaurants;

-- menu_items
INSERT INTO menu_items (item_id, restaurant_id, name, category, price)
SELECT item_id::int, restaurant_id::int, name, NULLIF(TRIM(category),''),
       NULLIF(price,'')::numeric
FROM stg_menu_items;

-- riders
INSERT INTO riders (rider_id, name, city, join_date, vehicle_type)
SELECT rider_id::int, name, NULLIF(INITCAP(TRIM(city)),''),
       try_parse_date(join_date), NULLIF(TRIM(vehicle_type),'')
FROM stg_riders;

-- orders: only keep customers/restaurants that survived cleaning; negative
-- delivery times set to NULL (invalid). rider_id nullable for cancelled.
INSERT INTO orders (order_id, customer_id, restaurant_id, rider_id, order_timestamp,
                    status, payment_method, total_amount, delivery_time_minutes, discount_applied)
SELECT o.order_id::int,
       o.customer_id::int,
       o.restaurant_id::int,
       NULLIF(o.rider_id,'')::int,
       o.order_timestamp::timestamp,
       o.status,
       NULLIF(TRIM(o.payment_method),''),
       NULLIF(o.total_amount,'')::numeric,
       CASE WHEN NULLIF(o.delivery_time_minutes,'')::int < 0 THEN NULL
            ELSE NULLIF(o.delivery_time_minutes,'')::int END,
       COALESCE(NULLIF(o.discount_applied,'')::numeric, 0)
FROM stg_orders o
WHERE o.customer_id::int   IN (SELECT customer_id   FROM customers)
  AND o.restaurant_id::int IN (SELECT restaurant_id FROM restaurants);

-- order_items: only for orders that loaded
INSERT INTO order_items (order_item_id, order_id, item_id, quantity, unit_price)
SELECT oi.order_item_id::int, oi.order_id::int, oi.item_id::int,
       oi.quantity::int, NULLIF(oi.unit_price,'')::numeric
FROM stg_order_items oi
WHERE oi.order_id::int IN (SELECT order_id FROM orders);

-- reviews: tolerant date parse, NULL ratings preserved, only for loaded orders
INSERT INTO reviews (review_id, order_id, rating, review_text, review_date)
SELECT r.review_id::int, r.order_id::int,
       NULLIF(r.rating,'')::int, r.review_text, try_parse_date(r.review_date)
FROM stg_reviews r
WHERE r.order_id::int IN (SELECT order_id FROM orders);

-- ----------------------------------------------------------------------------
-- 4. Row-count verification
-- ----------------------------------------------------------------------------
\echo '=== Row counts (final tables) ==='
SELECT 'customers'   AS table, COUNT(*) FROM customers
UNION ALL SELECT 'restaurants', COUNT(*) FROM restaurants
UNION ALL SELECT 'menu_items',  COUNT(*) FROM menu_items
UNION ALL SELECT 'riders',      COUNT(*) FROM riders
UNION ALL SELECT 'orders',      COUNT(*) FROM orders
UNION ALL SELECT 'order_items', COUNT(*) FROM order_items
UNION ALL SELECT 'reviews',     COUNT(*) FROM reviews
ORDER BY 1;

\echo '=== Data-quality sanity checks ==='
SELECT
  (SELECT COUNT(*) FROM customers)                                   AS customers_after_dedup,
  (SELECT 508 - COUNT(*) FROM customers)                            AS dupes_removed,
  (SELECT COUNT(*) FROM restaurants WHERE avg_rating IS NULL)       AS null_ratings,
  (SELECT COUNT(*) FROM reviews WHERE rating IS NULL)               AS null_review_ratings,
  (SELECT COUNT(*) FROM orders WHERE delivery_time_minutes IS NULL) AS null_delivery_times,
  (SELECT COUNT(*) FROM orders WHERE delivery_time_minutes > 180)   AS outlier_delivery_times;
