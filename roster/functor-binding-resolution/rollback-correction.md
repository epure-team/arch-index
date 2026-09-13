# Binding global rollback — corrective implementation evidence

Date: 2026-09-13. Formal review finding remains OPEN pending round2.

## Scope and sequence

Spec1.0.1 revalidation retained26FR and added AC13/CHECK5. Sequential Sol/Terra
planning scoped one vertical correction, test before code. Root implemented the
small producer-orchestration patch; Sol authored the disjoint standalone checker.
No new worktree or persistent generated database was created.

Fresh baseline build exit0; full Dune baseline exit0 (320Tezt and64Alcotest).
Product was unchanged from b98fcd0 when baseline and RED ran. Review pre-fix SHA
remains5338a81ebeafbe11eb1fe61bf11aa8a0e65b74c5 (same product code).

## Authentic RED

Command, inherited selected OCaml environment:

```sh
rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- node roster/functor-binding-resolution/check-global-rollback.js
```

Exit1: AssertionError, fault producer exited1 instead of0 after the healthy control
passed. Actual stderr contained `injected binding global rollback`, rollback
uncertainty, failure-row FOREIGN KEY failure, and `cannot commit - no transaction
is active`. This was a semantic RED, not setup/build failure. The trigger required
ordinal1 and one declaration for the fault input, plus two earlier binding rows.

Before RED, root review corrected two test-oracle defects: distinct invocation
paths changed legitimate producer provenance, and counts alone did not establish
intact binding contents. The checker now reuses exact invocation paths while
recreating only its owned DB and compares complete successful binding rows. It
does not ignore invocation_digest. Only inherent timestamps and the intentionally
different binding marker are normalized/excluded from old-table comparisons.

## Minimal correction and GREEN

Only lib/arch_index/arch_index.ml product orchestration changed. Callback collects
immutable collection payloads or failed outcomes, without binding SQL. After all
old transactions and intent restoration, List.iter drains each input independently
through the existing storage API. Collection failures latch false immediately;
storage failures latch false, warn and attempt the failed row. Later jobs still run.
The existing independent finalizer remains last.

Same CHECK5 command exit0 after rebuild. Output:

```json
{"ok":true,"two_input":{"applications_per_input":2,"earlier_binding_input_preserved":true},"continuation":{"inputs":3,"failed":1,"collected":2,"later_input_preserved":true},"trigger":"ordinal_2_after_distinct_artifact_once","old_graph_and_catalogue_semantics":"equal","binding_marker_after_fault":"absent"}
```

Both owned fixture directories/databases were removed in the checker finally block.
No new coverage percentage is claimed. Full post-correction suite is running;
formal convergence scratch RED/GREEN, round2 review, QA, PR/CI and merge are pending.
No new Tezos measurement or call-target improvement is claimed in this correction.

All four existing standalone Node families rerun after correction: inventory,
lifecycle, query and compatibility exit0. Independent Sol source audit returned
no findings for the bounded fix/checker; it performed no build or execution and
is not the required formal round2 review verdict.

Post-correction full suite completed exit1:319/320Tezt passed,64Alcotest passed.
The single origin recurring authentic-consumer check failed. A fresh runConsumer
diagnostic reports coverage-drift, not policy failure:25modules unchanged,
954→956functions,6131→6145calls,553→554origins, option/raise304→305.
No reference has been changed on that observation alone. Authorized symmetric
fresh engine/corpus attribution is running under calibration/rollback-r1; retain
headroom25, rules and allowlist unchanged. Its two owned temporary worktrees and
build artifacts are cleaned by the existing calibration script's finally block.

Attribution finished twice, exit0/SOURCE_ONLY for rollback-r1 and rollback-r2.
Each run used fresh base/candidate builds and eight cross-cells. Complete grouped
calls hashes, origin groups and module sets match A=B and C=D in both scopes.
Origin A=B:25/954/6131/553; C=D:25/956/6145/554. Whole-build MUST-null534
in all four cells: this correction has zero marginal effect on that metric.
The pinned clean524 and headroom25 remain unchanged (534 is within the band).
Updated only golden self-index counts, origin reference totals/option group and
the authentic check's corresponding totals. No rules or allowlist edits.
Reference provenance identifies r1's actual base+snapshot, not an invented commit.
Both calibration temporary roots were removed with their owned worktrees/builds.
Final full build exit0; full post-reference suite is now running.
Final full suite completed18:54:18UTC, exit0:320Tezt+64Alcotest. Raw combined log
is rollback-final-tests.log. CHECK1–5, authentic origin consumer, scope, bundle,
syntax and whitespace pass. Corrective implementation complete; formal review next.
