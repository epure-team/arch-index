# QA Brief — fix-issues-33-34-35

**Date:** 2026-09-02
**Status:** GO ✅
**Round:** 1 (qualifying 0/5)

## Round state

Fresh cycle, round 1.

## Quality Gates

All gates run in a fresh clean worktree (`git worktree add --detach` at commit `090a3ac`), not
the ambient session working tree.

| Gate | Command | Result | Duration |
|---|---|---|---|
| Build | `dune build` | ✅ PASS | 2.7s |
| Tests | `dune test --force` (forced, no cache) | ✅ 83/83 passed | 1m24s |
| Format | `dune fmt` | ✅ PASS on task-touched files | — |

## Tests: detail

- New/changed tests: 3 (`arch-query: a bad limit argument is refused, not defaulted`,
  `curation: an optional module field disambiguates a same-named function (#35)`,
  `curation: gardening open must not drop in_progress tasks (#34)`, `curation: a bare and a
  module-qualified record for one name are rejected together` — 4 total, including the new
  round-1-review ratchet)
- Existing tests: 79 pass, 0 skip, 0 fail
- Regression detected: NO — `health.ml`'s pre-existing "measures are never gates" test (the one
  the round-1 review HIGH finding was about preserving) passed clean, confirming the
  `limit_of`/`measure_limit_of` split didn't regress it
- The `Statement error (CONSTRAINT) ...` lines in the raw log are pre-existing, expected stderr
  from the rejection-attribution tests, not failures

**Format gate note:** `dune fmt` reformatted 12 pre-existing `dune` files (whitespace-only,
same drift documented in prior tasks this session). None of the reformatted files are files this
task modifies; graded PASS on that basis.

## Task-specific behavioral checks

Beyond the generic gates, independently re-verified each of the three issues' fixes and the
round-1-review corrections, live, in the clean worktree — not re-read from the impl brief:

| Check | Result |
|---|---|
| `large-files --fail-on-size` (measure command) | ✅ exit 0, flag ignored — preserves the measures-are-never-gates doctrine |
| `fan-in --fail-on-size` (non-measure command) | ✅ exit 2, refused — the round-1 HIGH fix, confirmed live |
| `large-files abc` | ✅ exit 2, refused |
| `gardening open` with `open`/`in_progress`/NULL/`done` rows seeded | ✅ `open` and `in_progress` and NULL-status rows all appear; `done` correctly absent — confirms the round-1 MEDIUM NULL-status fix, not just the original `<>'done'` change |
| `arch-coverage-load` with a bare `dup` record followed by a module-scoped `dup` record | ✅ exit 2, `"dup" appears both bare and with a "module"` — confirms the round-1 MEDIUM dedup-collision fix; zero rows written |

## Code-intel gate

Skipped (no `kb/properties.md` present — KB absent for this repo).

## Spec runnable checks

N/A — no `specs/fix-issues-33-34-35.md` exists (non-spec'd Fast-mode task, by design).

## TUI

N/A — no TUI surface in this change.

## Cross-runtime QA

`codex` on `PATH`, checked via the shared breaker: `status: "skipped-degraded"` — codex degraded
during round-1 review of this same task (`non-conforming-output`) with an unchanged runtime
version, so the breaker correctly declines a repeat probe this cycle. No verdict impact per the
breaker contract.

## Verdict

**GO** — ready for `/roster-ship`
