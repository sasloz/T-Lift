/*=====================================================================
  Demo 02: Dispatch SLA dashboard

  Shows:
    - wrapper generation for common dashboard usage patterns
    - dynamic predicates for dispatcher filters
    - local variable handoff into sp_executesql via --#var / --#usevar
=====================================================================*/

USE TLift_BusinessDemo;
GO

DROP PROCEDURE IF EXISTS dbo.demo02_DispatchQueue_Source;
DROP PROCEDURE IF EXISTS dbo.demo02_DispatchQueue_Recompile;
DROP PROCEDURE IF EXISTS dbo.demo02_DispatchQueue_Rendered;
DROP PROCEDURE IF EXISTS dbo.demo02_DispatchQueue_Rendered_technician;
DROP PROCEDURE IF EXISTS dbo.demo02_DispatchQueue_Rendered_region;
DROP PROCEDURE IF EXISTS dbo.demo02_DispatchQueue_Rendered_breach;
DROP PROCEDURE IF EXISTS dbo.demo02_DispatchQueue_Rendered_general;
GO

CREATE OR ALTER PROCEDURE dbo.demo02_DispatchQueue_Recompile
    @Region NVARCHAR(20) = NULL,
    @TechnicianID INT = NULL,
    @Priority TINYINT = NULL,
    @OnlyBreached BIT = 0,
    @CustomerID INT = NULL,
    @ProductCategory NVARCHAR(30) = NULL,
    @PageSize INT = 100
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @NowUtc DATETIME2(0) = SYSUTCDATETIME();

    SELECT TOP (@PageSize)
        /*Demo02_DispatchQueue_Recompile*/
        t.TicketID,
        t.OpenedAt,
        t.Region,
        t.Priority,
        t.Status,
        t.TechnicianID,
        t.ProductCategory,
        t.SLADeadline,
        c.CustomerName,
        c.CustomerSegment,
        MinutesToSLA = DATEDIFF(MINUTE, @NowUtc, t.SLADeadline)
    FROM demo.ServiceTickets AS t
    INNER JOIN demo.Customers AS c
        ON c.CustomerID = t.CustomerID
    WHERE t.Status IN (N'Open', N'Assigned', N'Waiting')
      AND (@Region IS NULL OR t.Region = @Region)
      AND (@TechnicianID IS NULL OR t.TechnicianID = @TechnicianID)
      AND (@Priority IS NULL OR t.Priority = @Priority)
      AND (@OnlyBreached = 0 OR t.SLADeadline < @NowUtc)
      AND (@CustomerID IS NULL OR t.CustomerID = @CustomerID)
      AND (@ProductCategory IS NULL OR t.ProductCategory = @ProductCategory)
    ORDER BY
        CASE WHEN t.SLADeadline < @NowUtc THEN 0 ELSE 1 END,
        t.Priority ASC,
        t.SLADeadline ASC
    OPTION (RECOMPILE);
END;
GO

CREATE OR ALTER PROCEDURE dbo.demo02_DispatchQueue_Source
    @Region NVARCHAR(20) = NULL,
    @TechnicianID INT = NULL,
    @Priority TINYINT = NULL,
    @OnlyBreached BIT = 0,
    @CustomerID INT = NULL,
    @ProductCategory NVARCHAR(30) = NULL,
    @PageSize INT = 100
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @NowUtc DATETIME2(0) = SYSUTCDATETIME(); --#var

--#wrapper
--#branch _technician @TechnicianID IS NOT NULL
--#branch _region @TechnicianID IS NULL AND @Region IS NOT NULL
--#branch _breach @TechnicianID IS NULL AND @Region IS NULL AND @OnlyBreached = 1
--#branch-default _general

                                                    --#[ Demo02_DispatchQueue
                                                    --#usevar @NowUtc
SELECT TOP (@PageSize)
    t.TicketID,
    t.OpenedAt,
    t.Region,
    t.Priority,
    t.Status,
    t.TechnicianID,
    t.ProductCategory,
    t.SLADeadline,
    c.CustomerName,
    c.CustomerSegment,
    MinutesToSLA = DATEDIFF(MINUTE, @NowUtc, t.SLADeadline)
FROM demo.ServiceTickets AS t
INNER JOIN demo.Customers AS c
    ON c.CustomerID = t.CustomerID
WHERE t.Status IN (N'Open', N'Assigned', N'Waiting')
                                                    --#{if @Region IS NOT NULL
AND
(
    @Region IS NULL OR                              --#-
    t.Region = @Region
)
                                                    --#}
                                                    --#{if @TechnicianID IS NOT NULL
AND
(
    @TechnicianID IS NULL OR                        --#-
    t.TechnicianID = @TechnicianID
)
                                                    --#}
                                                    --#{if @Priority IS NOT NULL
AND
(
    @Priority IS NULL OR                            --#-
    t.Priority = @Priority
)
                                                    --#}
                                                    --#{if @OnlyBreached = 1
AND
(
    @OnlyBreached = 0 OR                            --#-
    t.SLADeadline < @NowUtc
)
                                                    --#}
                                                    --#{if @CustomerID IS NOT NULL
AND
(
    @CustomerID IS NULL OR                          --#-
    t.CustomerID = @CustomerID
)
                                                    --#}
                                                    --#{if @ProductCategory IS NOT NULL
AND
(
    @ProductCategory IS NULL OR                     --#-
    t.ProductCategory = @ProductCategory
)
                                                    --#}
ORDER BY
    CASE WHEN t.SLADeadline < @NowUtc THEN 0 ELSE 1 END,
    t.Priority ASC,
    t.SLADeadline ASC
                                                    --#]
END;
GO

DECLARE @dynsql NVARCHAR(MAX);

EXEC TLift_Engine.dbo.sp_tlift
    @DatabaseName = N'TLift_BusinessDemo',
    @SchemaName = N'dbo',
    @ProcedureName = N'demo02_DispatchQueue_Source',
    @ProcedureNameNew = N'demo02_DispatchQueue_Rendered',
    @Result = @dynsql OUTPUT;

SELECT @dynsql AS RenderedProcedure;
EXEC demo.ExecuteRenderedScript @dynsql;
GO

PRINT 'Source procedure: valid catch-all query.';
EXEC dbo.demo02_DispatchQueue_Source
    @Region = N'West',
    @Priority = 1,
    @PageSize = 20;

PRINT 'Rendered wrapper: technician branch.';
EXEC dbo.demo02_DispatchQueue_Rendered
    @TechnicianID = 42,
    @OnlyBreached = 1,
    @PageSize = 20;

PRINT 'Rendered wrapper: region branch.';
EXEC dbo.demo02_DispatchQueue_Rendered
    @Region = N'West',
    @Priority = 1,
    @PageSize = 20;

PRINT 'Rendered wrapper: SLA breach branch.';
EXEC dbo.demo02_DispatchQueue_Rendered
    @OnlyBreached = 1,
    @ProductCategory = N'Hardware',
    @PageSize = 20;

PRINT 'OPTION(RECOMPILE) comparison procedure.';
EXEC dbo.demo02_DispatchQueue_Recompile
    @OnlyBreached = 1,
    @ProductCategory = N'Hardware',
    @PageSize = 20;
GO

SELECT
    o.name AS ProcedureName,
    ps.execution_count,
    ps.cached_time,
    ps.last_execution_time
FROM sys.dm_exec_procedure_stats AS ps
INNER JOIN sys.objects AS o
    ON o.object_id = ps.object_id
WHERE ps.database_id = DB_ID()
  AND o.name LIKE N'demo02_DispatchQueue_Rendered%'
ORDER BY o.name;
GO

SELECT
    cp.usecounts,
    st.text
FROM sys.dm_exec_cached_plans AS cp
CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) AS st
WHERE st.text LIKE N'%/*Demo02_DispatchQueue*/%'
  AND st.text NOT LIKE N'%dm_exec_cached_plans%'
ORDER BY cp.usecounts DESC;
GO
