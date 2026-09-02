# Implementation Brief — fix-issues-33-34-35

**Date:** 2026-09-02
**Mode:** fast
**Status:** COMPLETED

## Modified files

| File | Type of change | Reason |
|---|---|---|
| `bin/arch_query/arch_query.ml` | modification | #33 — `limit_of` no longer silently defaults on garbage; #34 — `gardening open`'s status filter |
| `bin/arch_coverage_load/arch_coverage_load.ml` | modification | #35 — optional `"module"` field disambiguates same-named functions |
| `tezt/tests/query_limits.ml` | new | ratchet for #33 |
| `tezt/tests/curation.ml` | modification (two new registered tests) | ratchets for #34 and #35 |
| `tezt/tests/main.ml` | modification | registers the three new tests |

## #33 — `limit_of` silently swallows a bad numeric argument

**Location:** `bin/arch_query/arch_query.ml:158` (was `:152` in the issue, before other work
shifted line numbers).

**Fix:** `limit_of` now exits 2 on any argument that reads as an attempted number and gets it
wrong — not an integer at all, or a negative one (SQLite reads `LIMIT -1` as unlimited, so a
negative limit silently means the opposite of what the caller asked for).

**Decision made — this is the one worth a reviewer's attention.** The issue's fix direction
("exit 2 on a non-empty argument that is not a non-negative integer") collides with an existing,
deliberate invariant test in `tezt/tests/health.ml` ("health: facts are exact, measures are not
gates"), which asserts that `large-files --fail-on-size 100` must exit 0 — a stray
`--fail-on-...`-shaped argument to a MEASURE command is *deliberately* ignored, specifically so
nobody can wire one of these commands into a real gate later. A literal reading of the issue's fix
direction breaks that test outright (confirmed: applying the naive fix made `health.ml` fail with
exactly the flag-ignoring assertion).

Resolved by distinguishing the failure classes `limit_of` actually sees: an argument starting with
`--` is not treated as an attempted number at all and keeps falling back to the default (preserving
the "measures are never gates" doctrine intact); anything else that fails to parse as a
non-negative integer (a typo like `abc`, or a negative number) is refused with exit 2. This
satisfies the issue's own explicit repro (`large-files abc` and `large-functions -1`) without
reopening the hole `health.ml` exists to keep closed. Both directions are now covered by tests:
`query_limits.ml` (the new refusals) and the pre-existing `health.ml` case (the flag exemption,
re-verified passing, not just left alone).

**Empty-string handling unchanged:** the empty string is the pre-existing "no argument given"
sentinel used throughout this file (e.g. `type-search`'s `if a = "" then die 2 ...`) and still
falls through to the default — this is not a new no-argument-supplied error.

## #34 — `gardening open` drops `in_progress` tasks

**Location:** `bin/arch_query/arch_query.ml` (the `gardening` / `"open"` branch).

**Fix:** `WHERE t.status='open'` → `WHERE t.status<>'done'`, exactly as the issue's fix direction
specifies and as PR #6 (closed, superseded) already did. `t.status` was already in both the header
list and the `SELECT` — no further change needed there; the new ratchet test explicitly asserts the
column value is visible in the output, not just present in the SQL.

## #35 — coverage for a same-named function is silently unattributable

**Location:** `bin/arch_coverage_load/arch_coverage_load.ml`.

**Fix, minimal per the roadmap's explicit instruction (the durable fix is item 1.6, out of
scope):** an optional `"module"` NDJSON field, holding a `modules.path` value. When present,
resolution joins `functions` to `modules` and requires both `f.name = ?` and `m.path = ?`; when
absent, resolution falls back to the pre-existing name-only behavior (skip if absent from the
index, ignore if ambiguous). The duplicate-detection hash table now keys on `(function, module)`
rather than `function` alone, since two records for the same function name in two different
modules are no longer necessarily the same coverage fact.

`usage` text and the module-level doc comment updated to describe the optional field; a comment on
`resolve` names roadmap item 1.6 as the durable fix this one is deliberately not attempting.

## Quality Gates

- [x] Build: `dune build` ✅ (clean, 0 warnings/errors)
- [x] Tests: `dune test --force` ✅ 83/83 (was 79/79 before this task; +4 new/modified: `arch-query:
      a bad limit argument is refused, not defaulted`, `curation: an optional module field
      disambiguates a same-named function (#35)`, `curation: gardening open must not drop
      in_progress tasks (#34)`, plus the pre-existing `health.ml` MEASURE test re-verified passing
      against the refined `limit_of`)
- [x] Format: `dune fmt` — clean on the touched files; reformatted 17 unrelated pre-existing `dune`
      files (whitespace-only drift, same as prior tasks in this session), reverted as out of scope

**Red-then-green, verified against actual pre-fix code (not asserted):** stashed the three fix
files, rebuilt, and confirmed all four new/changed test cases fail with the exact pre-fix
behavior — `query_limits.ml` reported both `abc` and `-1` exiting 0 (silently defaulted/unlimited);
`curation.ml`'s module-disambiguation case reported "unknown field module"; `curation.ml`'s
gardening case showed the `in_progress` row missing from the output. Then popped the stash and
reconfirmed all four green.

## Points of attention for review

- The `--` exemption in `limit_of` (see #33 above) is the one substantive design decision in this
  task — everything else is a direct application of the issue's own fix direction. Worth checking
  independently that the exemption is drawn in the right place (any `--`-prefixed string, not just
  the literal `--fail-on-size` the existing test happens to use).
- `#35`'s duplicate-detection key change (`(function, module)` instead of bare `function`) is a
  behavior change beyond the issue's literal ask, but necessary: without it, the same function name
  appearing once per module in one input would falsely trip the "appears more than once" abort.
  Flagging it explicitly since it's not spelled out in the issue text.

## Identified out-of-scope

- #35's durable fix (a stable qualified identity shared by every loader, not scoped resolution one
  loader at a time) is roadmap item 1.6 — noted inline in the code comment and here, not attempted.
- The 17 pre-existing `dune`-fmt-drifted files — not touched, already logged as out-of-scope debt
  in a prior task this session (`wire-checks-into-ci`).

## Ratchet

(First round — no loop-back yet, no ratchet-of-a-ratchet needed.)

## Addendum — review round 1 fixes (2026-09-02)

Review round 1 found 1 HIGH and 4 MEDIUM (one of which is a pre-existing, out-of-scope sibling
bug), all addressed here except the sibling bug, which is deliberately filed rather than fixed.

- **HIGH — the `--` exemption leaked onto non-measure commands.** `limit_of`'s exemption for
  `--`-prefixed arguments (added to preserve `health.ml`'s "measures are never gates" doctrine)
  had been applied to all 8 call sites sharing its shape, but the doctrine only covers the three
  commands whose own output says "measure only" (`large-files`, `large-functions`,
  `god-modules`). `low-coverage --fail-on-coverage 80` silently defaulted instead of refusing —
  the exact false-green hole #33 exists to close. Split into two functions: `limit_of` (strict —
  used by `fan-in`, `dead-blocks`, `useless-branches`, `mutation-density`, `low-coverage`) and
  `measure_limit_of` (the `--`-exempt variant, used only by the three measure commands).
- **MEDIUM — #34 was NULL-blind.** `t.status<>'done'` reads NULL as neither equal nor unequal to
  `'done'` under SQL's three-valued logic, so an explicitly-NULL status vanished from the open
  view exactly like the bug the query already fixes once. `gardening_tasks.status` has a
  `DEFAULT` but no `NOT NULL`. Fixed to `COALESCE(t.status,'open')<>'done'`, and applied the same
  fix to `architecture-schema.sql`'s `v_open_tasks` view (unused by any command today, but the
  same bug class — fixed for consistency rather than left to reappear for its next consumer).
- **MEDIUM — #35's dedup key allowed a same-input collision with a misleading diagnosis.** A
  bare record and a module-qualified record for the same function name both passed phase-1
  validation (different `(fn, module)` keys) but could resolve to the same `function_id`,
  colliding on `coverage`'s `UNIQUE(function_id, recorded_at)` in phase 2 with a message telling
  the caller to "run again in a moment" — advice that can never help, since the cause is two rows
  in one input, not a prior run. Added a second pair of hash tables (`seen_bare`/`seen_scoped`,
  keyed on function name alone) that reject mixing a bare and a scoped record for one name,
  independent of `(fn, module)` exact-duplicate detection. Two *distinct* scoped records for one
  name across different modules remain accepted, unchanged — that is the feature #35 added.
- **MEDIUM — the ratchet's own coverage claim was wrong.** `query_limits.ml`'s comment claimed 6
  of 8 `limit_of` call sites die with exit 3 before reaching the limit parse on the test fixture;
  in fact only `useless-branches`/`mutation-density` do (they additionally gate on a non-zero row
  count; `god-modules`/`low-coverage`/`dead-blocks` only check table *existence*, which is always
  true on a main-schema fixture). Rewrote the file: explicit `measure_commands`/`strict_commands`
  lists, assertions for both directions of the HIGH fix (measure commands still ignore `--...`,
  strict commands now refuse it), and coverage of the OCaml-integer-literal syntax hole
  (`0x10`/`1_0`/`+5` silently reinterpreted by `int_of_string_opt`) with a strict decimal-only
  parse shared by both `limit_of` variants.
- **Deliberately NOT fixed here — filed as issue #47:** `bin/arch_body_compare/arch_body_compare.ml`
  has the identical silent-default-on-garbage shape #33 fixed in `arch_query.ml`. None of #33/#34/#35
  named this file; fixing it here would be scope creep mid-branch. Filed as a fast follow-up,
  matching how #33/#34/#35 themselves were filed from PR triage.
- Also updated `docs/curation-workflow.md` (the `gardening open` one-liner and the coverage-load
  jq recipe now mention the `module` field and `in_progress`) — `tezt/tests/curation_doc.ml` only
  executes the doc's fenced ```sql``` blocks, so this prose edit does not risk that test.

**Re-verified red-then-green against real pre-fix code** (a clean worktree at `cf30125`, the
round-1 commit, with only the new/updated test files overlaid): all new/changed assertions failed
with the exact pre-fix symptom described above, then passed clean after the fixes.

**Quality gates (round 2):**
- Build: `dune build` ✅
- Tests: `dune test --force` ✅ 83/83, 0 failures
- Format: clean on touched files; same 17-file pre-existing `dune`-fmt drift reverted, unrelated
