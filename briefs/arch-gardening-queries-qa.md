# QA Brief — arch-gardening-queries

**Date:** 2026-07-08
**Status:** GO ✅

## Quality Gates

| Gate | Command | Result | Duration |
|---|---|---|---|
| Build | `opam exec -- dune build` | ✅ PASS | <1s |
| Tests | `opam exec -- dune test --force` | ✅ 7 suites, 98 tests, 0 failed | <1s |
| Format | — | not documented | — |
| Selftests | contract/load/mcp/health | ✅ 0/0/0/0 | ~5s |

Metrics self-gate: OK (5 unchanged). selftest-effects.sh: pre-existing failure, excluded.

## Spec Runnable Checks

CHECK-1 (query scenarios incl. latest-record exclusion, gardening open incl. in_progress, unsafe-params filters, flat exit 3): ✅ (selftest-health assertions). CHECK-2 (loader idempotency + rollback count-unchanged): ✅. CHECK-3 (skips exit 0): ✅ (unit + selftest). CHECK-4 (documented SQL executed via extraction — zero-statement guard): ✅. CHECK-5 (full suite green): ✅. Extra: bad --stamp → 2; flat loader → 3; determinism ✅.

## Tests: detail

New: 5+2 Alcotest (arch_coverage incl. stamp-range regressions) + ~20 selftest curation assertions. Existing: 91 pass, 0 fail. Regression: NO.

## Cross-runtime QA (codex, workspace-write)

GATE-1..3 PASS matching primary; spot-check "low-coverage latest-record exclusion" confirmed. DISPUTED: none. VERDICT: GO. Tree integrity OK.

## Verdict

**GO** — ready for `/roster-ship`
