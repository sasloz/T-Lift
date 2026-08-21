/*=====================================================================
  Demo 01: B2B order workbench

  Shows:
    - many optional business filters
    - optional product lookups for product filters
    - readable static source procedure
    - rendered dynamic SQL that can reuse plans per query shape
=====================================================================*/

USE TLift_BusinessDemo;
GO

DROP PROCEDURE IF EXISTS dbo.demo01_OrderWorkbench_Source;
DROP PROCEDURE IF EXISTS dbo.demo01_OrderWorkbench_Recompile;
DROP PROCEDURE IF EXISTS dbo.demo01_OrderWorkbench_Rendered;
GO

CREATE OR ALTER PROCEDURE dbo.demo01_OrderWorkbench_Recompile
    @CustomerID INT = NULL,
    @CustomerSegment NVARCHAR(20) = NULL,
    @Region NVARCHAR(20) = NULL,
    @Status NVARCHAR(20) = NULL,
    @Channel NVARCHAR(20) = NULL,
    @DateFrom DATE = NULL,
    @DateTo DATE = NULL,
    @ProductCategory NVARCHAR(30) = NULL,
    @MinOrderAmount MONEY = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP (200)
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
    OPTION (RECOMPILE);
END;
GO

CREATE OR ALTER PROCEDURE dbo.demo01_OrderWorkbench_Source
    @CustomerID INT = NULL,
    @CustomerSegment NVARCHAR(20) = NULL,
    @Region NVARCHAR(20) = NULL,
    @Status NVARCHAR(20) = NULL,
    @Channel NVARCHAR(20) = NULL,
    @DateFrom DATE = NULL,
    @DateTo DATE = NULL,
    @ProductCategory NVARCHAR(30) = NULL,
    @MinOrderAmount MONEY = NULL
AS
BEGIN
    SET NOCOUNT ON;

                                                    --#define productFilter = @ProductCategory IS NOT NULL
                                                    --#[ Demo01_OrderWorkbench
SELECT TOP (200)
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
                                                    --#{if @CustomerID IS NOT NULL
AND
(
    @CustomerID IS NULL OR                          --#-
    o.CustomerID = @CustomerID
)
                                                    --#}
                                                    --#{if @CustomerSegment IS NOT NULL
AND
(
    @CustomerSegment IS NULL OR                     --#-
    c.CustomerSegment = @CustomerSegment
)
                                                    --#}
                                                    --#{if @Region IS NOT NULL
AND
(
    @Region IS NULL OR                              --#-
    c.Region = @Region
)
                                                    --#}
                                                    --#{if @Status IS NOT NULL
AND
(
    @Status IS NULL OR                              --#-
    o.Status = @Status
)
                                                    --#}
                                                    --#{if @Channel IS NOT NULL
AND
(
    @Channel IS NULL OR                             --#-
    o.Channel = @Channel
)
                                                    --#}
                                                    --#{if @DateFrom IS NOT NULL
AND
(
    @DateFrom IS NULL OR                            --#-
    o.OrderDate >= @DateFrom
)
                                                    --#}
                                                    --#{if @DateTo IS NOT NULL
AND
(
    @DateTo IS NULL OR                              --#-
    o.OrderDate < DATEADD(DAY, 1, @DateTo)
)
                                                    --#}
                                                    --#{if @MinOrderAmount IS NOT NULL
AND
(
    @MinOrderAmount IS NULL OR                      --#-
    o.TotalAmount >= @MinOrderAmount
)
                                                    --#}
                                                    --#{if productFilter
AND
(
    @ProductCategory IS NULL OR                     --#-
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
                                                    --#}
ORDER BY o.OrderDate DESC, o.OrderID DESC
                                                    --#]
END;
GO

DECLARE @dynsql NVARCHAR(MAX);

EXEC TLift_Engine.dbo.sp_tlift
    @DatabaseName = N'TLift_BusinessDemo',
    @SchemaName = N'dbo',
    @ProcedureName = N'demo01_OrderWorkbench_Source',
    @ProcedureNameNew = N'demo01_OrderWorkbench_Rendered',
    @Result = @dynsql OUTPUT;

SELECT @dynsql AS RenderedProcedure;
EXEC demo.ExecuteRenderedScript @dynsql;
GO

PRINT 'Static source procedure: still valid plain T-SQL.';
EXEC dbo.demo01_OrderWorkbench_Source
    @CustomerSegment = N'Enterprise',
    @Region = N'North',
    @Status = N'Shipped',
    @DateFrom = '2025-01-01';

PRINT 'Rendered procedure: same business call, but unused predicates are not in the dynamic SQL.';
EXEC dbo.demo01_OrderWorkbench_Rendered
    @CustomerSegment = N'Enterprise',
    @Region = N'North',
    @Status = N'Shipped',
    @DateFrom = '2025-01-01';

PRINT 'Rendered procedure with product filter: product joins are only present for this shape.';
EXEC dbo.demo01_OrderWorkbench_Rendered
    @ProductCategory = N'SpareParts',
    @MinOrderAmount = 10000,
    @DateFrom = '2025-01-01';

PRINT 'OPTION(RECOMPILE) comparison procedure: valid fallback, but compiles on every call.';
EXEC dbo.demo01_OrderWorkbench_Recompile
    @ProductCategory = N'SpareParts',
    @MinOrderAmount = 10000,
    @DateFrom = '2025-01-01';
GO

SELECT
    cp.usecounts,
    st.text
FROM sys.dm_exec_cached_plans AS cp
CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) AS st
WHERE st.text LIKE N'%/*Demo01_OrderWorkbench*/%'
  AND st.text NOT LIKE N'%dm_exec_cached_plans%'
ORDER BY cp.usecounts DESC;
GO
