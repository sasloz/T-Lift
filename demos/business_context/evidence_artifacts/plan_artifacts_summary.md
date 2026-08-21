# T-Lift Plan Evidence Artifacts

Generated from TLift_BusinessDemo after a successful evidence run.

## EvidenceResults

| ID | Status | Check | Detail |
|---:|:------:|-------|--------|
| 1 | PASS | Evidence captured all demo variants | Captured variant rows: 6 of 6 expected. |
| 2 | PASS | 01 Order workbench - compile work comparison | CompilePerExecution RECOMPILE=1.0000, T-LIFT=0.0408. RECOMPILE should normally compile repeatedly, while T-Lift should reuse dynamic SQL shapes. |
| 3 | PASS | 02 Dispatch SLA - compile work comparison | CompilePerExecution RECOMPILE=1.0000, T-LIFT=0.0204. RECOMPILE should normally compile repeatedly, while T-Lift should reuse dynamic SQL shapes. |
| 4 | PASS | 03 Receivables risk - compile work comparison | CompilePerExecution RECOMPILE=1.0000, T-LIFT=0.0400. RECOMPILE should normally compile repeatedly, while T-Lift should reuse dynamic SQL shapes. |
| 5 | PASS | 01 Order workbench - total CPU/read comparison | AvgExecCpuUs RECOMPILE=8650.72, T-LIFT=8663.37; AvgTotalCpuUsInclCompile RECOMPILE=38078.1200000000000000, T-LIFT=9112.3495918367346938; AvgLogicalReads RECOMPILE=302.50, T-LIFT=299.33. |
| 6 | PASS | 02 Dispatch SLA - total CPU/read comparison | AvgExecCpuUs RECOMPILE=715.10, T-LIFT=2797.78; AvgTotalCpuUsInclCompile RECOMPILE=6457.7000000000000000, T-LIFT=2859.0044897959183673; AvgLogicalReads RECOMPILE=89.00, T-LIFT=64.96. |
| 7 | PASS | 03 Receivables risk - total CPU/read comparison | AvgExecCpuUs RECOMPILE=5333.28, T-LIFT=4951.92; AvgTotalCpuUsInclCompile RECOMPILE=18337.0800000000000000, T-LIFT=5231.9200000000000000; AvgLogicalReads RECOMPILE=187.00, T-LIFT=175.24. |
| 8 | PASS | T-Lift query text removes catch-all predicates | T-Lift dynamic SQL text should not contain @param IS NULL OR catch-all predicates for the active shapes. |
| 9 | PASS | Order workbench has optional product-shape split | Demo 01 should produce at least one T-Lift query shape with product lookup and at least one without it. |
| 10 | PASS | Receivables risk exposes bucketed dynamic SQL | Demo 03 should show bucket comments such as /*01*/ or /*04*/ in T-Lift dynamic SQL text. |
| 11 | PASS | Execution plans captured as XML | Captured Query Store and plan-cache plans with XML: 10. Open query_plan to inspect seek/scan/join choices. |
| 12 | PASS | T-Lift dynamic SQL plan cache reuse | Max plan-cache usecounts for T-Lift labeled dynamic SQL: 50. |

## Exported Plans

| Name | Source | UseCount | Plan | Query Text |
|------|--------|---------:|------|------------|
| demo01_before_option_recompile | QueryStore |  | `demo01_before_option_recompile.sqlplan` | `demo01_before_option_recompile.sql` |
| demo01_after_tlift_dynamic | PlanCache | 25 | `demo01_after_tlift_dynamic.sqlplan` | `demo01_after_tlift_dynamic.sql` |
| demo02_before_option_recompile | QueryStore |  | `demo02_before_option_recompile.sqlplan` | `demo02_before_option_recompile.sql` |
| demo02_after_tlift_dynamic | PlanCache | 50 | `demo02_after_tlift_dynamic.sqlplan` | `demo02_after_tlift_dynamic.sql` |
| demo03_before_option_recompile | QueryStore |  | `demo03_before_option_recompile.sqlplan` | `demo03_before_option_recompile.sql` |
| demo03_after_tlift_dynamic | PlanCache | 25 | `demo03_after_tlift_dynamic.sqlplan` | `demo03_after_tlift_dynamic.sql` |

