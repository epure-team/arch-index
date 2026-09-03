# Ship Gate — coverage-matrix

**Date:** 2026-09-03
**Mode:** fast

## Commits prepared

```
9733c10 feat(analysis): coverage-matrix — analysis_coverage table + arch-coverage-matrix (roadmap 1.3)
```

Branch: `feat/coverage-matrix`
Target: `main`
Base: rebased onto `origin/main@e93f654`.

## Pipeline summary

- **Review:** GO (`briefs/coverage-matrix-review.json`) — reviewer + architect, cross-runtime
  codex skipped (degraded all session). 2 CRITICAL, 3 HIGH, 3 MEDIUM, 1 LOW found and fixed. The
  headline finding: `repo_root` was computed as a single `dirname` hop, landing inside
  `_build/default/` rather than the true repo root, silently defeating ALL Go/Rust callgraph
  detection in every real invocation — both specialists caught it independently. Fixing it took
  two passes (dune mirrors `architecture-schema.sql` into `_build/default/` too, so the first fix
  hit the same trap one level shallower) and new stub-based positive tests, since the existing
  test suite could not previously distinguish "driver absent" from "detection logic broken."
- **QA:** GO (`briefs/coverage-matrix-qa.md`) — build clean, 105/105 tests. No spec exists (Fast
  mode); substituted independent fresh-fixture reverification of the previously-broken
  repo_root/Rust-two-gate/exit-code logic, confirming every review-round fix holds outside the
  review round's own test files.

## What this feature does

Adds `analysis_coverage`, a new table recording — for a target project — which (language,
analysis) pairs were actually invocable, so a language/analysis with no working producer is
recorded as `not_analysed` with a concrete fix instruction, never left as silent zero rows (the
honest-absence guarantee, closing the same failure class as issue #23). A new binary,
`arch-coverage-matrix`, computes this by detecting each of six analysis kinds
(`callgraph`/`effects`/`cfg`/`decisions`/`coverage`/`types`) on the genuinely different terms
each one actually requires in this codebase — bundled OCaml executables, LSP server lookup, or
each Go/Rust producer's own repo-root wrapper script's internal gating.

## Authorization

Per the user's standing instruction ("travaille en autonomie, tu as le droit de merger tes PRs
SSI elles ont passé toutes les phases du pipeline roster") — review GO + QA GO both hold, full
pipeline passed. Proceeding to push, open PR, and merge autonomously once CI is green.
