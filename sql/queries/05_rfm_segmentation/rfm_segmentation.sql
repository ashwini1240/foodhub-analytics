-- ============================================================================
-- 05 — RFM segmentation
-- Recency / Frequency / Monetary scoring and human-readable segment labels.
-- ============================================================================

-- Q1. RFM scores (1-5 each) per customer using NTILE quintiles.
-- Business question: score every customer on how recently, how often, and how
-- much they buy.
WITH ref AS (
    SELECT MAX(order_timestamp)::date AS as_of
    FROM orders WHERE status = 'delivered'
), base AS (
    SELECT o.customer_id,
           (SELECT as_of FROM ref) - MAX(o.order_timestamp)::date AS recency_days,
           COUNT(*)                                               AS frequency,
           SUM(o.total_amount)                                    AS monetary
    FROM orders o
    WHERE o.status = 'delivered'
    GROUP BY o.customer_id
), scored AS (
    SELECT customer_id, recency_days, frequency, monetary,
           -- recency: fewer days = better = score 5 (note DESC on recency_days)
           NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score,
           NTILE(5) OVER (ORDER BY frequency)         AS f_score,
           NTILE(5) OVER (ORDER BY monetary)          AS m_score
    FROM base
)
SELECT customer_id, recency_days, frequency, ROUND(monetary, 2) AS monetary,
       r_score, f_score, m_score,
       (r_score::text || f_score::text || m_score::text) AS rfm_cell,
       r_score + f_score + m_score                       AS rfm_total
FROM scored
ORDER BY rfm_total DESC;

-- Q2. Segment labels from RFM scores.
-- Business question: bucket customers into actionable marketing segments.
WITH ref AS (
    SELECT MAX(order_timestamp)::date AS as_of FROM orders WHERE status='delivered'
), base AS (
    SELECT o.customer_id,
           (SELECT as_of FROM ref) - MAX(o.order_timestamp)::date AS recency_days,
           COUNT(*)            AS frequency,
           SUM(o.total_amount) AS monetary
    FROM orders o WHERE o.status='delivered'
    GROUP BY o.customer_id
), scored AS (
    SELECT customer_id, recency_days, frequency, monetary,
           NTILE(5) OVER (ORDER BY recency_days DESC) AS r,
           NTILE(5) OVER (ORDER BY frequency)         AS f,
           NTILE(5) OVER (ORDER BY monetary)          AS m
    FROM base
), labelled AS (
    SELECT *,
        CASE
            WHEN r >= 4 AND f >= 4 AND m >= 4 THEN 'Champions'
            WHEN r >= 4 AND f >= 3            THEN 'Loyal'
            WHEN r >= 4 AND f <= 2            THEN 'New / Promising'
            WHEN r = 3  AND f >= 3            THEN 'Potential Loyalist'
            WHEN r <= 2 AND f >= 4            THEN 'At Risk'
            WHEN r <= 2 AND f >= 3 AND m >= 4 THEN 'Cant Lose Them'
            WHEN r <= 2 AND f <= 2            THEN 'Hibernating / Lost'
            ELSE 'Needs Attention'
        END AS segment
    FROM scored
)
SELECT customer_id, recency_days, frequency, ROUND(monetary,2) AS monetary,
       r, f, m, segment
FROM labelled
ORDER BY segment, monetary DESC;

-- Q3. Segment roll-up: size, revenue share, and average value per segment.
-- Business question: which segments hold the most value and deserve budget?
WITH ref AS (
    SELECT MAX(order_timestamp)::date AS as_of FROM orders WHERE status='delivered'
), base AS (
    SELECT o.customer_id,
           (SELECT as_of FROM ref) - MAX(o.order_timestamp)::date AS recency_days,
           COUNT(*) AS frequency, SUM(o.total_amount) AS monetary
    FROM orders o WHERE o.status='delivered' GROUP BY o.customer_id
), scored AS (
    SELECT customer_id, monetary, frequency,
           NTILE(5) OVER (ORDER BY recency_days DESC) AS r,
           NTILE(5) OVER (ORDER BY frequency)         AS f,
           NTILE(5) OVER (ORDER BY monetary)          AS m
    FROM base
), labelled AS (
    SELECT customer_id, monetary, frequency,
        CASE
            WHEN r >= 4 AND f >= 4 AND m >= 4 THEN 'Champions'
            WHEN r >= 4 AND f >= 3            THEN 'Loyal'
            WHEN r >= 4 AND f <= 2            THEN 'New / Promising'
            WHEN r = 3  AND f >= 3            THEN 'Potential Loyalist'
            WHEN r <= 2 AND f >= 4            THEN 'At Risk'
            WHEN r <= 2 AND f >= 3 AND m >= 4 THEN 'Cant Lose Them'
            WHEN r <= 2 AND f <= 2            THEN 'Hibernating / Lost'
            ELSE 'Needs Attention'
        END AS segment
    FROM scored
)
SELECT segment,
       COUNT(*)                                                        AS customers,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)             AS pct_customers,
       ROUND(SUM(monetary), 2)                                         AS total_revenue,
       ROUND(100.0 * SUM(monetary) / SUM(SUM(monetary)) OVER (), 1)   AS pct_revenue,
       ROUND(AVG(monetary), 2)                                         AS avg_revenue_per_customer,
       ROUND(AVG(frequency), 1)                                        AS avg_orders
FROM labelled
GROUP BY segment
ORDER BY total_revenue DESC;
