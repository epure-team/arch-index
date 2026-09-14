# Reviewer — round 3, cycle 1

Reviewed HEAD `8bc4fb054cbf9997ed10cbf3519ce18194252093` and the complete `d4d9455..HEAD` delta in file batches, including historical review artifacts, current implementation brief/specification (15 FR, 14 AC, 6 CHECK), round2 repair/verdict, complete smoke checker and native registration files. Recommendation: **approve this reviewed repair**; no new or unresolved finding established. This is not hosted-CI, QA, merge or keep approval.

## Prior findings

- `test/fixtures/self-index-stats.txt:2:integration#3f5e6e18`: RESOLVED. Personally executed CHECK-6 successfully against the current built producer: exact bytes are `modules: 25`, `functions: 980`, `calls: 6245`, each newline-terminated. The prior expected 956/6145 is gone. No comparison tolerance or CI bypass was introduced.
- `lib/arch_index/arch_index_cmt.ml:2174:correctness#e6e59b53`, `lib/arch_index/arch_index_cmt.ml:2150:spec#208245bb`, and `lib/arch_index/arch_index_cmt.ml:2150:correctness#0e5e8ad3`: remain RESOLVED. CHECK-4 again passes all four native callers in both ownership-context modes, including omitted required/optional labels and fully supplied residual controls. No producer change in this repair.
- `roster/tezos-call-resolution/check-comparison.js:116:spec#36ef3d4f`: remains RESOLVED. CHECK-5 again passes 39 isolated actual-validator controls; provenance, artifact/run completeness and witness binding remain fail-closed.

## Correctness, integration and cleanup assessment

The new checker reproduces CI's actual three SQLite statements and compares Buffers, preserving the final-newline contract. It runs the explicit built producer over the same library corpus and schema, into a fresh mkdtemp-owned database. It never refreshes the fixture. Missing inputs, failed/timed-out producer/query and failed cleanup become SETUP exit2; only a byte mismatch after successful production/query becomes assertion exit1. Both subprocesses have 120-second timeouts and bounded output. Cleanup is confined to the generated scratch path and is guarded against setup failures before allocation.

The local `_opam` switch is used only when present; otherwise the producer inherits the environment, matching CI's opam-enabled test step. The script and golden are explicit Dune dependencies (`tezt/tests/dune:154`); the native list registers the new checker and the standalone wrapper requires all seven SUCCESS titles. Existing architecture ownership/masking/refusal/arity/flat-attribution behavior and compiler witness gates are unchanged. The full suite actually exercises the new smoke gate, so the earlier gap between local tests and CI's golden comparison is closed.

Reviewed runtime boundaries and ordinary correctness/regression risks; no evidence-backed security issue or new product regression found. This is not a vulnerability-hunting pass. No formatter or coverage percentage is claimed. Language-pattern files remained unavailable as recorded in round1. The historical authentic smoke RED/GREEN is supporting evidence, not a newly executed historical-red gate: `pre_fix_sha` and `red_verified` remain null under the dirty-tree limitation.

## Commands personally executed

All commands ran from `/home/mathias/dev/arch-index` with the RTK prefix.

| Command | Exit | Evidence |
| --- | ---: | --- |
| `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune build --root .` | 0 | Current build PASS |
| `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune runtest --root . --force` | 0 | Session79107; Tezt327/327 plus other Dune suites |
| `rtk proxy node roster/tezos-call-resolution/check-native.js` | 0 | Session76693; all7/7 required SUCCESS titles |
| `rtk proxy node roster/tezos-call-resolution/check-native.js --self-test` | 0 | Wrapper5 assertions |
| `rtk proxy node roster/tezos-call-resolution/check-comparison.js` | 0 | CHECK-2;28 assertions |
| `rtk proxy node roster/tezos-call-resolution/check-labeled-arity.js` | 0 | CHECK-4; four callers/both contexts and exact head/residual metadata |
| `rtk proxy node roster/tezos-call-resolution/check-verifier-inputs.js` | 0 | CHECK-5;39 assertions |
| `rtk proxy node roster/tezos-call-resolution/check-self-index-smoke.js` | 0 | CHECK-6; exact25/980/6245 |
| `rtk proxy node scripts/review-bundle-verify.js` | 0 | Bundle1.6.0;22 hash-matched files |
| `rtk proxy git diff --check main...HEAD` | 0 | Whitespace PASS |
| `rtk proxy node roster/tezos-call-resolution/verify.js --baseline /tmp/arch-index-resolution-baseline-OmhcEs/baseline.db --witness improvement/2026-09-14-tezos-resolution/attempt1-reviewed-witness.json` | 0 | Session96231; candidate PASS |
| `rtk proxy node roster/tezos-call-resolution/verify.js --baseline /tmp/arch-index-resolution-baseline-OmhcEs/baseline.db --self` | 0 | Self PASS;45018 unchanged rows |

Candidate report: `improvement/2026-09-14-tezos-resolution/2026-09-14T07-06-38-634Z-candidate-2764925/report.json`. Canonical digest remains `90e76d6b40b2d7f108fcc25523f85de1cb533a98565a8a7d6d284c1654939d4b`;45052 rows,831 removed/865 added,795 distinct relation gains (400 Irmin/395 protocol), zero relation losses. Exact prior reviewed witness still binds this canonical snapshot; gains are not described as syntactic calls or proof from counts alone.

Self report: `improvement/2026-09-14-tezos-resolution/2026-09-14T07-07-05-430Z-self-2768791/report.json`; baseline digest `4ce3270de370cc9db7b449531610c0dfaa7eb45647ce4dd68601fa417933fecd`, zero movement. Both reports retain `retention_authorized=false`.

Full-suite output includes intentional assertion/setup/cleanup-injection diagnostics; its actual final process exit was0. Output was inspected via tool sessions with truncation, not retained here as a claimed complete raw log. Native warnings about old Tezt temporary directories were not cleaned because those directories are not owned by this review.

## Other owners and remaining delivery gates

Root owns the actual scope-gate PASS and cross-runtime skipped-degraded outcome; neither is relabeled as my execution or external approval. Root separately executed pristine committed-tree recalibration, documented in `pristine-recalibration-round3.md`: exit0, golden A=B25/956/6145 and C=D25/980/6245; whole-tree ceiling A=B534/C=D537 remains within524±25. I read that report and the complete script operational workflow, but did not execute its worktree/build/cleanup operations. Root's mechanical QA-scope14AC/6CHECK correction is documentation-only and separately owned.

The pristine aggregate result supports the golden refresh on the self corpus, not semantic correctness on all Tezos inputs. Hosted exact-head CI, independent QA and merge remain outstanding delivery requirements. All unrelated user dirt is preserved. No product/CI/golden edit, commit, worktree or Tezos-input mutation was performed by this reviewer. Only the two owned review reports were written, after candidate/self provenance checks completed. The empty findings array contains no historical resolved finding disguised as OPEN.
