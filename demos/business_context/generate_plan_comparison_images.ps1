param(
    [string]$ArtifactDir = (Join-Path $PSScriptRoot "evidence_artifacts"),
    [string]$Server = "localhost,1433",
    [string]$User = "sa",
    [string]$Password = $env:TLIFT_SQL_PASSWORD,
    [switch]$UseIntegratedSecurity
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Drawing

function New-Connection {
    param([string]$Database)

    $connection = New-Object System.Data.SqlClient.SqlConnection
    $builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
    $builder["Data Source"] = $Server
    $builder["Initial Catalog"] = $Database
    $builder["Encrypt"] = $false
    $builder["TrustServerCertificate"] = $true
    $builder["Connect Timeout"] = 15

    if ($UseIntegratedSecurity) {
        $builder["Integrated Security"] = $true
    }
    else {
        if ([string]::IsNullOrWhiteSpace($Password)) {
            throw "Provide -Password, set TLIFT_SQL_PASSWORD, or use -UseIntegratedSecurity."
        }
        $builder["User ID"] = $User
        $builder["Password"] = $Password
    }

    $connection.ConnectionString = $builder.ConnectionString
    return $connection
}

function Invoke-Query {
    param([string]$Sql)

    $connection = New-Connection -Database "TLift_BusinessDemo"
    try {
        $connection.Open()
        $command = $connection.CreateCommand()
        $command.CommandTimeout = 120
        $command.CommandText = $Sql
        $adapter = New-Object System.Data.SqlClient.SqlDataAdapter $command
        $table = New-Object System.Data.DataTable
        [void]$adapter.Fill($table)
        return ,$table
    }
    finally {
        $connection.Close()
    }
}

function Get-RuntimeMetrics {
    $sql = @"
SELECT
    DemoKey = CASE Family
        WHEN N'01 Order workbench' THEN 'demo01'
        WHEN N'02 Dispatch SLA' THEN 'demo02'
        WHEN N'03 Receivables risk' THEN 'demo03'
    END,
    Variant = CASE Variant
        WHEN N'RECOMPILE' THEN 'before'
        WHEN N'T-LIFT' THEN 'after'
    END,
    Executions,
    AvgWorkerUs = AvgCpuUs,
    AvgElapsedUs = AvgDurationUs,
    AvgLogicalReads,
    Compiles,
    CompilePerExecution,
    ApproxCompileMs,
    MaxUseCount = CONVERT(int, NULL),
    Shapes = Plans
FROM demo.EvidenceMetricSummary;
"@

    $table = Invoke-Query -Sql $sql
    $useCountSql = @"
SELECT
    DemoKey = CASE e.Family
        WHEN N'01 Order workbench' THEN 'demo01'
        WHEN N'02 Dispatch SLA' THEN 'demo02'
        WHEN N'03 Receivables risk' THEN 'demo03'
    END,
    MaxUseCount = MAX(cp.usecounts)
FROM
(
    VALUES
        (N'01 Order workbench', N'%/*Demo01_OrderWorkbench*/%'),
        (N'02 Dispatch SLA', N'%/*Demo02_DispatchQueue*/%'),
        (N'03 Receivables risk', N'%/*Demo03_ReceivablesRisk*/%')
) AS e(Family, Pattern)
INNER JOIN sys.dm_exec_cached_plans AS cp
    ON 1 = 1
CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) AS st
WHERE st.text LIKE e.Pattern
  AND st.text LIKE N'(@%'
  AND st.text NOT LIKE N'%dm_exec_cached_plans%'
GROUP BY e.Family;
"@
    $useCounts = Invoke-Query -Sql $useCountSql
    $useCountMap = @{}
    foreach ($row in $useCounts.Rows) {
        $useCountMap[[string]$row.DemoKey] = [int]$row.MaxUseCount
    }

    $map = @{}
    foreach ($row in $table.Rows) {
        $key = "$($row.DemoKey):$($row.Variant)"
        $maxUseCount = if ($row.Variant -eq "after" -and $useCountMap.ContainsKey([string]$row.DemoKey)) { $useCountMap[[string]$row.DemoKey] } else { $null }
        $map[$key] = [pscustomobject]@{
            Executions = [int64]$row.Executions
            AvgWorkerUs = [decimal]$row.AvgWorkerUs
            AvgElapsedUs = [decimal]$row.AvgElapsedUs
            AvgLogicalReads = [decimal]$row.AvgLogicalReads
            Compiles = [int64]$row.Compiles
            CompilePerExecution = [decimal]$row.CompilePerExecution
            ApproxCompileMs = if ([DBNull]::Value.Equals($row.ApproxCompileMs)) { $null } else { [decimal]$row.ApproxCompileMs }
            MaxUseCount = $maxUseCount
            Shapes = [int64]$row.Shapes
        }
    }
    return $map
}

function Get-PlanInfo {
    param(
        [string]$PlanPath,
        [string]$QueryPath,
        [Nullable[int]]$UseCount
    )

    [xml]$xml = Get-Content -LiteralPath $PlanPath -Raw
    $ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
    $ns.AddNamespace("sp", "http://schemas.microsoft.com/sqlserver/2004/07/showplan")

    $stmt = $xml.SelectSingleNode("//sp:StmtSimple", $ns)
    $queryPlan = $xml.SelectSingleNode("//sp:QueryPlan", $ns)
    $relOps = @($xml.SelectNodes("//sp:RelOp", $ns))
    $queryText = Get-Content -LiteralPath $QueryPath -Raw

    $operatorCounts = $relOps |
        Group-Object { $_.PhysicalOp } |
        Sort-Object -Property @{ Expression = "Count"; Descending = $true }, @{ Expression = "Name"; Descending = $false } |
        Select-Object -First 7

    $topOps = $relOps |
        Sort-Object { [double]($_.EstimatedTotalSubtreeCost) } -Descending |
        Select-Object -First 5

    return [pscustomobject]@{
        PlanFile = Split-Path -Leaf $PlanPath
        QueryFile = Split-Path -Leaf $QueryPath
        StatementCost = [double]$stmt.StatementSubTreeCost
        EstRows = [double]$stmt.StatementEstRows
        CompileTimeMs = if ($queryPlan.CompileTime) { [int]$queryPlan.CompileTime } else { $null }
        CompileCpuMs = if ($queryPlan.CompileCPU) { [int]$queryPlan.CompileCPU } else { $null }
        CachedPlanSizeKb = if ($queryPlan.CachedPlanSize) { [int]$queryPlan.CachedPlanSize } else { $null }
        MemoryGrantKb = if ($queryPlan.MemoryGrantInfo.SerialDesiredMemory) { [int]$queryPlan.MemoryGrantInfo.SerialDesiredMemory } else { $null }
        UseCount = $UseCount
        HasCatchAll = $queryText -match "@[A-Za-z0-9_]+ IS NULL OR"
        HasProductLookup = $queryText -match "demo\.SalesOrderLines"
        HasBucketComment = $queryText -match "/\*0[0-9]\*/"
        OperatorCounts = $operatorCounts
        TopOperators = $topOps
    }
}

function Write-WrappedText {
    param(
        [System.Drawing.Graphics]$Graphics,
        [string]$Text,
        [System.Drawing.Font]$Font,
        [System.Drawing.Brush]$Brush,
        [int]$X,
        [int]$Y,
        [int]$Width,
        [int]$LineHeight
    )

    $words = $Text -split "\s+"
    $line = ""
    $currentY = $Y

    foreach ($word in $words) {
        $candidate = if ($line.Length -eq 0) { $word } else { "$line $word" }
        if ($Graphics.MeasureString($candidate, $Font).Width -gt $Width -and $line.Length -gt 0) {
            $Graphics.DrawString($line, $Font, $Brush, $X, $currentY)
            $currentY += $LineHeight
            $line = $word
        }
        else {
            $line = $candidate
        }
    }

    if ($line.Length -gt 0) {
        $Graphics.DrawString($line, $Font, $Brush, $X, $currentY)
        $currentY += $LineHeight
    }

    return $currentY
}

function Draw-PlanPanel {
    param(
        [System.Drawing.Graphics]$Graphics,
        [object]$Info,
        [string]$Title,
        [int]$X,
        [int]$Y,
        [int]$Width,
        [int]$Height,
        [System.Drawing.Brush]$AccentBrush
    )

    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(210, 210, 210), 2)
    $Graphics.FillRectangle([System.Drawing.Brushes]::White, $X, $Y, $Width, $Height)
    $Graphics.DrawRectangle($pen, $X, $Y, $Width, $Height)
    $Graphics.FillRectangle($AccentBrush, $X, $Y, $Width, 8)

    $titleFont = New-Object System.Drawing.Font("Segoe UI", 18, [System.Drawing.FontStyle]::Bold)
    $labelFont = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $textFont = New-Object System.Drawing.Font("Segoe UI", 10)
    $monoFont = New-Object System.Drawing.Font("Consolas", 9)
    $dark = [System.Drawing.Brushes]::Black
    $muted = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(80, 80, 80))

    $cursorY = $Y + 22
    $Graphics.DrawString($Title, $titleFont, $dark, $X + 18, $cursorY)
    $cursorY += 38

    $metrics = @()
    if ($Info.Runtime) {
        $compileUs = if ($null -eq $Info.Runtime.ApproxCompileMs -or $Info.Runtime.Executions -eq 0) { 0 } else { ($Info.Runtime.ApproxCompileMs * 1000) / $Info.Runtime.Executions }
        $totalCpuUs = $Info.Runtime.AvgWorkerUs + $compileUs
        $metrics += ("Avg total CPU incl compile: {0:N0} us" -f $totalCpuUs)
        $metrics += ("Avg logical reads: {0:N0}" -f $Info.Runtime.AvgLogicalReads)
        $metrics += ("Compile per execution: {0:N4}" -f $Info.Runtime.CompilePerExecution)
        $metrics += ("Avg execution CPU only: {0:N0} us" -f $Info.Runtime.AvgWorkerUs)
        $metrics += ("Avg elapsed: {0:N0} us" -f $Info.Runtime.AvgElapsedUs)
        $metrics += ("Executions / shapes: {0} / {1}" -f $Info.Runtime.Executions, $Info.Runtime.Shapes)
    }

    $metrics += ("Estimated plan cost (not runtime proof): {0:N4}" -f $Info.StatementCost)
    $metrics += ("Estimated rows: {0:N2}" -f $Info.EstRows)
    $metrics += ("Plan compile time / CPU: {0} ms / {1} ms" -f $(if ($null -eq $Info.CompileTimeMs) { "n/a" } else { $Info.CompileTimeMs }), $(if ($null -eq $Info.CompileCpuMs) { "n/a" } else { $Info.CompileCpuMs }))
    $metrics += ("Cached plan size: {0} KB" -f $(if ($null -eq $Info.CachedPlanSizeKb) { "n/a" } else { $Info.CachedPlanSizeKb }))
    $metrics += ("Plan cache usecount: {0}" -f $(if ($null -eq $Info.UseCount) { "n/a" } else { $Info.UseCount }))

    foreach ($metric in $metrics) {
        $Graphics.DrawString($metric, $textFont, $dark, $X + 18, $cursorY)
        $cursorY += 23
    }

    $cursorY += 6
    $shapeText = "Shape: catch-all predicates={0}; product lookup={1}; bucket comment={2}" -f $Info.HasCatchAll, $Info.HasProductLookup, $Info.HasBucketComment
    $cursorY = Write-WrappedText -Graphics $Graphics -Text $shapeText -Font $labelFont -Brush $dark -X ($X + 18) -Y $cursorY -Width ($Width - 36) -LineHeight 20

    $cursorY += 12
    $Graphics.DrawString("Operator counts", $labelFont, $dark, $X + 18, $cursorY)
    $cursorY += 22
    foreach ($op in $Info.OperatorCounts) {
        $Graphics.DrawString(("{0}: {1}" -f $op.Name, $op.Count), $textFont, $dark, $X + 28, $cursorY)
        $cursorY += 21
    }

    $cursorY += 12
    $Graphics.DrawString("Top estimated-cost operators", $labelFont, $dark, $X + 18, $cursorY)
    $cursorY += 22
    foreach ($op in $Info.TopOperators) {
        $line = "#{0} {1} / {2} cost={3:N4} rows={4:N2}" -f $op.NodeId, $op.PhysicalOp, $op.LogicalOp, [double]$op.EstimatedTotalSubtreeCost, [double]$op.EstimateRows
        $cursorY = Write-WrappedText -Graphics $Graphics -Text $line -Font $monoFont -Brush $dark -X ($X + 28) -Y $cursorY -Width ($Width - 56) -LineHeight 18
    }

    $cursorY = $Y + $Height - 56
    $Graphics.DrawString($Info.PlanFile, $monoFont, $muted, $X + 18, $cursorY)
    $Graphics.DrawString($Info.QueryFile, $monoFont, $muted, $X + 18, $cursorY + 18)
}

function New-ComparisonImage {
    param(
        [string]$DemoName,
        [string]$Title,
        [string]$BeforePlan,
        [string]$BeforeQuery,
        [string]$AfterPlan,
        [string]$AfterQuery,
        [Nullable[int]]$AfterUseCount,
        [hashtable]$RuntimeMetrics
    )

    $before = Get-PlanInfo -PlanPath (Join-Path $ArtifactDir $BeforePlan) -QueryPath (Join-Path $ArtifactDir $BeforeQuery) -UseCount $null
    $after = Get-PlanInfo -PlanPath (Join-Path $ArtifactDir $AfterPlan) -QueryPath (Join-Path $ArtifactDir $AfterQuery) -UseCount $AfterUseCount
    $before | Add-Member -NotePropertyName Runtime -NotePropertyValue $RuntimeMetrics["$DemoName`:before"]
    $after | Add-Member -NotePropertyName Runtime -NotePropertyValue $RuntimeMetrics["$DemoName`:after"]

    $width = 1800
    $height = 1100
    $bitmap = New-Object System.Drawing.Bitmap($width, $height)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
    $graphics.Clear([System.Drawing.Color]::FromArgb(246, 247, 249))

    $titleFont = New-Object System.Drawing.Font("Segoe UI", 26, [System.Drawing.FontStyle]::Bold)
    $subFont = New-Object System.Drawing.Font("Segoe UI", 12)
    $dark = [System.Drawing.Brushes]::Black
    $muted = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(82, 82, 82))

    $graphics.DrawString($Title, $titleFont, $dark, 38, 28)
    $graphics.DrawString("Runtime metrics are from SQL Server. Estimated plan cost is shown for orientation only.", $subFont, $muted, 42, 74)

    if ($before.Runtime -and $after.Runtime) {
        $beforeCompileUs = if ($null -eq $before.Runtime.ApproxCompileMs -or $before.Runtime.Executions -eq 0) { 0 } else { ($before.Runtime.ApproxCompileMs * 1000) / $before.Runtime.Executions }
        $afterCompileUs = if ($null -eq $after.Runtime.ApproxCompileMs -or $after.Runtime.Executions -eq 0) { 0 } else { ($after.Runtime.ApproxCompileMs * 1000) / $after.Runtime.Executions }
        $beforeTotalCpuUs = $before.Runtime.AvgWorkerUs + $beforeCompileUs
        $afterTotalCpuUs = $after.Runtime.AvgWorkerUs + $afterCompileUs
        $cpuDelta = (($afterTotalCpuUs - $beforeTotalCpuUs) / $beforeTotalCpuUs) * 100
        $readDelta = (($after.Runtime.AvgLogicalReads - $before.Runtime.AvgLogicalReads) / $before.Runtime.AvgLogicalReads) * 100
        $compileDelta = (($after.Runtime.CompilePerExecution - $before.Runtime.CompilePerExecution) / $before.Runtime.CompilePerExecution) * 100
        $verdictFont = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
        $verdictBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(23, 113, 76))
        $graphics.DrawString(("T-Lift delta: total CPU incl compile {0:N1}%; logical reads {1:N1}%; compile/execution {2:N1}%" -f $cpuDelta, $readDelta, $compileDelta), $verdictFont, $verdictBrush, 42, 96)
    }

    Draw-PlanPanel -Graphics $graphics -Info $before -Title "Before - OPTION(RECOMPILE)" -X 42 -Y 122 -Width 838 -Height 900 -AccentBrush (New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(185, 78, 72)))
    Draw-PlanPanel -Graphics $graphics -Info $after -Title "After - T-Lift dynamic SQL" -X 920 -Y 122 -Width 838 -Height 900 -AccentBrush (New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(38, 126, 93)))

    $footerFont = New-Object System.Drawing.Font("Segoe UI", 10)
    $graphics.DrawString("Generated from .sqlplan XML plus Query Store / plan-cache metrics. Open the .sqlplan files in SSMS for the native graphical plan.", $footerFont, $muted, 42, 1040)

    $pngPath = Join-Path $ArtifactDir "$DemoName`_plan_comparison.png"
    $bitmap.Save($pngPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose()
    $bitmap.Dispose()

    return $pngPath
}

$runtimeMetrics = Get-RuntimeMetrics

$outputs = @()
$outputs += New-ComparisonImage -DemoName "demo01" -Title "Demo 01 - B2B Order Workbench Evidence" -BeforePlan "demo01_before_option_recompile.sqlplan" -BeforeQuery "demo01_before_option_recompile.sql" -AfterPlan "demo01_after_tlift_dynamic.sqlplan" -AfterQuery "demo01_after_tlift_dynamic.sql" -AfterUseCount $runtimeMetrics["demo01:after"].MaxUseCount -RuntimeMetrics $runtimeMetrics
$outputs += New-ComparisonImage -DemoName "demo02" -Title "Demo 02 - Dispatch SLA Dashboard Evidence" -BeforePlan "demo02_before_option_recompile.sqlplan" -BeforeQuery "demo02_before_option_recompile.sql" -AfterPlan "demo02_after_tlift_dynamic.sqlplan" -AfterQuery "demo02_after_tlift_dynamic.sql" -AfterUseCount $runtimeMetrics["demo02:after"].MaxUseCount -RuntimeMetrics $runtimeMetrics
$outputs += New-ComparisonImage -DemoName "demo03" -Title "Demo 03 - Receivables Risk Dashboard Evidence" -BeforePlan "demo03_before_option_recompile.sqlplan" -BeforeQuery "demo03_before_option_recompile.sql" -AfterPlan "demo03_after_tlift_dynamic.sqlplan" -AfterQuery "demo03_after_tlift_dynamic.sql" -AfterUseCount $runtimeMetrics["demo03:after"].MaxUseCount -RuntimeMetrics $runtimeMetrics

$summaryPath = Join-Path $ArtifactDir "runtime_plan_comparison_summary.md"
$summary = New-Object System.Text.StringBuilder
[void]$summary.AppendLine("# Runtime and Plan Comparison Summary")
[void]$summary.AppendLine()
[void]$summary.AppendLine("Generated from the persisted EvidenceMetricSummary table plus exported `.sqlplan` files.")
[void]$summary.AppendLine()
[void]$summary.AppendLine("| Demo | Variant | Executions | Avg exec CPU us | Avg total CPU incl compile us | Avg elapsed us | Avg logical reads | Compile/execution | Shapes | Max usecount |")
[void]$summary.AppendLine("|------|---------|-----------:|----------------:|------------------------------:|---------------:|------------------:|------------------:|-------:|-------------:|")

foreach ($demo in @("demo01", "demo02", "demo03")) {
    foreach ($variant in @("before", "after")) {
        $metric = $runtimeMetrics["$demo`:$variant"]
        $label = if ($variant -eq "before") { "OPTION(RECOMPILE)" } else { "T-Lift dynamic SQL" }
        $useCount = if ($null -eq $metric.MaxUseCount) { "" } else { $metric.MaxUseCount }
        $compileUs = if ($null -eq $metric.ApproxCompileMs -or $metric.Executions -eq 0) { 0 } else { ($metric.ApproxCompileMs * 1000) / $metric.Executions }
        $totalCpuUs = $metric.AvgWorkerUs + $compileUs
        [void]$summary.AppendLine("| $demo | $label | $($metric.Executions) | $([math]::Round($metric.AvgWorkerUs, 0)) | $([math]::Round($totalCpuUs, 0)) | $([math]::Round($metric.AvgElapsedUs, 0)) | $([math]::Round($metric.AvgLogicalReads, 0)) | $([math]::Round($metric.CompilePerExecution, 4)) | $($metric.Shapes) | $useCount |")
    }
}

[void]$summary.AppendLine()
[void]$summary.AppendLine("## T-Lift Delta vs OPTION(RECOMPILE)")
[void]$summary.AppendLine()
[void]$summary.AppendLine("| Demo | Total CPU incl compile | Logical reads | Compile/execution |")
[void]$summary.AppendLine("|------|-----------------------:|--------------:|------------------:|")

foreach ($demo in @("demo01", "demo02", "demo03")) {
    $beforeMetric = $runtimeMetrics["$demo`:before"]
    $afterMetric = $runtimeMetrics["$demo`:after"]
    $beforeCompileUs = if ($null -eq $beforeMetric.ApproxCompileMs -or $beforeMetric.Executions -eq 0) { 0 } else { ($beforeMetric.ApproxCompileMs * 1000) / $beforeMetric.Executions }
    $afterCompileUs = if ($null -eq $afterMetric.ApproxCompileMs -or $afterMetric.Executions -eq 0) { 0 } else { ($afterMetric.ApproxCompileMs * 1000) / $afterMetric.Executions }
    $beforeTotalCpuUs = $beforeMetric.AvgWorkerUs + $beforeCompileUs
    $afterTotalCpuUs = $afterMetric.AvgWorkerUs + $afterCompileUs
    $cpuDelta = (($afterTotalCpuUs - $beforeTotalCpuUs) / $beforeTotalCpuUs) * 100
    $readDelta = (($afterMetric.AvgLogicalReads - $beforeMetric.AvgLogicalReads) / $beforeMetric.AvgLogicalReads) * 100
    $compileDelta = (($afterMetric.CompilePerExecution - $beforeMetric.CompilePerExecution) / $beforeMetric.CompilePerExecution) * 100
    [void]$summary.AppendLine("| $demo | $([math]::Round($cpuDelta, 1))% | $([math]::Round($readDelta, 1))% | $([math]::Round($compileDelta, 1))% |")
}

[void]$summary.AppendLine()
[void]$summary.AppendLine("Interpretation:")
[void]$summary.AppendLine()
[void]$summary.AppendLine('- For these recurring high-frequency query shapes, dynamic SQL powered by T-Lift is a valid alternative to `OPTION(RECOMPILE)`: it keeps the source procedure readable, removes unused catch-all predicates in the rendered SQL, enables plan reuse, and avoids paying compilation CPU on every execution.')
[void]$summary.AppendLine('- This is not a universal "T-Lift is always faster" claim. It is evidence that T-Lift can be a measurable fit when the workload has repeated business query shapes and `OPTION(RECOMPILE)` compile CPU is material.')
[void]$summary.AppendLine("- Estimated plan cost in the PNGs is shown only as plan context, not as proof of faster runtime.")

Set-Content -LiteralPath $summaryPath -Value $summary.ToString() -Encoding UTF8

Write-Host "Generated comparison images:"
$outputs | ForEach-Object { Write-Host $_ }
Write-Host "Runtime summary: $summaryPath"
