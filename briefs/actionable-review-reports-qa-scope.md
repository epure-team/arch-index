# QA scope — actionable-review-reports

**Date:** 2026-09-12
**Status: VALIDATED**

## Quality gates

Run sequentially in /home/mathias/dev/arch-index-worktrees/actionable-review-reports:
```bash
rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune build --root . @install
rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune test --root . --force
rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune exec --root . tezt/tests/main.exe -- --file report.ml
rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- node checks/actionable-review-reports.js rules
rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- node checks/actionable-review-reports.js ordering
rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- node checks/actionable-review-reports.js operands
rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- node checks/actionable-review-reports.js compatibility
rtk proxy git diff --check
```

Also execute documented CI self-index golden, recalibration and architecture-rule gates using
current sources/ADR001, not invented counts. Verify produced artifact contents, not only exits.
No separately documented formatter/linter; existing opam metadata lint error is not a passing
gate. MCP remains untested absent required dependency/token.

## Behavior scope

Actual CLI witnesses and cross-format parity; unavailable no-rules vs evaluated census;
UNKNOWN vs no contract vs per-rule NOT_COMPUTED; report-success vs gate-failure exits; ordinal
and tier determinism, duplicate display names and PASS handling; native/imported provenance;
typed primitive original slot2, literal kinds and syntax-only policy; old/malformed metadata;
allow-count multiplicity and independent200site/200context limits; 256UTF8-byte representations;
unchanged CMT results after source removal; safe HTML, truthful logical SARIF locations and
pre-write rejection/write failures. All4checker modes are registered in ordinary Tezt and
honor actual assertion1 versus execution-error>=2 controls. SARIF validates via existing schema.

## Process and resource constraints

Read QA skill and implementation/review artifacts; GO only from completed commands with real
exit codes. Baseline231 is not final acceptance. Independent cross-runtime execution if helper
permits it; respect persisted degraded breaker. DRAFT convergence before state/report, truthful
round/cycle audit. Sole shared worktree; no simultaneous Dune and no unnecessary worktrees.
Retain small proof logs separately; clean exact owned temporary DBs/build fixtures. Root handles
PR, green CI, merge, roadmap and removal of delivery worktree/build after completion.
