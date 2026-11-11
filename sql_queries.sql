-- ============================================================
-- SECTION 1: DATA OVERVIEW AND BASIC METRICS
-- ============================================================

-- Q1: Dataset overview: total orders and unique customers.
SELECT 
    COUNT(DISTINCT order_id) AS total_orders,
    COUNT(DISTINCT customer_unique_id) AS total_distinct_customers
FROM olist_orders_dataset
JOIN olist_customers_dataset ON olist_orders_dataset.customer_id = olist_customers_dataset.customer_id;
-- Insight: 99441 orders from 96096 unique customers, so about 3.36% of orders came from returning buyers.

-- Q2: Order status distribution (ranked from most to least common).
SELECT 
    order_status, 
    COUNT(order_id) AS total_orders
FROM olist_orders_dataset
GROUP BY order_status
ORDER BY total_orders DESC;
-- Insight: 97% of orders are delivered, while 1% are cancelled or unavailable.

-- Q3: Total revenue generated across all order items.
SELECT 
    ROUND(SUM(price), 2) AS total_revenue
FROM olist_order_items_dataset;
-- Insight:Items generated 13591643.7 in total revenue.

-- Q4: Total freight cost and its share of revenue (%).
SELECT 
    ROUND(SUM(freight_value), 2) AS total_freight,
    ROUND((SUM(freight_value) * 100.0) / SUM(price), 2) AS freight_pct_of_revenue
FROM olist_order_items_dataset;
-- Insight: Freight adds 16.57% on top of revenue, so shipping is a significant cost for customers.

-- Q5: Order volume by year.
SELECT 
    strftime('%Y', order_purchase_timestamp) AS order_year,
    COUNT(order_id) AS total_orders
FROM olist_orders_dataset
WHERE order_purchase_timestamp IS NOT NULL
GROUP BY order_year
ORDER BY order_year;
-- Insight: Orders grew from 45101 in 2017 to 54011 in 2018, 2016 is partial.

-- Q6: Top 10 states by customer count.
SELECT 
    customer_state,
    COUNT(DISTINCT customer_unique_id) AS total_customers
FROM olist_customers_dataset
GROUP BY customer_state
ORDER BY total_customers DESC
LIMIT 10;
-- Insight: SP has 40302 customers, and the top 3 states hold 66.54%.

-- ============================================================
-- SECTION 2: REVENUE, PRODUCTS AND PAYMENTS
-- ============================================================

-- Q7: Top 10 product categories by revenue (English category names).
SELECT 
    t.product_category_name_english,
    ROUND(SUM(oi.price), 2) AS category_revenue
FROM olist_order_items_dataset oi
JOIN olist_products_dataset p ON oi.product_id = p.product_id
LEFT JOIN product_category_name_translation t ON p.product_category_name = t.product_category_name
GROUP BY t.product_category_name_english
ORDER BY category_revenue DESC
LIMIT 10;
-- Insight: health_beauty leads with 1,258,681.34, 4.45% ahead of watches_gifts (1,205,005.68).

-- Q8: Monthly revenue trend.
SELECT 
    strftime('%Y-%m', order_purchase_timestamp) AS year_month,
    ROUND(SUM(oi.price), 2) AS monthly_revenue
FROM olist_orders_dataset o
JOIN olist_order_items_dataset oi ON o.order_id = oi.order_id
WHERE o.order_purchase_timestamp IS NOT NULL
GROUP BY year_month
ORDER BY year_month;
-- Insight: Revenue peaked in November 2017 at 1,010,271.37, the highest of any month, up 52.1% from October.

-- Q9: Average order value (calculated per order, not per item).
WITH order_totals AS (
    SELECT 
        order_id,
        SUM(price) AS order_value
    FROM olist_order_items_dataset
    GROUP BY order_id
)
SELECT 
    ROUND(AVG(order_value), 2) AS avg_order_value
FROM order_totals;
-- Insight: The average order is worth 137.75, so customers are making higher-value purchases, buying premium or mid-tier products, or combining multiple items into a single basket..

-- Q10: Payment method breakdown and each method's share of total payment value (%).
WITH total_spend AS (
    SELECT SUM(payment_value) AS overall_value FROM olist_order_payments_dataset
)
SELECT 
    op.payment_type,
    COUNT(DISTINCT op.order_id) AS total_orders,
    ROUND(SUM(op.payment_value), 2) AS total_payment_value,
    ROUND((SUM(op.payment_value) * 100.0) / (SELECT overall_value FROM total_spend), 2) AS percentage_share
FROM olist_order_payments_dataset op
GROUP BY op.payment_type
ORDER BY total_payment_value DESC;
-- Insight: Credit Card is used in 76505 orders and accounts for 78.34% of value.

-- Q11: High-volume categories: those with 1,000+ items sold.
SELECT 
    t.product_category_name_english,
    COUNT(oi.order_item_id) AS items_sold
FROM olist_order_items_dataset oi
JOIN olist_products_dataset p ON oi.product_id = p.product_id
LEFT JOIN product_category_name_translation t ON p.product_category_name = t.product_category_name
GROUP BY t.product_category_name_english
HAVING items_sold >= 1000
ORDER BY items_sold DESC;
-- Insight: 22 categories sold over 1,000 items, led by bed and baths and tables.

-- Q12: Order value segmentation: small (< 50), medium (50-200), large (> 200).
WITH order_totals AS (
    SELECT 
        order_id,
        SUM(price) AS total_order_value
    FROM olist_order_items_dataset
    GROUP BY order_id
),
bracketed_orders AS (
    SELECT 
        order_id,
        CASE 
            WHEN total_order_value < 50 THEN 'small'
            WHEN total_order_value BETWEEN 50 AND 200 THEN 'medium'
            ELSE 'large'
        END AS value_bracket
    FROM order_totals
)
SELECT 
    value_bracket,
    COUNT(order_id) AS order_count
FROM bracketed_orders
GROUP BY value_bracket
ORDER BY 
    CASE value_bracket 
        WHEN 'small' THEN 1 
        WHEN 'medium' THEN 2 
        WHEN 'large' THEN 3 
    END;
-- Insight: 29.55% of orders are small, so most customers buy medium-valued items, followed by small-value baskets.

-- ============================================================
-- SECTION 3: CUSTOMERS AND GROWTH (ADVANCED SQL)
-- ============================================================

-- Q13: Repeat purchase rate: share of customers with more than one order.
WITH customer_order_counts AS (
    SELECT 
        c.customer_unique_id,
        COUNT(o.order_id) AS total_orders
    FROM olist_customers_dataset c
    JOIN olist_orders_dataset o ON c.customer_id = o.customer_id
    GROUP BY c.customer_unique_id
)
SELECT 
    COUNT(CASE WHEN total_orders > 1 THEN 1 END) AS repeat_customers,
    COUNT(*) AS total_customers,
    ROUND((COUNT(CASE WHEN total_orders > 1 THEN 1 END) * 100.0) / COUNT(*), 2) AS repeat_customer_pct
FROM customer_order_counts;
-- Insight: Only 3.12% of customers ordered more than once, so growth depends on new customers.

-- Q14: Month-over-month revenue growth (%), using LAG.
WITH monthly_rev AS (
    SELECT 
        strftime('%Y-%m', o.order_purchase_timestamp) AS year_month,
        SUM(oi.price) AS revenue
    FROM olist_orders_dataset o
    JOIN olist_order_items_dataset oi ON o.order_id = oi.order_id
    WHERE o.order_purchase_timestamp IS NOT NULL
    GROUP BY year_month
)
SELECT 
    year_month,
    ROUND(revenue, 2) AS revenue,
    ROUND(LAG(revenue, 1) OVER (ORDER BY year_month), 2) AS prev_month_revenue,
    ROUND(
        ((revenue - LAG(revenue, 1) OVER (ORDER BY year_month)) * 100.0) / 
        NULLIF(LAG(revenue, 1) OVER (ORDER BY year_month), 0), 2
    ) AS mom_growth_pct
FROM monthly_rev;
-- Insight: Growth peaked at +52.1% in November 2017; the sharpest drop among full months was -26.36% in December 2017 (1.01M to ~743k), consistent with a post-peak seasonal dip.

-- Q15: Product categories ranked by revenue, using RANK.
SELECT 
    t.product_category_name_english,
    ROUND(SUM(oi.price), 2) AS total_revenue,
    RANK() OVER (ORDER BY SUM(oi.price) DESC) AS category_rank
FROM olist_order_items_dataset oi
JOIN olist_products_dataset p ON oi.product_id = p.product_id
LEFT JOIN product_category_name_translation t ON p.product_category_name = t.product_category_name
GROUP BY t.product_category_name_english
ORDER BY category_rank;
-- Insight: The top 3 categories (health_beauty, watches_gifts, bed_bath_table) bring 25.76% of revenue, so about a quarter of revenue depends on just three of the categories.


-- Q16: Top 3 revenue-generating categories within each year (RANK with PARTITION BY).
WITH yearly_category_rev AS (
    SELECT 
        strftime('%Y', o.order_purchase_timestamp) AS order_year,
        t.product_category_name_english AS category_name,
        SUM(oi.price) AS category_revenue,
        RANK() OVER (
            PARTITION BY strftime('%Y', o.order_purchase_timestamp) 
            ORDER BY SUM(oi.price) DESC
        ) AS rank_in_year
    FROM olist_orders_dataset o
    JOIN olist_order_items_dataset oi ON o.order_id = oi.order_id
    JOIN olist_products_dataset p ON oi.product_id = p.product_id
    LEFT JOIN product_category_name_translation t ON p.product_category_name = t.product_category_name
    WHERE o.order_purchase_timestamp IS NOT NULL
    GROUP BY order_year, category_name
)
SELECT 
    order_year,
    rank_in_year,
    category_name,
    ROUND(category_revenue, 2) AS category_revenue
FROM yearly_category_rev
WHERE rank_in_year <= 3
ORDER BY order_year, rank_in_year;
-- Insight: The same three categories lead in both 2017 and 2018 (2016 is partial and excluded), but the order changes: health_beauty rises from 3rd to 1st (+60.3%, 481.8k to 772.2k) despite 2018 covering fewer months, while bed_bath_table slips from 1st to 3rd (+8.0%).


-- Q17: Customer spend ranking: top 10 customers and their share of total revenue (%).
WITH customer_spend AS (
    SELECT 
        c.customer_unique_id,
        SUM(oi.price) AS total_spend,
        RANK() OVER (ORDER BY SUM(oi.price) DESC) AS spend_rank
    FROM olist_customers_dataset c
    JOIN olist_orders_dataset o ON c.customer_id = o.customer_id
    JOIN olist_order_items_dataset oi ON o.order_id = oi.order_id
    GROUP BY c.customer_unique_id
),
top_10 AS (
    SELECT SUM(total_spend) AS top_10_spend FROM customer_spend WHERE spend_rank <= 10
),
overall AS (
    SELECT SUM(price) AS overall_spend FROM olist_order_items_dataset
)
SELECT 
    cs.spend_rank,
    cs.customer_unique_id,
    ROUND(cs.total_spend, 2) AS total_spend,
    ROUND((t10.top_10_spend * 100.0) / o.overall_spend, 3) AS top_10_pct_of_total_revenue
FROM customer_spend cs
CROSS JOIN top_10 t10
CROSS JOIN overall o
WHERE cs.spend_rank <= 10
ORDER BY cs.spend_rank;
-- Insight: The top 10 customers account for only 0.5%, so no single-customer dependence.


-- ============================================================
-- SECTION 4: DELIVERY PERFORMANCE AND CUMULATIVE TRENDS
-- ============================================================

-- Q18: Late delivery rate: delivered orders that arrived after the estimated date (%).
SELECT 
    COUNT(CASE WHEN julianday(order_delivered_customer_date) > julianday(order_estimated_delivery_date) THEN 1 END) AS late_orders,
    COUNT(order_id) AS total_delivered_orders,
    ROUND(
        (COUNT(CASE WHEN julianday(order_delivered_customer_date) > julianday(order_estimated_delivery_date) THEN 1 END) * 100.0) / 
        COUNT(order_id), 2
    ) AS late_delivery_pct
FROM olist_orders_dataset
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NOT NULL 
  AND order_estimated_delivery_date IS NOT NULL;
  -- Insight: 8.11% of delivered orders arrived after the estimated date.


-- Q19: Average delivery time (days) by state, identifying the slowest states.
SELECT 
    c.customer_state,
    ROUND(AVG(julianday(o.order_delivered_customer_date) - julianday(o.order_purchase_timestamp)), 2) AS avg_delivery_days
FROM olist_orders_dataset o
JOIN olist_customers_dataset c ON o.customer_id = c.customer_id
WHERE o.order_status = 'delivered' 
  AND o.order_delivered_customer_date IS NOT NULL
GROUP BY c.customer_state
ORDER BY avg_delivery_days DESC;
-- Insight: RR averages 29.39 days vs 8.76 for SP.


-- Q20: Cumulative (running total) revenue by month.
WITH monthly_revenue AS (
    SELECT 
        strftime('%Y-%m', o.order_purchase_timestamp) AS year_month,
        SUM(oi.price) AS monthly_rev
    FROM olist_orders_dataset o
    JOIN olist_order_items_dataset oi ON o.order_id = oi.order_id
    WHERE o.order_purchase_timestamp IS NOT NULL
    GROUP BY year_month
)
SELECT 
    year_month,
    ROUND(monthly_rev, 2) AS monthly_revenue,
    ROUND(SUM(monthly_rev) OVER (ORDER BY year_month ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW), 2) AS cumulative_revenue
FROM monthly_revenue
ORDER BY year_month;
-- Insight: Cumulative revenue reaches 13.59M by August 2018, matching the total overall revenue calculated in Q3..