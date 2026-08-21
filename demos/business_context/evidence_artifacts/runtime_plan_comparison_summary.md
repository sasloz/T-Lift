# Runtime and Plan Comparison Summary

Generated from the persisted EvidenceMetricSummary table plus exported .sqlplan files.

| Demo | Variant | Executions | Avg exec CPU us | Avg total CPU incl compile us | Avg elapsed us | Avg logical reads | Compile/execution | Shapes | Max usecount |
|------|---------|-----------:|----------------:|------------------------------:|---------------:|------------------:|------------------:|-------:|-------------:|
| demo01 | OPTION(RECOMPILE) | 50 | 8651 | 38078 | 8674 | 302 | 1.0000 | 2 |  |
| demo01 | T-Lift dynamic SQL | 49 | 8663 | 9112 | 8687 | 299 | 0.0408 | 2 | 25 |
| demo02 | OPTION(RECOMPILE) | 50 | 715 | 6458 | 716 | 89 | 1.0000 | 1 |  |
| demo02 | T-Lift dynamic SQL | 49 | 2798 | 2859 | 2798 | 65 | 0.0204 | 1 | 50 |
| demo03 | OPTION(RECOMPILE) | 50 | 5333 | 18337 | 5334 | 187 | 1.0000 | 2 |  |
| demo03 | T-Lift dynamic SQL | 50 | 4952 | 5232 | 4953 | 175 | 0.0400 | 2 | 25 |

## T-Lift Delta vs OPTION(RECOMPILE)

| Demo | Total CPU incl compile | Logical reads | Compile/execution |
|------|-----------------------:|--------------:|------------------:|
| demo01 | -76.1% | -1.0% | -95.9% |
| demo02 | -55.7% | -27.0% | -98.0% |
| demo03 | -71.5% | -6.3% | -96.0% |

Interpretation:

- For these recurring high-frequency query shapes, dynamic SQL powered by T-Lift is a valid alternative to `OPTION(RECOMPILE)`: it keeps the source procedure readable, removes unused catch-all predicates in the rendered SQL, enables plan reuse, and avoids paying compilation CPU on every execution.
- This is not a universal "T-Lift is always faster" claim. It is evidence that T-Lift can be a measurable fit when the workload has repeated business query shapes and `OPTION(RECOMPILE)` compile CPU is material.
- Estimated plan cost in the PNGs is shown only as plan context, not as proof of faster runtime.

