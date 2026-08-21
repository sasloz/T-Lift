# T-Lift Independent Integration Test Protocol

Date: 2026-06-17  
Runner: `integration_tests/run_integration_tests.ps1`  
Harness: `integration_tests/tlift_integration_tests.sql`  
SQL Server target: `localhost`  
Engine DB: `TLift_Engine_IT`  
Target DB: `TLift_Target_IT`

## Summary

The independent integration harness was implemented and executed against a local SQL Server container. It creates isolated test databases, installs `sp_tlift`, defines deterministic fixtures, renders feature-specific source procedures, deploys rendered procedures, and compares source behavior against rendered behavior.

Latest observed result:

| Status | Count |
| --- | ---: |
| PASS | 82 |
| FAIL | 0 |

The previously observed failures are resolved:

1. Output parameter propagation from dynamic SQL.
2. Directive scanning inside multiline string literals outside dynamic sections.
3. Unknown directive validation behavior.

## Test Scope

The harness is independent from `intern_stuff` and uses its own fixtures, assertions, and result table.

Covered feature areas:

| Feature area | Result |
| --- | --- |
| Installation/help mode | PASS |
| Required parameter validation | PASS |
| Missing procedure validation | PASS |
| Dynamic SQL sections | PASS |
| Single-line `--#if` | PASS |
| Multiple optional filters | PASS |
| `--#-` line removal/commenting behavior | PASS |
| `--#{if` block conditionals | PASS |
| `--#else` and `--#{elseif` | PASS |
| Inline block conditionals inside dynamic sections | PASS |
| Block removal `--#{-` / `--#-}` | PASS |
| Named section labels | PASS |
| `--#recompile` | PASS |
| `--#c` comment directive | PASS |
| Named conditions via `--#define` | PASS |
| Local variables via `--#var` / `--#usevar` | PASS |
| Parameter type rendering for `nvarchar`, `nchar`, `decimal` | PASS |
| Bucket rendering and execution | PASS |
| Long parameter names in buckets | PASS |
| Wrapper procedure generation and dispatch | PASS |
| No-directive baseline procedure | PASS |
| Unmatched dynamic section validation | PASS |
| Unmatched removal block validation | PASS |
| Missing `--#var` for `--#usevar` validation | PASS |
| Wrapper without branch validation | PASS |
| Bucket unknown parameter validation | PASS |
| Output parameter propagation | PASS |
| Multiline literal directive scanning | PASS |
| Unknown directive hard validation | PASS |

## Successful Behaviors

### Render and Deploy Pipeline

The harness successfully renders and deploys procedures for the main directive families. Rendered output is captured in:

```sql
SELECT ProcedureName, RenderedName, RenderedSql
FROM TLift_Target_IT.it.RenderOutput
ORDER BY CreatedAt;
```

The deploy helper correctly handles rendered scripts containing `GO` batch separators, including wrapper output with one dispatcher procedure and multiple child procedures.

### Semantic Equivalence

For most feature procedures, the test harness executes both the annotated source procedure and the rendered procedure with the same parameter combinations. Both write observations to `it.Observed`, and the harness compares rows in both directions with `EXCEPT`.

Successful semantic equivalence was observed for:

- Single optional filter with `NULL`, matching value, and no-match value.
- Multi-filter queries with all filters omitted, one filter set, and all filters set.
- Block `if` / `elseif` / `else` branch selection.
- Inline conditional blocks inside a dynamic section.
- Named condition resolution across multiple sections.
- Local variable forwarding via `--#var` and `--#usevar`.
- Bucketed SQL generation across boundary values.
- Wrapper dispatcher execution for customer, city, and default branches.
- Plain procedure baseline without T-Lift directives.

### Render Text Invariants

The harness verified important generated-text invariants:

- Named sections emit labels such as `/*SingleFilter*/`.
- `sp_executesql` is used for dynamic sections.
- `--#recompile` emits `OPTION(RECOMPILE)`.
- `--#c` comments out the target line.
- Named conditions are resolved into the original condition text.
- `nvarchar(50)`, `nchar(10)`, and `decimal(12,2)` are rendered with correct type shape.
- Bucket directives generate `@bucketsN` CASE variables and prepend bucket comments.
- Wrapper mode creates dispatcher and child procedures.

## Issues

### ISSUE-001: Output Parameter Is Not Propagated Back From `sp_executesql`

Status: Resolved 2026-06-17  
Severity: High  
Feature: Output parameters  
Failing test: `Types and output parameters / output value matches source`

Resolution:

The generated `sp_executesql` argument list now appends `OUTPUT` for stored procedure output parameters, matching the existing parameter definition string.

Observed result:

```text
Source output 2, rendered output 0
```

Source fixture:

```sql
CREATE OR ALTER PROCEDURE it.src_types_and_output
    @RunID UNIQUEIDENTIFIER,
    @SearchName NVARCHAR(50) = NULL,
    @Code NCHAR(10) = NULL,
    @MinimumAmount DECIMAL(12,2) = NULL,
    @HitCount INT OUTPUT
AS
SET @HitCount = 0;
-- dynamic section inserts rows and then:
SELECT @HitCount = COUNT(*)
FROM it.Observed
WHERE RunID = @RunID
  AND SectionName = N'types-output'
```

Rendered output contains the correct parameter definition:

```sql
@HitCount int OUTPUT
```

But the actual argument list does not pass the variable back as output:

```sql
exec sp_executesql @sql,
    N'..., @HitCount int OUTPUT',
    @RunID, @SearchName, @Code, @MinimumAmount, @HitCount
```

Expected:

```sql
exec sp_executesql @sql,
    N'..., @HitCount int OUTPUT',
    @RunID, @SearchName, @Code, @MinimumAmount, @HitCount OUTPUT
```

Impact:

Any source procedure using output parameters inside a T-Lift dynamic section may silently return stale or default output values from the rendered procedure.

Repro:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\integration_tests\run_integration_tests.ps1 `
  -Server localhost `
  -User sa `
  -Password 'StrongPass123!'
```

Then inspect:

```sql
SELECT *
FROM TLift_Target_IT.it.TestResults
WHERE Feature = 'Types and output parameters';
```

### ISSUE-002: Directive Scanner Misinterprets `--#` Inside Multiline String Literal

Status: Resolved 2026-06-17  
Severity: High  
Feature: Directive scanning / literal handling  
Failing tests:

- `Literal scanner and deployment splitter / src_literal_scanner`
- `Literal scanner and deployment splitter / GO and directive tokens inside literals`

Resolution:

Directive scanning now keeps single-quote state across source lines and ignores `--#` markers while inside multiline string literals.

Observed result:

```text
Must declare the scalar variable "@sql".
Could not find stored procedure 'it.rendered_literal_scanner'.
```

Source fixture:

```sql
CREATE OR ALTER PROCEDURE it.src_literal_scanner
    @RunID UNIQUEIDENTIFIER
AS
DECLARE @msg NVARCHAR(MAX) = N'alpha
GO
beta --#if still literal';
PRINT @msg;

--#[ LiteralScanner
...
--#]
```

Rendered output is corrupted before `@sql` is declared:

```sql
DECLARE @msg NVARCHAR(MAX) = N'alpha
GO
IF still literal';
set @sql = @sql + 'beta '+CHAR(13)+CHAR(10)
PRINT @msg;

declare @sql nvarchar(max) = N''
```

Expected:

- `--#if still literal` remains part of the string.
- No dynamic SQL builder line is emitted before `DECLARE @sql`.
- `GO` inside the string literal is preserved and not treated as a batch separator.

Impact:

Procedures containing multiline string literals with `--#` can be rendered into invalid SQL. This is especially risky because such literals may be logging text, generated SQL templates, messages, or documentation blocks.

Repro:

```sql
SELECT RenderedSql
FROM TLift_Target_IT.it.RenderOutput
WHERE RenderedName = 'rendered_literal_scanner';
```

### ISSUE-003: Unknown Directives Do Not Fail Validation Mode

Status: Resolved 2026-06-17  
Severity: Medium  
Feature: Validation mode  
Failing test: `Validation mode / unknown directive`

Resolution:

Unknown T-Lift directives now raise an error instead of printing a warning, both in validation mode and normal rendering.

Observed result:

```text
Expected an error but command succeeded.
```

Source fixture:

```sql
CREATE OR ALTER PROCEDURE it.src_bad_unknown_directive
AS
--#[ BadUnknown
SELECT 1 --#fi @x = 1
--#]
```

Runtime output includes a warning:

```text
WARNING: Unknown directive(s) found: Line 4: --#fi @x = 1
Validation passed. No rendering performed (@validateOnly = 1).
```

Expected:

Validation mode should fail for unknown directives, as documented in the README validation section:

```text
Unknown directives - catches typos like --#fi instead of --#if.
```

Impact:

Directive typos can pass validation and may only surface later as incorrect render output or runtime behavior. This weakens `@validateOnly = 1` as a pre-deployment safety check.

Repro:

```sql
DECLARE @r NVARCHAR(MAX);
EXEC TLift_Engine_IT.dbo.sp_tlift
    @DatabaseName = N'TLift_Target_IT',
    @SchemaName = N'it',
    @ProcedureName = N'src_bad_unknown_directive',
    @validateOnly = 1,
    @Result = @r OUTPUT;
```

### ISSUE-004: Literal Scanner Follow-Up Failure

Status: Resolved with ISSUE-002  
Severity: Low as standalone issue  
Feature: Test execution after failed deploy  
Failing test: `Literal scanner and deployment splitter / GO and directive tokens inside literals`

Observed result:

```text
Could not find stored procedure 'it.rendered_literal_scanner'.
```

This is not a separate root cause. The rendered procedure is missing because deployment failed in ISSUE-002. Once literal scanning is fixed, this test should exercise semantic equivalence for:

- `GO` inside string literal.
- `--#` inside string literal.
- quoted string value inside a dynamic section.

## Result Query

Use this query after any run to inspect the full protocol stored in SQL Server:

```sql
SELECT TestID, Feature, Scenario, Phase, Status, Detail, CreatedAt
FROM TLift_Target_IT.it.TestResults
ORDER BY TestID;
```

Failures only:

```sql
SELECT TestID, Feature, Scenario, Phase, Detail
FROM TLift_Target_IT.it.TestResults
WHERE Status = 'FAIL'
ORDER BY TestID;
```

Rendered SQL for previously failed areas:

```sql
SELECT RenderedName, RenderedSql
FROM TLift_Target_IT.it.RenderOutput
WHERE RenderedName IN (
    'rendered_types_and_output',
    'rendered_literal_scanner'
);
```

## Completed Fix Verification

Verified with:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\integration_tests\run_integration_tests.ps1 `
  -Server localhost `
  -User sa `
  -Password 'StrongPass123!'
```

Result: all independent T-Lift integration tests passed (`PASS = 82`, `FAIL = 0`).
