# QA Brief — arch-health-queries

**Date:** 2026-07-08
**Status:** GO ✅

## Quality Gates

| Gate | Command | Result | Duration |
|---|---|---|---|
| Build | `opam exec -- dune build` | ✅ PASS (exit 0) | <1s |
| Tests | `opam exec -- dune test --force` | ✅ 6 suites, 91 tests, 0 failed | <1s |
| Format | — | not documented | — |
| Shell selftests | contract + load + mcp + **health (new)** | ✅ 0/0/0/0 | ~4s |

`selftest-effects.sh`: pre-existing failure, excluded (items 1–2 briefs).

## Spec Runnable Checks

| Check | Result |
|---|---|
| CHECK-1 self-index rows + flat exit 3 | ✅ PASS |
| CHECK-2 non-numeric threshold → exit 2 | ✅ PASS |
| CHECK-3 duplicates/type-search fixture + flat refusal | ✅ PASS (selftest-health) |
| CHECK-4 body-compare IDENTICAL + unknown → 1 | ✅ PASS (selftest-health) |
| CHECK-5 full suite + metrics self-gate (5 unchanged, OK) | ✅ PASS |
| CHECK-6 determinism | ✅ PASS |

## Tests: detail

- New: 4 (test_arch_index_compare) + selftest-health e2e matrix (~30 assertions).
- Existing: 87 pass, 0 fail. Regression: NO.

## Cross-runtime QA (codex, workspace-write)

GATE-1..4 all PASS matching primary; spot-check "test_arch_index_compare adds 4 tests" confirmed. DISPUTED: none. VERDICT: GO. Tree integrity OK.

## Verdict

**GO** — ready for `/roster-ship`
