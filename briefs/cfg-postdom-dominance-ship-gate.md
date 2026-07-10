# Ship Gate — cfg-postdom-dominance

**Date:** 2026-07-10
**Branch:** feat/cfg-postdom-dominance → main (already based on origin/main tip)
**Gates:** review.json GO (full mode) · qa.md GO · 17 conventional per-step commits

## Commits

```
14da61d..HEAD (17):
docs artifacts → test(step 0) → feat(step 1 CFG engine) → feat(step 2 walker)
→ fix(partiality) → feat(step 3 noreturn) → fix(3b arg-order) → feat(step 4
enumerated demotion) → fix(4b cgo) → feat(step 5 lambda nodes) → feat(step 6
local-invocation MUST) → fix(7a occurrence edges) → docs(step 7)
→ fix(review round: letop/perf/beta-redex/hygiene) → fix(round 2:
find/exported + spec erratum) → docs(review GO) → docs(QA GO)
```

## Net effect

- MUST = computed post-dominance over per-node CFGs (OCaml); enumerated
  demotion in both backends; lambda literals are graph nodes.
- Self-index: MAY_TOP 79% → **3.9%**; 57 P1 STRICT; zero dropped edges
  (exhaustive diff vs main); goldens deterministic.
- Known accepted residuals + follow-ups recorded in review.json (incl. codex
  re-verification of steps 5–6 when the spend cap resets).

## Out-of-scope working-tree files (untouched, pre-existing)

`briefs/arch-serve-state.json` (M), `briefs/attack-surface-capability-phase2-review.json`,
`docs/plans/`, `docs/rust-sound-callgraph-design.md` — not part of this ship.

## Plan

Push `feat/cfg-postdom-dominance`, open PR to main, wait for CI green, rebase-merge on your approval.
