(@CustomerID int,@CustomerSegment nvarchar(20),@Region nvarchar(20),@Status nvarchar(20),@Channel nvarchar(20),@DateFrom date,@DateTo date,@MinOrderAmount money,@ProductCategory nvarchar(30))SELECT TOP (200)
        /*Demo01_OrderWorkbench_Recompile*/
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
    WHERE
        (@CustomerID IS NULL OR o.CustomerID = @CustomerID)
        AND (@CustomerSegment IS NULL OR c.CustomerSegment = @CustomerSegment)
        AND (@Region IS NULL OR c.Region = @Region)
        AND (@Status IS NULL OR o.Status = @Status)
        AND (@Channel IS NULL OR o.Channel = @Channel)
        AND (@DateFrom IS NULL OR o.OrderDate >= @DateFrom)
        AND (@DateTo IS NULL OR o.OrderDate < DATEADD(DAY, 1, @DateTo))
        AND (@MinOrderAmount IS NULL OR o.TotalAmount >= @MinOrderAmount)
        AND
        (
            @ProductCategory IS NULL
            OR EXISTS
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
    OPTION (RECOMPILE)
