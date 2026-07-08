# Ship Gate — arch-metrics-gate

**Date:** 2026-07-08
**Branch:** feat/arch-metrics-gate → main (rebase-merge)

## Commits

- 6ff4d14 feat(compare): arch-compare metrics regression engine
- 8c5ca0e feat(query): metrics subcommand emitting flat JSON
- 0a35015 ci: self-applied metrics regression gate
- 792b4fb docs: ADR 002 metrics gate + README use case
- b4546fd chore(roster): arch-metrics-gate pipeline artifacts

## Gate status

- review.json: GO (1 HIGH + 2 MEDIUM + 1 LOW cross-runtime findings, all RESOLVED)
- qa.md: GO (61 tests, CHECK-1..7 + AC-7 pass, cross-runtime gates identical)
- Out-of-scope dirty files left uncommitted on main: briefs/arch-serve-state.json,
  briefs/attack-surface-capability-phase2-review.json, docs/plans/,
  docs/rust-sound-callgraph-design.md
- Quiz: waived — autonomous mode pre-authorized by user ("run autonomously but
  follow the full roster pipeline").

## Action

Push branch + open PR against main; merge left to human (rebase-merge, CI green required).
