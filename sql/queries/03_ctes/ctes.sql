-- ============================================================================
-- 03 — Common Table Expressions (CTEs), including a recursive CTE
-- Multi-step readable pipelines + one recursive example.
-- ============================================================================

-- Q1. Multi-step CTE: per-city, compare each restaurant's AOV to the city AOV.
-- Business question: which restaurants over/under-index on order value vs. their
-- local market?
WITH order_rev AS (           -- step 1: delivered revenue per restaurant
    SELECT restaurant_id, COUNT(*) AS orders, SUM(total_amount) AS revenue
    FROM orders
    WHERE status = 'delivered'
    GROUP BY restaurant_id
), enriched AS (              -- step 2: attach city + AOV
    SELECT r.restaurant_id, r.name, r.city,
           orv.orders, orv.revenue,
           orv.revenue / NULLIF(orv.orders, 0) AS aov
    FROM order_rev orv
    JOIN restaurants r ON r.restaurant_id = orv.restaurant_id
), city_aov AS (             -- step 3: city benchmark
    SELECT city, AVG(aov) AS city_avg_aov
    FROM enriched
    GROUP BY city
)
SELECT e.name, e.city, e.orders,
       ROUND(e.aov, 2)                              AS restaurant_aov,
       ROUND(c.city_avg_aov, 2)                     AS city_avg_aov,
       ROUND(100.0 * (e.aov - c.city_avg_aov)
             / NULLIF(c.city_avg_aov, 0), 1)        AS pct_vs_city
FROM enriched e
JOIN city_aov c ON c.city = e.city
WHERE e.orders >= 50
ORDER BY pct_vs_city DESC
LIMIT 25;

-- Q2. Multi-step CTE: new vs. returning revenue split per month.
-- Business question: how much monthly GMV comes from first-time vs repeat buyers?
WITH first_order AS (        -- each customer's first delivered order month
    SELECT customer_id,
           MIN(date_trunc('month', order_timestamp)) AS cohort_month
    FROM orders WHERE status = 'delivered'
    GROUP BY customer_id
), tagged AS (
    SELECT o.order_id,
           date_trunc('month', o.order_timestamp) AS order_month,
           o.total_amount,
           CASE WHEN date_trunc('month', o.order_timestamp) = f.cohort_month
                THEN 'new' ELSE 'returning' END      AS customer_type
    FROM orders o
    JOIN first_order f ON f.customer_id = o.customer_id
    WHERE o.status = 'delivered'
)
SELECT order_month::date AS month,
       ROUND(SUM(total_amount) FILTER (WHERE customer_type = 'new'), 2)       AS new_revenue,
       ROUND(SUM(total_amount) FILTER (WHERE customer_type = 'returning'), 2) AS returning_revenue,
       ROUND(100.0 * SUM(total_amount) FILTER (WHERE customer_type = 'returning')
             / NULLIF(SUM(total_amount), 0), 1)                              AS pct_returning
FROM tagged
GROUP BY order_month
ORDER BY order_month;

-- Q3. RECURSIVE CTE — menu-category taxonomy roll-up.
-- Business question: roll flat menu categories into higher-level department
-- groups and report revenue at every level of the tree.
--
-- NOTE ON THE SCHEMA: our menu_items.category column is FLAT — the schema stores
-- no parent/child hierarchy, so there is no stored tree to recurse over. To still
-- demonstrate a genuine recursive CTE, we define a small category->department
-- taxonomy inline and walk it top-down. (If a self-referencing category table
-- with parent_id existed, the same WITH RECURSIVE pattern would traverse it.)
WITH RECURSIVE taxonomy(node, parent, level) AS (
    -- Level 0: departments (roots have no parent)
    VALUES
        ('Food',      NULL, 0),
        ('Drinks',    NULL, 0),
        -- Level 1: category -> department
        ('Starters',      'Food',   1),
        ('Main Course',   'Food',   1),
        ('Breads',        'Food',   1),
        ('Rice & Biryani','Food',   1),
        ('Sides',         'Food',   1),
        ('Combos',        'Food',   1),
        ('Desserts',      'Food',   1),
        ('Beverages',     'Drinks', 1)
),
tree AS (                              -- recursive walk from roots down
    SELECT node, parent, level, node AS root
    FROM taxonomy WHERE parent IS NULL
    UNION ALL
    SELECT t.node, t.parent, t.level, tr.root
    FROM taxonomy t
    JOIN tree tr ON t.parent = tr.node
),
cat_rev AS (                           -- revenue per leaf category
    SELECT mi.category,
           SUM(oi.quantity * oi.unit_price) AS revenue
    FROM order_items oi
    JOIN orders o      ON o.order_id = oi.order_id AND o.status = 'delivered'
    JOIN menu_items mi ON mi.item_id = oi.item_id
    GROUP BY mi.category
)
SELECT COALESCE(t.root, 'Uncategorised') AS department,
       cr.category,
       ROUND(cr.revenue, 2)              AS category_revenue,
       ROUND(SUM(cr.revenue) OVER (PARTITION BY t.root), 2) AS department_revenue
FROM cat_rev cr
LEFT JOIN tree t ON t.node = cr.category AND t.level = 1
ORDER BY department_revenue DESC NULLS LAST, category_revenue DESC;

-- Q4. RECURSIVE CTE — generate a continuous month spine.
-- Business question: build a gap-free month axis (useful so reports show months
-- with zero orders instead of skipping them). Demonstrates recursion for series
-- generation (equivalent to generate_series, shown here as the recursive idiom).
WITH RECURSIVE months(m) AS (
    SELECT date '2024-01-01'
    UNION ALL
    SELECT (m + interval '1 month')::date
    FROM months
    WHERE m < date '2026-06-01'
)
SELECT m AS month,
       COALESCE(COUNT(o.order_id), 0)                         AS orders,
       ROUND(COALESCE(SUM(o.total_amount) FILTER (WHERE o.status='delivered'), 0), 2) AS revenue
FROM months
LEFT JOIN orders o ON date_trunc('month', o.order_timestamp) = m
GROUP BY m
ORDER BY m;
