# QA Brief — wire-checks-into-ci

**Date:** 2026-09-01
**Status:** GO ✅
**Round:** 1 (qualifying 0/5)

## Round state

Fresh cycle, round 1.

## Quality Gates

All gates run in a fresh clean worktree (`git worktree add --detach` at commit `08c4306`), not the
ambient session working tree — deliberately, given round 1 of this same task shipped a wrong
number by measuring against a dirty tree.

| Gate | Command | Result | Duration |
|---|---|---|---|
| Build | `dune build` | ✅ PASS | 2.4s |
| Tests | `dune test --force` (forced, no cache) | ✅ 77/77 passed | 1m23s |
| Format | `dune fmt` | ✅ PASS on task-touched files | — |

## Tests: detail

- New tests added: 0 OCaml tests (this task adds `checks/*.js` ratchets, not `tezt/` cases)
- Existing tests: 77 pass, 0 skip, 0 fail
- Regression detected: NO
- The `Statement error (CONSTRAINT) ...` lines in the raw log are pre-existing, expected stderr
  from the rejection-attribution tests (`tezt/tests/rejection_attribution.ml` and related) —
  deliberate negative-path exercises, not failures; the suite's own exit code and per-test
  `[SUCCESS]` lines are what govern the verdict.

**Format gate note:** `dune fmt` reformatted 17 pre-existing `dune` files (whitespace-only,
`ocamlformat`/dune-fmt version drift). Verified this drift is **not introduced by this branch** —
a clean worktree of `main` at `161f3d7` shows the identical drift before this task's commits are
applied. None of the reformatted files are files this task modifies (`checks/*.js`,
`.github/workflows/ci.yml` are outside `dune fmt`'s scope). Graded PASS on that basis; the
pre-existing drift itself is already logged as out-of-scope in `briefs/wire-checks-into-ci-impl.md`.

## Task-specific behavioral checks

Beyond the generic gates, this task's actual deliverable is three ratchet scripts and a
CI wiring change, verified directly:

| Check | Result |
|---|---|
| `node checks/nested-module-resolution.js` | ✅ exit 0 — both scenarios hold |
| `node checks/no-must-null-regression.js` | ✅ exit 0 — `calls=9289 MUST-with-NULL-callee=2015 baseline=2040` |
| `node checks/baseline-has-headroom.js` | ✅ exit 0 — `CLEAN_MEASURED=2015 HEADROOM=25` |

`MUST-with-NULL-callee=2015` in a fresh clean worktree matches `CLEAN_MEASURED` in the source
exactly — independent confirmation of round 2's clean re-measurement, not a re-read of the same
number the implementer already reported.

**Exit-code contract** (0 pass / 1 assertion fired / ≥2 setup failure) — independently verified,
not inferred from code inspection:
- `no-must-null-regression.js` with `sqlite3` removed from `PATH` (node/dune/opam/ocaml toolchain
  otherwise intact): **exits 2**, `SETUP FAILURE: sqlite3 failed for ...`. Confirms the round-2 fix
  (wrapping the sqlite3 call in try/catch → `setupFail()`) holds under a live re-run, not just a
  reading of the diff.
- `nested-module-resolution.js` under the same reduced `PATH`: also exits 2, but at its `dune
  build` fixture step (missing system assembler `as`) rather than at the `sqlite3` call
  specifically — constructing a `PATH` that keeps a full working OCaml native-code toolchain
  while excluding only `sqlite3` proved impractical without also pulling in the switch's `as`/`ld`
  toolchain-adjacent binaries. Not treated as a gap: `nested-module-resolution.js`'s `sql()` helper
  applies the identical guarded pattern the direct `no-must-null-regression.js` repro already
  proved, and this was reviewed line-by-line in round 2's review pass. Recorded as a QA
  methodology note, not a finding.

## Code-intel gate

Skipped (no `kb/properties.md` present — KB absent for this repo).

## Spec runnable checks

N/A — no `specs/wire-checks-into-ci.md` exists (non-spec'd Fast-mode task, by design).

## TUI

N/A — no TUI surface in this change.

## Cross-runtime QA

`codex` on `PATH`, checked via the shared breaker
(`node scripts/xruntime-review.js codex --task wire-checks-into-ci --phase qa --check-availability --write`):
`status: "skipped-degraded"` — codex degraded during round-1 review of this same task
(`non-conforming-output`) with an unchanged runtime version, so the breaker correctly declines a
repeat probe this cycle rather than re-spending a call already known to degrade. No verdict
impact per the breaker contract.

## Verdict

**GO** — ready for `/roster-ship`
