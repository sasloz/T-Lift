# T-Lift Independent Integration Tests

This folder contains an integration harness that is independent from `intern_stuff`.
It creates fresh databases, installs `sp_tlift`, creates feature fixtures, renders
them, deploys the rendered procedures, and records assertion results in SQL Server.

## Run

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\integration_tests\run_integration_tests.ps1 `
  -Server localhost `
  -User sa `
  -Password 'StrongPass123!'
```

The runner recreates these databases on every run:

- `TLift_Engine_IT`
- `TLift_Target_IT`

## Result Table

After a run, detailed results are available in:

```sql
SELECT *
FROM TLift_Target_IT.it.TestResults
ORDER BY TestID;
```

Current expected status for this revision is fully green (117 assertions). The
independent tests cover all directives (including `--#sort` whitelist sorting),
output parameter propagation, literal directive scanning outside dynamic
sections, validation of unknown directives, and the lifecycle features:
`@execute` deployment (single, wrapper, and GO-inside-literal cases), the
render metadata stamp, `@checkDrift` (OK / DRIFT / SOURCE_MISSING), and
`@suggest` catch-all detection.

The same suite runs in CI via `.github/workflows/integration-tests.yml`
against SQL Server 2017, 2019, 2022, and 2025 containers.
