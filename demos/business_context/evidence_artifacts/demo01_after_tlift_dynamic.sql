(@CustomerID int, @CustomerSegment nvarchar(20), @Region nvarchar(20), @Status nvarchar(20), @Channel nvarchar(20), @DateFrom date, @DateTo date, @ProductCategory nvarchar(30), @MinOrderAmount money)/*Demo01_OrderWorkbench*/SELECT TOP (200)
o.OrderID,
o.OrderDate,
o.Status,
o.Channel,
o.TotalAmount,
c.CustomerID,
c.CustomerName,
c.CustomerSegment,
c.Region
FROM demo.SalesOrders AS o
INNER JOIN demo.Customers AS c
ON c.CustomerID = o.CustomerID
WHERE 1 = 1
AND
(
o.OrderDate >= @DateFrom
)
AND
(
o.TotalAmount >= @MinOrderAmount
)
AND
(
EXISTS
(
SELECT 1
FROM demo.SalesOrderLines AS sol
INNER JOIN demo.Products AS p
ON p.ProductID = sol.ProductID
WHERE sol.OrderID = o.OrderID
AND p.ProductCategory = @ProductCategory
)
)
ORDER BY o.OrderDate DESC, o.OrderID DESC

