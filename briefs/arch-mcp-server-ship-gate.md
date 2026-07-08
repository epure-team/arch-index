# Ship Gate — arch-mcp-server

**Date:** 2026-07-08
**Branch:** feat/arch-mcp-server → base feat/arch-metrics-gate (STACKED on PR #3; retarget to main after #3 merges)

## Commits

- d8e1f6a feat(mcp): arch-mcp stdio server engine + binary
- ffbf9fc test(mcp): end-to-end stdio session selftest
- 2131d2c docs+ci(mcp): README + selftest-mcp in CI + release packaging
- c9e19b7 chore(roster): pipeline artifacts

## Gate status

- review.json: GO (1 HIGH FK-closure soundness bug + 2 MEDIUM from codex cross-runtime, +1 primary — all RESOLVED with regression tests)
- qa.md: GO (87 tests, CHECK-1..7, cross-runtime gates identical; stale test-count doc dispute corrected)
- Out-of-scope dirty files remain uncommitted (same set as item 1).
- Quiz waived — autonomous mode pre-authorized.

## Action

Push branch + open stacked PR; merge left to human (merge #3 first, then retarget/merge this).
