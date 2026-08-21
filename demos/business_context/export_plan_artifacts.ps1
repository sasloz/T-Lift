param(
    [string]$Server = "localhost,1433",
    [string]$User = "sa",
    [string]$Password = $env:TLIFT_SQL_PASSWORD,
    [switch]$UseIntegratedSecurity,
    [string]$OutputDir = (Join-Path $PSScriptRoot "evidence_artifacts")
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = "Stop"

if (-not $UseIntegratedSecurity -and [string]::IsNullOrWhiteSpace($Password)) {
    throw "Provide -Password, set TLIFT_SQL_PASSWORD, or use -UseIntegratedSecurity."
}

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
        $builder["User ID"] = $User
        $builder["Password"] = $Password
    }

    $connection.ConnectionString = $builder.ConnectionString
    return $connection
}

function Invoke-Query {
    param(
        [string]$Sql,
        [hashtable]$Parameters = @{}
    )

    $connection = New-Connection -Database "TLift_BusinessDemo"
    try {
        $connection.Open()
        $command = $connection.CreateCommand()
        $command.CommandTimeout = 120
        $command.CommandText = $Sql

        foreach ($key in $Parameters.Keys) {
            [void]$command.Parameters.AddWithValue($key, $Parameters[$key])
        }

        $adapter = New-Object System.Data.SqlClient.SqlDataAdapter $command
        $table = New-Object System.Data.DataTable
        [void]$adapter.Fill($table)
        return ,$table
    }
    finally {
        $connection.Close()
    }
}

function Export-Plan {
    param(
        [string]$Name,
        [string]$Source,
        [string]$Pattern
    )

    if ($Source -eq "QueryStore") {
        $sql = @"
SELECT TOP (1)
    PlanXml = CONVERT(NVARCHAR(MAX), p.query_plan),
    QueryText = CONVERT(NVARCHAR(MAX), qt.query_sql_text),
    UseCount = CONVERT(INT, NULL)
FROM sys.query_store_query_text AS qt
INNER JOIN sys.query_store_query AS q
    ON q.query_text_id = qt.query_text_id
INNER JOIN sys.query_store_plan AS p
    ON p.query_id = q.query_id
WHERE qt.query_sql_text LIKE @Pattern
  AND qt.query_sql_text NOT LIKE N'%@Evidence%'
  AND qt.query_sql_text NOT LIKE N'%sys.query_store_query_text%'
  AND TRY_CONVERT(XML, p.query_plan) IS NOT NULL
ORDER BY q.query_id, p.plan_id;
"@
    }
    elseif ($Source -eq "PlanCache") {
        $sql = @"
SELECT TOP (1)
    PlanXml = CONVERT(NVARCHAR(MAX), qp.query_plan),
    QueryText = CONVERT(NVARCHAR(MAX), st.text),
    UseCount = cp.usecounts
FROM sys.dm_exec_cached_plans AS cp
CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) AS st
CROSS APPLY sys.dm_exec_query_plan(cp.plan_handle) AS qp
WHERE st.text LIKE @Pattern
  AND st.text LIKE N'(@%'
  AND st.text NOT LIKE N'%@Evidence%'
  AND st.text NOT LIKE N'%dm_exec_cached_plans%'
  AND qp.query_plan IS NOT NULL
ORDER BY cp.usecounts DESC;
"@
    }
    else {
        throw "Unknown plan source '$Source'."
    }

    $result = Invoke-Query -Sql $sql -Parameters @{ "@Pattern" = $Pattern }
    if ($result.Rows.Count -eq 0) {
        throw "No plan found for $Name using pattern $Pattern."
    }

    $row = $result.Rows[0]
    $planPath = Join-Path $OutputDir "$Name.sqlplan"
    $sqlPath = Join-Path $OutputDir "$Name.sql"

    Set-Content -LiteralPath $planPath -Value ([string]$row.PlanXml) -Encoding UTF8
    Set-Content -LiteralPath $sqlPath -Value ([string]$row.QueryText) -Encoding UTF8

    return [pscustomobject]@{
        Name = $Name
        Source = $Source
        UseCount = $row.UseCount
        PlanPath = $planPath
        QueryPath = $sqlPath
    }
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$evidence = Invoke-Query -Sql @"
SELECT EvidenceID, CheckName, Status, Detail
FROM demo.EvidenceResults
ORDER BY EvidenceID;
"@

if ($evidence.Rows.Count -eq 0) {
    throw "demo.EvidenceResults is empty. Run run_business_context_demos.ps1 first."
}

if (@($evidence | Where-Object { $_.Status -eq "FAIL" }).Count -gt 0) {
    throw "demo.EvidenceResults contains FAIL rows. Run the evidence demo successfully before exporting plans."
}

$exports = @()
$exports += Export-Plan -Name "demo01_before_option_recompile" -Source "QueryStore" -Pattern "%Demo01_OrderWorkbench_Recompile%"
$exports += Export-Plan -Name "demo01_after_tlift_dynamic" -Source "PlanCache" -Pattern "%/*Demo01_OrderWorkbench*/%"
$exports += Export-Plan -Name "demo02_before_option_recompile" -Source "QueryStore" -Pattern "%Demo02_DispatchQueue_Recompile%"
$exports += Export-Plan -Name "demo02_after_tlift_dynamic" -Source "PlanCache" -Pattern "%/*Demo02_DispatchQueue*/%"
$exports += Export-Plan -Name "demo03_before_option_recompile" -Source "QueryStore" -Pattern "%Demo03_ReceivablesRisk_Recompile%"
$exports += Export-Plan -Name "demo03_after_tlift_dynamic" -Source "PlanCache" -Pattern "%/*Demo03_ReceivablesRisk*/%"

$summaryPath = Join-Path $OutputDir "plan_artifacts_summary.md"
$summary = New-Object System.Text.StringBuilder
[void]$summary.AppendLine("# T-Lift Plan Evidence Artifacts")
[void]$summary.AppendLine()
[void]$summary.AppendLine("Generated from TLift_BusinessDemo after a successful evidence run.")
[void]$summary.AppendLine()
[void]$summary.AppendLine("## EvidenceResults")
[void]$summary.AppendLine()
[void]$summary.AppendLine("| ID | Status | Check | Detail |")
[void]$summary.AppendLine("|---:|:------:|-------|--------|")
foreach ($row in $evidence.Rows) {
    $detail = ([string]$row.Detail).Replace("|", "\|")
    $check = ([string]$row.CheckName).Replace("|", "\|")
    [void]$summary.AppendLine("| $($row.EvidenceID) | $($row.Status) | $check | $detail |")
}

[void]$summary.AppendLine()
[void]$summary.AppendLine("## Exported Plans")
[void]$summary.AppendLine()
[void]$summary.AppendLine("| Name | Source | UseCount | Plan | Query Text |")
[void]$summary.AppendLine("|------|--------|---------:|------|------------|")
foreach ($export in $exports) {
    $planName = Split-Path -Leaf $export.PlanPath
    $queryName = Split-Path -Leaf $export.QueryPath
    $useCount = if ($null -eq $export.UseCount -or [DBNull]::Value.Equals($export.UseCount)) { "" } else { $export.UseCount }
    [void]$summary.AppendLine("| $($export.Name) | $($export.Source) | $useCount | ``$planName`` | ``$queryName`` |")
}

Set-Content -LiteralPath $summaryPath -Value $summary.ToString() -Encoding UTF8

Write-Host "Exported plan artifacts:"
$exports | Format-Table -AutoSize | Out-String | Write-Host
Write-Host "Summary: $summaryPath"
