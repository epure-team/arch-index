# Implementation Brief — wire-checks-into-ci

**Date:** 2026-09-01
**Mode:** fast
**Status:** COMPLETED

## Modified files

| File | Type of change | Reason |
|---|---|---|
| `checks/README.md` | addition (ported from `rebase/sound-qual`), then corrected | documents the three ratchets, now updated to note they run in CI and fixes the dangling brief references |
| `checks/nested-module-resolution.js` | addition (ported from `rebase/sound-qual`), then fixed | ratchet for review CRITICALs `arch_index.ml:344`/`:359`; round 2 guarded `sql()` against unguarded throws and fixed `fnId()`'s multi-row ambiguity |
| `checks/no-must-null-regression.js` | addition (ported), then baseline recalibrated twice | whole-repo ceiling on `MUST` calls with a NULL callee; round 2 fixed a dirty-tree measurement, added headroom, guarded `count()`, added cleanup and a tightening-direction warning |
| `checks/baseline-has-headroom.js` | new (round 2) | ratchet for the round-1 HIGH finding that the baseline had zero headroom |
| `.github/workflows/ci.yml` | modification, then reordered | new `Soundness ratchets (checks/)` step, moved to run right after `Build`; added an explicit `sqlite3` install and a fail-fast `opam env` capture |

## Decisions made

- **Both `checks/*.js` scripts wired as hard gates, not one informational.** The task description
  (sourced from the roadmap's Phase 0/4 notes) assumed `nested-module-resolution.js` would fail on
  `main` until item 4.1 (sound-qual round 3) lands, and asked for `continue-on-error`. Running it
  against `main` at `161f3d7` shows it passes cleanly, twice, after a forced rebuild — most likely
  because `278f182` ("a dropped in-project callee is ⊤, not a MUST external leaf", already merged)
  independently fixes the same class of bug this check guards. Wired as a normal hard gate.
  **The roadmap's Phase 4 entry for `rebase/sound-qual` may be stale** — noted in
  `~/notes/2026-09-01-arch-index-roadmap.md` item 0.2's implementer notes, not independently
  re-verified against that branch's own review artifacts.
- **Round 1 review (`briefs/wire-checks-into-ci-review.json`) found the recalibrated baseline
  (2024) was itself measured on a dirty working tree** — this repo's pre-existing, out-of-scope
  uncommitted files were present in `_build/default` at measurement time, inflating the count by
  9. Round 2 re-measured from a clean `git worktree add --detach`: `2015`. Fixed the baseline to
  `CLEAN_MEASURED = 2015` plus a documented `HEADROOM = 25`, and ratcheted the headroom
  requirement itself (`checks/baseline-has-headroom.js`, red-then-green proven against `d735da8`).
- **Round 1 review found both scripts' `sqlite3` calls violated the documented three-way
  exit-code contract** — an unguarded `execFileSync`/`run()` throw exited 1 ("bug present")
  instead of `>=2` ("setup failure"). Fixed by wrapping both in try/catch calling `setupFail()`.
  Verified live: with `sqlite3` removed from `PATH` (node/dune/opam still present), the check now
  exits 2, not 1.
- **Round 1 review found `fnId()` in `nested-module-resolution.js` silently picked an arbitrary
  row on a multi-row match**, unlike `goCall()` a few lines later which explicitly guards row
  count == 1 with matching reasoning. Applied the same guard to `fnId()`; this made the private
  `scalar()` helper dead code (its only caller), removed.
- **Round 1 review found the two brief artifacts cited in the ported files
  (`briefs/sound-qualified-name-resolution-{impl.md,review.json}`) do not exist on `main`** — a
  verbatim-port leftover. Rewrote both references to cite what actually exists
  (`-intake.md`/`-plan.md`) and preserved the finding text inline instead of only by reference.
- **Round 1 review found the CI step ran after `dune test`** (a different `_build/default` state
  than `Build` alone produces, and maskable by an unrelated test flake). Moved it to run directly
  after `Build`.
- **Round 1 review found no workflow step installs `sqlite3`**, which both checks (and the
  pre-existing `Self-index smoke test` step) depend on. Added an explicit, idempotent
  `apt-get install`.
- **Round 1 review found `eval "$(opam env)"` doesn't fail fast under `bash -e`** if `opam env`
  itself fails (`eval ""` still exits 0). Captured into a variable before `eval`.
- **Round 1 review found both scripts leak their `mkdtemp` fixture directories.** Added
  `fs.rmSync(..., {recursive:true, force:true})` on the success path in both, keeping the
  directory on a fired assertion so it stays inspectable — matches the existing
  keep-on-`setupFail` convention.
- **Architect's finding that `checks/` is a standalone Node runtime invisible to `dune
  build`/`dune test`, disconnected from the rest of the quality gates: ACCEPTED, not fixed.**
  Presented to the human as a grouped review ambiguity; the human chose "file as a separate
  roadmap item, defer" over the two live alternatives (a `checks/dune` alias — untested, risky
  given each check itself shells out to `dune build --root <tmp>` at runtime — or a migration into
  proper `tezt/` tests, a larger rewrite since the three-way exit contract has no `dune test`
  equivalent). Filed in the roadmap's item 0.2 implementer notes rather than implemented here.
- Ran `dune fmt --auto-promote` in round 1 as part of the format gate; it reformatted 17 unrelated
  `dune` files (pre-existing formatter version drift, whitespace-only). Reverted all of them —
  out of scope for this task.

## Quality Gates

- [x] Build: `dune build` ✅ (clean, 0 warnings/errors, both rounds)
- [x] Tests: `dune test` ✅ (78/78 tezt cases SUCCESS, exit 0, both rounds)
- [x] Format: `dune fmt` — clean on the touched files (round 2 touched no `.ml`); unrelated
      pre-existing drift reverted, not fixed (out of scope)
- [x] `node checks/nested-module-resolution.js` ✅ exit 0, verified in a clean worktree at the
      final commit (`a650003`)
- [x] `node checks/no-must-null-regression.js` ✅ exit 0 in a clean worktree:
      `calls=9289 MUST-with-NULL-callee=2015 baseline=2040`
- [x] `node checks/baseline-has-headroom.js` ✅ exit 0: `CLEAN_MEASURED=2015 HEADROOM=25`;
      confirmed red against `d735da8` (no `CLEAN_MEASURED`/`HEADROOM` split existed)
- [x] Exit-code contract verified live: `sqlite3` removed from `PATH` → both scripts exit 2, not 1

## Points of attention for review

- The clean-worktree re-measurement (2015) is the number that matters — the round-1 measurement
  (2024) is now known-wrong and superseded; don't compare against it.
- `checks/baseline-has-headroom.js` checks the *shape* of the baseline definition (text match on
  the source), not a live SQL measurement — it can't tell you the headroom is the *right* size,
  only that one exists. That's a deliberate scope limit, not an oversight.
- The architect's ACCEPT (checks/ vs dune) is recorded in `briefs/wire-checks-into-ci-review.json`
  as a same-round accept; the roadmap carries the follow-up.

## Identified out-of-scope

- 17 `dune` files have stale auto-formatting relative to the current `dune fmt` — not touched.
- Integrating `checks/` into `dune build`/`dune test` (architect's HIGH, human-deferred) — filed
  in the roadmap, not this task.
- The roadmap's Phase 4 `rebase/sound-qual` status line may be stale in light of
  `nested-module-resolution.js` passing on `main` — noted in the roadmap, not independently
  re-verified against that branch's own review.

## Ratchet

- **Finding:** `checks/no-must-null-regression.js:41:architecture` — baseline set to exactly the
  measured value, zero headroom.
  **Check:** `checks/baseline-has-headroom.js`
  **Red command:** `node checks/baseline-has-headroom.js` (exits 1 on `d735da8`, no
  `CLEAN_MEASURED`/`HEADROOM` split existed; exits 0 after the fix)
  **check_encodable:** true
- **Finding:** `checks/no-must-null-regression.js:41:correctness` — baseline measured on a dirty
  working tree.
  **Check:** none — this is a one-time measurement-methodology correction (the number itself,
  2015 vs 2024), not an ongoing code invariant a red/green check can express. The corrected
  number and the reproducible clean-measurement procedure are documented in the file's own
  comment block and in `checks/README.md`.
  **check_encodable:** false — no deterministic runtime invariant to assert; the fix is the
  corrected constant itself, verified once against a clean worktree (see Quality Gates above).
