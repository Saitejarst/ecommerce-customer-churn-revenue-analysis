LOAD DATA LOCAL INFILE 'D:/Downloads/archive (5)/olist_orders_dataset.csv'
INTO TABLE orders_staging
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

SELECT COUNT(*) AS staging_orders
FROM ecommerce_analytics.orders_staging;

INSERT INTO orders (
    order_id,
    customer_id,
    order_status,
    order_purchase_timestamp,
    order_approved_at,
    order_delivered_carrier_date,
    order_delivered_customer_date,
    order_estimated_delivery_date
)
SELECT
    order_id,
    customer_id,
    order_status,
    NULLIF(order_purchase_timestamp, ''),
    NULLIF(order_approved_at, ''),
    NULLIF(order_delivered_carrier_date, ''),
    NULLIF(order_delivered_customer_date, ''),
    NULLIF(order_estimated_delivery_date, '')
FROM orders_staging;

SELECT COUNT(*) AS total_orders
FROM ecommerce_analytics.orders;

-- Understand the overall order-status distribution before calculating delivery and cancellation metrics 
SELECT order_status, count(*) AS total_orders
FROM orders
GROUP BY order_status
ORDER BY total_orders DESC;

 -- Display every order alongside the total number of orders in the dataset
SELECT
    order_id,
    order_status,
    COUNT(*) OVER () AS total_orders
FROM orders
LIMIT 100;

-- Create a customer table to analyze repeat purchases and customer retention
CREATE TABLE ecommerce_analytics.customers (
    customer_id VARCHAR(50) PRIMARY KEY,
    customer_unique_id VARCHAR(50),
    customer_zip_code_prefix VARCHAR(10),
    customer_city VARCHAR(100),
    customer_state VARCHAR(2)
);

-- Load the customer CSV into the staging table before validating and transferring it
CREATE TABLE ecommerce_analytics.customers_staging (
    customer_id VARCHAR(50),
    customer_unique_id VARCHAR(50),
    customer_zip_code_prefix VARCHAR(10),
    customer_city VARCHAR(100),
    customer_state VARCHAR(2)
);

-- Load the complete customer CSV into the staging table for customer-level analysis
LOAD DATA LOCAL INFILE 'D:/Downloads/archive (5)/olist_customers_dataset.csv'
INTO TABLE ecommerce_analytics.customers_staging
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

-- Verify that the customer staging table contains all expected customer records
SELECT COUNT(*) AS total_customer_records
FROM ecommerce_analytics.customers_staging;

-- Transfer all customer records from staging into the final analysis table
INSERT INTO ecommerce_analytics.customers (
    customer_id,
    customer_unique_id,
    customer_zip_code_prefix,
    customer_city,
    customer_state
)
SELECT
    customer_id,
    customer_unique_id,
    customer_zip_code_prefix,
    customer_city,
    customer_state
FROM ecommerce_analytics.customers_staging;

SELECT c.customer_unique_id, count(o.order_id) as total_orders
from ecommerce_analytics.customers as c
join ecommerce_analytics.orders as o
on c.customer_id = o.customer_id
group by c.customer_unique_id
having count(o.order_id) > 1
order by total_orders desc;


-- Calculate the percentage of unique customers who placed more than one order
WITH customer_order_counts AS (
    SELECT
        c.customer_unique_id,
        COUNT(o.order_id) AS total_orders
    FROM ecommerce_analytics.customers AS c
    JOIN ecommerce_analytics.orders AS o
        ON c.customer_id = o.customer_id
    GROUP BY c.customer_unique_id
)
SELECT
    COUNT(CASE WHEN total_orders > 1 THEN 1 END) AS repeat_customers,
    COUNT(*) AS total_customers,
    ROUND(
        COUNT(CASE WHEN total_orders > 1 THEN 1 END) * 100.0
        / COUNT(*),
        2
    ) AS repeat_customer_rate_pct
FROM customer_order_counts;


-- Create a staging table to import payment records for revenue analysis
CREATE TABLE ecommerce_analytics.order_payments_staging (
    order_id VARCHAR(50),
    payment_sequential INT,
    payment_type VARCHAR(30),
    payment_installments INT,
    payment_value DECIMAL(12,2)
);

-- Load all payment records into the staging table for order-level revenue analysis
LOAD DATA LOCAL INFILE 'D:/Downloads/archive (5)/olist_order_payments_dataset.csv'
INTO TABLE ecommerce_analytics.order_payments_staging
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

-- Verify that all payment records were loaded into the staging table
SELECT COUNT(*) AS total_payment_records
FROM ecommerce_analytics.order_payments_staging;

-- Create the final payment table for customer revenue and payment analysis
CREATE TABLE ecommerce_analytics.order_payments (
    order_id VARCHAR(50),
    payment_sequential INT,
    payment_type VARCHAR(30),
    payment_installments INT,
    payment_value DECIMAL(12,2),
    PRIMARY KEY (order_id, payment_sequential)
);

-- Transfer all verified payment records from staging into the final analysis table
INSERT INTO ecommerce_analytics.order_payments (
    order_id,
    payment_sequential,
    payment_type,
    payment_installments,
    payment_value
)
SELECT
    order_id,
    payment_sequential,
    payment_type,
    payment_installments,
    payment_value
FROM ecommerce_analytics.order_payments_staging;

-- Identify the 10 highest-revenue customers using their complete payment records
WITH order_payment_totals AS (
    SELECT
        order_id,
        SUM(payment_value) AS order_revenue
    FROM ecommerce_analytics.order_payments
    GROUP BY order_id
)
SELECT
    c.customer_unique_id,
    ROUND(SUM(p.order_revenue), 2) AS total_revenue
FROM ecommerce_analytics.customers AS c
JOIN ecommerce_analytics.orders AS o
    ON c.customer_id = o.customer_id
JOIN order_payment_totals AS p
    ON o.order_id = p.order_id
GROUP BY c.customer_unique_id
ORDER BY total_revenue DESC
LIMIT 10;

-- Calculate monthly revenue to identify sales trends over time
SELECT
    DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS revenue_month,
    COUNT(DISTINCT o.order_id) AS total_orders,
    ROUND(SUM(p.payment_value), 2) AS total_revenue
FROM ecommerce_analytics.orders AS o
JOIN ecommerce_analytics.order_payments AS p
    ON o.order_id = p.order_id
WHERE o.order_status = 'delivered'
GROUP BY DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m')
ORDER BY revenue_month;

-- Create a staging table to import product-level order items for category revenue analysis
CREATE TABLE ecommerce_analytics.order_items_staging (
    order_id VARCHAR(50),
    order_item_id INT,
    product_id VARCHAR(50),
    seller_id VARCHAR(50),
    shipping_limit_date DATETIME,
    price DECIMAL(12,2),
    freight_value DECIMAL(12,2)
);

-- Import all product-level order items for category and product revenue analysis
LOAD DATA LOCAL INFILE 'D:/Downloads/archive (5)/olist_order_items_dataset.csv'
INTO TABLE ecommerce_analytics.order_items_staging
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

-- Confirm that every order-item record was imported successfully
SELECT COUNT(*) AS total_order_items
FROM ecommerce_analytics.order_items_staging;

-- Create the final table for product-level sales and revenue analysis
CREATE TABLE ecommerce_analytics.order_items (
    order_id VARCHAR(50),
    order_item_id INT,
    product_id VARCHAR(50),
    seller_id VARCHAR(50),
    shipping_limit_date DATETIME,
    price DECIMAL(12,2),
    freight_value DECIMAL(12,2),
    PRIMARY KEY (order_id, order_item_id)
);

-- Convert empty shipping dates to NULL so MySQL can insert valid DATETIME values
INSERT INTO ecommerce_analytics.order_items (
    order_id,
    order_item_id,
    product_id,
    seller_id,
    shipping_limit_date,
    price,
    freight_value
)
SELECT
    order_id,
    order_item_id,
    product_id,
    seller_id,
    STR_TO_DATE(
        NULLIF(TRIM(shipping_limit_date), ''),
        '%Y-%m-%d %H:%i:%s'
    ),
    price,
    freight_value
FROM ecommerce_analytics.order_items_staging;

-- Create a staging table to import product details and category names
CREATE TABLE ecommerce_analytics.products_staging (
    product_id VARCHAR(50),
    product_category_name VARCHAR(100),
    product_name_length INT,
    product_description_length INT,
    product_photos_qty INT,
    product_weight_g INT,
    product_length_cm INT,
    product_height_cm INT,
    product_width_cm INT
);

-- Verify the product row count and check how many category names are missing
SELECT
    COUNT(*) AS total_products,
    SUM(
        CASE
            WHEN product_category_name IS NULL
                 OR TRIM(product_category_name) = ''
            THEN 1
            ELSE 0
        END
    ) AS missing_categories
FROM ecommerce_analytics.products_staging;

-- Display the product count and number of missing category names
SELECT
    COUNT(*) AS total_products,
    SUM(
        CASE
            WHEN product_category_name IS NULL
                 OR TRIM(product_category_name) = ''
            THEN 1
            ELSE 0
        END
    ) AS missing_categories
FROM ecommerce_analytics.products_staging;

-- Show the total number of products imported into the staging table
SELECT COUNT(*) AS total_products
FROM ecommerce_analytics.products_staging;

-- Create the final product dimension table for category and revenue analysis
CREATE TABLE ecommerce_analytics.products (
    product_id VARCHAR(50) PRIMARY KEY,
    product_category_name VARCHAR(100),
    product_name_length INT,
    product_description_length INT,
    product_photos_qty INT,
    product_weight_g INT,
    product_length_cm INT,
    product_height_cm INT,
    product_width_cm INT
);

-- Move product data into the final table while converting missing numeric values to NULL
INSERT INTO ecommerce_analytics.products (
    product_id,
    product_category_name,
    product_name_length,
    product_description_length,
    product_photos_qty,
    product_weight_g,
    product_length_cm,
    product_height_cm,
    product_width_cm
)
SELECT
    product_id,
    NULLIF(TRIM(product_category_name), ''),
    NULLIF(product_name_length, ''),
    NULLIF(product_description_length, ''),
    NULLIF(product_photos_qty, ''),
    NULLIF(product_weight_g, ''),
    NULLIF(product_length_cm, ''),
    NULLIF(product_height_cm, ''),
    NULLIF(product_width_cm, '')
FROM ecommerce_analytics.products_staging;

-- Rank product categories by the total sales value of their order items
SELECT
    COALESCE(
        p.product_category_name,
        'Unknown'
    ) AS product_category,
    COUNT(*) AS total_items_sold,
    ROUND(SUM(oi.price), 2) AS product_revenue,
    ROUND(SUM(oi.freight_value), 2) AS total_freight
FROM ecommerce_analytics.order_items AS oi
JOIN ecommerce_analytics.products AS p
    ON oi.product_id = p.product_id
JOIN ecommerce_analytics.orders AS o
    ON oi.order_id = o.order_id
WHERE o.order_status = 'delivered'
GROUP BY COALESCE(
    p.product_category_name,
    'Unknown'
)
ORDER BY product_revenue DESC
LIMIT 10;

-- Calculate each category's share of total delivered product revenue
WITH category_revenue AS (
    SELECT
        COALESCE(p.product_category_name, 'Unknown') AS product_category,
        SUM(oi.price) AS revenue
    FROM ecommerce_analytics.order_items AS oi
    JOIN ecommerce_analytics.products AS p
        ON oi.product_id = p.product_id
    JOIN ecommerce_analytics.orders AS o
        ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY COALESCE(p.product_category_name, 'Unknown')
)
SELECT
    product_category,
    ROUND(revenue, 2) AS product_revenue,
    ROUND(
        revenue * 100.0 / SUM(revenue) OVER (),
        2
    ) AS revenue_share_pct
FROM category_revenue
ORDER BY revenue DESC
LIMIT 10;

-- Calculate total product sales value across all delivered orders
SELECT
    COUNT(*) AS total_items_sold,
    ROUND(SUM(oi.price), 2) AS total_product_revenue,
    ROUND(SUM(oi.freight_value), 2) AS total_freight_revenue
FROM ecommerce_analytics.order_items AS oi
JOIN ecommerce_analytics.orders AS o
    ON oi.order_id = o.order_id
WHERE o.order_status = 'delivered';

-- Measure late deliveries and calculate the percentage of delivered orders arriving late
SELECT
    COUNT(*) AS delivered_orders,
    SUM(
        CASE
            WHEN order_delivered_customer_date > order_estimated_delivery_date
            THEN 1
            ELSE 0
        END
    ) AS late_orders,
    ROUND(
        100.0 * SUM(
            CASE
                WHEN order_delivered_customer_date > order_estimated_delivery_date
                THEN 1
                ELSE 0
            END
        ) / COUNT(*),
        2
    ) AS late_delivery_pct
FROM ecommerce_analytics.orders
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NOT NULL
  AND order_estimated_delivery_date IS NOT NULL;
  
  -- Identify customers inactive for 90+ days relative to the dataset's latest order date
WITH customer_last_order AS (
    SELECT
        c.customer_unique_id,
        MAX(o.order_purchase_timestamp) AS last_purchase_date
    FROM ecommerce_analytics.customers AS c
    JOIN ecommerce_analytics.orders AS o
        ON c.customer_id = o.customer_id
    GROUP BY c.customer_unique_id
),
dataset_end AS (
    SELECT MAX(order_purchase_timestamp) AS latest_order_date
    FROM ecommerce_analytics.orders
)
SELECT
    COUNT(*) AS total_customers,
    SUM(
        CASE
            WHEN DATEDIFF(d.latest_order_date, c.last_purchase_date) >= 90
            THEN 1
            ELSE 0
        END
    ) AS inactive_90_days,
    ROUND(
        100.0 * SUM(
            CASE
                WHEN DATEDIFF(d.latest_order_date, c.last_purchase_date) >= 90
                THEN 1
                ELSE 0
            END
        ) / COUNT(*),
        2
    ) AS inactive_customer_pct
FROM customer_last_order AS c
CROSS JOIN dataset_end AS d;

-- Measure one-time versus repeat customers to understand retention
WITH customer_order_counts AS (
    SELECT
        c.customer_unique_id,
        COUNT(o.order_id) AS total_orders
    FROM ecommerce_analytics.customers AS c
    JOIN ecommerce_analytics.orders AS o
        ON c.customer_id = o.customer_id
    GROUP BY c.customer_unique_id
)
SELECT
    CASE
        WHEN total_orders = 1 THEN 'One-time customer'
        ELSE 'Repeat customer'
    END AS customer_type,
    COUNT(*) AS customer_count,
    ROUND(
        100.0 * COUNT(*) / SUM(COUNT(*)) OVER (),
        2
    ) AS customer_percentage
FROM customer_order_counts
GROUP BY customer_type;

-- Compare monthly delivered order volume and recorded payment revenue over time
SELECT
    DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS order_month,
    COUNT(DISTINCT o.order_id) AS delivered_orders,
    ROUND(SUM(p.payment_value), 2) AS payment_revenue
FROM ecommerce_analytics.orders AS o
JOIN ecommerce_analytics.order_payments AS p
    ON o.order_id = p.order_id
WHERE o.order_status = 'delivered'
GROUP BY DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m')
ORDER BY order_month;

-- Calculate average payment revenue per delivered order
WITH order_revenue AS (
    SELECT
        o.order_id,
        SUM(p.payment_value) AS total_order_revenue
    FROM ecommerce_analytics.orders AS o
    JOIN ecommerce_analytics.order_payments AS p
        ON o.order_id = p.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY o.order_id
)
SELECT
    COUNT(*) AS delivered_orders,
    ROUND(SUM(total_order_revenue), 2) AS total_revenue,
    ROUND(AVG(total_order_revenue), 2) AS average_order_value
FROM order_revenue;


-- Compare delivered-order payment methods by transaction count and recorded revenue
SELECT
    p.payment_type,
    COUNT(*) AS payment_records,
    COUNT(DISTINCT p.order_id) AS unique_orders,
    ROUND(SUM(p.payment_value), 2) AS total_payment_value,
    ROUND(AVG(p.payment_value), 2) AS average_payment_value
FROM ecommerce_analytics.order_payments AS p
JOIN ecommerce_analytics.orders AS o
    ON p.order_id = o.order_id
WHERE o.order_status = 'delivered'
GROUP BY p.payment_type
ORDER BY total_payment_value DESC;

-- Compare order counts and recorded payment values across order statuses
SELECT
    o.order_status,
    COUNT(DISTINCT o.order_id) AS total_orders,
    ROUND(SUM(p.payment_value), 2) AS recorded_payment_value
FROM ecommerce_analytics.orders AS o
LEFT JOIN ecommerce_analytics.order_payments AS p
    ON o.order_id = p.order_id
GROUP BY o.order_status
ORDER BY recorded_payment_value DESC;


-- Segment customers by total historical revenue to identify high-value customers

WITH customer_revenue AS (
    SELECT
        c.customer_unique_id,
        SUM(p.payment_value) AS total_revenue
    FROM ecommerce_analytics.customers AS c
    JOIN ecommerce_analytics.orders AS o
        ON c.customer_id = o.customer_id
    JOIN ecommerce_analytics.order_payments AS p
        ON o.order_id = p.order_id
    GROUP BY c.customer_unique_id
),
customer_segments AS (
    SELECT
        customer_unique_id,
        total_revenue,
        CASE
            WHEN total_revenue >= 500 THEN 'High Value'
            WHEN total_revenue >= 200 THEN 'Medium Value'
            ELSE 'Low Value'
        END AS revenue_segment
    FROM customer_revenue
)
SELECT
    revenue_segment,
    COUNT(*) AS total_customers,
    ROUND(SUM(total_revenue), 2) AS total_revenue,
    ROUND(AVG(total_revenue), 2) AS average_customer_revenue
FROM customer_segments
GROUP BY revenue_segment
ORDER BY total_revenue DESC;


-- Measure monthly customer acquisition and subsequent repeat purchasing

WITH customer_months AS (
    SELECT DISTINCT
        c.customer_unique_id,
        DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS purchase_month
    FROM ecommerce_analytics.customers AS c
    JOIN ecommerce_analytics.orders AS o
        ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
),
first_purchase AS (
    SELECT
        customer_unique_id,
        MIN(purchase_month) AS first_purchase_month
    FROM customer_months
    GROUP BY customer_unique_id
)
SELECT
    f.first_purchase_month,
    COUNT(DISTINCT f.customer_unique_id) AS acquired_customers,
    COUNT(DISTINCT CASE
        WHEN cm.purchase_month > f.first_purchase_month
        THEN f.customer_unique_id
    END) AS customers_returned_in_later_months,
    ROUND(
        100.0 * COUNT(DISTINCT CASE
            WHEN cm.purchase_month > f.first_purchase_month
            THEN f.customer_unique_id
        END) / COUNT(DISTINCT f.customer_unique_id),
        2
    ) AS later_month_return_rate_pct
FROM first_purchase AS f
LEFT JOIN customer_months AS cm
    ON f.customer_unique_id = cm.customer_unique_id
GROUP BY f.first_purchase_month
ORDER BY f.first_purchase_month;


-- Measure delivery delays to identify potential customer-experience problems

SELECT
    COUNT(*) AS delivered_orders,
    SUM(
        CASE
            WHEN order_delivered_customer_date >
                 order_estimated_delivery_date
            THEN 1
            ELSE 0
        END
    ) AS late_orders,
    SUM(
        CASE
            WHEN order_delivered_customer_date <=
                 order_estimated_delivery_date
            THEN 1
            ELSE 0
        END
    ) AS on_time_or_early_orders,
    ROUND(
        100.0 * SUM(
            CASE
                WHEN order_delivered_customer_date >
                     order_estimated_delivery_date
                THEN 1
                ELSE 0
            END
        ) / COUNT(*),
        2
    ) AS late_delivery_pct
FROM ecommerce_analytics.orders
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NOT NULL
  AND order_estimated_delivery_date IS NOT NULL;
  
  -- Validate record counts and check order ID uniqueness before Power BI modelling

SELECT
    'orders' AS table_name,
    COUNT(*) AS total_rows,
    COUNT(DISTINCT order_id) AS unique_order_ids
FROM ecommerce_analytics.orders

UNION ALL

SELECT
    'customers' AS table_name,
    COUNT(*) AS total_rows,
    COUNT(DISTINCT customer_id) AS unique_order_ids
FROM ecommerce_analytics.customers

UNION ALL

SELECT
    'order_payments' AS table_name,
    COUNT(*) AS total_rows,
    COUNT(DISTINCT CONCAT(order_id, '-', payment_sequential)) AS unique_order_ids
FROM ecommerce_analytics.order_payments

UNION ALL

SELECT
    'order_items' AS table_name,
    COUNT(*) AS total_rows,
    COUNT(DISTINCT CONCAT(order_id, '-', order_item_id)) AS unique_order_ids
FROM ecommerce_analytics.order_items

UNION ALL

SELECT
    'products' AS table_name,
    COUNT(*) AS total_rows,
    COUNT(DISTINCT product_id) AS unique_order_ids
FROM ecommerce_analytics.products;