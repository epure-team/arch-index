---
auditor: spec-compliance-auditor
date: 2026-09-14
status: 0 critical, 0 warnings, 0 info
coverage: 15/15 functional requirements and 14/14 acceptance criteria verified
verdict: SPEC-COMPLIANT; delivery gates remain pending
---

# Spec compliance — tezos-call-resolution, round 3 cycle 1

Embedded-mode path adaptation: the skill's default `kb/reports/` destination is replaced by this task-owned `roster/tezos-call-resolution/` path. Reviewed HEAD `8bc4fb054cbf9997ed10cbf3519ce18194252093`, the complete `d4d9455..HEAD` delta, the updated 14-AC/6-CHECK spec, implementation and round-2 repair/review evidence, and the relevant files in full. Scope was independently gated PASS and is not re-adjudicated here.

## Compliance matrix

| Claims | Status | Implementation | Tests/evidence | Notes |
|---|---|---|---|---|
| FR-001–FR-006 / AC-1–AC-5 | PASS | `lib/arch_index/arch_index_cmt.ml:997-1114` | `tezt/tests/local_module_targets.ml:115-249`; CHECK-1 | Compiler identity, concrete ownership, source-order masking, stored binding names, includes/constraints, recursive and functor-body boundaries remain unchanged by the golden-only repair. |
| FR-007–FR-010 / AC-6–AC-8, AC-12 | PASS | `lib/arch_index/arch_index_cmt.ml:1548-1595,2150-2279`; `lib/arch_index/call_graph_extractor.ml:269-351` | CHECK-1 and CHECK-4 | The labeled-arity correction remains green for four native callers in both collector contexts; enumeration, metadata, refusal, point-free and flat same-file behavior remain covered. No production file changed in round 3. |
| FR-011–FR-013 / AC-9, AC-10 | PASS | `roster/tezos-call-resolution/comparison.js:4-169`; `roster/tezos-call-resolution/verify.js:71-176` | CHECK-2; CHECK-3 candidate+self | Canonical relation/multiset comparison, positioned groups, multiplicity and slice reporting remain intact. Fixed410 retains +400 Irmin/+395 protocol and zero relation loss. |
| FR-014 / AC-10, AC-13 | PASS | `roster/tezos-call-resolution/comparison.js:30-89`; `roster/tezos-call-resolution/verify.js:36-121` | CHECK-5, 39 assertions | Isolated real validators cover manifest, provenance, completeness/run-set and witness refusals with positive controls. As before, this is not CLI-wide fault injection or synthetic compiler-decoding evidence. |
| FR-015 / AC-11 | PASS | `roster/tezos-call-resolution/verify.js:170-177` | CHECK-3 candidate+self | Both reports retain `retention_authorized:false`. Positive gain alone does not authorize keep; review, QA, hosted exact-head CI and merge remain future delivery gates. |
| FR-015 / AC-14 | PASS | `test/fixtures/self-index-stats.txt:1-3`; `roster/tezos-call-resolution/check-self-index-smoke.js:1-63` | CHECK-6; CHECK-1 registration; full forced suite | The current built producer and exact CI query match the committed `25/980/6245` golden byte-for-byte. The checker has no threshold or rewrite path, distinguishes assertion exit 1 from setup exit 2, and cleans only its owned temporary directory. |

No unspecified public behavior was introduced: round 3 changes only the exact golden, its self-contained checker, Dune/test registration, and task/spec evidence. The checker invokes the same built producer, corpus path, schema and SQL output format used by `.github/workflows/ci.yml:130-141`; it reads the committed fixture as bytes and never refreshes it (`roster/tezos-call-resolution/check-self-index-smoke.js:9-17,20-52`).

## Prior finding resolution

The round-2 owner HIGH integration finding is **FIXED**. `test/fixtures/self-index-stats.txt:1-3` now records `modules: 25`, `functions: 980`, `calls: 6245`; CHECK-6 independently reproduced those exact bytes. The check is registered in both the native wrapper and full Dune suite (`tezt/tests/local_module_targets.ml:251-267`, `tezt/tests/dune:152-155`), so the standalone CI oracle can no longer remain stale while the normal task gates stay green.

The earlier FR-007/AC-12 and FR-014/AC-13 repairs remain verified. No production or Tezos canonical relation changed in this golden-only round: CHECK-3 returned the same candidate digest `90e76d6b40b2d7f108fcc25523f85de1cb533a98565a8a7d6d284c1654939d4b`, 45,052 candidate rows, 795 gains and zero loss; self replay retained 45,018 unchanged rows.

This report does not claim hosted CI, QA, keep or merge completion. Those are pending delivery gates under FR-015/AC-11, not code/spec violations. Root's separate pristine recalibration is external to this specialist pass and is not inferred from these commands.

## Commands personally executed

All commands used the RTK prefix and ran from `/home/mathias/dev/arch-index`. The fixed410 candidate/self pair ran only after root confirmed repository and Tezos stability.

| Exact command | Exit | Result |
|---|---:|---|
| `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune build --root .` | 0 | PASS |
| `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune runtest --root . --force` | 0 | PASS, Tezt 327/327 |
| `rtk proxy node roster/tezos-call-resolution/check-native.js` | 0 | CHECK-1 PASS, 7/7 registered cases |
| `rtk proxy node roster/tezos-call-resolution/check-comparison.js` | 0 | CHECK-2 PASS, 28 assertions |
| `rtk proxy node roster/tezos-call-resolution/verify.js --baseline /tmp/arch-index-resolution-baseline-OmhcEs/baseline.db --witness improvement/2026-09-14-tezos-resolution/attempt1-reviewed-witness.json` | 0 | CHECK-3 candidate PASS; +400 Irmin/+395 protocol, zero losses, `retention_authorized:false`; report `improvement/2026-09-14-tezos-resolution/2026-09-14T07-12-37-476Z-candidate-2823474/report.json` |
| `rtk proxy node roster/tezos-call-resolution/verify.js --baseline /tmp/arch-index-resolution-baseline-OmhcEs/baseline.db --self` | 0 | CHECK-3 self PASS; 45,018 unchanged rows, zero movement, `retention_authorized:false`; report `improvement/2026-09-14-tezos-resolution/2026-09-14T07-12-47-901Z-self-2823792/report.json` |
| `rtk proxy node roster/tezos-call-resolution/check-labeled-arity.js` | 0 | CHECK-4 PASS; four native callers, both contexts, exact head/residual metadata |
| `rtk proxy node roster/tezos-call-resolution/check-verifier-inputs.js` | 0 | CHECK-5 PASS, 39 assertions |
| `rtk proxy node roster/tezos-call-resolution/check-self-index-smoke.js` | 0 | CHECK-6 PASS; exact `25/980/6245` |
| `rtk proxy node scripts/review-bundle-verify.js` | 0 | PASS, bundle 1.6.0 and 22 hash-matched files |
| `rtk proxy git diff --check` | 0 | PASS |

The findings array contains only novel or unresolved spec-compliance findings and is therefore empty.
