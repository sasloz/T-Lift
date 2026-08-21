param(
    [string]$Server = "localhost",
    [string]$User = "sa",
    [string]$Password = $env:TLIFT_SQL_PASSWORD,
    [switch]$UseIntegratedSecurity,
    [switch]$SkipEvidence
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = "Stop"

$demoRoot = $PSScriptRoot
$repoRoot = Split-Path -Parent (Split-Path -Parent $demoRoot)
$engineScript = Join-Path $repoRoot "sp_tlift.sql"

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

function Split-SqlBatches {
    param([string]$SqlText)

    $batches = New-Object System.Collections.Generic.List[string]
    $current = New-Object System.Text.StringBuilder
    $inSingleQuote = $false
    $inBlockComment = $false

    $normalized = $SqlText -replace "`r`n", "`n"
    $lines = $normalized -split "`n", -1

    foreach ($line in $lines) {
        $trimmed = $line.Trim()

        if (-not $inSingleQuote -and -not $inBlockComment -and $trimmed -match '^(?i)GO(\s+\d+)?$') {
            $batch = $current.ToString().Trim()
            if ($batch.Length -gt 0) {
                $batches.Add($batch)
            }
            [void]$current.Clear()
            continue
        }

        [void]$current.AppendLine($line)

        $i = 0
        while ($i -lt $line.Length) {
            $ch = $line[$i]
            $next = if ($i + 1 -lt $line.Length) { $line[$i + 1] } else { [char]0 }

            if ($inSingleQuote) {
                if ($ch -eq "'") {
                    if ($next -eq "'") {
                        $i += 2
                    }
                    else {
                        $inSingleQuote = $false
                        $i++
                    }
                }
                else {
                    $i++
                }
            }
            elseif ($inBlockComment) {
                if ($ch -eq "*" -and $next -eq "/") {
                    $inBlockComment = $false
                    $i += 2
                }
                else {
                    $i++
                }
            }
            elseif ($ch -eq "-" -and $next -eq "-") {
                break
            }
            elseif ($ch -eq "/" -and $next -eq "*") {
                $inBlockComment = $true
                $i += 2
            }
            elseif ($ch -eq "'") {
                $inSingleQuote = $true
                $i++
            }
            else {
                $i++
            }
        }
    }

    $lastBatch = $current.ToString().Trim()
    if ($lastBatch.Length -gt 0) {
        $batches.Add($lastBatch)
    }

    return $batches
}

function Invoke-SqlBatch {
    param(
        [string]$Database,
        [string]$Sql,
        [int]$Timeout = 300
    )

    $connection = New-Connection -Database $Database
    try {
        $connection.Open()
        $command = $connection.CreateCommand()
        $command.CommandTimeout = $Timeout
        $command.CommandText = $Sql
        [void]$command.ExecuteNonQuery()
    }
    finally {
        $connection.Close()
    }
}

function Invoke-SqlQuery {
    param(
        [string]$Database,
        [string]$Sql,
        [int]$Timeout = 300
    )

    $connection = New-Connection -Database $Database
    try {
        $connection.Open()
        $command = $connection.CreateCommand()
        $command.CommandTimeout = $Timeout
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

function Invoke-SqlScript {
    param(
        [string]$Database,
        [string]$Path,
        [string]$Prefix = ""
    )

    $content = Get-Content -LiteralPath $Path -Raw
    if ($Prefix.Length -gt 0) {
        $content = $Prefix + "`r`n" + $content
    }

    $connection = New-Connection -Database $Database
    try {
        $connection.Open()

        $batchNumber = 0
        foreach ($batch in Split-SqlBatches -SqlText $content) {
            $batchNumber++
            try {
                $command = $connection.CreateCommand()
                $command.CommandTimeout = 300
                $command.CommandText = $batch
                [void]$command.ExecuteNonQuery()
            }
            catch {
                throw "Failed executing batch $batchNumber from $Path. $($_.Exception.Message)"
            }
        }
    }
    finally {
        $connection.Close()
    }
}

Write-Host "Preparing TLift_Engine on $Server..."
Invoke-SqlBatch -Database "master" -Sql @"
IF DB_ID(N'TLift_Engine') IS NULL
BEGIN
    CREATE DATABASE TLift_Engine;
END;
"@

Write-Host "Installing sp_tlift into TLift_Engine..."
Invoke-SqlScript -Database "TLift_Engine" -Path $engineScript -Prefix "USE [TLift_Engine];"

$scripts = @(
    "00_setup_business_context_demo.sql",
    "01_b2b_order_workbench.sql",
    "02_dispatch_sla_dashboard.sql",
    "03_finance_receivables_risk.sql"
)

if (-not $SkipEvidence) {
    $scripts += "04_query_store_evidence.sql"
}

foreach ($script in $scripts) {
    $path = Join-Path $demoRoot $script
    Write-Host "Running $script..."
    Invoke-SqlScript -Database "master" -Path $path
}

if (-not $SkipEvidence) {
    $evidence = Invoke-SqlQuery -Database "TLift_BusinessDemo" -Sql @"
SELECT EvidenceID, CheckName, Status, Detail
FROM demo.EvidenceResults
ORDER BY EvidenceID;
"@

    if ($evidence.Rows.Count -eq 0) {
        throw "Evidence demo completed, but demo.EvidenceResults is empty."
    }

    Write-Host ""
    Write-Host "Evidence result summary:"
    $evidence | Format-Table -AutoSize -Wrap | Out-String | Write-Host
}

Write-Host "Business context demos completed."
