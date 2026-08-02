-- ============================================================================
-- 04 — Cohort analysis, retention curves, churn flag
-- Monthly acquisition cohorts and how they retain over time.
-- ============================================================================

-- Q1. Monthly acquisition cohort sizes.
-- Business question: how many new customers did we acquire each month?
WITH first_order AS (
    SELECT customer_id,
           date_trunc('month', MIN(order_timestamp))::date AS cohort_month
    FROM orders
    WHERE status = 'delivered'
    GROUP BY customer_id
)
SELECT cohort_month, COUNT(*) AS new_customers
FROM first_order
GROUP BY cohort_month
ORDER BY cohort_month;

-- Q2. Cohort retention MATRIX — % of each cohort still ordering N months later.
-- Business question: how does each monthly cohort's retention decay over time?
WITH first_order AS (
    SELECT customer_id,
           date_trunc('month', MIN(order_timestamp)) AS cohort_month
    FROM orders WHERE status = 'delivered'
    GROUP BY customer_id
), activity AS (
    SELECT DISTINCT o.customer_id,
           f.cohort_month,
           date_trunc('month', o.order_timestamp) AS active_month
    FROM orders o
    JOIN first_order f ON f.customer_id = o.customer_id
    WHERE o.status = 'delivered'
), offsets AS (
    SELECT cohort_month,
           -- whole months between cohort and activity month
           (EXTRACT(YEAR  FROM age(active_month, cohort_month)) * 12
          + EXTRACT(MONTH FROM age(active_month, cohort_month)))::int AS month_offset,
           customer_id
    FROM activity
), sizes AS (
    SELECT cohort_month, COUNT(DISTINCT customer_id) AS cohort_size
    FROM first_order GROUP BY cohort_month
)
SELECT o.cohort_month::date AS cohort_month,
       s.cohort_size,
       o.month_offset,
       COUNT(DISTINCT o.customer_id)                                  AS active_customers,
       ROUND(100.0 * COUNT(DISTINCT o.customer_id) / s.cohort_size, 1) AS retention_pct
FROM offsets o
JOIN sizes s ON s.cohort_month = o.cohort_month
GROUP BY o.cohort_month, s.cohort_size, o.month_offset
ORDER BY o.cohort_month, o.month_offset;

-- Q3. Overall retention curve (all cohorts pooled) — the classic decay curve.
-- Business question: platform-wide, what share of customers come back N months
-- after their first order?
WITH first_order AS (
    SELECT customer_id, date_trunc('month', MIN(order_timestamp)) AS cohort_month
    FROM orders WHERE status = 'delivered' GROUP BY customer_id
), activity AS (
    SELECT DISTINCT o.customer_id, f.cohort_month,
           (EXTRACT(YEAR  FROM age(date_trunc('month', o.order_timestamp), f.cohort_month)) * 12
          + EXTRACT(MONTH FROM age(date_trunc('month', o.order_timestamp), f.cohort_month)))::int AS month_offset
    FROM orders o JOIN first_order f ON f.customer_id = o.customer_id
    WHERE o.status = 'delivered'
), total AS (SELECT COUNT(*) AS n FROM first_order)
SELECT month_offset,
       COUNT(DISTINCT customer_id)                                       AS active_customers,
       ROUND(100.0 * COUNT(DISTINCT customer_id) / (SELECT n FROM total), 1) AS pct_of_all_customers
FROM activity
GROUP BY month_offset
ORDER BY month_offset;

-- Q4. Churn flag — customers with no delivered order in the last 90 days.
-- Business question: who has churned (relative to the latest activity in the DB)?
WITH last_order AS (
    SELECT customer_id, MAX(order_timestamp)::date AS last_order_date
    FROM orders WHERE status = 'delivered'
    GROUP BY customer_id
), ref AS (SELECT MAX(order_timestamp)::date AS as_of FROM orders WHERE status='delivered')
SELECT lo.customer_id, c.name, c.segment,
       lo.last_order_date,
       (SELECT as_of FROM ref) - lo.last_order_date AS days_since_last_order,
       CASE WHEN (SELECT as_of FROM ref) - lo.last_order_date > 90
            THEN 'churned' ELSE 'active' END          AS churn_status
FROM last_order lo
JOIN customers c ON c.customer_id = lo.customer_id
ORDER BY days_since_last_order DESC;

-- Q5. Churn rate summary.
-- Business question: what % of our active-at-some-point customers are churned?
WITH last_order AS (
    SELECT customer_id, MAX(order_timestamp)::date AS last_order_date
    FROM orders WHERE status = 'delivered' GROUP BY customer_id
), ref AS (SELECT MAX(order_timestamp)::date AS as_of FROM orders WHERE status='delivered')
SELECT COUNT(*) AS customers_with_orders,
       COUNT(*) FILTER (WHERE (SELECT as_of FROM ref) - last_order_date > 90) AS churned,
       ROUND(100.0 * COUNT(*) FILTER (WHERE (SELECT as_of FROM ref) - last_order_date > 90)
             / COUNT(*), 1)                                                    AS churn_rate_pct
FROM last_order;
