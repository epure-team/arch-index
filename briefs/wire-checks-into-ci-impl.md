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

## Addendum — post-ship-gate rework (2026-09-02)

At the ship gate, the human reversed the earlier "accept, defer" decision on the architect's HIGH
finding (`checks/` is a standalone Node runtime invisible to `dune build`/`dune test`) and asked
for it to be fixed before merging, choosing the tezt-migration path over a dune-alias.

**Modified/removed files (this addendum):**

| File | Type of change | Reason |
|---|---|---|
| `tezt/tests/nested_module_qualification.ml` | new | replaces `checks/nested-module-resolution.js`, using `Arch_tezt.with_fixture`/`Arch_tezt.index`/`Batch` (only `Fixture.dune_project` is from the `Fixture` module itself) |
| `tezt/tests/must_null_ceiling.ml` | new | replaces `checks/no-must-null-regression.js` + `checks/baseline-has-headroom.js` (the headroom check became a direct assertion on the OCaml constants, not source-text regex) |
| `tezt/tests/main.ml` | modification | registers both new tests |
| `checks/` (all four files) | deletion | superseded — the exit-code contract they existed to carry has no work left once these are ordinary tezt assertions |
| `.github/workflows/ci.yml` | modification | removed the now-redundant "Soundness ratchets (checks/)" step (`dune test` covers it); kept "Install sqlite3" (the Self-index smoke test still needs it), corrected its comment |

**Baseline recalibrated a third time.** Adding these two files to the repository's own indexed
corpus (the ratchet measures the repo's own `_build/default`) raised the clean-measured
`MUST-with-NULL-callee` count from 2015 to 2060. Verified via a clean `git worktree add --detach`
running the actual `dune test` (not a separate manual measurement) to avoid the exact mismatch
this task already hit twice — measuring with a different tool/method than what ships is what
produced the 2024-vs-2015 discrepancy in round 1.

**Not changed:** the two remaining OPEN MEDIUM findings from round 2 review (duplicate reindex
with the Self-index smoke test step; this ratchet indexing the whole repo rather than sharing one
artifact) — still out of this task's scope, still filed in the roadmap.

**Quality gates (re-verified in a fresh clean worktree at commit `33775a8`):**
- Build: `dune build` ✅
- Tests: `dune test --force` ✅ 79/79 (was 77/77 before the two new tests; +2 registered, 0 failed)
- Both migrated tests independently confirmed passing with the exact expected measurement
  (`calls=9406 MUST-with-NULL-callee=2060 ceiling=2085`)

## Addendum 2 — review cycle 2 round 1 fixes (2026-09-02)

Review cycle 2 (triggered by the addendum above) found one CRITICAL and one HIGH, both fixed here:

- **CRITICAL** — `.github/workflows/ci.yml`'s edit removing the dead "Soundness ratchets
  (checks/)" step was made on disk but never actually staged into commit `33775a8`: a `git add`
  invocation that mixed already-`git rm`'d `checks/` paths with the still-live `ci.yml` path
  failed on the stale paths and, in doing so, staged *nothing* from that command — including
  `ci.yml` — and this went unnoticed because the file still showed as modified in `git status`,
  just unstaged rather than staged. The commit as pushed would have run CI steps invoking four
  deleted files on every build. Fixed by staging and committing `ci.yml` for real, then
  re-verifying the whole branch from a fresh clean worktree (not just the OCaml side, which is
  what the previous clean-worktree check happened to cover).
- **HIGH** — the un-scoped `MUST`-with-NULL-callee ceiling in `must_null_ceiling.ml` was ~87%
  calls into `Stdlib` (`Stdlib.Printf.sprintf`, `Stdlib.&&`, `Stdlib.ref`, …), which can never be
  anything but a NULL callee — Stdlib is never part of this index — so it carried no signal about
  the resolver-miss class the ratchet exists to catch, and its volume alone consumed most of
  `headroom` on ordinary code growth (this migration's own two files: +45 against a headroom of
  25). Re-scoped the query to `callee_name NOT LIKE 'Stdlib.%'`; the clean baseline drops from
  2060 to 260, spread across 44 modules (max ~9%), which is what `clean_measured`/`headroom` are
  now set against.
- **MEDIUM** — `repo_build_default ()` had no guard against `ARCH_CALLGRAPH_OCAML` pointing
  outside this tree (which would silently measure an unrelated directory) and no guard against
  indexing a directory that merely exists but isn't this repository's real build output. Added an
  existence check on a `lib/arch_index`-specific `.cmi` path, failing loudly rather than
  proceeding on a wrong corpus.
- **MEDIUM** — nothing asserted the measured corpus (`_build/default`) was actually fully built;
  an under-built tree would index fewer calls across the board and read as a comfortable pass.
  Added a floor on the total call count (`min_total_calls = 8000`), well below the clean
  measurement (9406), that fails loudly rather than silently passing on a partial build.
- **LOW** — Scenario B's dependent assertions in `nested_module_qualification.ml` ran even when a
  precondition (both `linked` and `decoy` resolved, and distinct) was unmet, producing misleading
  failure text (e.g. "attributed to the decoy (`<none>`)" when nothing was attributed to anything).
  Restructured as a `match linked, decoy with` so the dependent checks only run once both
  preconditions hold; an unmet precondition now reports only the accurate `Batch.note`.
- **LOW** — the commit message and this brief both named `Fixture.with_fixture`/`Fixture.index`,
  which don't exist; the tests actually call `Arch_tezt.with_fixture`/`Arch_tezt.index` (top-level,
  not in the `Fixture` module). Corrected above.
- **LOW** — `briefs/wire-checks-into-ci-qa.md` still recorded the deleted `checks/*.js` gates as
  the verified evidence. Addendum below records the post-migration gate run.
- **MEDIUM, scope** — the reviewer flagged that the branch's working tree carries unrelated
  uncommitted files (`lib/arch_index/runner.ml`, `tezt/tests/lsp_doc_comment_lines.ml` and its
  registration line in `main.ml`) alongside this task's changes, and that a dirty-tree measurement
  had leaked into a re-run of the numbers. Confirmed: those files are **pre-existing, out-of-scope
  work** present in this working tree since before this task started (see the roadmap snapshot's
  "must not be staged or reverted" note) — never staged or committed by this task at any point.
  The reviewer's own dirty-tree numbers (`2069`/`9433`) came from measuring the ambient session
  tree directly rather than a clean worktree of the actual commit; every number this brief cites
  was measured in a `git worktree add --detach` containing only this branch's commits. No action
  needed beyond the discipline already being followed — re-confirmed rather than newly applied.

**Re-verification (clean worktree, final commit — see Quality Gates addendum below).**
