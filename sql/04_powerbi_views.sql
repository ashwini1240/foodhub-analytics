-- ============================================================================
-- FoodHub Analytics — Power BI star-schema views
-- PostgreSQL 17
--
-- One FACT view (fact_orders, grain = one order) + conformed DIMENSION views.
-- Import these directly via Power BI "Get Data > PostgreSQL". They are
-- denormalized/typed for a clean import model — see powerbi/build_guide.md.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- dim_date — one row per calendar day across the order date range.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW dim_date AS
WITH bounds AS (
    SELECT date_trunc('day', MIN(order_timestamp))::date AS d0,
           date_trunc('day', MAX(order_timestamp))::date AS d1
    FROM orders
)
SELECT d::date                                    AS date_key,
       EXTRACT(YEAR    FROM d)::int               AS year,
       EXTRACT(QUARTER FROM d)::int               AS quarter,
       'Q' || EXTRACT(QUARTER FROM d)::int        AS quarter_name,
       EXTRACT(MONTH   FROM d)::int               AS month_no,
       to_char(d, 'Mon')                          AS month_short,
       to_char(d, 'YYYY-MM')                      AS year_month,
       EXTRACT(DAY     FROM d)::int               AS day_of_month,
       EXTRACT(ISODOW  FROM d)::int               AS iso_weekday,
       to_char(d, 'Dy')                           AS weekday_short,
       (EXTRACT(ISODOW FROM d) >= 6)              AS is_weekend
FROM bounds, generate_series(bounds.d0, bounds.d1, interval '1 day') AS g(d);

-- ----------------------------------------------------------------------------
-- dim_customers
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW dim_customers AS
SELECT c.customer_id,
       c.name           AS customer_name,
       COALESCE(c.city, 'Unknown') AS city,
       c.signup_date,
       to_char(c.signup_date, 'YYYY-MM') AS signup_month,
       COALESCE(c.segment, 'unknown')    AS segment
FROM customers c;

-- ----------------------------------------------------------------------------
-- dim_restaurants
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW dim_restaurants AS
SELECT r.restaurant_id,
       r.name          AS restaurant_name,
       r.cuisine_type,
       COALESCE(r.city, 'Unknown') AS city,
       r.active_since,
       r.avg_rating
FROM restaurants r;

-- ----------------------------------------------------------------------------
-- dim_riders
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW dim_riders AS
SELECT rd.rider_id,
       rd.name        AS rider_name,
       COALESCE(rd.city, 'Unknown') AS city,
       rd.join_date,
       rd.vehicle_type
FROM riders rd;

-- ----------------------------------------------------------------------------
-- dim_menu_items
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW dim_menu_items AS
SELECT mi.item_id,
       mi.name        AS item_name,
       mi.category,
       mi.price       AS list_price,
       mi.restaurant_id,
       r.name         AS restaurant_name
FROM menu_items mi
JOIN restaurants r ON r.restaurant_id = mi.restaurant_id;

-- ----------------------------------------------------------------------------
-- fact_orders — grain = one order. Denormalized keys + measures + flags.
-- rider_key falls back to 0 (a "No Rider" member) for cancelled orders so
-- Power BI relationships stay valid; add a 0-row to dim_riders in Power BI or
-- keep the relationship as single-direction with "assume referential integrity"
-- OFF (documented in the build guide).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW fact_orders AS
SELECT
    o.order_id,
    o.customer_id,
    o.restaurant_id,
    o.rider_id,                                   -- NULL for cancelled orders
    o.order_timestamp,
    o.order_timestamp::date                       AS date_key,
    o.status,
    o.payment_method,
    o.total_amount,
    o.discount_applied,
    -- delivery time cleaned to a sane operational range (dirty values -> NULL)
    CASE WHEN o.delivery_time_minutes BETWEEN 1 AND 180
         THEN o.delivery_time_minutes END         AS delivery_time_minutes,
    -- flags for easy DAX/visual filtering
    (o.status = 'delivered')                                          AS is_delivered,
    (o.status = 'cancelled')                                          AS is_cancelled,
    (o.status = 'delivered' AND o.delivery_time_minutes BETWEEN 1 AND 45) AS is_on_time,
    (o.discount_applied > 0)                                          AS had_discount,
    -- item rollup from order_items
    li.item_count,
    li.total_quantity
FROM orders o
LEFT JOIN (
    SELECT order_id, COUNT(*) AS item_count, SUM(quantity) AS total_quantity
    FROM order_items GROUP BY order_id
) li ON li.order_id = o.order_id;

-- Optional convenience: expose reviews joined to orders as a small fact if
-- sentiment analysis is desired on its own page.
CREATE OR REPLACE VIEW fact_reviews AS
SELECT rv.review_id, rv.order_id, o.customer_id, o.restaurant_id,
       rv.rating, rv.review_date AS date_key
FROM reviews rv
JOIN orders o ON o.order_id = rv.order_id;
