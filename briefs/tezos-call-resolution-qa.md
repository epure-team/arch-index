# QA Brief — tezos-call-resolution

**Date:** 2026-09-14T07:23:58.257Z
**Status:** GO ✅
**Round:** 2 (qualifying 0/5)

## Round state

Cycle1 round2. Prior round1 NO-GO (missing optional timing executable, before
build invocation) is retained in qa-state.json and qa-round1-setup-failure.md.
No product code changed to rerun. Actual QA convergence gate exit0, no warnings
or violations; state persisted before this report. Review GO round3 remains valid.
Reviewed product HEAD:8bc4fb054cbf9997ed10cbf3519ce18194252093; subsequent edits
are task evidence only. All gates below were personally executed by root.

## Quality gates and runnable checks

| Gate | Command (rtk proxy prefix used) | Exit/result | Wall time |
|---|---|---|---|
| Build | opam exec --switch=/home/mathias/dev/arch-index -- dune build --root . | 0 PASS |0.344s|
| Full tests | opam exec --switch=/home/mathias/dev/arch-index -- dune runtest --root . --force |0;327/327 Tezt, other Dune suites pass|188.296s|
| Whitespace | git diff --check |0 PASS|not timed|
| Bundle | node scripts/review-bundle-verify.js |0;22 hashes|not timed|
| CHECK1 | node roster/tezos-call-resolution/check-native.js |0;7/7|27.036s|
| CHECK2 | node roster/tezos-call-resolution/check-comparison.js |0;28 assertions|0.065s|
| CHECK4 | node roster/tezos-call-resolution/check-labeled-arity.js |0;4 callers ×2 contexts|0.598s|
| CHECK5 | node roster/tezos-call-resolution/check-verifier-inputs.js |0;39 assertions|0.412s|
| CHECK6 | node roster/tezos-call-resolution/check-self-index-smoke.js |0;exact25/980/6245|0.183s|
| Wrapper control | node roster/tezos-call-resolution/check-native.js --self-test |0;5 assertions|0.021s|
| CHECK3 | node roster/tezos-call-resolution/verify.js --baseline /tmp/arch-index-resolution-baseline-OmhcEs/baseline.db --witness improvement/2026-09-14-tezos-resolution/attempt1-reviewed-witness.json |0 PASS|3.896s|
| Self replay | node roster/tezos-call-resolution/verify.js --baseline /tmp/arch-index-resolution-baseline-OmhcEs/baseline.db --self |0 PASS|0.953s|

Raw logs: [full](../improvement/2026-09-14-tezos-resolution/qa-round2-full.log),
[build](../improvement/2026-09-14-tezos-resolution/qa-round2-build.log),
[native](../improvement/2026-09-14-tezos-resolution/qa-round2-native.log).
Sibling qa-round2-{comparison,arity,inputs,smoke,wrapper,candidate,self}.log files
retain raw outputs and Bash builtin timing. Full log46660 bytes, SHA256
0fd7c45282807f314c7e1bd376584c9a6321c0554ba76a23a4086bcf55ec4454.
Parsed327 SUCCESS and0 FAILURE records. Seven task-added tests and320 existing
Tezt cases pass. Deliberate failure-injection diagnostics remain in the raw log,
not removed or presented as unexpected failures. No configured formatter/full
linter/coverage tool exists; whitespace is not claimed as a full linter or a
coverage percentage.

## Behavioral scope

FR001–010 / AC1–8,12: native ownership, identity/homonym, masking, includes,
constraints, alias/parameter/application/unpack refusal, exact stored targets,
partial/return residuals, storage rejection and both collectors pass. CHECK4
verifies omitted required/optional labels in both context modes with exact
metadata. FR011–014 / AC9,10,13: duplicate/multiset mutation controls and actual
isolated input/provenance/run/witness refusal validators pass. The synthetic
validator fixtures do not claim authentic compiler decoding; native/fixed410 do.
FR015 / AC11,14: exact golden passes, while both comparison reports still say
retention_authorized:false. Hosted CI and merge are not inferred from QA.

Candidate report: improvement/2026-09-14-tezos-resolution/2026-09-14T07-23-18-051Z-candidate-2867559/report.json.
45018→45052 rows;831 removed/865 added,795 distinct relation gains
(Irmin400/protocol395),0 losses. Canonical90e76d6b40b2d7f108fcc25523f85de1cb533a98565a8a7d6d284c1654939d4b
is unchanged from independently reviewed UID-backed evidence. These are relations,
not unique syntactic calls or a semantic certificate from counts.
Self report:2026-09-14T07-23-36-125Z-self-2867999,45018 unchanged rows,
baseline4ce3270de370cc9db7b449531610c0dfaa7eb45647ce4dd68601fa417933fecd.
All410 CMT inputs and retained baseline remain unchanged.

## Conditional checks

Code-intel command: node /home/mathias/dev/agent-roster/scripts/code-intel-resolve.js gate --timeout 120, exit0:
```text
SKIP: no code-intel block
RESULT: skip
```
TUI/web: not applicable. Managed claims/projection/hooks: absent, no success claimed.

## Cross-runtime QA

Actual provider-free availability command:
node scripts/xruntime-review.js opencode --task tezos-call-resolution --phase qa --check-availability --write
returned0, skipped-degraded, reason "runtime degraded during review with unchanged
runtime version", digest opencode:76f897c73342fdbf, source review-go.
Cross-runtime QA: skipped (review breaker, unchanged runtime version).
No human retry inferred, no external approval claimed. The helper also warned
that briefs/ is not ignored; its tracked task journal remains explicitly scoped.

## Delivery and cleanup

Root's separate pristine recalibration PASS and complete owned-worktree cleanup
are documented in roster/tezos-call-resolution/pristine-recalibration-round3.md.
No temporary verification DB/worktree remains from those checks. Keep the
necessary61MiB baseline directory and1.9MiB old source/DB proof until the loop
finishes. Foreign Tezt leftovers/worktrees and unrelated dirty files are untouched.
QA GO authorizes the next ship phase under standing user autonomy; hosted
exact-head CI and rebase merge are still required. Product attempts delivered0/5.
