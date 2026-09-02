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
