/*=====================================================================
  Demo 03: Receivables risk dashboard

  Shows:
    - aggregate report with optional business filters
    - bucket-based plan cache segmentation for skewed exposure thresholds
    - local variable handoff for date calculations
=====================================================================*/

USE TLift_BusinessDemo;
GO

DROP PROCEDURE IF EXISTS dbo.demo03_ReceivablesRisk_Source;
DROP PROCEDURE IF EXISTS dbo.demo03_ReceivablesRisk_Recompile;
DROP PROCEDURE IF EXISTS dbo.demo03_ReceivablesRisk_Rendered;
GO

CREATE OR ALTER PROCEDURE dbo.demo03_ReceivablesRisk_Recompile
    @Region NVARCHAR(20) = NULL,
    @CustomerSegment NVARCHAR(20) = NULL,
    @RiskClass NVARCHAR(10) = NULL,
    @CurrencyCode CHAR(3) = NULL,
    @MinOpenAmount MONEY = NULL,
    @MinDaysPastDue INT = NULL,
    @IncludeDisputed BIT = 1,
    @TopN INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Today DATE = CONVERT(DATE, GETDATE());

    SELECT TOP (@TopN)
        /*Demo03_ReceivablesRisk_Recompile*/
        c.CustomerID,
        c.CustomerName,
        c.CustomerSegment,
        c.Region,
        InvoiceCount = COUNT_BIG(*),
        TotalOpenAmount = SUM(i.OpenAmount),
        OldestDueDate = MIN(i.DueDate),
        MaxDaysPastDue = MAX(DATEDIFF(DAY, i.DueDate, @Today)),
        DisputedAmount = SUM(CASE WHEN i.DisputeStatus = N'Disputed' THEN i.OpenAmount ELSE 0 END)
    FROM demo.Invoices AS i
    INNER JOIN demo.Customers AS c
        ON c.CustomerID = i.CustomerID
    WHERE i.OpenAmount > 0
      AND (@Region IS NULL OR c.Region = @Region)
      AND (@CustomerSegment IS NULL OR c.CustomerSegment = @CustomerSegment)
      AND (@RiskClass IS NULL OR i.RiskClass = @RiskClass)
      AND (@CurrencyCode IS NULL OR i.CurrencyCode = @CurrencyCode)
      AND (@IncludeDisputed = 1 OR i.DisputeStatus <> N'Disputed')
    GROUP BY
        c.CustomerID,
        c.CustomerName,
        c.CustomerSegment,
        c.Region
    HAVING (@MinOpenAmount IS NULL OR SUM(i.OpenAmount) >= @MinOpenAmount)
       AND (@MinDaysPastDue IS NULL OR MAX(DATEDIFF(DAY, i.DueDate, @Today)) >= @MinDaysPastDue)
    ORDER BY SUM(i.OpenAmount) DESC
    OPTION (RECOMPILE);
END;
GO

CREATE OR ALTER PROCEDURE dbo.demo03_ReceivablesRisk_Source
    @Region NVARCHAR(20) = NULL,
    @CustomerSegment NVARCHAR(20) = NULL,
    @RiskClass NVARCHAR(10) = NULL,
    @CurrencyCode CHAR(3) = NULL,
    @MinOpenAmount MONEY = NULL,
    @MinDaysPastDue INT = NULL,
    @IncludeDisputed BIT = 1,
    @TopN INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Today DATE = CONVERT(DATE, GETDATE()); --#var

                                                    --#[ Demo03_ReceivablesRisk
                                                    --#usevar @Today
                                                    --#buckets @MinOpenAmount: 1000, 10000, 50000, 250000
SELECT TOP (@TopN)
    c.CustomerID,
    c.CustomerName,
    c.CustomerSegment,
    c.Region,
    InvoiceCount = COUNT_BIG(*),
    TotalOpenAmount = SUM(i.OpenAmount),
    OldestDueDate = MIN(i.DueDate),
    MaxDaysPastDue = MAX(DATEDIFF(DAY, i.DueDate, @Today)),
    DisputedAmount = SUM(CASE WHEN i.DisputeStatus = N'Disputed' THEN i.OpenAmount ELSE 0 END)
FROM demo.Invoices AS i
INNER JOIN demo.Customers AS c
    ON c.CustomerID = i.CustomerID
WHERE i.OpenAmount > 0
                                                    --#{if @Region IS NOT NULL
AND
(
    @Region IS NULL OR                              --#-
    c.Region = @Region
)
                                                    --#}
                                                    --#{if @CustomerSegment IS NOT NULL
AND
(
    @CustomerSegment IS NULL OR                     --#-
    c.CustomerSegment = @CustomerSegment
)
                                                    --#}
                                                    --#{if @RiskClass IS NOT NULL
AND
(
    @RiskClass IS NULL OR                           --#-
    i.RiskClass = @RiskClass
)
                                                    --#}
                                                    --#{if @CurrencyCode IS NOT NULL
AND
(
    @CurrencyCode IS NULL OR                        --#-
    i.CurrencyCode = @CurrencyCode
)
                                                    --#}
                                                    --#{if @IncludeDisputed = 0
AND
(
    @IncludeDisputed = 1 OR                         --#-
    i.DisputeStatus <> N'Disputed'
)
                                                    --#}
GROUP BY
    c.CustomerID,
    c.CustomerName,
    c.CustomerSegment,
    c.Region
HAVING 1 = 1
                                                    --#{if @MinOpenAmount IS NOT NULL
AND
(
    @MinOpenAmount IS NULL OR                       --#-
    SUM(i.OpenAmount) >= @MinOpenAmount
)
                                                    --#}
                                                    --#{if @MinDaysPastDue IS NOT NULL
AND
(
    @MinDaysPastDue IS NULL OR                      --#-
    MAX(DATEDIFF(DAY, i.DueDate, @Today)) >= @MinDaysPastDue
)
                                                    --#}
ORDER BY SUM(i.OpenAmount) DESC
                                                    --#]
END;
GO

DECLARE @dynsql NVARCHAR(MAX);

EXEC TLift_Engine.dbo.sp_tlift
    @DatabaseName = N'TLift_BusinessDemo',
    @SchemaName = N'dbo',
    @ProcedureName = N'demo03_ReceivablesRisk_Source',
    @ProcedureNameNew = N'demo03_ReceivablesRisk_Rendered',
    @Result = @dynsql OUTPUT;

SELECT @dynsql AS RenderedProcedure;
EXEC demo.ExecuteRenderedScript @dynsql;
GO

PRINT 'Source procedure: readable aggregate business query.';
EXEC dbo.demo03_ReceivablesRisk_Source
    @Region = N'North',
    @RiskClass = N'High',
    @MinOpenAmount = 10000,
    @MinDaysPastDue = 30,
    @TopN = 20;

PRINT 'Rendered procedure: same report with dynamic filters and threshold bucket.';
EXEC dbo.demo03_ReceivablesRisk_Rendered
    @Region = N'North',
    @RiskClass = N'High',
    @MinOpenAmount = 10000,
    @MinDaysPastDue = 30,
    @TopN = 20;

PRINT 'Rendered procedure: different exposure bucket, separate reusable plan comment.';
EXEC dbo.demo03_ReceivablesRisk_Rendered
    @CustomerSegment = N'Enterprise',
    @MinOpenAmount = 250000,
    @IncludeDisputed = 0,
    @TopN = 20;

PRINT 'OPTION(RECOMPILE) comparison procedure.';
EXEC dbo.demo03_ReceivablesRisk_Recompile
    @CustomerSegment = N'Enterprise',
    @MinOpenAmount = 250000,
    @IncludeDisputed = 0,
    @TopN = 20;
GO

SELECT
    cp.usecounts,
    st.text
FROM sys.dm_exec_cached_plans AS cp
CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) AS st
WHERE st.text LIKE N'%/*Demo03_ReceivablesRisk*/%'
  AND st.text NOT LIKE N'%dm_exec_cached_plans%'
ORDER BY cp.usecounts DESC;
GO
