# QA Scope — origin-recurring-consumer

**Date:** 2026-09-12
**Status: VALIDATED**

## Exact Quality Gates

- Build: `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune build --root . @install`
- Full suite: `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune test --root . --force` (baseline and green verification, terminal exit required).
- Whitespace: `rtk proxy git diff --check` (no separate formatter configured).
- `rtk proxy node checks/origin-recurring-consumer.js authentic`
- `rtk proxy node checks/origin-recurring-consumer.js failures`
- `rtk proxy node checks/origin-recurring-consumer.js package`
- Fresh production `rtk proxy node scripts/origin-consumer.js --out <new-owned-leaf>` then
  `rtk proxy node scripts/origin-consumer-artifacts.js <same-leaf>`; create parent with mktemp -d,
  no literal-placeholder execution. Record real measured corpus/status/package evidence.
- Existing self golden/recalibration/reach rules/impact smoke: current CI commands unchanged.
  Root QA executes them and exact-head remote CI checks all before ship.

## Behaviors

Validate all20 ACs in specs/origin-recurring-consumer.md. Actual native success/new/count,
exact production UNKNOWN0 (not proof), declared reference groups and modules, drift1 versus
error2 versus policy-failed1, unchanged reachability rules. Valid closed report package and
retention validator on every supported terminal status, no overwritten existing output, no
partial reports advertised complete, no leaked DB/build uploads. New Tezt3 modes + checker
assertion/execution controls; full suite required, test collection alone is not execution.
Run QA's deterministic state/convergence gate before final verdict; external review availability
is provider-free, not a second runtime review. No TUI in scope, no MCP claim without token.

## Risks

| Risk | Mitigation |
|---|---|
| Compiler fixture identities | Pin native line/function/count details; investigate differences, no auto-regeneration. |
| Reporter field compatibility | Use current existing reporter contract; shared-field validation, not guessed extra schema or changed evaluator. |
| Output/cleanup or mutation | Exclusive leaf ownership, same-run hashes, final marker last, errors visible; no atomic-filesystem claim. |
| CI loses evidence/masks failure | Independent status-aware validator then upload after actual consumer start, known files only, no continue-on-error. |
| Tests look green after execution failure | Checker0 means expected results verified,1 assertion,>=2 execution; deliberate controls. |
| Fixed counters drift on legitimate change | Manual reviewed reference edits; separate allow-list; no completeness claim. |
