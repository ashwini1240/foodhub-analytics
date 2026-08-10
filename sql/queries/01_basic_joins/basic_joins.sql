-- ============================================================================
-- 01 — Basic joins, aggregations, filtering
-- Core relational patterns against the FoodHub schema.
-- ============================================================================

-- Q1. Revenue and order volume by city (delivered orders only).
-- Business question: which cities drive the most GMV?
SELECT r.city,
       COUNT(*)                       AS delivered_orders,
       ROUND(SUM(o.total_amount), 2)  AS revenue,
       ROUND(AVG(o.total_amount), 2)  AS avg_order_value
FROM orders o
JOIN restaurants r ON r.restaurant_id = o.restaurant_id
WHERE o.status = 'delivered'
GROUP BY r.city
ORDER BY revenue DESC;

-- Q2. Top 15 restaurants by revenue, with cuisine and rating.
-- Business question: who are our highest-grossing partners?
SELECT r.restaurant_id, r.name, r.cuisine_type, r.city, r.avg_rating,
       COUNT(o.order_id)              AS orders,
       ROUND(SUM(o.total_amount), 2)  AS revenue
FROM restaurants r
JOIN orders o ON o.restaurant_id = r.restaurant_id AND o.status = 'delivered'
GROUP BY r.restaurant_id
ORDER BY revenue DESC
LIMIT 15;

-- Q3. Revenue by cuisine type.
-- Business question: which cuisines are most commercially important?
SELECT r.cuisine_type,
       COUNT(o.order_id)              AS orders,
       ROUND(SUM(o.total_amount), 2)  AS revenue,
       ROUND(AVG(rev.rating), 2)      AS avg_review_rating
FROM restaurants r
JOIN orders o   ON o.restaurant_id = r.restaurant_id AND o.status = 'delivered'
LEFT JOIN reviews rev ON rev.order_id = o.order_id AND rev.rating IS NOT NULL
GROUP BY r.cuisine_type
ORDER BY revenue DESC;

-- Q4. Payment-method mix.
-- Business question: how do customers pay, and does AOV differ by method?
SELECT payment_method,
       COUNT(*)                                                        AS orders,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)             AS pct_of_orders,
       ROUND(AVG(total_amount), 2)                                     AS avg_order_value
FROM orders
WHERE status = 'delivered' AND payment_method IS NOT NULL
GROUP BY payment_method
ORDER BY orders DESC;

-- Q5. Customers who have never placed a delivered order (LEFT JOIN + NULL filter).
-- Business question: which signed-up customers have zero completed orders?
SELECT c.customer_id, c.name, c.city, c.signup_date, c.segment
FROM customers c
LEFT JOIN orders o
       ON o.customer_id = c.customer_id AND o.status = 'delivered'
WHERE o.order_id IS NULL
ORDER BY c.signup_date;

-- Q6. Most popular menu items by units sold (join through order_items).
-- Business question: what are our best-selling items platform-wide?
SELECT mi.name, mi.category, r.name AS restaurant,
       SUM(oi.quantity)                       AS units_sold,
       ROUND(SUM(oi.quantity * oi.unit_price), 2) AS item_revenue
FROM order_items oi
JOIN orders o     ON o.order_id = oi.order_id AND o.status = 'delivered'
JOIN menu_items mi ON mi.item_id = oi.item_id
JOIN restaurants r ON r.restaurant_id = mi.restaurant_id
GROUP BY mi.item_id, mi.name, mi.category, r.name
ORDER BY units_sold DESC
LIMIT 20;

-- Q7. Average rating and review count per restaurant (only rated reviews).
-- Business question: which restaurants have the best/worst customer sentiment?
SELECT r.name, r.city, r.cuisine_type,
       COUNT(rev.review_id)          AS reviews,
       ROUND(AVG(rev.rating), 2)     AS avg_customer_rating
FROM restaurants r
JOIN orders o    ON o.restaurant_id = r.restaurant_id
JOIN reviews rev ON rev.order_id = o.order_id AND rev.rating IS NOT NULL
GROUP BY r.restaurant_id
HAVING COUNT(rev.review_id) >= 20
ORDER BY avg_customer_rating DESC
LIMIT 20;
