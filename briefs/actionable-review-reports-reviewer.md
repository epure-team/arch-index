# Reviewer — actionable-review-reports

**Date:** 2026-09-12
**Status: VALIDATED**

## Goal and expected change

Review complete optional rule-aware JSON/SARIF/HTML reports and bounded typed divisor context.
Use the implementation brief for what actually changed; do not assume planned work exists.
Mandatory independent owner/architect review for public OCaml modules and multi-file scope,
cross-runtime availability/breaker discipline, normalizer, full then static convergence and trace.
Scope is only this feature plus carried roadmap-step bookkeeping. Do not mutate vendor gates.

## Audit first

Parser/evaluator extraction in arch_rule_eval and arch_rules; report model/CLI/renderers;
origin typed-AST capture, schema/writer, metadata decoder; self-contained checker and Tezt wiring.

## Behaviors and risks to verify

Preserve every arch-rules verdict/allow identity/count/exit policy. Report success is not gate
success. No --rules retains eight unavailable placeholders; invalid/empty input rejects before
writes. Supplied evaluation census is distinct from individual NOT_COMPUTED/coverage. Ordinals
are one-based and disambiguate names; only alert projection sorts tiers. PASS is not an alert.
Rule producer is arch-rules, not a foreign importer. Witness labels/order survive; no fake
locations. Typed metadata uses original argument slot2, no value inference/source reread or
origin suppression. Old/NULL metadata is unavailable; malformed present metadata refuses.
200 sites and 200 contexts are independent; exact totals and multiplicity/exempt counts persist.
256-byte text limit omits whole representations with reason. HTML escapes all fields. Nonzero
write failure never prints success. No snapshot/viewer-order promises or unsupported MCP claims.

## Gates and evidence

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

Require the spec's eighteen FRs/fifteen ACs and all4checker modes plus authentic failure
controls; derive any new findings from actual source/commands. Root baseline231 only applies
before implementation; reverify final tree. Check self-index movement is measured, no gate
weakened. Same worktree, no concurrent Dune, no extra builds/worktrees for read-only specialists.
Record degraded cross-runtime honestly. Leave review artifacts conforming to installed bundle.

