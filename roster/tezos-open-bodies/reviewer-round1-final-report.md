# Independent owner review — same-round repair

Recommendation: approve. No current open findings. Both original findings were repaired in the same round and independently verified below. This is the owner's recommendation, not a pipeline GO, QA result or retention authorization.

Reviewed and tested HEAD: cd3cb3c7c4bcf9e87bcde69707f4db531f390286. Product source remains a5ae981; the repair changes task-local checkers and associated evidence/specification. The historical reviewer-round1-findings.json and reviewer-round1-report.md are preserved unchanged, including the original assertion failure.

## Resolution of original findings

- `correctness:open-body-residual-native-head-reuse`: resolved. `loadWitness` now rejects a repeated residual head_index before consuming its positioned row. The permanent CHECK6 compiles authentic same-line groups, accepts one residual for supplied counts [1,2], accepts two distinct heads for [2,2], and refuses reuse in both groups. This reviewer personally reproduced the original failure before repair and now personally executed the permanent repaired control successfully. Its native-derived positioned snapshots remain explicitly labelled admission controls, not actual database snapshots. Unchanged existing residual rows still require no new delta witness.
- `testing:open-body-rich-effect-preservation-coverage`: resolved. Strengthened CHECK1 runs predecessor/current process_cmt on the same compiled fixture and compares stable persisted function/effect/channel facts plus every pending-call field, including ownership, scopes, conditionality and deadness. It pins permitted head normalization to exact caller/site pairs and separately checks old0/current1 for each of three allowed residual sites. Effectful structure/application/unpack opens, actual optional/refutable partial/full/defaulted applications, result carriers/scopes/origins and homonym flat rows are now non-vacuous controls. Duplicate-sensitive flat comparison remains exact. This reviewer read the complete repair and personally executed the strengthened check.

## Personally executed final gates

All commands used RTK prefixes and ran serially under the exclusive owner build/gate lock. Main confirmed a write freeze in advance; CHECK3/4 ran without concurrent source/report writes.

| Command | Actual exit | Evidence |
|---|---:|---|
| opam exec -- dune build | 0 | Final build |
| opam exec -- _build/default/tezt/tests/main.exe --no-color --keep-going | 0 | 336 SUCCESS, no failures; first/last success 22:07:54.507–22:11:58.150 UTC on 2026-09-14 |
| node roster/tezos-open-bodies/check-native.js | 0 | Strengthened paired preservation plus existing identity, arity, drop and Tezt controls |
| node roster/tezos-open-bodies/check-witness-inputs.js | 0 | 316 actual DB pairs, genuine duplicate fixture, existing refusal controls |
| node roster/tezos-open-bodies/check-baseline.js --replay | 0 | 45052 rows, neutral replay, 17 record refusals, frozen bytes unchanged |
| node roster/tezos-open-bodies/verify.js --witness improvement/2026-09-14-tezos-resolution/attempt3-reviewed-witness.json | 0 | +316 protocol / +0 Irmin relations, zero losses/unexplained changes |
| node roster/tezos-open-bodies/check-self.js | 0 | Exact smoke, frozen policy and source attribution |
| node roster/tezos-open-bodies/check-residual-witness.js | 0 | Two native positives and two reused-head refusals |
| node scripts/review-bundle-verify.js | 0 | 22 SHA-matched files, bundle 1.6.0 |
| git diff --check | 0 | No whitespace errors at verification time |
| node roster/tezos-open-bodies/check-self-parser-test.js | 0 | Parser controls |

Full guard log: improvement/2026-09-14-tezos-resolution/attempt3-review-owner-final-full.log. Final owner CHECK4 evidence: improvement/2026-09-14-tezos-resolution/attempt3-candidate-TlNtWD. Both snapshots contain45052 rows;316 rows are replaced by exactly witnessed transitions. Candidate digest: 9ab4e0b13457247fb93dc83bf80323fcc5cec67866a18f56995ac0ec4a20867e. Baseline digest: 00f1769d6db7f6ee91ee51becabccd7b4ce13975acb6610c95ace69a7f620e9b. Retention remains unauthorized in the comparator report.

Correctness, security/evidence trust, regression and test-impact dimensions were re-reviewed. No new product, checker or scope issue remains from this owner review. The initial full source review remains applicable because product and Tezt source are unchanged. Exact self references still identify the same sole source assertion with x1; policy and calibrated measured source remain unchanged.

Formatter/coverage and language-pattern files remain unavailable, not passing. Crossruntime, managed hooks/claims and final pipeline normalization are main-owned dispositions; no successful execution is invented here. Only these two separate final owner report files were written by this reviewer after verification. Original unrelated user paths and historical reports were preserved. No open questions require user direction.
