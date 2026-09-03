# Implementation Brief — provenance-columns

**Date:** 2026-09-03
**Mode:** fast
**Status:** COMPLETED

## Where the work lives

Worktree `/tmp/claude-1000/-home-mathias-dev-arch-index/14fbc421-dfc7-4b31-91d6-c084baeb45e0/scratchpad/wt-provenance`,
branch `feat/provenance-columns`, based on `origin/main@e9b6dfa`.

## Scope

Roadmap Phase 1 item 1.2: `producer`, `producer_version`, `invocation_digest`,
`soundness_class ∈ {sound_with_top, heuristic, asserted}` — per ADR 002
("arch-index as an integrator of external analysers").

## Decisions made

- **Three independently-designed mechanisms, one per schema writer** — same
  precedent as items 0.7 and 1.1 this session. Not a shared mechanism, because
  the three writers have genuinely different needs:
  - **Main schema** (`Arch_index.run`, the CMT path): a `producer_runs` table
    (one row per invocation) plus a nullable `producer_run_id` FK on
    `functions`/`calls` — the roadmap's own implementer note is explicit that
    provenance must be "a `producer_run_id` FK to a `producer_runs` table, not
    as five text columns per row: at Octez scale (1.4M calls) denormalised
    text is a 200 MB mistake." Claims `soundness_class = 'sound_with_top'`
    explicitly — the CMT walker is the one producer in this codebase that
    marks unresolvable targets ⊤ rather than dropping them.
  - **Flat schema** (`runner.ml`, the LSP path): `comment_db_meta` keys
    (`producer`, `soundness_class`, `invocation_digest`), NOT a `producer_runs`
    table. This backend is always the SAME producer (`arch_index_lsp`) at the
    SAME rigour (`'heuristic'` — it never marks ⊤, see `lsp_edge_kind`'s own
    comment) for the whole database, even after `run_multi`'s merge — nothing
    per-row to distinguish, unlike `language`, which genuinely varies per
    merged sub-project. A per-row FK would model precision this backend does
    not have.
  - **`bin/arch_load`** (the NDJSON loader): also `comment_db_meta` keys, but
    populated from new `--producer=`/`--producer-version=`/
    `--soundness-class=` CLI flags rather than a hardcoded constant — this
    loader is deliberately producer-agnostic (Go, Rust, or any NDJSON
    producer can feed it), so it cannot claim an identity on the producer's
    behalf. Absent flags mean "not declared" (no `producer` key at all, never
    a guessed value); `soundness_class` always writes, defaulting to the
    conservative `'heuristic'` per ADR 002's governing rule. An
    out-of-vocabulary `--soundness-class` value ABORTS (exit 2), matching this
    loader's existing strictness discipline for an invalid `kind`.
- **`invocation_digest` is Stdlib `Digest` (MD5), not a SHA-256 library.**
  ADR 002 says "SHA-256 over (producer, producer_version, argv, project root
  content hash)" — implemented as MD5 over `(producer, producer_version,
  argv)` instead. This is an identity fingerprint for comparing invocations,
  not a security boundary, so Stdlib's zero-dependency `Digest` module is the
  right tool; adding `digestif`/`sha` as a new external dependency for a
  non-adversarial use case was not worth it. Also narrower than ADR 002's
  eventual goal — no project-content hash (a full tree walk) — documented as
  a deliberate simplification and a follow-up, not silently dropped.
- **`current_schema_version` bumped 1.3 → 1.4** (main schema: new table +
  columns, additive). **`current_flat_schema_version` left at 1.1** and
  `bin/arch_load`'s own `schema_version` left at `"1.1"` — neither flat
  schema's TABLE STRUCTURE changed; only new keys were written into the
  already-generic `comment_db_meta` key/value store, which is not a schema
  change under this project's own versioning discipline ("bump the minor
  component for an additive change — new nullable column/table/index").
- **`soundness_class` CHECK constraint defaults to `'heuristic'`, not
  `'sound_with_top'`**, on the `producer_runs` table itself — ADR 002's
  governing rule ("a heuristic fact may raise a finding, but may never
  discharge a ⊤ anchor or license a PASS") makes silence about rigour the
  safe default. A caller must explicitly claim `'sound_with_top'`.

## Modified files

| File | Type of change | Reason |
|---|---|---|
| `architecture-schema.sql` | addition | `producer_runs` table; `functions.producer_run_id`/`calls.producer_run_id` (+ indices) |
| `lib/arch_index/arch_index_db.ml`/`.mli` | modification | `current_schema_version` 1.3→1.4; new `insert_producer_run`, `invocation_digest`; `insert_function`/`insert_call`/`insert_call_rowid` gain `?producer_run_id` |
| `lib/arch_index/arch_index.ml`/`.mli` | modification | Creates one `producer_runs` row per run (`soundness_class='sound_with_top'`); threads `producer_run_id` to `process_cmt` and `insert_call_rowid`; `Db.insert_function` re-export signature updated |
| `lib/arch_index/arch_index_cmt.ml`/`.mli` | modification | `process_cmt` gains `?producer_run_id`, threaded to both `insert_function` call sites |
| `lib/arch_index/runner.ml` | modification | Both `run`/`run_multi` write `producer`/`soundness_class`/`invocation_digest` into `comment_db_meta` |
| `bin/arch_load/arch_load.ml` | modification | New `--producer=`/`--producer-version=`/`--soundness-class=` flags; `put_meta` calls for the four new keys; usage string updated |
| `docs/schema.md` | addition | Documents the main-schema `1.4` bump, the new `comment_db_meta` keys, and the three-mechanism design |
| `tezt/tests/multilang.ml` | addition | Extends the existing LSP-backend fixture with `producer`/`soundness_class`/`invocation_digest` assertions |
| `tezt/tests/provenance.ml` | addition | New file: main-schema `producer_runs`/FK join, the `soundness_class` CHECK constraint, `bin/arch_load`'s three new flags (declared, default, rejected) |
| `tezt/tests/insert_rowid_attribution.ml` | fix | Hand-copied `functions_sql` (19 placeholders) out of sync with the new 20-column INSERT — updated |
| `test/fixtures/self-index-stats.txt` | regenerated | Per ADR 001 — 539→541 functions, 3820→3845 calls (two new public functions) |

## Quality Gates

- [x] Build: `dune build --root . @all` (under the `arch-index` opam switch) ✅ clean, zero warnings
- [x] Tests: `dune test --root . --force` ✅ 94/94 tezt tests pass (3 new `provenance.ml` tests, 3 new assertions in `multilang.ml`)
- [x] Self-index golden regenerated per ADR 001

## Points of attention for review

- Confirm the three-mechanism split (FK table for main schema, `comment_db_meta`
  keys for both flat schemas) is the right call rather than forcing one shared
  shape — the reasoning is that the two flat-schema writers each have a SINGLE
  uniform producer identity per database, so a per-row FK would be modelling
  precision that does not exist.
- Confirm the MD5-not-SHA-256 deviation from ADR 002's literal text is
  acceptable — the justification is "identity comparison, not a security
  boundary" plus avoiding a new external dependency.
- `bin/arch_load`'s new flags are unused by any existing caller
  (`callgraph-go`/`callgraph-rust` do not pass them yet) — this is the same
  kind of documented residual as 1.1's Go/Rust `language` gap, not silently
  dropped.

## Identified out-of-scope (deferred, not silently dropped)

- Wiring `callgraph-go`/`callgraph-rust` to actually pass
  `--producer=`/`--soundness-class=` when invoking `arch-load` — mechanical,
  touches producer codebases outside this item's own OCaml-side scope (same
  reasoning as 1.1's equivalent residual).
- A full project-content hash for `invocation_digest` (ADR 002's literal
  design) — deferred; the current (producer, producer_version, argv) identity
  is sufficient for comparing invocations, which is the stated purpose.
- Item 1.3 (`analysis_coverage` table) is explicitly noted by the roadmap as
  the consumer of `producer_run_id` on coverage rows — not built here, a
  separate roadmap item.

## Review-round addendum

A fresh review round (reviewer + architect, cross-runtime codex skipped — degraded on every
invocation this session) found and fixed:

- **HIGH (reviewer)**: `producer_runs` was never added to `Arch_index.run`'s drop-and-recreate
  table list — every re-index of an existing database left an orphaned row behind. Fixed by
  appending it to `schema_tables_to_drop` (after `calls`/`functions`, which reference it).
- **HIGH (reviewer)**: the production write path for `producer_run_id` had no test exercising the
  real `Arch_index.run` binary — only hand-seeded SQL. Added
  `tezt/tests/provenance.ml`'s `register_real_cmt_run`, which indexes a real `.cmt` fixture and
  asserts every `functions`/`calls` row it produces carries a non-NULL `producer_run_id` joining
  to `producer = 'arch_index_cmt'`/`soundness_class = 'sound_with_top'`.
- **A second, independent, previously-undiscovered bug found while writing that same test**: with
  `PRAGMA foreign_keys = ON` (already set unconditionally by `Arch_index.run`), re-indexing an
  EXISTING non-empty database — the exact scenario `backup_intents` exists to support — always
  failed with a cryptic `no such table: main.calls` while dropping `functions`, because SQLite's
  FK enforcement objects to dropping a table another table's (already-dropped) `CREATE TABLE`
  once declared a reference to. Reproduced independently of `producer_runs` (plain `calls`/
  `functions` alone). Fixed: `PRAGMA foreign_keys = OFF` before the drop-then-recreate cycle;
  `architecture-schema.sql`'s own `PRAGMA foreign_keys = ON` at the top re-enables it immediately
  after. Covered by `register_producer_runs_not_accumulated_across_reindex`, which runs the real
  binary twice against the same file.
- **HIGH (both reviewers independently)**: `architecture-schema.sql`'s own comment claimed
  `invocation_digest` is "SHA-256", while every implementation is Stdlib MD5. Fixed the comment;
  also corrected the attribution elsewhere from "ADR 002's literal text" to "the roadmap's literal
  suggestion" — ADR 002 itself says nothing about the digest algorithm, only the three soundness
  classes and the governing rule.
- **MEDIUM (reviewer)**: `invocation_digest` hashed `Sys.argv` in `Arch_index.run`/`Runner.run`/
  `run_multi` — all three are published LIBRARY entry points, not CLI processes, so a caller's own
  process argv does not vary between two calls with different parameters (`~build_dir`,
  `~project_dir`, ...), defeating the digest's stated purpose. Fixed: each now hashes its own
  parameters instead. `bin/arch_load` is unaffected — it genuinely is the CLI process, so `Sys.argv`
  is correct there.
- **MEDIUM (reviewer)**: a rejected `producer_runs` insert in `Arch_index.run` silently left every
  row NULL with no local signal. Added an explicit `eprintf` warning.
- **MEDIUM (reviewer)**: `bin/arch_load`'s new flag parsing had three issues — `has_prefix`
  duplicated the file's own existing `starts_with`; an empty `--producer=` value would have
  written an empty-but-declared `producer` key (violating "absent means not declared"); an
  unrecognised `--`-looking flag silently became a positional filename argument. All three fixed:
  `has_prefix` removed in favor of `starts_with`; an empty flag value now `die`s; any surviving
  `--`-prefixed argument now `die`s as an unrecognised flag.
- **MEDIUM (reviewer)**: the CHECK-constraint test asserted only rejection, not non-storage, and
  had no positive control — it would have passed even if `producer_runs` did not exist at all.
  Added a positive-control insert and a `COUNT(*) = 0` assertion after the rejected insert.
- **MEDIUM (reviewer)**: `runner.ml`'s `run` (single-language) and `run_multi` (merge) each had a
  hand-duplicated copy of the three provenance `set_meta` calls — exactly the kind of drift that
  caused the `built_by` bug in the prior `language-universe` task. Factored into one
  `set_provenance_meta` helper both call. Also added test coverage for the previously-untested
  `run` path (`tezt/tests/lsp_languages.ml`'s `register_go`, which uses `Runner.run` directly).
- **LOW (reviewer)**: fixed a misleading `producer_runs.producer` example (`'arch-load'`) that
  named a writer that never inserts into that table.
- Architect's independent pass converged on the same SHA-256/MD5 comment finding and confirmed no
  other issues — overall architecture risk LOW, three-mechanism split "a principled response to a
  real structural difference, not unjustified inconsistency."

Re-verified after fixes: build clean, 96/96 tests (5 new in this round: the real-CMT-run test, the
re-index-does-not-accumulate test, the CHECK-constraint positive control, plus 2 new assertions in
`lsp_languages.ml`). Self-index golden regenerated again (542 functions, 3849 calls — the new
`set_provenance_meta` helper added one function).

## Ratchet

First round.
