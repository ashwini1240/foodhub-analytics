-- ============================================================================
-- FoodHub Analytics — Schema DDL
-- PostgreSQL 17
-- Normalized (3NF) schema for a food-delivery platform.
-- Run against the foodhub database (see 02_load_data.sql for DB creation).
-- ============================================================================

-- Idempotent rebuild: drop in FK-dependency order.
DROP TABLE IF EXISTS reviews       CASCADE;
DROP TABLE IF EXISTS order_items   CASCADE;
DROP TABLE IF EXISTS orders        CASCADE;
DROP TABLE IF EXISTS menu_items    CASCADE;
DROP TABLE IF EXISTS riders        CASCADE;
DROP TABLE IF EXISTS restaurants   CASCADE;
DROP TABLE IF EXISTS customers     CASCADE;

-- ----------------------------------------------------------------------------
-- customers
-- ----------------------------------------------------------------------------
CREATE TABLE customers (
    customer_id   INTEGER      PRIMARY KEY,
    name          TEXT         NOT NULL,
    city          TEXT,
    signup_date   DATE,
    -- Behavioural/marketing segment assigned at signup.
    segment       TEXT         CHECK (segment IN ('new','regular','premium','vip'))
);

-- ----------------------------------------------------------------------------
-- restaurants
-- ----------------------------------------------------------------------------
CREATE TABLE restaurants (
    restaurant_id INTEGER      PRIMARY KEY,
    name          TEXT         NOT NULL,
    cuisine_type  TEXT,
    city          TEXT,
    active_since  DATE,
    avg_rating    NUMERIC(3,2) CHECK (avg_rating IS NULL OR avg_rating BETWEEN 0 AND 5)
);

-- ----------------------------------------------------------------------------
-- menu_items
-- ----------------------------------------------------------------------------
CREATE TABLE menu_items (
    item_id       INTEGER      PRIMARY KEY,
    restaurant_id INTEGER      NOT NULL REFERENCES restaurants(restaurant_id),
    name          TEXT         NOT NULL,
    category      TEXT,
    price         NUMERIC(8,2) CHECK (price >= 0)
);

-- ----------------------------------------------------------------------------
-- riders (delivery partners)
-- ----------------------------------------------------------------------------
CREATE TABLE riders (
    rider_id      INTEGER      PRIMARY KEY,
    name          TEXT         NOT NULL,
    city          TEXT,
    join_date     DATE,
    vehicle_type  TEXT         CHECK (vehicle_type IN ('bike','scooter','car','bicycle'))
);

-- ----------------------------------------------------------------------------
-- orders
-- rider_id is nullable: cancelled orders may never be assigned a rider.
-- ----------------------------------------------------------------------------
CREATE TABLE orders (
    order_id              INTEGER      PRIMARY KEY,
    customer_id           INTEGER      NOT NULL REFERENCES customers(customer_id),
    restaurant_id         INTEGER      NOT NULL REFERENCES restaurants(restaurant_id),
    rider_id              INTEGER      REFERENCES riders(rider_id),
    order_timestamp       TIMESTAMP    NOT NULL,
    status                TEXT         NOT NULL
                          CHECK (status IN ('delivered','cancelled','refunded','in_progress')),
    payment_method        TEXT         CHECK (payment_method IN ('card','upi','wallet','cash','netbanking')),
    total_amount          NUMERIC(10,2) CHECK (total_amount >= 0),
    -- NOTE: intentionally NOT constrained to be positive — dirty data
    -- (negative / >300 min outliers) is injected here to showcase cleaning.
    delivery_time_minutes INTEGER,
    discount_applied      NUMERIC(10,2) DEFAULT 0 CHECK (discount_applied >= 0)
);

-- ----------------------------------------------------------------------------
-- order_items (line items)
-- ----------------------------------------------------------------------------
CREATE TABLE order_items (
    order_item_id INTEGER      PRIMARY KEY,
    order_id      INTEGER      NOT NULL REFERENCES orders(order_id),
    item_id       INTEGER      NOT NULL REFERENCES menu_items(item_id),
    quantity      INTEGER      NOT NULL CHECK (quantity > 0),
    unit_price    NUMERIC(8,2) CHECK (unit_price >= 0)
);

-- ----------------------------------------------------------------------------
-- reviews
-- One review per order (at most). rating nullable — dirty data injected.
-- ----------------------------------------------------------------------------
CREATE TABLE reviews (
    review_id     INTEGER      PRIMARY KEY,
    order_id      INTEGER      NOT NULL REFERENCES orders(order_id),
    rating        INTEGER      CHECK (rating IS NULL OR rating BETWEEN 1 AND 5),
    review_text   TEXT,
    review_date   DATE
);
