-- ============================================================================
-- 06 — Operational KPIs
-- Delivery SLAs, speed by city/rider, cancellation & refund rates.
-- Dirty delivery times (negative -> already NULL on load; >180 min outliers)
-- are excluded from SLA metrics via a sane-range filter.
-- ============================================================================

-- Q1. On-time delivery rate (SLA = 45 minutes), platform-wide and by city.
-- Business question: what share of deliveries meet our 45-minute promise?
SELECT r.city,
       COUNT(*)                                                             AS valid_deliveries,
       COUNT(*) FILTER (WHERE o.delivery_time_minutes <= 45)                AS on_time,
       ROUND(100.0 * COUNT(*) FILTER (WHERE o.delivery_time_minutes <= 45)
             / COUNT(*), 1)                                                 AS on_time_pct
FROM orders o
JOIN restaurants r ON r.restaurant_id = o.restaurant_id
WHERE o.status = 'delivered'
  AND o.delivery_time_minutes BETWEEN 1 AND 180   -- exclude dirty/outlier times
GROUP BY ROLLUP (r.city)                            -- ROLLUP adds a grand-total row
ORDER BY r.city NULLS LAST;

-- Q2. Average / median / p90 delivery time by city.
-- Business question: where are deliveries slowest, and how bad is the tail?
SELECT r.city,
       COUNT(*)                                                            AS deliveries,
       ROUND(AVG(o.delivery_time_minutes), 1)                             AS avg_minutes,
       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY o.delivery_time_minutes) AS median_minutes,
       PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY o.delivery_time_minutes) AS p90_minutes
FROM orders o
JOIN restaurants r ON r.restaurant_id = o.restaurant_id
WHERE o.status = 'delivered'
  AND o.delivery_time_minutes BETWEEN 1 AND 180
GROUP BY r.city
ORDER BY avg_minutes DESC;

-- Q3. Rider leaderboard — fastest riders with >= 30 valid deliveries.
-- Business question: who are our most efficient delivery partners?
SELECT rd.name, rd.city, rd.vehicle_type,
       COUNT(*)                               AS deliveries,
       ROUND(AVG(o.delivery_time_minutes), 1) AS avg_minutes,
       ROUND(100.0 * COUNT(*) FILTER (WHERE o.delivery_time_minutes <= 45)
             / COUNT(*), 1)                   AS on_time_pct
FROM orders o
JOIN riders rd ON rd.rider_id = o.rider_id
WHERE o.status = 'delivered'
  AND o.delivery_time_minutes BETWEEN 1 AND 180
GROUP BY rd.rider_id, rd.name, rd.city, rd.vehicle_type
HAVING COUNT(*) >= 30
ORDER BY avg_minutes ASC
LIMIT 20;

-- Q4. Order cancellation & refund rate by city.
-- Business question: where are we losing orders to cancellations/refunds?
SELECT r.city,
       COUNT(*)                                                          AS total_orders,
       COUNT(*) FILTER (WHERE o.status = 'delivered')                    AS delivered,
       COUNT(*) FILTER (WHERE o.status = 'cancelled')                    AS cancelled,
       COUNT(*) FILTER (WHERE o.status = 'refunded')                     AS refunded,
       ROUND(100.0 * COUNT(*) FILTER (WHERE o.status = 'cancelled')
             / COUNT(*), 1)                                              AS cancel_rate_pct,
       ROUND(100.0 * COUNT(*) FILTER (WHERE o.status = 'refunded')
             / COUNT(*), 1)                                              AS refund_rate_pct
FROM orders o
JOIN restaurants r ON r.restaurant_id = o.restaurant_id
GROUP BY r.city
ORDER BY cancel_rate_pct DESC;

-- Q5. Delivery performance by vehicle type.
-- Business question: which vehicle types deliver fastest?
SELECT rd.vehicle_type,
       COUNT(*)                               AS deliveries,
       ROUND(AVG(o.delivery_time_minutes), 1) AS avg_minutes,
       ROUND(100.0 * COUNT(*) FILTER (WHERE o.delivery_time_minutes <= 45)
             / COUNT(*), 1)                   AS on_time_pct
FROM orders o
JOIN riders rd ON rd.rider_id = o.rider_id
WHERE o.status = 'delivered'
  AND o.delivery_time_minutes BETWEEN 1 AND 180
GROUP BY rd.vehicle_type
ORDER BY avg_minutes;

-- Q6. Hourly order volume heat-strip (peak-hours analysis).
-- Business question: when do orders peak during the day?
SELECT EXTRACT(HOUR FROM order_timestamp)::int AS hour_of_day,
       COUNT(*)                                 AS orders,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_orders
FROM orders
GROUP BY hour_of_day
ORDER BY hour_of_day;
