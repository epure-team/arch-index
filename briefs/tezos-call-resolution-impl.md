# Implementation Brief — tezos-call-resolution

**Date:** 2026-09-14
**Mode:** full
**Status:** COMPLETED

## Modified files

- `lib/arch_index/arch_index_cmt.ml` and `.mli`: same-CMT compiler-identity structured-module ownership, source-order masking and optional collector context.
- `lib/arch_index/call_graph_extractor.ml`: both collector paths receive context; exact same-file flat target attribution.
- `tezt/tests/local_module_targets.ml`, registration in `tezt/tests/main.ml`: four native identity/refusal/arity/storage/fallback cases.
- `roster/tezos-call-resolution/`: canonical comparison, mutation checks, native wrapper and independent compiler UID endpoint evidence.
- `.gitignore`, task briefs/spec, `docs/edge-kind-contract.md`, friction log and external roadmap: scoped measurement, workflow and capability documentation.

## Decisions made

Comparison setup was verified before product edits and consumes no product iteration. An authentic failing native resolution assertion preceded implementation. New ordinary targets remain MAY_ENUMERATED, not MUST. Overapplication preserves explicit computed-return TOP rows. UID endpoint evidence is independent of product ownership resolution, but does not replace its refusal-policy tests or roster review.

The first real-corpus comparator refused pending explicit reviewed witnesses. The subsequent comparator update handles exact qualified-display corrections, duplicate transition multiplicity and separately witnessed return residuals; its28 assertions pass. Fresh approved-witness verification now passes (session77121), with exact canonical candidate digest90e76d6b40b2d7f108fcc25523f85de1cb533a98565a8a7d6d284c1654939d4b. Report: improvement/2026-09-14-tezos-resolution/2026-09-14T05-46-32-165Z-candidate-2339422/report.json.

The user approved the six-file scope extension on resume. Sol recalibrated only the two concrete A.run expectations/query outputs and the reviewed self-analysis origin reference/assertion location. Existing X.run/M.run TOP refusals, exact-table comparisons and failure injections remain. Historical gate observations are preserved. Root's compiler-probe review found location-only occurrence keys could combine PPX identifiers; the corrected probe keys complete located Longidents and rejects ambiguous native bodies before looking at DB targets. All831 endpoints still match. Eight identical native duplicates are consumed with multiplicity, not guessed unique.

## Quality Gates

- Baseline full build/test guard: PASS, Tezt320/320, before product implementation.
- Product build: PASS (session50326 and fresh final root build exit0).
- `rtk proxy node roster/tezos-call-resolution/check-native.js`: PASS, four native cases (session76644).
- `rtk proxy node roster/tezos-call-resolution/check-native.js --self-test`: PASS, five wrapper-classification assertions, root rerun.
- `rtk proxy node roster/tezos-call-resolution/check-comparison.js`: PASS, 28 assertions, root rerun.
- Fixed410 candidate measurement: +400 Irmin / +395 protocol distinct relations, no existing-relation loss; not an approved keep. 831 transitioned rows include31 aliases excluded from the primary metric;34 return TOP additions.
- Independent UID evidence v2: 831 endpoints and34 residuals, all810 caller/site buckets covered. Raw evidence SHA2568811a7e0b1d93c25eb5e40c2f680112add0d54e2a7f764f1a2aa1668e094c909; prior location-only report retained as historical, not used for approval.
- First full post-product guard: FAIL, Tezt321/324 (session8451), diagnosed and corrected under user-approved scope extension. Final full `dune runtest --root . --force`: PASS, exit0, Tezt324/324 (session3501); raw trace retained in improvement/2026-09-14-tezos-resolution/attempt1-guard-green-trace.csexp.
- Review bundle preflight: PASS,22 files hash-matched, bundle1.6.0.
- `rtk proxy git diff --check`: PASS. No configured formatter/coverage percentage claimed.
- Round ready for owned-file commit and independent review. No review/QA GO, PR or merge claimed. Unrelated user dirt preserved; the task manifest remains for scope verification after its active slot is deactivated.

## Points of attention for review

Review identity/member masking and flat attribution; native positive tests alone cannot establish safety of all refusal cases. Examine exact compiler UID witnesses and residual arity before approving fixed410 changes. CHECK-3 now names the concrete witness; verifier accepts a deactivated slot but refuses a foreign active task and still requires the pinned task manifest. Keep comparison approval versus retention distinct. Review all six recalibrated golden/query/origin evidence files explicitly.

## Identified out-of-scope

The previously requested six-path extension is now approved and implemented; the diagnosis remains historical. No new scope expansion is proposed. Do not change historical gate results, Tezos inputs, schema, dependencies, held PR93 or unrelated worktrees. Product attempts delivered remain0/5; attempt1 awaits independent review/QA/CI, not yet discarded or kept.
