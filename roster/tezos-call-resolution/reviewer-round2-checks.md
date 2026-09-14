# Reviewer — round 2, cycle 1

Reviewed `d4d945543e977617352f901138aa275ea4d33f8b`; recommendation **changes required** due to one new HIGH integration finding in `reviewer-round2-findings.json`. All four prior observations are resolved. No new call-target correctness defect was established.

Read updated implementation/spec (15 FR, 13 AC, 5 CHECK), actual `briefs/tezos-call-resolution-round1-repair.md`, full `12ab1fc..HEAD` diff by file batches, relevant complete new checkers and surrounding producer/validator/native registration code, prior finding records and ratchet evidence. Initial guessed `briefs/tezos-call-resolution-repair.md` was absent (read exit 1), then the actual path was read. Scope gate and external-runtime breaker are owned by root: actual scope PASS2 and skipped-degraded unchanged runtime digest are not claimed as this reviewer's executions.

## Previous finding resolution

| Prior fid | Round 2 assessment | Personally executed evidence |
| --- | --- | --- |
| `lib/arch_index/arch_index_cmt.ml:2174:correctness#e6e59b53` | RESOLVED | CHECK-4 passes: omitted required label remains partial with zero residual; fully supplied control retains one residual |
| `lib/arch_index/arch_index_cmt.ml:2150:spec#208245bb` | RESOLVED | Same CHECK-4 additionally covers omitted optional label and both ownership-context modes |
| `lib/arch_index/arch_index_cmt.ml:2150:correctness#0e5e8ad3` | RESOLVED | Same implemented invariant and native assertions; three observations of one repaired defect |
| `roster/tezos-call-resolution/check-comparison.js:116:spec#36ef3d4f` | RESOLVED | CHECK-5 passes 39 positive/negative checks against actual provenance, manifest, collection and positioned-witness validators |

The 15-line correction calculates `body_nargs` from `Some` expressions only when `module_target` proves an owned body; it uses that count for partial/residual accounting. Legacy heads and noreturn CFG continue to use the old slot count. Compiler-inserted default expressions carried by `Some` remain supplied expressions. Owner identity, masks, refusal policy, ordinary/point-free head forms, scope/channel metadata and flat collector wiring are unchanged.

CHECK-4 compiles authentic fixtures and links the exact checkout/private collector, checks all native premises before semantic residual assertions, verifies eight caller/context rows, and classifies assertion/setup failures separately. CHECK-5 mutates isolated files/SQLite databases, retains positive controls, checks the actual error types, and verifies cleanup and assertion/setup status controls. Both 410-row input tables now must belong to the declared run and contain 410 distinct artifacts. Their join cannot succeed through an undeclared run. The exported fixture parameters do not alter CLI defaults.

Both new checkers are native test registrations and explicit Dune dependencies. The CI unit/integration step executes `dune test --root .`, so they run there; private linking uses existing built library artifacts. Synthetic CMT bytes in CHECK-5 test hashing/selection only, not compiler decoding. Its invalid cases call actual validator functions, not every complete fixed410 CLI path; no wider coverage claim is made.

Historical native RED/GREEN is supported by the retained round1 evidence and the now-passing unchanged CHECK-4, but this review does not relabel it as automated historical ratchet verification. `pre_fix_sha` and `red_verified` must remain null under the recorded dirty-tree limitation. The comparator strengthening's old-code failure is retrospective evidence, not pre-edit RED.

## Commands personally executed at this head

All commands below ran from `/home/mathias/dev/arch-index`, prefixed with RTK.

| Command | Exit | Result |
| --- | --- | --- |
| `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune build --root .` | 0 | Build PASS |
| `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune runtest --root . --force` | 0 | Session 81978, Tezt 326/326 plus other Dune suites |
| `rtk proxy node roster/tezos-call-resolution/check-native.js` | 0 | Session 89616, 6/6 native tests |
| `rtk proxy node roster/tezos-call-resolution/check-native.js --self-test` | 0 | 5 wrapper assertions |
| `rtk proxy node roster/tezos-call-resolution/check-comparison.js` | 0 | CHECK-2, 28 assertions |
| `rtk proxy node roster/tezos-call-resolution/check-labeled-arity.js` | 0 | CHECK-4, four native callers/both contexts, exact partial/head/residual assertions |
| `rtk proxy node roster/tezos-call-resolution/check-verifier-inputs.js` | 0 | CHECK-5, 39 assertions |
| `rtk proxy node scripts/review-bundle-verify.js` | 0 | 22 file hashes, bundle 1.6.0 |
| `rtk proxy git diff --check main...HEAD` | 0 | Whitespace PASS |
| `rtk proxy node roster/tezos-call-resolution/verify.js --baseline /tmp/arch-index-resolution-baseline-OmhcEs/baseline.db --witness improvement/2026-09-14-tezos-resolution/attempt1-reviewed-witness.json` | 0 | Session 25015, CHECK-3 candidate PASS |
| `rtk proxy node roster/tezos-call-resolution/verify.js --baseline /tmp/arch-index-resolution-baseline-OmhcEs/baseline.db --self` | 0 | Self PASS, 45,018 unchanged rows |

Candidate report: `improvement/2026-09-14-tezos-resolution/2026-09-14T06-36-03-687Z-candidate-2585984/report.json`; canonical digest `90e76d6b40b2d7f108fcc25523f85de1cb533a98565a8a7d6d284c1654939d4b`, unchanged from the prior independently reviewed witness. 45,052 candidate rows, 831 removed/865 added, 795 relation gains (400 Irmin/395 protocol), zero relation loss. Self report: `improvement/2026-09-14-tezos-resolution/2026-09-14T06-36-22-123Z-self-2588280/report.json`. Both retain `retention_authorized=false`. The existing source/endpoint witnesses therefore remain exact for every canonical changed row; counts alone are not treated as semantic proof.

## New required CI gate failure

CI's independent self-index smoke test (`.github/workflows/ci.yml:130-140`) exact-diffs `test/fixtures/self-index-stats.txt`. That oracle remains pre-feature, although the origin-consumer oracle was correctly refreshed. Personally executed a fresh current producer with CI's build-dir/schema arguments, queried the same three exact output lines, and compared them byte-for-byte:

```text
Expected:
modules: 25
functions: 956
calls: 6145
Actual:
modules: 25
functions: 980
calls: 6245
ASSERTION FAILED: CI self-index exact golden mismatch
```

Producer and query each exit 0; comparison exits 1. Exact diagnostic command executed (temporary directory cleaned in finally; SQL `char(...)` only spells the identical CI labels):

```sh
rtk proxy node -e 'const fs=require("node:fs"),os=require("node:os"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");const dir=fs.mkdtempSync(path.join(os.tmpdir(),"arch-index-reviewer-ci-smoke-"));try{const db=path.join(dir,"self.db");const r=cp.spawnSync("./_build/default/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe",["--build-dir=_build/default/lib/arch_index","--db-path="+db,"--schema-path=architecture-schema.sql"],{encoding:"utf8",maxBuffer:32*1024*1024});assert.equal(r.status,0,r.stderr);const q=cp.spawnSync("sqlite3",[db,"SELECT char(109,111,100,117,108,101,115,58,32) || count(*) FROM modules; SELECT char(102,117,110,99,116,105,111,110,115,58,32) || count(*) FROM functions; SELECT char(99,97,108,108,115,58,32) || count(*) FROM calls;"],{encoding:"utf8"});assert.equal(q.status,0,q.stderr);const expected=fs.readFileSync("test/fixtures/self-index-stats.txt","utf8");console.log("Expected:\n"+expected+"Actual:\n"+q.stdout);if(q.stdout!==expected){console.error("ASSERTION FAILED: CI self-index exact golden mismatch");process.exitCode=1;}}finally{fs.rmSync(dir,{recursive:true});}'
```

HIGH is justified by deterministic failure of a required ship gate, not by an unsound target or incorrect product semantics. Existing Dune tests do not execute this separate smoke comparison. Repair should refresh this exact golden according to `docs/adr/001-self-index-golden.md`, retaining CI and its exact comparison. No change is made during review.

## Limits and handoff

No formatter or coverage percentage is claimed; language pattern files remained unavailable as recorded in round1. Full Dune output was observed via the tool session; no standalone untruncated raw log is claimed. Root reports cross-runtime skipped-degraded under the unchanged breaker; that is not external approval. No hosted CI, QA, keep or merge approval is granted by this report.

Original arity reproducer `/tmp/arch-index-reviewer-label-qt01kV` remains untouched. No product, golden, CI file, commit, branch, worktree or Tezos input was modified. Report writes began only after candidate/self source-stability checks completed. Unrelated user dirt is preserved.
