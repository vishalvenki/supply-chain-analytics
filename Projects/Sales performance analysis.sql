CREATE DATABASE supply_analytics;

USE supply_analytics;

-- import csv tables into database using table data import wizard

-- create back up copy of sales table, since it needs some data wrangling 

CREATE TABLE sales_copy LIKE sales;

INSERT INTO sales_copy
SELECT *
FROM sales; 


-- Changing dates to DATE data types 
UPDATE sales SET `Procured Date` = STR_TO_DATE(`Procured Date`, '%m/%d/%Y'); 
ALTER TABLE sales MODIFY COLUMN `Procured Date` DATE; 

UPDATE sales SET OrderDate = STR_TO_DATE(OrderDate, '%m/%d/%Y'); 
ALTER TABLE sales MODIFY COLUMN OrderDate DATE; 

UPDATE sales SET `Delivery Date` = STR_TO_DATE(`Delivery Date`, '%m/%d/%Y'); 
ALTER TABLE sales MODIFY COLUMN `Delivery Date` DATE; 

-- rounding unit cost to 2 d.p 
UPDATE sales
SET `Unit Cost` = ROUND(`Unit Cost`, 2);

-- Range of orders
SELECT 
	MIN(`OrderDate`) as `Earliest order date`,
	MAX(`OrderDate`) as `Latest order date`
FROM sales;

-- Total revenue and total profit over the recording period 
SELECT 
	CONCAT('$',FORMAT(ROUND(
	SUM(`Order Quantity` * `Unit Price`) / 1000000, 1), 1), 'M') AS `Total Revenue`, 
	CONCAT('$',FORMAT(ROUND(
	(SUM(`Order Quantity` * `Unit Price`) - SUM(`Order Quantity` * `Unit Cost`))/ 1000000, 1), 1), 'M') AS `Total Profit`     
FROM sales;

-- Monthly revenue and the cumulative revenue generated 
SELECT 
    date_format(`orderdate`, '%Y-%m') AS `Month`,
    FORMAT(ROUND(SUM(`Order Quantity` * `Unit Price`),1),1) AS `Total Revenue`,
    FORMAT(ROUND(SUM(SUM(`Order Quantity` * `Unit Price`)) OVER (ORDER BY DATE_FORMAT(`orderdate`, '%Y-%m')), 1),1) AS `Cumulative Revenue`
FROM 
    sales
GROUP BY 
    `Month`
ORDER BY
    `Month`;

-- Total unique orders 
SELECT 
	COUNT(
	DISTINCT(`OrderNumber`)) 
	as `Unique orders` 
FROM sales;

-- Average lead time 
SELECT 
    Round(AVG(DATEDIFF(`Delivery Date`, `OrderDate`)), 1) AS `Avg Lead Time (Days)`
FROM sales;

-- Total revenue by channel and % contribution of each channel to revenue 
SELECT `channel`, 
		FORMAT(ROUND(SUM(`Order Quantity` * `Unit Price`),0),0) AS `Channel Revenue`,
		ROUND(SUM(`Order Quantity` * `Unit Price`) / (SELECT
        ROUND(SUM(`Order Quantity` * `Unit Price`),1) FROM sales ) *100,1) AS `% percent`
FROM sales
GROUP BY `channel`
ORDER BY `Channel revenue` DESC;

-- Revenue by warehouse and the order quantities from respective warehouses
SELECT
	`Warehouse Code`,
    sum(`order quantity`) as `order quantities`,
	Format(Round(SUM(`Order Quantity` * `Unit Price`),1),1) AS `Total Revenue` 
FROM sales s
join warehouse w using (`Warehouse Index`)
GROUP BY `Warehouse code`
ORDER BY `Total Revenue` DESC;

-- Warehouses which contribute the most to cross provincial orders 
SELECT
    w.`warehouse code`,
    COUNT(*) AS `Cross-Province Order Count`
FROM sales s
JOIN region r ON s.`region index` = r.`index`
JOIN warehouse w ON s.`warehouse index` = w.`warehouse index`
WHERE r.province <> w.province
GROUP BY w.`warehouse code`;

-- Determining the profitability category of each order and shipment category 
SELECT
    s.`Ordernumber`, 
    s.`Orderdate`, 
    p.`Product name`,
    FORMAT((s.`Order quantity` * (s.`Unit price` - s.`Unit cost`)),0) AS `Profit`,
    CASE
        WHEN (s.`Order quantity` * (s.`Unit price` - s.`Unit cost`)) > 10000 THEN 'High Profit'
        WHEN (s.`Order quantity` * (s.`Unit price` - s.`Unit cost`)) BETWEEN 5000 AND 10000 
        THEN 'Moderate Profit' ELSE 'Low Profit'
    END AS `Profit Category`,
    r.province AS `Order province`,
    w.province AS `Warehouse province`,
    CASE
        WHEN r.province <> w.province THEN 'Cross Province'
        ELSE 'Same Province'
    END AS `Shipment Type`
FROM sales s
JOIN products p ON s.`product index` = p.`index`
JOIN region r ON s.`region index` = r.`index`
JOIN warehouse w ON s.`warehouse index` = w.`warehouse index`;

-- Total Revenue by province 
SELECT 
    `Province`,
    FORMAT(ROUND(SUM(`Order Quantity` * `Unit Price`), 1), 1) AS `Total Provincial Revenue`,
    ROUND(SUM(`Order Quantity` * `Unit Price`) / (SELECT SUM(`Order Quantity` * `Unit Price`) FROM sales) * 100,2) AS `% Provincial Revenue`
FROM 
    sales s
JOIN 
    region r ON r.`Index` = s.`Region Index`
GROUP BY 
    `Province`
ORDER BY 
    `Total Provincial Revenue`,
    `% Provincial Revenue`;
    
-- Top 5 most profitable products 
SELECT
    `Product Name`,
    Format(round(SUM(`Order Quantity` * (`Unit Price` - `Unit Cost`)),2),1) AS `Total Profit`
FROM sales s
JOIN
    products p ON s.`Product Index` = p.`index`
GROUP BY
    `Product Name`
ORDER BY
    `Total Profit` DESC
LIMIT 5;

-- Top 3 profitable products per province 
SELECT *
FROM (
    SELECT 
        r.`province`, 
        p.`product name`,
        ROUND(SUM(s.`Order Quantity` * (s.`Unit Price` - s.`Unit Cost`)), 1) AS `profit`,
        ROW_NUMBER() OVER(PARTITION BY r.`province` ORDER BY ROUND(SUM(s.`Order Quantity` * (
        s.`Unit Price` - s.`Unit Cost`)), 1) DESC) AS rn
    FROM 
        sales s
    JOIN 
        products p ON s.`Product Index` = p.`Index`
    JOIN 
        region r ON s.`Region Index` = r.`Index`
    GROUP BY 
        r.`province`, p.`product name`
) AS provincial_revenue
WHERE rn <= 3;

-- Top 3 most profitable customers 
SELECT
    `Customer Names`,
    FORMAT(SUM(`Order Quantity` * (`Unit Price` - `Unit Cost`)), 0) AS `Profit`
FROM
    sales s
JOIN
    customers c ON s.`Customer Index` = c.`Customer Index`
GROUP BY
    `Customer Names`
ORDER BY
    SUM(`Order Quantity` * (`Unit Price` - `Unit Cost`)) desc 
LIMIT 3;

-- Retrieve order number, customer name, product name, total spent of the top 3 orders which generated the most revenue
WITH order_revenue AS (
    SELECT 
        `OrderNumber`, 
        SUM(`Order Quantity` * `Unit Price`) AS `total_spend`
    FROM sales
    GROUP BY `OrderNumber`
    ORDER BY `total_spend` DESC
    LIMIT 3 )
    
SELECT 
    s.`OrderNumber`,
    c.`Customer Names`,
    p.`Product name`,
    o.`total_spend`
FROM sales s
JOIN order_revenue o ON s.`OrderNumber` = o.`OrderNumber`
Join products p on s.`Product Index` = p.`Index`
Join customers c on s.`Customer Index` = c.`Customer Index`
ORDER BY o.`total_spend` DESC;

-- Who bought the most expensive products
SELECT 
    c.`customer names`,
    p.`Product Name`,
    s.`Unit Price`
FROM 
    products p
JOIN sales s ON p.`Index` = s.`Product Index`
JOIN customers c ON s.`Customer Index` = c.`Customer Index`
WHERE s.`Unit Price` = (
    SELECT MAX(s2.`Unit Price`)
    FROM sales s2);

-- City with the most customers 
SELECT r.`city`, COUNT(DISTINCT s.`customer index`) AS customer_count
FROM sales s
LEFT JOIN customers c ON s.`customer index` = c.`customer index`
LEFT JOIN region r ON s.`region index` = r.index
GROUP BY r.city
ORDER BY customer_count DESC
LIMIT 5;

-- Daily trends of orders 
SELECT 
    DATE_FORMAT(`OrderDate`, '%W') AS `Week day`,
    COUNT(DISTINCT `OrderNumber`) AS `Total Orders`
FROM 
    sales
GROUP BY 
    `week day`
ORDER BY 
    `Total Orders` DESC;

-- Overall Monthly trends 
SELECT 
    DATE_FORMAT(`OrderDate`, '%b') AS `Month`,
    COUNT(OrderNumber) as `Monthly orders`,
    SUM(`Order Quantity` * `Unit Price`) AS `Monthly Sales`
From sales 
GROUP BY `Month`
ORDER BY `Monthly orders` DESC ;

-- Yearly sales
SELECT 
    YEAR(`OrderDate`) AS `Year`,
    FORMAT(SUM(`Order Quantity` * `Unit Price`), 0) AS `Total Sales`
FROM 
    sales 
GROUP BY 
    `Year`;
    
-- Monthly sales trends for the year 2020
SELECT 
    DATE_FORMAT(`OrderDate`, '%M') AS `Month`,
    SUM(`Order Quantity` * `Unit Price`) AS `Total Sales`
FROM 
    sales 
WHERE 
    YEAR(`OrderDate`) = 2020
GROUP BY 
    MONTH
order by `total sales` desc;

-- Monthly orders for 2018, 2019 and 2020 
SELECT 
    YEAR(`OrderDate`) AS `Year`,
    MONTH(`OrderDate`) AS `Month`,
    COUNT(DISTINCT `OrderNumber`) AS `Total Orders`
FROM 
    sales
WHERE 
    YEAR(`OrderDate`) IN (2018, 2019, 2020)
GROUP BY 
    `Year`, `Month`
ORDER BY 
    `Year`, `Month`;
    
-- YTD sales (2020)
SELECT
    concat(Format(round(SUM(`Order quantity` * `unit price`)/1000000,1),1),'M') AS ytd_sales
FROM
    sales
WHERE
    `OrderDate` >= '2020-01-01'
    AND `OrderDate` <= '2020-12-31';

-- PYTD sales 
SELECT
    concat(Format(round(SUM(`Order quantity` * `unit price`)/1000000,1),1),'M') AS pytd_sales
FROM
    sales
WHERE
    `OrderDate` >= '2019-01-01'
    AND `OrderDate` <= '2019-12-31';
