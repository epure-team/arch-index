---
auditor: spec-compliance-auditor
date: 2026-09-14
status: 0 critical, 0 warnings, 0 info
coverage: 15/15 functional requirements verified (100%)
verdict: SPEC-COMPLIANT; integration gate still blocked
---

# Spec compliance — tezos-call-resolution, round 2 cycle 1

Embedded-mode path adaptation: the skill's default `kb/reports/` destination is replaced by this task-owned `roster/tezos-call-resolution/` path. This audit reviewed HEAD `d4d945543e977617352f901138aa275ea4d33f8b` against the full updated 13-AC/5-CHECK contract and the complete `12ab1fc..HEAD` repair delta.

## Compliance matrix

| Claim | Status | Implementation | Test/evidence | Notes |
|---|---|---|---|---|
| FR-001 / AC-1, AC-2 | PASS | `lib/arch_index/arch_index_cmt.ml:997-1007` | `tezt/tests/local_module_targets.ml:115-159,223-249`; CHECK-1 | Roots remain compiler-identity keyed per CMT; homonymous CMT targets stay file-local. |
| FR-002 / AC-2, AC-5 | PASS | `lib/arch_index/arch_index_cmt.ml:1023-1039,1090-1102` | `tezt/tests/local_module_targets.ml:185-190`; CHECK-1 | Alias, parameter, application, unpack and unproven hops refuse. |
| FR-003 / AC-3, AC-4 | PASS | `lib/arch_index/arch_index_cmt.ml:1040-1084` | `tezt/tests/local_module_targets.ml:177-192`; CHECK-1 | Source-order value/module/include masks remain intact. |
| FR-004 / AC-3 | PASS | `lib/arch_index/arch_index_cmt.ml:973-995,1053-1057` | `tezt/tests/local_module_targets.ml:191-192`; CHECK-1 | Targets retain stored qualified/ordinal binding names. |
| FR-005 / AC-4 | PASS | `lib/arch_index/arch_index_cmt.ml:1023-1026,1065-1083` | `tezt/tests/local_module_targets.ml:177-184`; CHECK-1 | Literal constraints/includes preserve proven exports; opaque include names mask. |
| FR-006 / AC-2, AC-5 | PASS | `lib/arch_index/arch_index_cmt.ml:1027-1032,1063-1064` | `tezt/tests/local_module_targets.ml:181-190`; CHECK-1 | Recursive/functor-local definitions are discovered without instance expansion. |
| FR-007 / AC-6, AC-12 | PASS | `lib/arch_index/arch_index_cmt.ml:2150-2162,2188-2192,2273-2279` | `roster/tezos-call-resolution/check-labeled-arity.js:10-18,96-130`; CHECK-4 | Round-1 C1 is fixed: only `Some` argument expressions are counted for a proven owned body. Omitted required/optional labels retain partial heads without residuals; fully supplied controls retain one residual. Legacy non-owned head accounting is unchanged. |
| FR-008 / AC-1, AC-6, AC-7, AC-12 | PASS | `lib/arch_index/arch_index_cmt.ml:2229-2236` | CHECK-1 and CHECK-4 | Owned heads remain enumerated; exact partial/residual metadata, dropped-node and existing CFG facts are covered. |
| FR-009 / AC-7 | PASS | `lib/arch_index/arch_index_cmt.ml:1582-1585` | `tezt/tests/local_module_targets.ml:193-194`; CHECK-1/2 | Point-free `value_alias` and ordinary-head contracts are unchanged. |
| FR-010 / AC-8 | PASS | `lib/arch_index/call_graph_extractor.ml:269-280,320-351` | `tezt/tests/local_module_targets.ml:223-249`; CHECK-1 | Both collectors share per-CMT ownership context; flat attribution keeps the same-file guard. |
| FR-011 / AC-9 | PASS | `roster/tezos-call-resolution/comparison.js:4-29,74-105` | CHECK-2 and CHECK-3/self | Canonical rows retain identity, nullable diagnostics and multiplicity. |
| FR-012 / AC-9 | PASS | `roster/tezos-call-resolution/comparison.js:91-100,106-169` | CHECK-2; CHECK-3/self | Reordering is neutral; deletion, swap, kind and duplicate mutations remain detected. |
| FR-013 / AC-10 | PASS | `roster/tezos-call-resolution/verify.js:71-86,161-176` | CHECK-3 | Reports retain positioned changed groups, relation terminology and Irmin/protocol partitioning. |
| FR-014 / AC-10, AC-13 | PASS | `roster/tezos-call-resolution/comparison.js:30-89`; `roster/tezos-call-resolution/verify.js:36-60,88-121` | `roster/tezos-call-resolution/check-verifier-inputs.js:53-162`; CHECK-5 | Round-1 W1 is fixed. Thirty-nine assertions exercise the actual isolated manifest, provenance, DB/run-completeness and witness validators with valid controls and cleanup. This is not CLI-wide fault injection and does not claim corrupted compiler decoding coverage; authentic decoding remains CHECK-4/fixed410. |
| FR-015 / AC-11 | PASS | `roster/tezos-call-resolution/verify.js:170-177` | CHECK-3 candidate/self | Reports keep `retention_authorized:false`; positive gains cannot authorize keep. Review, QA, hosted CI and merge remain delivery gates, not silently satisfied by this audit. |

No public repair behavior outside the updated spec was found. The repair exports small validator seams only to make the existing fail-closed policy directly testable; defaults and the CLI path remain pinned (`roster/tezos-call-resolution/verify.js:36-60,123-189`).

## Prior findings resolution

- Round-1 C1, FR-007/AC-6: **FIXED**. `body_nargs` counts supplied `Some` expressions only when `module_target path` proves the owned body (`lib/arch_index/arch_index_cmt.ml:2150-2162`), and both partial classification and residual emission use that count (`:2188-2192`, `:2273-2279`). CHECK-4 independently passed all four callers in both context-disabled/context-enabled collector runs with exact heads and residual counts.
- Round-1 W1, FR-014/AC-10: **FIXED**. CHECK-5 independently passed 39 assertions over real isolated validators. Its scope is accurately limited: it is not a complete CLI fault-injection campaign, does not mutate Tezos, and does not claim compiler decoding from synthetic bytes.

## Separate integration blocker

The required hosted-CI self-index golden is stale. `.github/workflows/ci.yml:130-141` produces and exact-diffs the three counts against `test/fixtures/self-index-stats.txt:1-3`. I personally ran the equivalent producer/query in a fresh owned temporary directory: the producer/query succeeded, but the exact comparison failed exit 1 because the fixture expects `25/956/6145` while HEAD produces `25/980/6245`.

This is a concrete HIGH integration blocker already owned by the round-2 reviewer, not a novel spec-compliance finding and not evidence of a Tezos/fixed410 semantic change. FR-015/AC-11 is still honored because no keep is authorized and hosted CI is still required; the implementation brief likewise claims no round-2 CI or merge approval. The focused repair is to review and refresh only the stale golden under `docs/adr/001-self-index-golden.md`, preserve the exact CI comparison, and rerun the gate. Until then, overall shipping verdict remains **NO-GO despite code/spec parity**.

## Commands personally executed

All commands used the RTK prefix and ran from `/home/mathias/dev/arch-index`.

| Command | Exit | Result |
|---|---:|---|
| `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune build --root .` | 0 | PASS |
| `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune runtest --root . --force` | 0 | PASS, Tezt 326/326 |
| `rtk proxy node roster/tezos-call-resolution/check-native.js` | 0 | CHECK-1 PASS, six registered tests |
| `rtk proxy node roster/tezos-call-resolution/check-comparison.js` | 0 | CHECK-2 PASS, 28 assertions |
| `rtk proxy node roster/tezos-call-resolution/verify.js --baseline /tmp/arch-index-resolution-baseline-OmhcEs/baseline.db --witness improvement/2026-09-14-tezos-resolution/attempt1-reviewed-witness.json` | 0 | CHECK-3 PASS; +400 Irmin/+395 protocol relations, zero losses, canonical digest `90e76d6b40b2d7f108fcc25523f85de1cb533a98565a8a7d6d284c1654939d4b`, `retention_authorized:false`; report `improvement/2026-09-14-tezos-resolution/2026-09-14T06-44-51-523Z-candidate-2652300/report.json` |
| `rtk proxy node roster/tezos-call-resolution/verify.js --baseline /tmp/arch-index-resolution-baseline-OmhcEs/baseline.db --self` | 0 | CHECK-3 replay PASS; 45,018 unchanged rows, zero movement, `retention_authorized:false`; report `improvement/2026-09-14-tezos-resolution/2026-09-14T06-45-04-318Z-self-2652690/report.json` |
| `rtk proxy node roster/tezos-call-resolution/check-labeled-arity.js` | 0 | CHECK-4 PASS; four native callers, both collector contexts, exact head/residual metadata |
| `rtk proxy node roster/tezos-call-resolution/check-verifier-inputs.js` | 0 | CHECK-5 PASS, 39 assertions |
| `rtk proxy node scripts/review-bundle-verify.js` | 0 | PASS, bundle 1.6.0 and 22 hash-matched files |
| `rtk proxy git diff --check` | 0 | PASS |
| CI-equivalent fresh self-index producer/query/exact fixture comparison in `arch-index-spec-ci-smoke-*` | 1 | Authentic assertion failure: expected `25/956/6145`, actual `25/980/6245`; temporary directory removed |

The findings JSON contains only novel or unresolved spec-compliance findings and is therefore an empty array. The stale CI golden remains explicitly visible here and in the owner's independent HIGH finding; it is not duplicated under a misleading FR-007/FR-014 classification.
