# FoodHub Analytics — Entity Relationship Diagram

Normalized (3NF) schema for a food-delivery platform. Seven tables: four core
dimensions (`customers`, `restaurants`, `riders`, `menu_items`), a central
`orders` fact, its `order_items` detail, and `reviews`.

```mermaid
erDiagram
    customers ||--o{ orders : places
    restaurants ||--o{ orders : receives
    restaurants ||--o{ menu_items : offers
    riders ||--o{ orders : delivers
    orders ||--o{ order_items : contains
    menu_items ||--o{ order_items : "listed in"
    orders ||--o| reviews : "reviewed by"

    customers {
        int customer_id PK
        text name
        text city
        date signup_date
        text segment "new|regular|premium|vip"
    }
    restaurants {
        int restaurant_id PK
        text name
        text cuisine_type
        text city
        date active_since
        numeric avg_rating "0-5"
    }
    menu_items {
        int item_id PK
        int restaurant_id FK
        text name
        text category
        numeric price
    }
    riders {
        int rider_id PK
        text name
        text city
        date join_date
        text vehicle_type "bike|scooter|car|bicycle"
    }
    orders {
        int order_id PK
        int customer_id FK
        int restaurant_id FK
        int rider_id FK "nullable (cancelled)"
        timestamp order_timestamp
        text status "delivered|cancelled|refunded|in_progress"
        text payment_method
        numeric total_amount
        int delivery_time_minutes "dirty: outliers injected"
        numeric discount_applied
    }
    order_items {
        int order_item_id PK
        int order_id FK
        int item_id FK
        int quantity
        numeric unit_price
    }
    reviews {
        int review_id PK
        int order_id FK
        int rating "nullable, 1-5"
        text review_text
        date review_date
    }
```

## Relationship notes
- **customers → orders** (1:N): one customer places many orders.
- **restaurants → orders** (1:N): one restaurant fulfils many orders.
- **restaurants → menu_items** (1:N): a menu item belongs to exactly one restaurant.
- **riders → orders** (1:N, optional): `rider_id` is nullable because cancelled
  orders may never be assigned a rider.
- **orders → order_items** (1:N): an order has 2–4 line items on average.
- **menu_items → order_items** (1:N): an item appears across many orders.
- **orders → reviews** (1:0..1): each delivered order may have at most one review.
