-- ============================================================================
-- Key findings — headline numbers for the README / case study.
-- Run after load + views: psql -d foodhub -f sql/05_key_findings.sql
-- ============================================================================
\echo '==================== KEY FINDINGS ===================='

\echo '\n-- [A] Top-line totals'
SELECT
    (SELECT COUNT(*) FROM customers)                                          AS customers,
    (SELECT COUNT(*) FROM restaurants)                                        AS restaurants,
    (SELECT COUNT(*) FROM orders)                                             AS total_orders,
    (SELECT COUNT(*) FROM orders WHERE status='delivered')                    AS delivered_orders,
    ROUND((SELECT SUM(total_amount) FROM orders WHERE status='delivered'),0)  AS total_revenue,
    ROUND((SELECT AVG(total_amount) FROM orders WHERE status='delivered'),2)  AS avg_order_value;

\echo '\n-- [B] Cancellation & refund rate (platform)'
SELECT
    ROUND(100.0*COUNT(*) FILTER (WHERE status='cancelled')/COUNT(*),1) AS cancel_rate_pct,
    ROUND(100.0*COUNT(*) FILTER (WHERE status='refunded')/COUNT(*),1)  AS refund_rate_pct
FROM orders;

\echo '\n-- [C] On-time delivery rate (SLA 45 min, valid times only)'
SELECT COUNT(*) AS valid_deliveries,
       ROUND(100.0*COUNT(*) FILTER (WHERE delivery_time_minutes<=45)/COUNT(*),1) AS on_time_pct,
       ROUND(AVG(delivery_time_minutes),1) AS avg_delivery_minutes
FROM orders
WHERE status='delivered' AND delivery_time_minutes BETWEEN 1 AND 180;

\echo '\n-- [D] Top 5 cities by revenue'
SELECT r.city, COUNT(*) AS orders, ROUND(SUM(o.total_amount),0) AS revenue
FROM orders o JOIN restaurants r ON r.restaurant_id=o.restaurant_id
WHERE o.status='delivered'
GROUP BY r.city ORDER BY revenue DESC LIMIT 5;

\echo '\n-- [E] Top 5 cuisines by revenue'
SELECT r.cuisine_type, COUNT(*) AS orders, ROUND(SUM(o.total_amount),0) AS revenue
FROM orders o JOIN restaurants r ON r.restaurant_id=o.restaurant_id
WHERE o.status='delivered'
GROUP BY r.cuisine_type ORDER BY revenue DESC LIMIT 5;

\echo '\n-- [F] Churn rate (90-day, of customers with >=1 delivered order)'
WITH last_order AS (
    SELECT customer_id, MAX(order_timestamp)::date AS last_dt
    FROM orders WHERE status='delivered' GROUP BY customer_id
), ref AS (SELECT MAX(order_timestamp)::date AS as_of FROM orders WHERE status='delivered')
SELECT COUNT(*) AS customers_with_orders,
       COUNT(*) FILTER (WHERE (SELECT as_of FROM ref)-last_dt>90) AS churned,
       ROUND(100.0*COUNT(*) FILTER (WHERE (SELECT as_of FROM ref)-last_dt>90)/COUNT(*),1) AS churn_rate_pct
FROM last_order;

\echo '\n-- [G] Repeat-customer share of revenue'
WITH fo AS (
    SELECT customer_id, MIN(date_trunc('month',order_timestamp)) AS cohort
    FROM orders WHERE status='delivered' GROUP BY customer_id
), tagged AS (
    SELECT o.total_amount,
           CASE WHEN date_trunc('month',o.order_timestamp)=f.cohort THEN 'new' ELSE 'returning' END AS t
    FROM orders o JOIN fo f ON f.customer_id=o.customer_id
    WHERE o.status='delivered'
)
SELECT ROUND(100.0*SUM(total_amount) FILTER (WHERE t='returning')/SUM(total_amount),1) AS pct_revenue_returning
FROM tagged;

\echo '\n-- [H] RFM segment roll-up (top segments by revenue)'
WITH ref AS (SELECT MAX(order_timestamp)::date AS as_of FROM orders WHERE status='delivered'),
base AS (
  SELECT customer_id,(SELECT as_of FROM ref)-MAX(order_timestamp)::date AS rec,
         COUNT(*) AS freq, SUM(total_amount) AS mon
  FROM orders WHERE status='delivered' GROUP BY customer_id),
scored AS (
  SELECT mon,
         NTILE(5) OVER (ORDER BY rec DESC) r, NTILE(5) OVER (ORDER BY freq) f,
         NTILE(5) OVER (ORDER BY mon) m FROM base),
lab AS (
  SELECT mon, CASE
     WHEN r>=4 AND f>=4 AND m>=4 THEN 'Champions'
     WHEN r>=4 AND f>=3 THEN 'Loyal'
     WHEN r>=4 AND f<=2 THEN 'New / Promising'
     WHEN r=3 AND f>=3 THEN 'Potential Loyalist'
     WHEN r<=2 AND f>=4 THEN 'At Risk'
     WHEN r<=2 AND f<=2 THEN 'Hibernating / Lost'
     ELSE 'Needs Attention' END AS segment FROM scored)
SELECT segment, COUNT(*) AS customers,
       ROUND(100.0*SUM(mon)/SUM(SUM(mon)) OVER (),1) AS pct_revenue
FROM lab GROUP BY segment ORDER BY pct_revenue DESC;

\echo '\n-- [I] Best month (by revenue) + YoY where available'
WITH m AS (
  SELECT date_trunc('month',order_timestamp)::date mo, SUM(total_amount) rev
  FROM orders WHERE status='delivered' GROUP BY 1)
SELECT to_char(mo,'YYYY-MM') AS month, ROUND(rev,0) AS revenue
FROM m ORDER BY rev DESC LIMIT 3;

\echo '==================== END FINDINGS ===================='
