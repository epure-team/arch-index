# Implementation Brief — report-verdict-absence

**Date:** 2026-09-12
**Mode:** fast
**Status:** COMPLETED

## Modified files

| File | Change | Reason |
|---|---|---|
| `lib/arch_tools/arch_report.ml` | modification | Explicit uncomputed verdict metadata in JSON/SARIF; unavailable HTML totals |
| `tezt/tests/report.ml` | modification | Actual CLI regressions across empty/native/imported findings |
| `specs/reporting-and-integration.md` | amendment | FR-021 availability contract and CHECK-6 |
| `briefs/report-verdict-absence-*` | addition | Preflight, implementation and durable phase state |
| `skills-meta/friction.jsonl` | append | Doctor, TDD and implementation audit |

## Decisions made

Issue #84's compatibility-preserving annotation option: keep the existing eight JSON numeric
keys but add `verdicts_status=NOT_COMPUTED` and `verdicts_reason`. Those zeros are placeholders,
not measurements. HTML shows unavailable cells. SARIF's top-level properties carry the same
three fields for report-wide totals; existing per-analysis run flags remain independent.
There is no verdict evaluation or persistence capability added here. Imported findings cannot
make verdict totals available. No public module/interface or dependency was introduced.

## Quality Gates

- Build: `opam exec --switch=/home/mathias/dev/arch-index -- dune build @install` — exit 0.
- Baseline tests: root's `dune test --force`, explicit project switch — exit 0, 227/227 Tezt.
- RED: `opam exec --switch=/home/mathias/dev/arch-index -- dune exec tezt/tests/main.exe -- --file report.ml --keep-going` — exit 1, 2/5 tests fail on missing metadata and HTML zeros before production changes.
- GREEN/full: `opam exec --switch=/home/mathias/dev/arch-index -- dune test --force` — exit 0, 227/227 Tezt and all Alcotest suites; 2 existing report tests strengthened, no newly registered tests. Includes SARIF schema validation.
- Format: `git diff --check` — exit 0. Repository has no configured formatter.
- Supplemental packaging lint: `opam lint arch-index.opam` — exit 1, existing error 23 (missing maintainer), warnings 25/35/36/68 (authors/homepage/bug-reports/license). Neither generated package metadata nor dune-project changed. This is not reported as green.
- Coverage percentage: unavailable; no test coverage instrumentation configured. Regression tests exercise the emitted CLI files, including reports with imported findings.

## Points of attention for review

Consumers must read verdicts_status before interpreting the retained numeric keys. This is an
additive machine-contract fix, not a guarantee for legacy consumers that ignore metadata.
Check the report-wide SARIF properties and preserved per-section findings/coverage. The eight
count buckets include NOT_COMPUTED, distinct from the availability status for the entire census.

## Identified out-of-scope

Existing opam lint metadata defects need separate packaging work. Full verdict persistence and
evaluation remain future roadmap work. Missing project specialist projection was resolved by
reading the source roster definition; no harness changes were made.
