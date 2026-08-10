-- ============================================================================
-- 02 — Window functions
-- Running totals, ranking, percentiles, top-N per group.
-- ============================================================================

-- Q1. Monthly revenue with running (cumulative) total and MoM growth.
-- Business question: how is cumulative GMV building, month over month?
WITH monthly AS (
    SELECT date_trunc('month', order_timestamp)::date AS month,
           SUM(total_amount)                          AS revenue
    FROM orders
    WHERE status = 'delivered'
    GROUP BY 1
)
SELECT month,
       ROUND(revenue, 2)                                                   AS revenue,
       ROUND(SUM(revenue) OVER (ORDER BY month), 2)                        AS running_total,
       ROUND(revenue - LAG(revenue) OVER (ORDER BY month), 2)             AS mom_change,
       ROUND(100.0 * (revenue - LAG(revenue) OVER (ORDER BY month))
             / NULLIF(LAG(revenue) OVER (ORDER BY month), 0), 1)          AS mom_pct
FROM monthly
ORDER BY month;

-- Q2. Rank restaurants by revenue WITHIN each city (DENSE_RANK partitioned).
-- Business question: who is the #1/#2/#3 restaurant in every city?
-- NOTE: PostgreSQL has no QUALIFY clause, so the window result is wrapped in a
-- CTE and filtered in the outer query.
WITH rest_rev AS (
    SELECT r.city, r.name, SUM(o.total_amount) AS revenue
    FROM restaurants r
    JOIN orders o ON o.restaurant_id = r.restaurant_id AND o.status = 'delivered'
    GROUP BY r.city, r.name
), ranked AS (
    SELECT city, name, revenue,
           DENSE_RANK() OVER (PARTITION BY city ORDER BY revenue DESC) AS city_rank
    FROM rest_rev
)
SELECT city, name, ROUND(revenue, 2) AS revenue, city_rank
FROM ranked
WHERE city_rank <= 3
ORDER BY city, city_rank;

-- Q3. Rider performance percentiles by delivery speed.
-- Business question: how does each rider rank on delivery time (fastest = best)?
-- Uses valid delivery times only (0 < t <= 180 excludes dirty outliers/NULLs).
WITH rider_stats AS (
    SELECT o.rider_id,
           COUNT(*)                          AS deliveries,
           ROUND(AVG(o.delivery_time_minutes), 1) AS avg_minutes
    FROM orders o
    WHERE o.status = 'delivered'
      AND o.rider_id IS NOT NULL
      AND o.delivery_time_minutes BETWEEN 1 AND 180
    GROUP BY o.rider_id
    HAVING COUNT(*) >= 30
)
SELECT rd.name, rd.city, rs.deliveries, rs.avg_minutes,
       NTILE(4)     OVER (ORDER BY rs.avg_minutes)                    AS speed_quartile,
       ROUND((100 * PERCENT_RANK() OVER (ORDER BY rs.avg_minutes))::numeric, 1) AS pct_rank_slowest_first,
       RANK()       OVER (ORDER BY rs.avg_minutes)                    AS fastest_rank
FROM rider_stats rs
JOIN riders rd ON rd.rider_id = rs.rider_id
ORDER BY rs.avg_minutes;

-- Q4. Top-3 best-selling menu items PER restaurant (ROW_NUMBER partitioned).
-- Business question: what should each restaurant never run out of?
WITH item_sales AS (
    SELECT mi.restaurant_id, mi.item_id, mi.name,
           SUM(oi.quantity) AS units
    FROM order_items oi
    JOIN orders o      ON o.order_id = oi.order_id AND o.status = 'delivered'
    JOIN menu_items mi ON mi.item_id = oi.item_id
    GROUP BY mi.restaurant_id, mi.item_id, mi.name
), ranked AS (
    SELECT restaurant_id, name, units,
           ROW_NUMBER() OVER (PARTITION BY restaurant_id ORDER BY units DESC) AS rn
    FROM item_sales
)
SELECT r.name AS restaurant, rk.name AS item, rk.units, rk.rn AS item_rank
FROM ranked rk
JOIN restaurants r ON r.restaurant_id = rk.restaurant_id
WHERE rk.rn <= 3
ORDER BY r.name, rk.rn;

-- Q5. Each customer's order sequence + days since their previous order.
-- Business question: how frequently do repeat customers reorder?
SELECT customer_id, order_id, order_timestamp::date AS order_date,
       ROW_NUMBER() OVER w                                        AS order_seq,
       (order_timestamp::date
        - LAG(order_timestamp::date) OVER w)                      AS days_since_prev
FROM orders
WHERE status = 'delivered'
WINDOW w AS (PARTITION BY customer_id ORDER BY order_timestamp)
ORDER BY customer_id, order_seq
LIMIT 200;
