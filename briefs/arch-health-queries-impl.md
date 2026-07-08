# Implementation Brief — arch-health-queries

**Date:** 2026-07-08
**Mode:** full
**Status:** COMPLETED

## Modified files

| File | Type of change | Reason |
|---|---|---|
| `arch-query` | modification | 8 new case branches (shared sub-case with hq_* helpers: column-level xinfo detection, threshold regex validation, LIKE escape helper) + header docs |
| `bin/arch_body_compare/` + `arch-body-compare` | addition | CLI over existing `Arch_index_compare.compare_bodies`; DIFFERS groups sorted by digest; empty-body disambiguation (missing file / no range / genuinely empty); exits 0/1/2/3 |
| `test/test_arch_index_compare.ml` + `test/dune` | addition | first coverage for the module: differs, identical-modulo-indentation, not-found, missing-file cases (4 tests) |
| `selftest-health.sh` | addition | e2e over a REAL main-schema fixture (canonical DDL) + flat refusal matrix + wildcard/threshold/determinism probes |
| `.github/workflows/ci.yml` | modification | run selftest-health; package arch_body_compare in releases |
| `README.md` | modification | code-health bullet |

## Decisions made

- All 8 commands share one case branch with helper functions (hq_has/hq_tbl/hq_refuse/hq_num/hq_like) — column-level detection per plan risk #1.
- `Arch_index_compare` library untouched (bound-param lookup verified present at `arch_index_compare.ml:84`); empty-body disambiguation lives in the CLI (plan decision).
- selftest expected-failure probes use `rc=0; cmd || rc=$?` (set -e-safe) — first draft used `cmd; [ $? -eq N ]` which set -e killed.
- arch-load flat fixture needs ≥1 call edge (loader refuses trust-stamped empty graphs) — MAY_TOP edge added.

## Quality Gates

- [x] Build ✅  Tests: `dune test --force` ✅ (6 suites; 4 new in test_arch_index_compare)
- [x] selftest-contract/load/mcp ✅ + new selftest-health ✅
- [x] Metrics self-gate unchanged (OK: 5 unchanged) — no tracked-metric drift (AC-5)
- [x] Spec checks: CHECK-1 (self-index rows + flat exit 3), CHECK-2 (exit 2), CHECK-3/4/6 (selftest-health assertions)
- [ ] selftest-effects.sh — pre-existing failure, excluded (items 1–2 briefs)

## Points of attention for review

- Threshold interpolation into SQL is regex-guarded (`^[0-9]+$`) — verify no bypass path.
- hq_like escape order (backslash first) and ESCAPE '\\' quoting inside the double-quoted SQL string.
- god-modules flat fallback groups by file_path (selftest covers).
- `unsafe-strings` uses `>=` (spec) while other thresholds use `>` (octez parity) — intentional.

## Identified out-of-scope

- MCP exposure of health queries (follow-up on item 2 registry).
- Global body-hash duplicate scan (per-name only, per spec).
- `duplicate_groups` as a tracked gate metric (would change gate semantics).
