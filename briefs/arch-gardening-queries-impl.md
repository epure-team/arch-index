# Implementation Brief — arch-gardening-queries

**Date:** 2026-07-08
**Mode:** full
**Status:** COMPLETED

## Modified files

| File | Change | Reason |
|---|---|---|
| `arch-query` | modification | hq_* helpers hoisted to script level (shared); 3 curation branches (low-coverage latest-record SQL, gardening open/log, unsafe-params filters); header docs |
| `lib/arch_coverage/` | addition | loader core: strict-UTC stamp validation (positional — Str lacks {n}), NDJSON parse/validate, exactly-one resolution, transactional load with rollback, written/skipped/ignored |
| `bin/arch_coverage_load/` + `arch-coverage-load` | addition | thin CLI + wrapper; exits 0/2/3 |
| `test/test_arch_coverage.ml` + `test/dune` | addition | 5 Alcotest cases (idempotent rerun, skips, rollback, validation, stamps) |
| `selftest-health.sh` | modification | curation section: executes doc-extracted SQL verbatim, ledger query scenarios, loader e2e (2-snapshot latest-record, idempotency, rollback, bad stamp, flat refusals) |
| `docs/curation-workflow.md` | addition | ledger SQL (selftest-extracted markers), NDJSON contract, heuristic→ledger flow |
| `.github/workflows/ci.yml` | modification | chmod + package arch_coverage_load |
| `README.md` | modification | curation bullet |

## Decisions made

- Doc-SQL execution via stdin pipe (sqlite3 misparses a leading `--` comment as an option when passed as argv).
- valid_stamp implemented positionally (OCaml Str has no `{n}` repetition — first attempt failed tests honestly, fixed).
- Loader reads all stdin lines then loads in one transaction (rollback-all on malformed per plan objection #4).

## Quality Gates

- [x] Build ✅ · Tests: 7 suites, 96 tests, 0 failed (5 new in test_arch_coverage) ✅
- [x] selftests contract/load/mcp/health (health now incl. ~20 curation assertions) ✅
- [x] Metrics self-gate: OK, 5 unchanged ✅
- [ ] selftest-effects.sh: pre-existing failure, excluded.

## Points of attention for review

- latest-record correlated subquery in `low-coverage` (selftest proves 2-snapshot exclusion).
- `unsafe-params` uses printf-composed SQL template — verify no user input lands in it (filter arg is matched against a fixed vocabulary first).
- Helper hoist: health branches re-verified by selftest-health.
- Loader transaction boundaries (BEGIN before iteration, COMMIT/ROLLBACK once).

## Out-of-scope

- Tool-specific coverage adapters; MCP curation tools; `gardening add` CLI writes (deliberate).
