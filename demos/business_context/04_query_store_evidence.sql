/*=====================================================================
  Demo 04: Query Store evidence for T-Lift vs OPTION(RECOMPILE)

  This script does not try to prove that every T-Lift plan is always faster.
  SQL Server performance is data-, statistics-, version-, and workload-dependent.

  It proves the things that are stable and relevant:
    1. OPTION(RECOMPILE) is a valid baseline, but compile work repeats.
    2. T-Lift produces reusable dynamic SQL shapes for repeated business calls.
    3. Query Store can show compile counts, compile duration, worker time,
       reads, plan count, and stored execution plans for those shapes.

  Run after:
    00_setup_business_context_demo.sql
    01_b2b_order_workbench.sql
    02_dispatch_sla_dashboard.sql
    03_finance_receivables_risk.sql
=====================================================================*/

SET NOCOUNT ON;
GO

IF DB_ID(N'TLift_BusinessDemo') IS NULL
BEGIN
    THROW 52000, 'TLift_BusinessDemo not found. Run 00_setup_business_context_demo.sql first.', 1;
END;
GO

DECLARE @MajorVersion INT = TRY_CONVERT(INT, SERVERPROPERTY('ProductMajorVersion'));

IF @MajorVersion IS NULL OR @MajorVersion < 13
BEGIN
    THROW 52001, 'Query Store requires SQL Server 2016 or newer for this demo.', 1;
END;
GO

ALTER DATABASE TLift_BusinessDemo SET QUERY_STORE = ON;
ALTER DATABASE TLift_BusinessDemo SET QUERY_STORE
(
    OPERATION_MODE = READ_WRITE,
    QUERY_CAPTURE_MODE = ALL,
    INTERVAL_LENGTH_MINUTES = 1,
    MAX_STORAGE_SIZE_MB = 256
);
ALTER DATABASE TLift_BusinessDemo SET QUERY_STORE CLEAR;
GO

USE TLift_BusinessDemo;
GO

IF OBJECT_ID(N'dbo.demo01_OrderWorkbench_Rendered', N'P') IS NULL
   OR OBJECT_ID(N'dbo.demo02_DispatchQueue_Rendered', N'P') IS NULL
   OR OBJECT_ID(N'dbo.demo03_ReceivablesRisk_Rendered', N'P') IS NULL
BEGIN
    THROW 52002, 'Rendered demo procedures not found. Run demo scripts 01, 02, and 03 first.', 1;
END;
GO

DECLARE @DemoDatabaseID INT = DB_ID();
DBCC FLUSHPROCINDB(@DemoDatabaseID) WITH NO_INFOMSGS;
GO

DECLARE @Iterations INT = 25;
DECLARE @i INT = 1;

PRINT 'Running repeated business workload against OPTION(RECOMPILE) and T-Lift rendered procedures...';

WHILE @i <= @Iterations
BEGIN
    EXEC dbo.demo01_OrderWorkbench_Recompile
        @CustomerSegment = N'Enterprise',
        @Region = N'North',
        @Status = N'Shipped',
        @DateFrom = '2025-01-01';

    EXEC dbo.demo01_OrderWorkbench_Rendered
        @CustomerSegment = N'Enterprise',
        @Region = N'North',
        @Status = N'Shipped',
        @DateFrom = '2025-01-01';

    EXEC dbo.demo01_OrderWorkbench_Recompile
        @ProductCategory = N'SpareParts',
        @MinOrderAmount = 10000,
        @DateFrom = '2025-01-01';

    EXEC dbo.demo01_OrderWorkbench_Rendered
        @ProductCategory = N'SpareParts',
        @MinOrderAmount = 10000,
        @DateFrom = '2025-01-01';

    EXEC dbo.demo02_DispatchQueue_Recompile
        @TechnicianID = 42,
        @OnlyBreached = 1,
        @PageSize = 20;

    EXEC dbo.demo02_DispatchQueue_Rendered
        @TechnicianID = 42,
        @OnlyBreached = 1,
        @PageSize = 20;

    EXEC dbo.demo02_DispatchQueue_Recompile
        @TechnicianID = 126,
        @OnlyBreached = 1,
        @PageSize = 20;

    EXEC dbo.demo02_DispatchQueue_Rendered
        @TechnicianID = 126,
        @OnlyBreached = 1,
        @PageSize = 20;

    EXEC dbo.demo03_ReceivablesRisk_Recompile
        @Region = N'North',
        @RiskClass = N'High',
        @MinOpenAmount = 10000,
        @MinDaysPastDue = 30,
        @TopN = 20;

    EXEC dbo.demo03_ReceivablesRisk_Rendered
        @Region = N'North',
        @RiskClass = N'High',
        @MinOpenAmount = 10000,
        @MinDaysPastDue = 30,
        @TopN = 20;

    EXEC dbo.demo03_ReceivablesRisk_Recompile
        @CustomerSegment = N'Enterprise',
        @MinOpenAmount = 250000,
        @IncludeDisputed = 0,
        @TopN = 20;

    EXEC dbo.demo03_ReceivablesRisk_Rendered
        @CustomerSegment = N'Enterprise',
        @MinOpenAmount = 250000,
        @IncludeDisputed = 0,
        @TopN = 20;

    SET @i += 1;
END;
GO

BEGIN TRY
    EXEC sys.sp_query_store_flush_db;
END TRY
BEGIN CATCH
    PRINT 'Could not flush Query Store explicitly. The result queries can still work after Query Store flushes asynchronously.';
END CATCH;
GO

DECLARE @Evidence TABLE
(
    Family NVARCHAR(80) NOT NULL,
    Variant NVARCHAR(20) NOT NULL,
    Pattern NVARCHAR(200) NOT NULL
);

INSERT @Evidence (Family, Variant, Pattern)
VALUES
    (N'01 Order workbench', N'RECOMPILE', N'%Demo01_OrderWorkbench_Recompile%'),
    (N'01 Order workbench', N'T-LIFT',    N'%/*Demo01_OrderWorkbench*/%'),
    (N'02 Dispatch SLA',    N'RECOMPILE', N'%Demo02_DispatchQueue_Recompile%'),
    (N'02 Dispatch SLA',    N'T-LIFT',    N'%/*Demo02_DispatchQueue*/%'),
    (N'03 Receivables risk',N'RECOMPILE', N'%Demo03_ReceivablesRisk_Recompile%'),
    (N'03 Receivables risk',N'T-LIFT',    N'%/*Demo03_ReceivablesRisk*/%');

DROP TABLE IF EXISTS demo.EvidenceResults;

CREATE TABLE demo.EvidenceResults
(
    EvidenceID INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_demo_EvidenceResults PRIMARY KEY,
    CapturedAt DATETIME2(0) NOT NULL CONSTRAINT DF_demo_EvidenceResults_CapturedAt DEFAULT SYSUTCDATETIME(),
    CheckName NVARCHAR(120) NOT NULL,
    Status NVARCHAR(10) NOT NULL,
    Detail NVARCHAR(MAX) NOT NULL
);

CREATE TABLE #EvidenceSummary
(
    Family NVARCHAR(80) NOT NULL,
    Variant NVARCHAR(20) NOT NULL,
    QueryTexts BIGINT NOT NULL,
    Plans INT NOT NULL,
    Executions BIGINT NULL,
    Compiles BIGINT NULL,
    CompilePerExecution DECIMAL(19,4) NULL,
    ApproxCompileMs DECIMAL(19,2) NULL,
    AvgCpuUs DECIMAL(19,2) NULL,
    AvgDurationUs DECIMAL(19,2) NULL,
    AvgLogicalReads DECIMAL(19,2) NULL
);

CREATE TABLE #PlanCacheReuse
(
    Family NVARCHAR(80) NOT NULL,
    plan_handle VARBINARY(64) NOT NULL,
    usecounts INT NOT NULL,
    CompileCpuMs DECIMAL(19,2) NULL,
    text NVARCHAR(MAX) NULL
);

INSERT #PlanCacheReuse (Family, plan_handle, usecounts, CompileCpuMs, text)
SELECT
    e.Family,
    cp.plan_handle,
    cp.usecounts,
    CompileCpuMs = COALESCE(
        CASE
            WHEN qp.query_plan.exist('declare default element namespace "http://schemas.microsoft.com/sqlserver/2004/07/showplan"; //QueryPlan/@CompileCPU') = 1
                THEN TRY_CONVERT(DECIMAL(19,2), qp.query_plan.value('declare default element namespace "http://schemas.microsoft.com/sqlserver/2004/07/showplan"; (//QueryPlan/@CompileCPU)[1]', 'int'))
        END,
        CASE
            WHEN qp.query_plan.exist('declare default element namespace "http://schemas.microsoft.com/sqlserver/2004/07/showplan"; //QueryPlan/@CompileTime') = 1
                THEN TRY_CONVERT(DECIMAL(19,2), qp.query_plan.value('declare default element namespace "http://schemas.microsoft.com/sqlserver/2004/07/showplan"; (//QueryPlan/@CompileTime)[1]', 'int'))
        END
    ),
    st.text
FROM @Evidence AS e
INNER JOIN sys.dm_exec_cached_plans AS cp
    ON 1 = 1
CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) AS st
CROSS APPLY sys.dm_exec_query_plan(cp.plan_handle) AS qp
WHERE e.Variant = N'T-LIFT'
  AND st.text LIKE e.Pattern
  AND st.text LIKE N'(@%'
  AND st.text NOT LIKE N'%dm_exec_cached_plans%'
  AND st.text NOT LIKE N'%@Evidence%';

PRINT 'Evidence 1: Query Store plus plan-cache compile/reuse summary.';

;WITH Captured AS
(
    SELECT
        e.Family,
        e.Variant,
        q.query_id,
        p.plan_id,
        q.count_compiles,
        q.avg_compile_duration,
        rs.count_executions,
        rs.avg_duration,
        rs.avg_cpu_time,
        rs.avg_logical_io_reads
    FROM @Evidence AS e
    INNER JOIN sys.query_store_query_text AS qt
        ON qt.query_sql_text LIKE e.Pattern
       AND qt.query_sql_text NOT LIKE N'%sys.query_store_query_text%'
       AND qt.query_sql_text NOT LIKE N'%@Evidence%'
    INNER JOIN sys.query_store_query AS q
        ON q.query_text_id = qt.query_text_id
    INNER JOIN sys.query_store_plan AS p
        ON p.query_id = q.query_id
    LEFT JOIN sys.query_store_runtime_stats AS rs
        ON rs.plan_id = p.plan_id
       AND rs.execution_type_desc = N'Regular'
),
QueryLevel AS
(
    SELECT
        Family,
        Variant,
        query_id,
        count_compiles = MAX(count_compiles),
        avg_compile_duration = MAX(avg_compile_duration)
    FROM Captured
    GROUP BY Family, Variant, query_id
),
CompileLevel AS
(
    SELECT
        Family,
        Variant,
        QueryTexts = COUNT_BIG(*),
        Compiles = SUM(count_compiles),
        ApproxCompileMs = SUM(CONVERT(DECIMAL(19,2), count_compiles) * CONVERT(DECIMAL(19,2), avg_compile_duration)) / 1000.0
    FROM QueryLevel
    GROUP BY Family, Variant
),
RuntimeLevel AS
(
    SELECT
        Family,
        Variant,
        Plans = COUNT(DISTINCT plan_id),
        Executions = SUM(ISNULL(count_executions, 0)),
        AvgCpuUs = SUM(CONVERT(DECIMAL(19,2), ISNULL(avg_cpu_time, 0)) * ISNULL(count_executions, 0))
            / NULLIF(SUM(ISNULL(count_executions, 0)), 0),
        AvgDurationUs = SUM(CONVERT(DECIMAL(19,2), ISNULL(avg_duration, 0)) * ISNULL(count_executions, 0))
            / NULLIF(SUM(ISNULL(count_executions, 0)), 0),
        AvgLogicalReads = SUM(CONVERT(DECIMAL(19,2), ISNULL(avg_logical_io_reads, 0)) * ISNULL(count_executions, 0))
            / NULLIF(SUM(ISNULL(count_executions, 0)), 0)
    FROM Captured
    GROUP BY Family, Variant
)
INSERT #EvidenceSummary
(
    Family,
    Variant,
    QueryTexts,
    Plans,
    Executions,
    Compiles,
    CompilePerExecution,
    ApproxCompileMs,
    AvgCpuUs,
    AvgDurationUs,
    AvgLogicalReads
)
SELECT
    c.Family,
    c.Variant,
    c.QueryTexts,
    r.Plans,
    r.Executions,
    c.Compiles,
    CompilePerExecution = CONVERT(DECIMAL(19,4), c.Compiles) / NULLIF(r.Executions, 0),
    ApproxCompileMs = CONVERT(DECIMAL(19,2), c.ApproxCompileMs),
    AvgCpuUs = CONVERT(DECIMAL(19,2), r.AvgCpuUs),
    AvgDurationUs = CONVERT(DECIMAL(19,2), r.AvgDurationUs),
    AvgLogicalReads = CONVERT(DECIMAL(19,2), r.AvgLogicalReads)
FROM CompileLevel AS c
INNER JOIN RuntimeLevel AS r
    ON r.Family = c.Family
   AND r.Variant = c.Variant;

INSERT #EvidenceSummary
(
    Family,
    Variant,
    QueryTexts,
    Plans,
    Executions,
    Compiles,
    CompilePerExecution,
    ApproxCompileMs,
    AvgCpuUs,
    AvgDurationUs,
    AvgLogicalReads
)
SELECT
    Family,
    Variant = N'T-LIFT',
    QueryTexts = COUNT_BIG(*),
    Plans = COUNT(*),
    Executions = SUM(ISNULL(qs.execution_count, usecounts)),
    Compiles = COUNT_BIG(*),
    CompilePerExecution = CONVERT(DECIMAL(19,4), CONVERT(DECIMAL(19,4), COUNT_BIG(*)) / NULLIF(SUM(ISNULL(qs.execution_count, usecounts)), 0)),
    ApproxCompileMs = SUM(ISNULL(CompileCpuMs, 0)),
    AvgCpuUs = SUM(CONVERT(DECIMAL(19,2), ISNULL(qs.total_worker_time, 0))) / NULLIF(SUM(ISNULL(qs.execution_count, 0)), 0),
    AvgDurationUs = SUM(CONVERT(DECIMAL(19,2), ISNULL(qs.total_elapsed_time, 0))) / NULLIF(SUM(ISNULL(qs.execution_count, 0)), 0),
    AvgLogicalReads = SUM(CONVERT(DECIMAL(19,2), ISNULL(qs.total_logical_reads, 0))) / NULLIF(SUM(ISNULL(qs.execution_count, 0)), 0)
FROM #PlanCacheReuse AS pc
LEFT JOIN sys.dm_exec_query_stats AS qs
    ON qs.plan_handle = pc.plan_handle
GROUP BY Family;

SELECT
    Family,
    Variant,
    QueryTexts,
    Plans,
    Executions,
    Compiles,
    CompilePerExecution,
    ApproxCompileMs,
    AvgCpuUs,
    AvgDurationUs,
    AvgLogicalReads
FROM #EvidenceSummary
ORDER BY Family, Variant;

DROP TABLE IF EXISTS demo.EvidenceMetricSummary;

CREATE TABLE demo.EvidenceMetricSummary
(
    Family NVARCHAR(80) NOT NULL,
    Variant NVARCHAR(20) NOT NULL,
    QueryTexts BIGINT NOT NULL,
    Plans INT NOT NULL,
    Executions BIGINT NULL,
    Compiles BIGINT NULL,
    CompilePerExecution DECIMAL(19,4) NULL,
    ApproxCompileMs DECIMAL(19,2) NULL,
    AvgCpuUs DECIMAL(19,2) NULL,
    AvgDurationUs DECIMAL(19,2) NULL,
    AvgLogicalReads DECIMAL(19,2) NULL
);

INSERT demo.EvidenceMetricSummary
(
    Family,
    Variant,
    QueryTexts,
    Plans,
    Executions,
    Compiles,
    CompilePerExecution,
    ApproxCompileMs,
    AvgCpuUs,
    AvgDurationUs,
    AvgLogicalReads
)
SELECT
    Family,
    Variant,
    QueryTexts,
    Plans,
    Executions,
    Compiles,
    CompilePerExecution,
    ApproxCompileMs,
    AvgCpuUs,
    AvgDurationUs,
    AvgLogicalReads
FROM #EvidenceSummary;

CREATE TABLE #EvidenceText
(
    Family NVARCHAR(80) NOT NULL,
    Variant NVARCHAR(20) NOT NULL,
    QueryTexts BIGINT NOT NULL,
    HasCatchAllCustomerPredicate BIT NOT NULL,
    HasCatchAllProductPredicate BIT NOT NULL,
    HasProductLookup BIT NOT NULL,
    HasBucketComment BIT NOT NULL,
    SampleText NVARCHAR(700) NULL
);

PRINT 'Evidence 2: Query-shape proof. T-Lift text should contain only active predicates/lookups.';

;WITH CapturedText AS
(
    SELECT DISTINCT
        e.Family,
        e.Variant,
        q.query_id,
        QueryText = CONVERT(NVARCHAR(4000), qt.query_sql_text)
    FROM @Evidence AS e
    INNER JOIN sys.query_store_query_text AS qt
        ON qt.query_sql_text LIKE e.Pattern
       AND qt.query_sql_text NOT LIKE N'%sys.query_store_query_text%'
       AND qt.query_sql_text NOT LIKE N'%@Evidence%'
    INNER JOIN sys.query_store_query AS q
        ON q.query_text_id = qt.query_text_id
)
INSERT #EvidenceText
(
    Family,
    Variant,
    QueryTexts,
    HasCatchAllCustomerPredicate,
    HasCatchAllProductPredicate,
    HasProductLookup,
    HasBucketComment,
    SampleText
)
SELECT
    Family,
    Variant,
    QueryTexts = COUNT_BIG(*),
    HasCatchAllCustomerPredicate = MAX(CASE WHEN QueryText LIKE N'%@CustomerID IS NULL OR%' THEN 1 ELSE 0 END),
    HasCatchAllProductPredicate = MAX(CASE WHEN QueryText LIKE N'%@ProductCategory IS NULL OR%' THEN 1 ELSE 0 END),
    HasProductLookup = MAX(CASE WHEN QueryText LIKE N'%demo.SalesOrderLines%' THEN 1 ELSE 0 END),
    HasBucketComment = MAX(CASE WHEN QueryText LIKE N'%/*00*/%' OR QueryText LIKE N'%/*01*/%' OR QueryText LIKE N'%/*02*/%' OR QueryText LIKE N'%/*03*/%' OR QueryText LIKE N'%/*04*/%' THEN 1 ELSE 0 END),
    SampleText = LEFT(MIN(QueryText), 700)
FROM CapturedText
GROUP BY Family, Variant;

INSERT #EvidenceText
(
    Family,
    Variant,
    QueryTexts,
    HasCatchAllCustomerPredicate,
    HasCatchAllProductPredicate,
    HasProductLookup,
    HasBucketComment,
    SampleText
)
SELECT
    Family,
    Variant = N'T-LIFT',
    QueryTexts = COUNT_BIG(*),
    HasCatchAllCustomerPredicate = MAX(CASE WHEN text LIKE N'%@CustomerID IS NULL OR%' THEN 1 ELSE 0 END),
    HasCatchAllProductPredicate = MAX(CASE WHEN text LIKE N'%@ProductCategory IS NULL OR%' THEN 1 ELSE 0 END),
    HasProductLookup = MAX(CASE WHEN text LIKE N'%demo.SalesOrderLines%' THEN 1 ELSE 0 END),
    HasBucketComment = MAX(CASE WHEN text LIKE N'%/*00*/%' OR text LIKE N'%/*01*/%' OR text LIKE N'%/*02*/%' OR text LIKE N'%/*03*/%' OR text LIKE N'%/*04*/%' THEN 1 ELSE 0 END),
    SampleText = LEFT(MIN(CONVERT(NVARCHAR(4000), text)), 700)
FROM #PlanCacheReuse
GROUP BY Family;

SELECT
    Family,
    Variant,
    QueryTexts,
    HasCatchAllCustomerPredicate,
    HasCatchAllProductPredicate,
    HasProductLookup,
    HasBucketComment,
    SampleText
FROM #EvidenceText
ORDER BY Family, Variant;

CREATE TABLE #EvidencePlan
(
    Family NVARCHAR(80) NOT NULL,
    Variant NVARCHAR(20) NOT NULL,
    query_id BIGINT NULL,
    plan_id BIGINT NULL,
    HasIndexSeek BIT NOT NULL,
    HasIndexScan BIT NOT NULL,
    HasTableScan BIT NOT NULL,
    HasHashMatch BIT NOT NULL,
    HasNestedLoops BIT NOT NULL,
    query_plan XML NULL
);

PRINT 'Evidence 3: Stored plans from Query Store and plan cache. Open query_plan XML to compare seek/scan/join differences.';

;WITH XMLNAMESPACES(DEFAULT 'http://schemas.microsoft.com/sqlserver/2004/07/showplan'),
CapturedPlans AS
(
    SELECT
        e.Family,
        e.Variant,
        q.query_id,
        p.plan_id,
        PlanXml = TRY_CONVERT(XML, p.query_plan)
    FROM @Evidence AS e
    INNER JOIN sys.query_store_query_text AS qt
        ON qt.query_sql_text LIKE e.Pattern
       AND qt.query_sql_text NOT LIKE N'%sys.query_store_query_text%'
       AND qt.query_sql_text NOT LIKE N'%@Evidence%'
    INNER JOIN sys.query_store_query AS q
        ON q.query_text_id = qt.query_text_id
    INNER JOIN sys.query_store_plan AS p
        ON p.query_id = q.query_id
)
INSERT #EvidencePlan
(
    Family,
    Variant,
    query_id,
    plan_id,
    HasIndexSeek,
    HasIndexScan,
    HasTableScan,
    HasHashMatch,
    HasNestedLoops,
    query_plan
)
SELECT
    Family,
    Variant,
    query_id,
    plan_id,
    HasIndexSeek = CASE WHEN PlanXml.exist('//RelOp[@PhysicalOp="Index Seek"]') = 1 THEN 1 ELSE 0 END,
    HasIndexScan = CASE WHEN PlanXml.exist('//RelOp[@PhysicalOp="Index Scan"]') = 1 THEN 1 ELSE 0 END,
    HasTableScan = CASE WHEN PlanXml.exist('//RelOp[@PhysicalOp="Table Scan"]') = 1 THEN 1 ELSE 0 END,
    HasHashMatch = CASE WHEN PlanXml.exist('//RelOp[@PhysicalOp="Hash Match"]') = 1 THEN 1 ELSE 0 END,
    HasNestedLoops = CASE WHEN PlanXml.exist('//RelOp[@PhysicalOp="Nested Loops"]') = 1 THEN 1 ELSE 0 END,
    query_plan = PlanXml
FROM CapturedPlans
WHERE PlanXml IS NOT NULL;

;WITH XMLNAMESPACES(DEFAULT 'http://schemas.microsoft.com/sqlserver/2004/07/showplan')
INSERT #EvidencePlan
(
    Family,
    Variant,
    query_id,
    plan_id,
    HasIndexSeek,
    HasIndexScan,
    HasTableScan,
    HasHashMatch,
    HasNestedLoops,
    query_plan
)
SELECT
    pc.Family,
    Variant = N'T-LIFT',
    query_id = NULL,
    plan_id = NULL,
    HasIndexSeek = CASE WHEN qp.query_plan.exist('//RelOp[@PhysicalOp="Index Seek"]') = 1 THEN 1 ELSE 0 END,
    HasIndexScan = CASE WHEN qp.query_plan.exist('//RelOp[@PhysicalOp="Index Scan"]') = 1 THEN 1 ELSE 0 END,
    HasTableScan = CASE WHEN qp.query_plan.exist('//RelOp[@PhysicalOp="Table Scan"]') = 1 THEN 1 ELSE 0 END,
    HasHashMatch = CASE WHEN qp.query_plan.exist('//RelOp[@PhysicalOp="Hash Match"]') = 1 THEN 1 ELSE 0 END,
    HasNestedLoops = CASE WHEN qp.query_plan.exist('//RelOp[@PhysicalOp="Nested Loops"]') = 1 THEN 1 ELSE 0 END,
    query_plan = qp.query_plan
FROM #PlanCacheReuse AS pc
CROSS APPLY sys.dm_exec_query_plan(pc.plan_handle) AS qp
WHERE qp.query_plan IS NOT NULL;

SELECT
    Family,
    Variant,
    query_id,
    plan_id,
    HasIndexSeek,
    HasIndexScan,
    HasTableScan,
    HasHashMatch,
    HasNestedLoops,
    query_plan
FROM #EvidencePlan
ORDER BY Family, Variant, query_id, plan_id;

PRINT 'Evidence 4: Normal plan cache reuse for T-Lift dynamic SQL labels.';

SELECT
    Family,
    usecounts,
    text
FROM #PlanCacheReuse
ORDER BY Family, usecounts DESC, text;

INSERT demo.EvidenceResults (CheckName, Status, Detail)
SELECT
    N'Evidence captured all demo variants',
    CASE WHEN COUNT(*) = 6 THEN N'PASS' ELSE N'FAIL' END,
    CONCAT(N'Captured variant rows: ', COUNT(*), N' of 6 expected.')
FROM #EvidenceSummary;

INSERT demo.EvidenceResults (CheckName, Status, Detail)
SELECT
    CONCAT(Family, N' - compile work comparison'),
    CASE
        WHEN MAX(CASE WHEN Variant = N'RECOMPILE' THEN CompilePerExecution END)
             > MAX(CASE WHEN Variant = N'T-LIFT' THEN CompilePerExecution END)
            THEN N'PASS'
        ELSE N'WARN'
    END,
    CONCAT(
        N'CompilePerExecution RECOMPILE=',
        COALESCE(CONVERT(NVARCHAR(40), MAX(CASE WHEN Variant = N'RECOMPILE' THEN CompilePerExecution END)), N'n/a'),
        N', T-LIFT=',
        COALESCE(CONVERT(NVARCHAR(40), MAX(CASE WHEN Variant = N'T-LIFT' THEN CompilePerExecution END)), N'n/a'),
        N'. RECOMPILE should normally compile repeatedly, while T-Lift should reuse dynamic SQL shapes.'
    )
FROM #EvidenceSummary
GROUP BY Family;

INSERT demo.EvidenceResults (CheckName, Status, Detail)
SELECT
    CONCAT(Family, N' - total CPU/read comparison'),
    CASE
        WHEN
        (
            MAX(CASE WHEN Variant = N'T-LIFT' THEN AvgCpuUs END)
            + ISNULL(MAX(CASE WHEN Variant = N'T-LIFT' THEN ApproxCompileMs * 1000.0 / NULLIF(Executions, 0) END), 0)
        )
        <=
        (
            MAX(CASE WHEN Variant = N'RECOMPILE' THEN AvgCpuUs END)
            + ISNULL(MAX(CASE WHEN Variant = N'RECOMPILE' THEN ApproxCompileMs * 1000.0 / NULLIF(Executions, 0) END), 0)
        )
         AND MAX(CASE WHEN Variant = N'T-LIFT' THEN AvgLogicalReads END)
             <= MAX(CASE WHEN Variant = N'RECOMPILE' THEN AvgLogicalReads END)
            THEN N'PASS'
        ELSE N'FAIL'
    END,
    CONCAT(
        N'AvgExecCpuUs RECOMPILE=',
        COALESCE(CONVERT(NVARCHAR(40), MAX(CASE WHEN Variant = N'RECOMPILE' THEN AvgCpuUs END)), N'n/a'),
        N', T-LIFT=',
        COALESCE(CONVERT(NVARCHAR(40), MAX(CASE WHEN Variant = N'T-LIFT' THEN AvgCpuUs END)), N'n/a'),
        N'; AvgTotalCpuUsInclCompile RECOMPILE=',
        COALESCE(CONVERT(NVARCHAR(40),
            MAX(CASE WHEN Variant = N'RECOMPILE' THEN AvgCpuUs END)
            + ISNULL(MAX(CASE WHEN Variant = N'RECOMPILE' THEN ApproxCompileMs * 1000.0 / NULLIF(Executions, 0) END), 0)
        ), N'n/a'),
        N', T-LIFT=',
        COALESCE(CONVERT(NVARCHAR(40),
            MAX(CASE WHEN Variant = N'T-LIFT' THEN AvgCpuUs END)
            + ISNULL(MAX(CASE WHEN Variant = N'T-LIFT' THEN ApproxCompileMs * 1000.0 / NULLIF(Executions, 0) END), 0)
        ), N'n/a'),
        N'; AvgLogicalReads RECOMPILE=',
        COALESCE(CONVERT(NVARCHAR(40), MAX(CASE WHEN Variant = N'RECOMPILE' THEN AvgLogicalReads END)), N'n/a'),
        N', T-LIFT=',
        COALESCE(CONVERT(NVARCHAR(40), MAX(CASE WHEN Variant = N'T-LIFT' THEN AvgLogicalReads END)), N'n/a'),
        N'.'
    )
FROM #EvidenceSummary
GROUP BY Family;

INSERT demo.EvidenceResults (CheckName, Status, Detail)
SELECT
    N'T-Lift query text removes catch-all predicates',
    CASE
        WHEN SUM(CASE WHEN Variant = N'T-LIFT' AND (HasCatchAllCustomerPredicate = 1 OR HasCatchAllProductPredicate = 1) THEN 1 ELSE 0 END) = 0
            THEN N'PASS'
        ELSE N'FAIL'
    END,
    N'T-Lift dynamic SQL text should not contain @param IS NULL OR catch-all predicates for the active shapes.'
FROM #EvidenceText;

INSERT demo.EvidenceResults (CheckName, Status, Detail)
SELECT
    N'Order workbench has optional product-shape split',
    CASE
        WHEN
        EXISTS
        (
            SELECT 1
            FROM #PlanCacheReuse AS pc
            WHERE pc.Family = N'01 Order workbench'
              AND pc.text LIKE N'%demo.SalesOrderLines%'
        )
        AND EXISTS
        (
            SELECT 1
            FROM #PlanCacheReuse AS pc
            WHERE pc.Family = N'01 Order workbench'
              AND pc.text NOT LIKE N'%demo.SalesOrderLines%'
        )
            THEN N'PASS'
        ELSE N'WARN'
    END,
    N'Demo 01 should produce at least one T-Lift query shape with product lookup and at least one without it.'
FROM (VALUES (0)) AS v(n);

INSERT demo.EvidenceResults (CheckName, Status, Detail)
SELECT
    N'Receivables risk exposes bucketed dynamic SQL',
    CASE
        WHEN EXISTS
        (
            SELECT 1
            FROM #EvidenceText
            WHERE Family = N'03 Receivables risk'
              AND Variant = N'T-LIFT'
              AND HasBucketComment = 1
        )
            THEN N'PASS'
        ELSE N'FAIL'
    END,
    N'Demo 03 should show bucket comments such as /*01*/ or /*04*/ in T-Lift dynamic SQL text.'
FROM (VALUES (0)) AS v(n);

INSERT demo.EvidenceResults (CheckName, Status, Detail)
SELECT
    N'Execution plans captured as XML',
    CASE WHEN COUNT(*) >= 6 THEN N'PASS' ELSE N'FAIL' END,
    CONCAT(N'Captured Query Store and plan-cache plans with XML: ', COUNT(*), N'. Open query_plan to inspect seek/scan/join choices.')
FROM #EvidencePlan;

INSERT demo.EvidenceResults (CheckName, Status, Detail)
SELECT
    N'T-Lift dynamic SQL plan cache reuse',
    CASE WHEN MAX(usecounts) >= 2 THEN N'PASS' ELSE N'WARN' END,
    CONCAT(N'Max plan-cache usecounts for T-Lift labeled dynamic SQL: ', COALESCE(CONVERT(NVARCHAR(40), MAX(usecounts)), N'n/a'), N'.')
FROM #PlanCacheReuse;

PRINT 'Evidence 5: Persisted PASS/WARN/FAIL result summary.';

SELECT
    EvidenceID,
    CapturedAt,
    CheckName,
    Status,
    Detail
FROM demo.EvidenceResults
ORDER BY EvidenceID;

IF EXISTS (SELECT 1 FROM demo.EvidenceResults WHERE Status = N'FAIL')
BEGIN
    THROW 52003, 'Evidence demo completed, but one or more evidence checks failed. Inspect demo.EvidenceResults.', 1;
END;
GO
