param(
    [string]$Server = "localhost",
    [string]$User = "sa",
    [string]$Password = $env:TLIFT_SQL_PASSWORD,
    [string]$EngineDatabase = "TLift_Engine_IT",
    [string]$TargetDatabase = "TLift_Target_IT"
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$engineScript = Join-Path $repoRoot "sp_tlift.sql"
$testScript = Join-Path $PSScriptRoot "tlift_integration_tests.sql"

if ([string]::IsNullOrWhiteSpace($Password)) {
    throw "Provide -Password or set TLIFT_SQL_PASSWORD."
}

function New-Connection {
    param([string]$Database)

    $connection = New-Object System.Data.SqlClient.SqlConnection
    $builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
    $builder["Data Source"] = $Server
    $builder["Initial Catalog"] = $Database
    $builder["User ID"] = $User
    $builder["Password"] = $Password
    $builder["Encrypt"] = $false
    $builder["TrustServerCertificate"] = $true
    $builder["Connect Timeout"] = 15
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
        [int]$Timeout = 120
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

    $batchNumber = 0
    foreach ($batch in Split-SqlBatches -SqlText $content) {
        $batchNumber++
        try {
            Invoke-SqlBatch -Database $Database -Sql $batch
        }
        catch {
            throw "Failed executing batch $batchNumber from $Path. $($_.Exception.Message)"
        }
    }
}

function Invoke-SqlQuery {
    param(
        [string]$Database,
        [string]$Sql,
        [int]$Timeout = 120
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

$setupSql = @"
USE [master];
IF DB_ID(N'$TargetDatabase') IS NOT NULL
BEGIN
    ALTER DATABASE [$TargetDatabase] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [$TargetDatabase];
END;
IF DB_ID(N'$EngineDatabase') IS NOT NULL
BEGIN
    ALTER DATABASE [$EngineDatabase] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [$EngineDatabase];
END;
CREATE DATABASE [$EngineDatabase];
CREATE DATABASE [$TargetDatabase];
"@

Write-Host "Preparing isolated databases $EngineDatabase and $TargetDatabase on $Server..."
Invoke-SqlBatch -Database "master" -Sql $setupSql

Write-Host "Installing sp_tlift into $EngineDatabase..."
Invoke-SqlScript -Database $EngineDatabase -Path $engineScript -Prefix "USE [$EngineDatabase];"

Write-Host "Running independent integration harness..."
$testPrefix = @"
:setvar EngineDatabase "$EngineDatabase"
:setvar TargetDatabase "$TargetDatabase"
"@
$testSql = (Get-Content -LiteralPath $testScript -Raw).
    Replace('$(EngineDatabase)', $EngineDatabase).
    Replace('$(TargetDatabase)', $TargetDatabase)
$tempTestScript = Join-Path ([System.IO.Path]::GetTempPath()) ("tlift_it_" + [guid]::NewGuid().ToString("N") + ".sql")
try {
    Set-Content -LiteralPath $tempTestScript -Value $testSql -Encoding UTF8
    Invoke-SqlScript -Database $TargetDatabase -Path $tempTestScript
}
finally {
    if (Test-Path -LiteralPath $tempTestScript) {
        Remove-Item -LiteralPath $tempTestScript -Force
    }
}

$summary = Invoke-SqlQuery -Database $TargetDatabase -Sql @"
SELECT Status, COUNT(*) AS Count
FROM it.TestResults
GROUP BY Status
ORDER BY Status;
"@

$failures = Invoke-SqlQuery -Database $TargetDatabase -Sql @"
SELECT Feature, Scenario, Phase, Detail
FROM it.TestResults
WHERE Status = 'FAIL'
ORDER BY TestID;
"@

Write-Host ""
Write-Host "Result summary:"
$summary | Format-Table -AutoSize | Out-String | Write-Host

if ($failures.Rows.Count -gt 0) {
    Write-Host "Failures:"
    $failures | Format-Table -AutoSize -Wrap | Out-String | Write-Host
    exit 1
}

Write-Host "All independent T-Lift integration tests passed."
