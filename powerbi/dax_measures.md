# Power BI — DAX Measures (ready to paste)

Create these in a dedicated measure table (recommended) or on `fact_orders`.
In Power BI Desktop: **Modeling > New Measure**, then paste one block at a time.
Names are chosen to read cleanly on cards/tooltips.

> Assumes the import model from `build_guide.md`: `fact_orders` related to
> `dim_customers`, `dim_restaurants`, `dim_riders`, `dim_menu_items`, and
> `dim_date` (marked as the date table), plus `fact_reviews`.

## Core volume & revenue
```DAX
Total Orders = COUNTROWS ( fact_orders )
```
```DAX
Delivered Orders =
CALCULATE ( [Total Orders], fact_orders[is_delivered] = TRUE )
```
```DAX
Total Revenue =
CALCULATE ( SUM ( fact_orders[total_amount] ), fact_orders[is_delivered] = TRUE )
```
```DAX
Average Order Value =
DIVIDE ( [Total Revenue], [Delivered Orders] )
```
```DAX
Total Discount Given =
CALCULATE ( SUM ( fact_orders[discount_applied] ), fact_orders[is_delivered] = TRUE )
```
```DAX
Total Items Sold =
CALCULATE ( SUM ( fact_orders[total_quantity] ), fact_orders[is_delivered] = TRUE )
```

## Time intelligence (needs dim_date marked as date table)
```DAX
Revenue MTD = TOTALMTD ( [Total Revenue], dim_date[date_key] )
```
```DAX
Revenue YTD = TOTALYTD ( [Total Revenue], dim_date[date_key] )
```
```DAX
Revenue PM =                       -- previous month
CALCULATE ( [Total Revenue], DATEADD ( dim_date[date_key], -1, MONTH ) )
```
```DAX
Revenue MoM % =
DIVIDE ( [Total Revenue] - [Revenue PM], [Revenue PM] )
```
```DAX
Revenue PY =                       -- previous year
CALCULATE ( [Total Revenue], DATEADD ( dim_date[date_key], -1, YEAR ) )
```
```DAX
Revenue YoY % =
DIVIDE ( [Total Revenue] - [Revenue PY], [Revenue PY] )
```
```DAX
Running Revenue =
CALCULATE (
    [Total Revenue],
    FILTER ( ALLSELECTED ( dim_date[date_key] ),
             dim_date[date_key] <= MAX ( dim_date[date_key] ) )
)
```

## Operational KPIs
```DAX
Valid Deliveries =                 -- delivered orders with a clean delivery time
CALCULATE ( [Total Orders],
    fact_orders[is_delivered] = TRUE,
    NOT ISBLANK ( fact_orders[delivery_time_minutes] ) )
```
```DAX
Avg Delivery Time =
CALCULATE ( AVERAGE ( fact_orders[delivery_time_minutes] ),
            fact_orders[is_delivered] = TRUE )
```
```DAX
On-Time Orders =
CALCULATE ( [Total Orders], fact_orders[is_on_time] = TRUE )
```
```DAX
On-Time Delivery % =
DIVIDE ( [On-Time Orders], [Valid Deliveries] )
```
```DAX
Cancelled Orders =
CALCULATE ( [Total Orders], fact_orders[is_cancelled] = TRUE )
```
```DAX
Cancellation Rate % =
DIVIDE ( [Cancelled Orders], [Total Orders] )
```

## Customers, retention & RFM
```DAX
Active Customers =
CALCULATE ( DISTINCTCOUNT ( fact_orders[customer_id] ),
            fact_orders[is_delivered] = TRUE )
```
```DAX
New Customers =                    -- first delivered order falls in the period
CALCULATE (
    [Active Customers],
    FILTER ( VALUES ( dim_customers[customer_id] ),
        CALCULATE ( MIN ( fact_orders[date_key] ), fact_orders[is_delivered] = TRUE )
            >= MIN ( dim_date[date_key] ) )
)
```
```DAX
Returning Customers = [Active Customers] - [New Customers]
```
```DAX
Repeat Rate % =
DIVIDE ( [Returning Customers], [Active Customers] )
```
```DAX
Revenue per Customer =
DIVIDE ( [Total Revenue], [Active Customers] )
```
```DAX
-- RFM segment counts: put dim_customers[segment] (or an RFM segment column you
-- import from the sql/queries/05 output) on a visual and use:
Customers in Segment = DISTINCTCOUNT ( dim_customers[customer_id] )
```

## Reviews / sentiment
```DAX
Avg Rating =
CALCULATE ( AVERAGE ( fact_reviews[rating] ),
            NOT ISBLANK ( fact_reviews[rating] ) )
```
```DAX
Review Count =
CALCULATE ( COUNTROWS ( fact_reviews ), NOT ISBLANK ( fact_reviews[rating] ) )
```

## Handy KPI-card helpers
```DAX
Revenue (Label) =
VAR v = [Total Revenue]
RETURN
    SWITCH ( TRUE(),
        v >= 1e7, FORMAT ( v / 1e7, "0.00" ) & " Cr",
        v >= 1e5, FORMAT ( v / 1e5, "0.00" ) & " L",
        FORMAT ( v, "#,0" ) )
```
