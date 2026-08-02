"""
FoodHub Analytics — synthetic data generator.

Generates realistic CSVs for a food-delivery platform, with DELIBERATE,
documented data-quality issues so the SQL layer can showcase cleaning skills.

Output: data/csv/*.csv  (loaded via sql/02_load_data.sql using psql \\copy).

Scale (approx):
    customers   ~500  (+ a few duplicate signups)
    restaurants  120
    menu_items  ~3000
    riders       150
    orders     25000
    order_items ~75000 (2-4 per order)
    reviews    12000

Dirty data is injected in clearly-marked sections and documented in
docs/data_quality_notes.md. Run:  python data/generate_data.py
"""

import csv
import os
import random
from datetime import date, datetime, timedelta

from faker import Faker

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
SEED = 42
random.seed(SEED)
fake = Faker("en_IN")
Faker.seed(SEED)

OUT_DIR = os.path.join(os.path.dirname(__file__), "csv")
os.makedirs(OUT_DIR, exist_ok=True)

N_CUSTOMERS   = 500
N_RESTAURANTS = 120
N_MENU_ITEMS  = 3000
N_RIDERS      = 150
N_ORDERS      = 25000
N_REVIEWS     = 12000

ORDER_START = date(2024, 1, 1)
ORDER_END   = date(2026, 6, 30)

CITIES = ["Mumbai", "Delhi", "Bengaluru", "Hyderabad", "Chennai",
          "Pune", "Kolkata", "Ahmedabad", "Jaipur", "Kochi"]
CUISINES = ["North Indian", "South Indian", "Chinese", "Italian", "Mughlai",
            "Fast Food", "Continental", "Thai", "Desserts", "Beverages",
            "Biryani", "Healthy"]
CATEGORIES = ["Starters", "Main Course", "Breads", "Rice & Biryani",
              "Desserts", "Beverages", "Sides", "Combos"]
SEGMENTS = ["new", "regular", "premium", "vip"]
VEHICLES = ["bike", "scooter", "car", "bicycle"]
PAYMENTS = ["card", "upi", "wallet", "cash", "netbanking"]
STATUSES = ["delivered", "cancelled", "refunded", "in_progress"]

REVIEW_TEXTS = [
    "Great food, arrived hot!", "Delivery was late but food was good.",
    "Loved it, will order again.", "Portion size was small.",
    "Packaging could be better.", "Absolutely delicious.",
    "Food was cold on arrival.", "Value for money.",
    "Rider was polite and quick.", "Order was missing an item.",
    "Best biryani in town.", "Average experience.",
    "Fresh and tasty.", "Would not recommend.", "Perfect as always.",
]

# Tracking for the data-quality report.
dirty_log = {}


def daterange(start, end):
    delta = (end - start).days
    return start + timedelta(days=random.randint(0, delta))


def write_csv(name, header, rows):
    path = os.path.join(OUT_DIR, name)
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(header)
        w.writerows(rows)
    print(f"  wrote {len(rows):>6} rows -> {name}")


# ===========================================================================
# customers
# ===========================================================================
def gen_customers():
    rows = []
    seg_weights = [0.30, 0.45, 0.18, 0.07]
    for cid in range(1, N_CUSTOMERS + 1):
        signup = daterange(date(2023, 6, 1), date(2026, 6, 1))
        city = random.choice(CITIES)
        # DIRTY #6: ~4% NULL city
        if random.random() < 0.04:
            city = ""
        # DIRTY #7: city casing/whitespace inconsistency (~3%)
        elif random.random() < 0.03:
            city = random.choice([city.lower(), city.upper(), city + " "])
        rows.append([
            cid, fake.name(), city,
            signup.isoformat(),
            random.choices(SEGMENTS, weights=seg_weights)[0],
        ])

    # DIRTY #1: duplicate customer signups (same person, new id, ISO date but
    # a couple use a non-ISO date format -> DIRTY #2). 8 duplicates.
    dup_count = 8
    bad_date_dups = 0
    next_id = N_CUSTOMERS + 1
    for _ in range(dup_count):
        src = random.choice(rows[:N_CUSTOMERS])
        signup_str = src[3]
        # 3 of the 8 dupes also get an inconsistent date format
        if bad_date_dups < 3:
            d = date.fromisoformat(src[3])
            signup_str = random.choice([
                d.strftime("%d/%m/%Y"),      # 05/11/2024
                d.strftime("%m-%d-%Y"),      # 11-05-2024
                d.strftime("%d-%b-%Y"),      # 05-Nov-2024
            ])
            bad_date_dups += 1
        rows.append([next_id, src[1], src[2], signup_str, src[4]])
        next_id += 1

    dirty_log["customers"] = (
        f"{dup_count} duplicate signups (near-identical name/city, new id); "
        f"{bad_date_dups} of them with non-ISO signup_date formats "
        f"(DD/MM/YYYY, MM-DD-YYYY, DD-Mon-YYYY); ~4% NULL city; "
        f"~3% city casing/whitespace inconsistency."
    )
    write_csv("customers.csv",
              ["customer_id", "name", "city", "signup_date", "segment"], rows)
    return rows


# ===========================================================================
# restaurants
# ===========================================================================
def gen_restaurants():
    rows = []
    null_ratings = 0
    for rid in range(1, N_RESTAURANTS + 1):
        rating = round(random.uniform(2.6, 5.0), 2)
        # DIRTY #8: ~5% NULL avg_rating
        if random.random() < 0.05:
            rating = ""
            null_ratings += 1
        rows.append([
            rid,
            f"{fake.last_name()}'s {random.choice(['Kitchen','Diner','Cafe','Bistro','Express','House','Corner'])}",
            random.choice(CUISINES),
            random.choice(CITIES),
            daterange(date(2020, 1, 1), date(2024, 12, 31)).isoformat(),
            rating,
        ])
    dirty_log["restaurants"] = f"{null_ratings} restaurants with NULL avg_rating."
    write_csv("restaurants.csv",
              ["restaurant_id", "name", "cuisine_type", "city",
               "active_since", "avg_rating"], rows)
    return rows


# ===========================================================================
# menu_items
# ===========================================================================
def gen_menu_items(restaurants):
    rows = []
    item_id = 1
    # distribute ~3000 items across restaurants (15-40 each)
    rest_ids = [r[0] for r in restaurants]
    while item_id <= N_MENU_ITEMS:
        rid = random.choice(rest_ids)
        rows.append([
            item_id, rid,
            fake.word().capitalize() + " " + random.choice(
                ["Special", "Deluxe", "Combo", "Platter", "Bowl", "Wrap", "Thali"]),
            random.choice(CATEGORIES),
            round(random.uniform(50, 800), 2),
        ])
        item_id += 1
    write_csv("menu_items.csv",
              ["item_id", "restaurant_id", "name", "category", "price"], rows)
    return rows


# ===========================================================================
# riders
# ===========================================================================
def gen_riders():
    rows = []
    for rid in range(1, N_RIDERS + 1):
        rows.append([
            rid, fake.name(), random.choice(CITIES),
            daterange(date(2021, 1, 1), date(2026, 5, 1)).isoformat(),
            random.choices(VEHICLES, weights=[0.5, 0.3, 0.1, 0.1])[0],
        ])
    write_csv("riders.csv",
              ["rider_id", "name", "city", "join_date", "vehicle_type"], rows)
    return rows


# ===========================================================================
# orders + order_items
# ===========================================================================
def gen_orders(customers, restaurants, riders, menu_items):
    # index menu items by restaurant for realistic baskets
    items_by_rest = {}
    for it in menu_items:
        items_by_rest.setdefault(it[1], []).append(it)

    cust_signup = {c[0]: c[3] for c in customers[:N_CUSTOMERS]}
    cust_ids = list(cust_signup.keys())
    rest_ids = [r[0] for r in restaurants]
    rider_ids = [r[0] for r in riders]

    orders, order_items = [], []
    oi_id = 1

    neg_delivery = 0
    huge_delivery = 0
    null_delivery_delivered = 0

    for oid in range(1, N_ORDERS + 1):
        cid = random.choice(cust_ids)
        # pick a restaurant that actually has menu items
        rid = random.choice(rest_ids)
        while rid not in items_by_rest:
            rid = random.choice(rest_ids)

        status = random.choices(STATUSES, weights=[0.82, 0.10, 0.05, 0.03])[0]

        # order timestamp: after signup (best-effort; skip malformed dup dates)
        try:
            su = date.fromisoformat(cust_signup[cid])
        except ValueError:
            su = ORDER_START
        lo = max(su, ORDER_START)
        if lo > ORDER_END:
            lo = ORDER_START
        odt = datetime.combine(daterange(lo, ORDER_END),
                               datetime.min.time()) + timedelta(
            hours=random.randint(8, 23), minutes=random.randint(0, 59))

        # basket: 2-4 items
        basket = random.sample(items_by_rest[rid],
                               k=min(random.randint(2, 4), len(items_by_rest[rid])))
        subtotal = 0.0
        pending_items = []
        for it in basket:
            qty = random.randint(1, 3)
            unit = float(it[4])
            subtotal += qty * unit
            pending_items.append([oi_id, oid, it[0], qty, round(unit, 2)])
            oi_id += 1

        discount = 0.0
        if random.random() < 0.35:
            discount = round(subtotal * random.choice([0.05, 0.10, 0.15, 0.20]), 2)
        total = round(max(subtotal - discount, 0), 2)

        # rider + delivery time depend on status
        rider = random.choice(rider_ids)
        delivery = random.randint(15, 70)

        if status in ("cancelled", "refunded", "in_progress"):
            # DIRTY #5: cancelled/in-progress -> no rider, no delivery time
            if status == "cancelled":
                rider = ""            # orphaned rider link
                delivery = ""
                total = 0.0 if random.random() < 0.5 else total
            elif status == "in_progress":
                delivery = ""
            # refunded keeps rider + delivery (it was delivered then refunded)

        # DIRTY #4: delivery-time outliers on delivered orders
        if status == "delivered":
            r = random.random()
            if r < 0.005:                 # negative delivery time
                delivery = -random.randint(1, 20)
                neg_delivery += 1
            elif r < 0.011:               # absurdly long (300-600 min)
                delivery = random.randint(300, 600)
                huge_delivery += 1
            elif r < 0.016:               # NULL delivery time on a delivered order
                delivery = ""
                null_delivery_delivered += 1

        orders.append([
            oid, cid, rid, rider,
            odt.strftime("%Y-%m-%d %H:%M:%S"),
            status, random.choice(PAYMENTS), total, delivery, discount,
        ])
        order_items.extend(pending_items)

    dirty_log["orders"] = (
        f"{neg_delivery} delivered orders with NEGATIVE delivery_time_minutes; "
        f"{huge_delivery} with 300-600 min outliers; "
        f"{null_delivery_delivered} delivered orders with NULL delivery_time; "
        f"cancelled orders have NULL rider_id + NULL delivery_time (orphaned "
        f"rider link) and ~50% have total_amount forced to 0."
    )
    write_csv("orders.csv",
              ["order_id", "customer_id", "restaurant_id", "rider_id",
               "order_timestamp", "status", "payment_method",
               "total_amount", "delivery_time_minutes", "discount_applied"],
              orders)
    write_csv("order_items.csv",
              ["order_item_id", "order_id", "item_id", "quantity", "unit_price"],
              order_items)
    return orders, order_items


# ===========================================================================
# reviews
# ===========================================================================
def gen_reviews(orders):
    # reviews only for delivered / refunded orders
    reviewable = [o for o in orders if o[5] in ("delivered", "refunded")]
    random.shuffle(reviewable)
    reviewable = reviewable[:N_REVIEWS]

    rows = []
    null_rating = 0
    bad_date_fmt = 0
    for i, o in enumerate(reviewable, start=1):
        oid = o[0]
        odt = datetime.strptime(o[4], "%Y-%m-%d %H:%M:%S").date()
        rdate = odt + timedelta(days=random.randint(0, 10))

        rating = random.choices([1, 2, 3, 4, 5],
                                weights=[0.05, 0.08, 0.15, 0.32, 0.40])[0]
        # DIRTY #3a: ~5% NULL ratings
        if random.random() < 0.05:
            rating = ""
            null_rating += 1

        rdate_str = rdate.isoformat()
        # DIRTY #3b: ~1.5% non-ISO review_date formats
        if random.random() < 0.015:
            rdate_str = random.choice([
                rdate.strftime("%d/%m/%Y"),
                rdate.strftime("%m/%d/%Y"),
            ])
            bad_date_fmt += 1

        rows.append([i, oid, rating, random.choice(REVIEW_TEXTS), rdate_str])

    dirty_log["reviews"] = (
        f"{null_rating} reviews with NULL rating; "
        f"{bad_date_fmt} reviews with non-ISO review_date formats."
    )
    write_csv("reviews.csv",
              ["review_id", "order_id", "rating", "review_text", "review_date"],
              rows)
    return rows


# ===========================================================================
def main():
    print("Generating FoodHub synthetic data...")
    customers   = gen_customers()
    restaurants = gen_restaurants()
    menu_items  = gen_menu_items(restaurants)
    riders      = gen_riders()
    orders, _   = gen_orders(customers, restaurants, riders, menu_items)
    gen_reviews(orders)

    print("\nData-quality issues injected:")
    for tbl, note in dirty_log.items():
        print(f"  [{tbl}] {note}")
    print("\nDone. CSVs in:", OUT_DIR)


if __name__ == "__main__":
    main()
