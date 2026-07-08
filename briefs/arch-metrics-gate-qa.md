# QA Brief — arch-metrics-gate

**Date:** 2026-07-08
**Status:** GO ✅

## Quality Gates

| Gate | Command | Result | Duration |
|---|---|---|---|
| Build | `opam exec -- dune build` | ✅ PASS (exit 0) | <1s |
| Tests | `opam exec -- dune test --force` | ✅ 61 passed, 0 failed (26+8+17+10 across 4 suites) | <1s |
| Format | — | not documented (no fmt/lint gate in this repo) | — |
| Shell selftests | `./selftest-contract.sh && ./selftest-load.sh` | ✅ PASS (exit 0, 0) | 1s |

Note: `./selftest-effects.sh` fails identically on a clean tree (pre-existing, verified via `git stash` during implement; not in CI) — ACCEPTED in review.json, excluded from this verdict.

## Spec Runnable Checks (specs/arch-metrics-gate.md)

| Check | Result |
|---|---|
| CHECK-1 metrics emits flat numeric JSON on self-index | ✅ PASS |
| CHECK-2 unwaived regression → exit 1 | ✅ PASS |
| CHECK-3 covered waiver → exit 0 + reason rendered | ✅ PASS |
| CHECK-4 reasonless waiver → exit 1, invalid reported | ✅ PASS |
| CHECK-5 Alcotest suite | ✅ PASS (26 arch_compare cases) |
| CHECK-6 missing tracked metric → exit 1 | ✅ PASS |
| CHECK-7 flat DB: exported_functions present, doc_coverage_pct absent | ✅ PASS |
| AC-7 dogfood: clean → 0; large_functions+1 → 1 | ✅ PASS |
| Determinism: two runs byte-identical | ✅ PASS |

## Tests: detail

- New tests added: 26 (test_arch_compare)
- Existing tests: 35 pass (parsers 10, effects 8, capabilities 17), 0 skip, 0 fail
- Regression detected: NO

## Cross-runtime QA (codex exec, workspace-write sandbox)

- GATE-1..6 (build, dune test, selftest-contract, selftest-load, CHECK-2, CHECK-3): **all PASS**, exit codes matching the primary run.
- Tree integrity: `git status --porcelain` identical before/after.
- DISPUTED: impl brief claimed "35 tests total, 25 new"; codex measured 61 total / 26 in arch_compare. **Resolution:** brief was stale (written before the review-phase test was added; total miscounted). Impl brief corrected in place. No gate divergence — codex's NO-GO was solely this doc claim; all deterministic gates pass identically under both runtimes.

## TUI

N/A — no TUI in scope.

## Verdict

**GO** — ready for `/roster-ship`
