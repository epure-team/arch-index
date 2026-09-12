# QA Brief — origin-recurring-consumer

**Date:** 2026-09-12T19:37:14.516Z
**Status:** GO ✅
**Round:** 1 (qualifying 0/5)

## Round state

Fresh cycle 1, round 1, causes []; draft convergence exit 0, no warnings or violations.
Tested clean product/review HEAD d8c224216d65 (implementation 189f805); no product edits in QA.

## Quality gates

Commands run from the task worktree; all OCaml commands use opam switch /home/mathias/dev/arch-index and explicit dune --root . where applicable.

| Gate | Exact command (all prefixed rtk proxy) | Result |
|---|---|---|
| Build | opam exec --switch=/home/mathias/dev/arch-index -- dune build --root . @install | exit 0; 0.120909481s |
| Full suite | opam exec --switch=/home/mathias/dev/arch-index -- dune test --root . --force | session 37625 terminal 0; 245/245 Tezt + 64 Alcotest |
| Whitespace | git diff --check d7112964df679fb44bc033e878059537208f58da..HEAD | exit 0 |
| CHECK-1 | opam exec --switch=/home/mathias/dev/arch-index -- node checks/origin-recurring-consumer.js authentic | exit 0; 1.040730105s |
| CHECK-2 | opam exec --switch=/home/mathias/dev/arch-index -- node checks/origin-recurring-consumer.js failures | exit 0; 2.980936691s |
| CHECK-3 | opam exec --switch=/home/mathias/dev/arch-index -- node checks/origin-recurring-consumer.js package | exit 0; 0.170741661s |
| Production | opam exec --switch=/home/mathias/dev/arch-index -- node scripts/origin-consumer.js --out /tmp/origin-rootqa.4IBk1S/output | exit 0; held; 0.290040544s |
| Package validator | node scripts/origin-consumer-artifacts.js /tmp/origin-rootqa.4IBk1S/output | exit 0 |
| Fresh self-index | opam exec --switch=/home/mathias/dev/arch-index -- ./_build/default/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe --build-dir=_build/default/lib/arch_index --db-path=/tmp/origin-rootqa.4IBk1S/self.db --schema-path=architecture-schema.sql | exit 0; 0.099811656s |
| Golden | sqlite3 counts for modules/functions/calls; Node strictEqual against test/fixtures/self-index-stats.txt | exit 0; byte-identical 23/828/5223 |
| Recalibration | opam exec --switch=/home/mathias/dev/arch-index -- env DUNE_CACHE=enabled DUNE_CACHE_STORAGE_MODE=copy ./scripts/recalibrate.sh --check | session 89491 terminal 0; all four cells 23/828/5223 and ceiling 396; pin 383 +/-25 unchanged |
| Old rules | ./_build/default/bin/arch_rules/arch_rules.exe /tmp/origin-rootqa.4IBk1S/self.db arch-rules.txt --on-vacuous fail | exit 0; 1 proved, 3 UNKNOWN, 0 failing |
| Impact | ./_build/default/bin/arch_impact/arch_impact.exe /tmp/origin-rootqa.4IBk1S/self.db --diff d7112964df679fb44bc033e878059537208f58da..HEAD --repo . | exit 0; zero indexed functions touched, 51 unindexed files explicitly UNKNOWN |
| Scope | bash scripts/check-scope-diff.sh briefs/origin-recurring-consumer-manifest.txt | exit 0 |
| Review resume | node scripts/check-review-convergence.js briefs/origin-recurring-consumer-review.json --static | exit 0; 8 trace lines |

Full command elapsed time for polled tests/recalibration was not retained; first-to-last Tezt success spans 135.499s, not whole-command duration. No separate formatter, full linter, or code-coverage framework configured; no coverage percentage claimed.

## Tests and behavior

Five new Tezt tests (three native checker modes and two exit controls); 240 existing Tezt +64 Alcotest pass; zero skipped or failed Tezt. No regression observed.
Native success/new-origin/multiplicity cases exercise the actual compile/index/rules/report pipeline; updated references cannot waive either native violation. Failure modes check drift, policy and error separation; package validation checks complete retained report sets and fail-closed publication. Production held is eligible UNKNOWN with an unchanged inventory, NOT a proof of origin absence. One exact assertion allowance remains; no division waiver.
All20 ACs were assessed by the spec specialist: the matrix is partial (26/45 claim rows PASS,19 UNTESTED), not complete coverage. Six MEDIUM and one LOW review observations remain explicit test/maintainability/classification debt; see specialist reports. Actual remote CI/upload remains a mandatory premerge check.

## Raw evidence

[Root command output](../roster/origin-recurring-consumer/qa-root.log).
Existing MUST-null 350 advisory in the ordinary suite is distinct from pristine recalibration396. Deliberate checker/cleanup/final-write errors are positive controls.
Optional /usr/bin/time instrumentation failed before any tests started (binary absent); the exact full-suite command above subsequently ran to terminal exit0. This is not a passing timed invocation.

## Code-intel gate

`node /home/mathias/dev/agent-roster/scripts/code-intel-resolve.js gate --timeout 120`: exit0, SKIP: no code-intel block / RESULT: skip. No invariant pass claimed.
Claims authority, KB, hook runner and task-context freshness mechanism absent (legacy); research question digest was verified in review. No TUI in scope. MCP not verified without token.

## Cross-runtime QA

Provider-free availability command (env OPENCODE_CONFIG_CONTENT selects github-copilot/gpt-5.6-sol) returned exit0, skipped-degraded, digest opencode:76f897c73342fdbf. Cross-runtime QA skipped (review breaker, unchanged runtime version). No second provider invocation or inferred human retry. Journal-not-ignored warning retained.

## Cleanup and verdict

Both recalibration worktrees cleaned by the script; 89 registered worktrees remain (one owned current delivery), no native consumer fixture leftovers. Root evidence directory retained only until shipping evidence capture/cleanup.
**GO** — ready for roster-ship under the user's explicit standing authorization. Remote exact-head CI and artifact availability must be green before merge.
