# T-Lift business context demos

These demos are intentionally larger than the README quick start. They show where
T-Lift helps in real stored procedures that are executed frequently enough that
`OPTION(RECOMPILE)` can become expensive CPU-wise.

## Prerequisites

1. Create/install the T-Lift engine as described in the root README:
   - `TLift_Engine` contains `dbo.sp_tlift`
2. Run the scripts in this folder from SSMS or sqlcmd in this order:
   - `00_setup_business_context_demo.sql`
   - `01_b2b_order_workbench.sql`
   - `02_dispatch_sla_dashboard.sql`
   - `03_finance_receivables_risk.sql`
   - `04_query_store_evidence.sql`

The setup script creates a separate database named `TLift_BusinessDemo`. It also
creates a small helper procedure that can deploy the generated T-Lift output.

Alternatively, run the whole demo set through PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\demos\business_context\run_business_context_demos.ps1 `
  -Server localhost `
  -User sa `
  -Password '...!'
```

For Windows authentication:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\demos\business_context\run_business_context_demos.ps1 `
  -Server localhost `
  -UseIntegratedSecurity
```

If Query Store is not available or the login cannot change database-level Query
Store settings, add `-SkipEvidence` and run `04_query_store_evidence.sql` later
with a login that has sufficient permissions.

After a successful evidence run, export SSMS-ready plan files:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\demos\business_context\export_plan_artifacts.ps1 `
  -Server localhost,1433 `
  -User sa `
  -Password 'StrongPass123!'
```

The export writes `.sqlplan` files, matching query text files, and a summary to
`demos/business_context/evidence_artifacts/`. Open the `before` and `after`
`.sqlplan` files in SSMS for visual comparison.

Recommended SSMS screenshot pairs:

- `demo01_before_option_recompile.sqlplan` vs. `demo01_after_tlift_dynamic.sqlplan`
- `demo02_before_option_recompile.sqlplan` vs. `demo02_after_tlift_dynamic.sqlplan`
- `demo03_before_option_recompile.sqlplan` vs. `demo03_after_tlift_dynamic.sqlplan`

The `before` files come from Query Store plans for the `OPTION(RECOMPILE)`
comparison procedures. The `after` files come from the reused T-Lift dynamic SQL
plans in the plan cache.

To generate screenshot-ready comparison images from those same `.sqlplan` files:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\demos\business_context\generate_plan_comparison_images.ps1
```

Generated PNGs:

- `demo01_plan_comparison.png`
- `demo02_plan_comparison.png`
- `demo03_plan_comparison.png`

The generator also writes `runtime_plan_comparison_summary.md`. Use that file
when discussing whether a scenario is actually faster. The current sample is
deliberately honest:

- For these recurring high-frequency query shapes, dynamic SQL powered by
  T-Lift is a valid alternative to `OPTION(RECOMPILE)`: it keeps the source
  procedure readable, removes unused catch-all predicates in the rendered SQL,
  enables plan reuse, and avoids paying compilation CPU on every execution.
- This is not a universal "T-Lift is always faster" claim. It is evidence that
  T-Lift can be a measurable fit when the workload has repeated business query
  shapes and `OPTION(RECOMPILE)` compile CPU is material.
- Estimated plan cost is included in the PNGs only as plan context; it is not a
  reliable proof of faster runtime.

## Can execution plans prove the value?

Execution plans can prove an important part of the story, but not all of it by
themselves.

They can prove that T-Lift changes the query shape in a way SQL Server can see:
unused predicates disappear, optional product lookups are absent when they are
not needed, wrapper branches get separate procedure plans, and bucket comments
create separate cached dynamic SQL texts for different value ranges.

They cannot honestly prove a universal "always faster" claim. Plan quality and
runtime depend on data volume, statistics, indexes, SQL Server version,
compatibility level, memory grants, concurrency, and parameter distribution.

For a sustainable proof, use the plans together with Query Store metrics:

- `count_compiles` and compile duration show the repeated CPU cost of
  `OPTION(RECOMPILE)`.
- execution count, worker time, duration, and logical reads show runtime impact.
- stored `query_plan` XML from Query Store and the plan cache lets you compare
  seeks, scans, joins, and plan variants after the workload has run.
- plan-cache `usecounts` show whether the rendered dynamic SQL shapes are reused.

That is what `04_query_store_evidence.sql` is for.

## What the demos show

### 01 - B2B order workbench

Business case: an inside-sales or account-management screen with many optional
filters. Users search by customer, segment, region, status, channel, order date,
product category, and minimum order value.

Why not just `OPTION(RECOMPILE)`: this screen can be used hundreds or thousands
of times per hour. Recompiling every search avoids parameter sniffing, but it
also spends CPU on compilation for common shapes that could have reused a stable
plan.

What the T-SQL developer gains: the source procedure remains a normal readable
catch-all query that can be highlighted and executed in SSMS. T-Lift removes
unused predicates and product lookups in the rendered procedure, so the optimizer
sees the real query shape without the developer hand-building dynamic SQL
strings.

### 02 - Dispatch SLA dashboard

Business case: a field-service dispatch board refreshed often by dispatchers
and technicians. The measured evidence workload focuses on repeated technician
worklists and SLA breach views, where calls are frequent and selective.

Why not just `OPTION(RECOMPILE)`: dashboard polling creates many repeated calls
with a small number of usage patterns. Wrapper generation lets those patterns
get separate cached procedures instead of compiling every refresh.

What the T-SQL developer gains: a single annotated source procedure generates a
wrapper plus specialized child procedures. The developer does not have to
maintain several near-duplicate procedures by hand.

### 03 - Receivables risk dashboard

Business case: finance users slice open receivables by region, risk class,
minimum exposure, and days past due. Very small and very large exposure
thresholds often need different plans.

Why not just `OPTION(RECOMPILE)`: the expensive part is not the optional filters
alone, but the skew in requested thresholds. Buckets create a small number of
cached plan variants for value ranges.

What the T-SQL developer gains: bucket comments and optional predicates are
generated from the readable query. The code stays close to the business logic,
while the plan cache can distinguish small, medium, and large exposure searches.

## Useful inspection queries

Each demo executes a few calls and then queries the plan cache for the section
label used by the generated dynamic SQL, for example `Demo01_OrderWorkbench`.
You can rerun the calls with different parameters and inspect how many cached
entries are used for each business query shape.

For a stronger comparison, run `04_query_store_evidence.sql` after demos 01-03.
It runs a repeated workload against the `OPTION(RECOMPILE)` comparison
procedures and the T-Lift rendered procedures, then returns:

- compile/runtime summary per business demo and variant
- query text shape checks
- stored Query Store and plan-cache execution plans with seek/scan/join flags
- normal plan-cache reuse for the rendered dynamic SQL labels

The script also writes a persisted summary to:

```sql
SELECT *
FROM TLift_BusinessDemo.demo.EvidenceResults
ORDER BY EvidenceID;
```

`PASS` means the expected evidence was observed. `WARN` means the demo still ran,
but the result is environment-dependent or weaker than expected. `FAIL` means a
required evidence artifact is missing; the script throws after writing the table
so the result is visible but cannot be mistaken for a successful proof run.
