# QA Brief — tezos-residual-targets

**Date:** 2026-09-14
**Status:** GO ✅
**Round:** 1 (qualifying0/5)

Fresh cycle1, round1. Review GO and static convergence0 read before QA;
wrapper/helper presence verified. QA state was derived by the lifecycle tool,
draft gated with max-rounds5 (exit0, no warnings/violations), then persisted
before this report. All commands below were personally executed sequentially
by root after review GO, not borrowed from specialist passes. Product HEAD
436cbfc667a5f01880fd9c11f53242c8fffb6ed3; pending changes are scoped reports.

## Quality gates

Commands below have the rtk proxy prefix. No failed gate or later retry.

| Gate | Command after prefix | Exit/result | Duration |
|---|---|---|---|
| Build |opam exec --switch=/home/mathias/dev/arch-index -- dune build --root .|0|0.246s|
| Full suite |opam exec --switch=/home/mathias/dev/arch-index -- dune runtest --root . --force|0;332/332 Tezt plus unit/check suites|Tezt17:29:28.519–17:33:11.561 UTC|
| Format/full lint |not configured in validated preflight|N/A, notPASS|N/A|
| Bundle |node scripts/review-bundle-verify.js|0;22 SHA-matched files|not separately timed|
| Whitespace |git diff --check|0|not separately timed|
| CHECK1 |node roster/tezos-residual-targets/check-native.js|0;both native contexts and5/5 feature tests|Tezt17:33:43.864–17:34:14.036 UTC|
| CHECK2 |node roster/tezos-residual-targets/check-comparison.js|0;38 controls,3 native positives/12 refusals, paired positive/10 refusals|not separately timed|
| CHECK3 |node roster/tezos-residual-targets/prepare-baseline.js --check|0;45052 rows,4772Irmin/11615protocol|not separately timed|
| CHECK4 |node roster/tezos-residual-targets/verify.js --witness improvement/2026-09-14-tezos-resolution/attempt2-reviewed-witness.json|0;124 gains,0 losses/errors|not separately timed|
| CHECK5 |node roster/tezos-call-resolution/check-self-index-smoke.js|0;25/989/6275 exact|0.083s|

Raw full-suite log: improvement/2026-09-14-tezos-resolution/attempt2-qa-full-guard.log.
SHA2569d56cdf8b4037d89ad05a7ea9e0987dee705afe935de9ecbe3681eb466d733d9.
Actual log census332 SUCCESS/0 FAILURE; five new cases and327 existing cases,
none skipped. Controlled assertion/setup/cleanup and foreign-key errors are
negative-path test output in that passing log, not suppressed failures.
No regression observed by these gates. Individual asynchronous checker wall
durations were not instrumented; no invented duration is supplied above.

## Scoped behavior coverage

| Criteria | QA evidence |
|---|---|
|AC1/2/3|CHECK1 actual same-file body endpoints, identity/form/refusal and source-order masking tests|
|AC4|CHECK1 exact Some supplied count, hidden arity, partial/residual metadata in both contexts|
|AC5|CHECK1 occurrence-provenance/legacy flat regression plus full CFG/channel/config suite; CHECK4 unchanged point-free facts|
|AC6|CHECK1 actual dropped-body rejection and flat missing-local/foreign-homonym refusal|
|AC7|CHECK3 fresh frozen neutral producer replay and unchanged canonical provenance|
|AC8/9/10|CHECK2 refusal/multiplicity controls; CHECK4 independently replayed native witnesses,0 loss/new MUST/unexplained movement|
|AC11|CHECK1 body-only table and unchanged unqualified alias-call behavior|
|AC12|CHECK4 retention_authorized=false; review GO now present, hosted CI/merge remain delivery conditions|
|AC13|CHECK5 exact golden; full authentic consumer passes with sole1559 assertion and unchanged rule|

CHECK4 output: improvement/2026-09-14-tezos-resolution/attempt2-2026-09-14T17-35-08-875Z-1047006/.
45052rows both sides,124 removed/added,124 relation gains (+9Irmin/+115protocol),
0loss/errors/other gain. Candidate digest00f1769d6db7f6ee91ee51becabccd7b4ce13975acb6610c95ace69a7f620e9b.
The earlier exact-commit pristine SOURCE_ONLY calibration remains separate
evidence in roster/tezos-residual-targets/pristine-repair-calibration.md; not
misrepresented as another QA execution.

## Conditional gates and cross-runtime QA

Code-intel skipped: no kb/properties.md, hence no code-intel declaration.
Managed claims/context projection and hooks unavailable as documented; no
freshness pass is invented. TUI/web skipped: no such behavior in validated scope.
Formatter/coverage absent. No tool installed to turn an absent check into a pass.

Actual command: node scripts/xruntime-review.js opencode --task tezos-residual-targets
--phase qa --check-availability --write. Exit0, status skipped-degraded,
reason runtime degraded during review with unchanged runtime version,
digest opencode:76f897c73342fdbf, source review-go. Cross-runtime QA skipped
under the shared breaker, not an independent PASS; no human retry inferred.
Helper warns that briefs/ is not ignored and its real journal is in scope.

## Verdict

GO for roster-ship. User has explicitly authorized routine autonomous review,
QA, PR and exact-head-green rebase merge; no new approval or quiz fabricated.
Still1/5 delivered until the actual merge. No task worktree remains, no unrelated
user files, held PR93 or Tezos source were modified by QA.
