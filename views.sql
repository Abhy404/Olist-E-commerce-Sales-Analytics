-- ============================================================
-- VIEWS (for the Power BI dashboard)
-- ============================================================

-- V1: Headline KPIs (one row)
CREATE VIEW v_kpis AS
WITH order_totals AS (
    SELECT order_id, SUM(price) AS order_value
    FROM olist_order_items_dataset
    GROUP BY order_id
),
cust AS (
    SELECT c.customer_unique_id, COUNT(o.order_id) AS n_orders
    FROM olist_customers_dataset c
    JOIN olist_orders_dataset o ON c.customer_id = o.customer_id
    GROUP BY c.customer_unique_id
)
SELECT
    (SELECT COUNT(*) FROM olist_orders_dataset) AS total_orders,
    (SELECT COUNT(*) FROM cust) AS unique_customers,
    (SELECT ROUND(SUM(price), 2) FROM olist_order_items_dataset) AS total_revenue,
    (SELECT ROUND(SUM(freight_value), 2) FROM olist_order_items_dataset) AS total_freight,
    (SELECT ROUND(AVG(order_value), 2) FROM order_totals) AS avg_order_value,
    (SELECT ROUND(100.0 * SUM(CASE WHEN n_orders > 1 THEN 1 ELSE 0 END) / COUNT(*), 2) FROM cust) AS repeat_customer_pct,
    (SELECT ROUND(100.0 * SUM(CASE WHEN julianday(order_delivered_customer_date) > julianday(order_estimated_delivery_date) THEN 1 ELSE 0 END) / COUNT(*), 2)
     FROM olist_orders_dataset
     WHERE order_status = 'delivered'
       AND order_delivered_customer_date IS NOT NULL
       AND order_estimated_delivery_date IS NOT NULL) AS late_delivery_pct;

-- V2: Monthly revenue, growth and running total
CREATE VIEW v_monthly_revenue AS
WITH m AS (
    SELECT strftime('%Y-%m', o.order_purchase_timestamp) AS year_month,
           SUM(oi.price) AS revenue,
           COUNT(DISTINCT o.order_id) AS orders
    FROM olist_orders_dataset o
    JOIN olist_order_items_dataset oi ON o.order_id = oi.order_id
    WHERE o.order_purchase_timestamp IS NOT NULL
    GROUP BY year_month
)
SELECT year_month,
       ROUND(revenue, 2) AS revenue,
       orders,
       ROUND(LAG(revenue) OVER (ORDER BY year_month), 2) AS prev_month_revenue,
       ROUND((revenue - LAG(revenue) OVER (ORDER BY year_month)) * 100.0
             / NULLIF(LAG(revenue) OVER (ORDER BY year_month), 0), 2) AS mom_growth_pct,
       ROUND(SUM(revenue) OVER (ORDER BY year_month
             ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW), 2) AS cumulative_revenue
FROM m;

-- V3: Category revenue, items sold and rank
CREATE VIEW v_category_revenue AS
SELECT COALESCE(t.product_category_name_english, p.product_category_name, 'unknown') AS category,
       ROUND(SUM(oi.price), 2) AS revenue,
       COUNT(*) AS items_sold,
       RANK() OVER (ORDER BY SUM(oi.price) DESC) AS revenue_rank
FROM olist_order_items_dataset oi
JOIN olist_products_dataset p ON oi.product_id = p.product_id
LEFT JOIN product_category_name_translation t ON p.product_category_name = t.product_category_name
GROUP BY category;

-- V4: Category rank within each year
CREATE VIEW v_yearly_category_rank AS
WITH y AS (
    SELECT strftime('%Y', o.order_purchase_timestamp) AS order_year,
           COALESCE(t.product_category_name_english, p.product_category_name, 'unknown') AS category,
           SUM(oi.price) AS revenue
    FROM olist_orders_dataset o
    JOIN olist_order_items_dataset oi ON o.order_id = oi.order_id
    JOIN olist_products_dataset p ON oi.product_id = p.product_id
    LEFT JOIN product_category_name_translation t ON p.product_category_name = t.product_category_name
    WHERE o.order_purchase_timestamp IS NOT NULL
    GROUP BY order_year, category
)
SELECT order_year, category,
       ROUND(revenue, 2) AS revenue,
       RANK() OVER (PARTITION BY order_year ORDER BY revenue DESC) AS rank_in_year
FROM y;

-- V5: Delivery performance and customers by state
CREATE VIEW v_state_performance AS
SELECT c.customer_state AS state,
       COUNT(DISTINCT c.customer_unique_id) AS customers,
       COUNT(o.order_id) AS orders,
       ROUND(AVG(CASE WHEN o.order_status = 'delivered' AND o.order_delivered_customer_date IS NOT NULL
                      THEN julianday(o.order_delivered_customer_date) - julianday(o.order_purchase_timestamp) END), 2) AS avg_delivery_days,
       ROUND(100.0 * SUM(CASE WHEN o.order_status = 'delivered'
                               AND o.order_delivered_customer_date IS NOT NULL
                               AND julianday(o.order_delivered_customer_date) > julianday(o.order_estimated_delivery_date)
                              THEN 1 ELSE 0 END)
             / NULLIF(SUM(CASE WHEN o.order_status = 'delivered'
                                AND o.order_delivered_customer_date IS NOT NULL
                               THEN 1 ELSE 0 END), 0), 2) AS late_delivery_pct
FROM olist_customers_dataset c
JOIN olist_orders_dataset o ON c.customer_id = o.customer_id
GROUP BY c.customer_state;

-- V6: Payment methods
CREATE VIEW v_payment_summary AS
SELECT payment_type,
       COUNT(DISTINCT order_id) AS orders,
       ROUND(SUM(payment_value), 2) AS total_value,
       ROUND(100.0 * SUM(payment_value) / (SELECT SUM(payment_value) FROM olist_order_payments_dataset), 2) AS value_share_pct
FROM olist_order_payments_dataset
GROUP BY payment_type;

-- V7: Order value segments
CREATE VIEW v_order_segments AS
WITH ot AS (
    SELECT order_id, SUM(price) AS order_value
    FROM olist_order_items_dataset
    GROUP BY order_id
)
SELECT CASE WHEN order_value < 50 THEN 'small'
            WHEN order_value <= 200 THEN 'medium'
            ELSE 'large' END AS segment,
       COUNT(*) AS orders,
       ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM ot), 2) AS pct_of_orders
FROM ot
GROUP BY segment;