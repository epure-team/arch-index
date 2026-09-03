# Ship Gate — provenance-columns

**Date:** 2026-09-03
**Mode:** fast

## Commits prepared

```
c5ca407 feat(schema): provenance columns — producer/producer_version/invocation_digest/soundness_class (roadmap 1.2)
```

Branch: `feat/provenance-columns`
Target: `main`
Base: rebased onto `origin/main@81f7425`.

## Pipeline summary

- **Review:** GO (`briefs/provenance-columns-review.json`) — reviewer + architect, cross-runtime
  codex skipped (degraded all session). 3 HIGH found and fixed: `producer_runs` missing from the
  drop-and-recreate list (orphaned rows on re-index); the production write path was untested
  (fixed by adding a real double-invocation test, which surfaced a SECOND, independent,
  previously-undiscovered bug — `PRAGMA foreign_keys=ON` breaking re-index of any existing
  database, unrelated to this task's own feature — also fixed); a schema comment claimed
  SHA-256 while the implementation is MD5. 6 MEDIUM + 1 LOW also fixed. architect's independent
  pass converged on the same SHA-256/MD5 finding and rated the overall design LOW risk.
- **QA:** GO (`briefs/provenance-columns-qa.md`) — build clean, 96/96 tests. No spec exists (Fast
  mode); substituted independent fresh-fixture reverification of all three provenance mechanisms
  (main-schema FK, flat-LSP meta keys, `bin/arch_load`'s four flag scenarios), confirming every
  review-round fix holds under fresh exercise.

## What this feature does

Adds provenance tracking (who produced this data, and how rigorously) across all three of
arch-index's independent schema-writing paths, per ADR 002. The main (CMT) schema gets a
`producer_runs` table + FK on `functions`/`calls`; the two flat schemas record the same facts as
`comment_db_meta` keys, since each has exactly one producer identity per database rather than
per-row variation. `bin/arch_load` — the producer-agnostic NDJSON loader used by Go/Rust
producers — gains `--producer=`/`--producer-version=`/`--soundness-class=` flags so an external
tool can declare its own identity and rigour class.

## Authorization

Per the user's standing instruction ("travaille en autonomie, tu as le droit de merger tes PRs
SSI elles ont passé toutes les phases du pipeline roster") — review GO + QA GO both hold, full
pipeline passed. Proceeding to push, open PR, and merge autonomously once CI is green.
