# Implementation Brief — language-universe

**Date:** 2026-09-03
**Mode:** fast
**Status:** COMPLETED

## Where the work lives

Worktree `/tmp/claude-1000/-home-mathias-dev-arch-index/14fbc421-dfc7-4b31-91d6-c084baeb45e0/scratchpad/wt-languni`,
branch `feat/language-universe`, now rebased onto `origin/main` at `38553ff`, commit `cf47d64`.

## Review-round addendum

A fresh review round (2 specialists + degraded cross-runtime) found and fixed:

- **CRITICAL, both specialists independently**: the branch was cut before PR #54
  (`exn-raise-sets`, roadmap 3.4) merged into `origin/main`. `git diff origin/main HEAD` was
  showing that entire, already-shipped feature as a wholesale deletion — merging as-is would
  have reverted it. Fixed by rebasing onto current `origin/main`, resolving the
  `test/fixtures/self-index-stats.txt` conflict by regenerating fresh against the fully-merged
  tree (not hand-merging the numbers), and re-running the full suite (91/91, including the two
  new `exn` tests).
- **HIGH**: `runner.ml`'s flat schema and `bin/arch_load`'s flat schema are structurally
  identical and both now carry independently-bumped `"1.1"` version strings, with no way for a
  consumer to tell which writer produced a given database (`Arch_db.schema` only discriminates
  `Flat` vs `Main`). Fixed: `runner.ml` now also writes `comment_db_meta.built_by =
  "arch_index_lsp"` (an existing, documented meta key — `arch_load` already writes
  `built_by="arch-load"`), giving a consumer a way to disambiguate the two version spaces.
  `docs/schema.md` documents this and adds `bin/arch_load`'s own version-history table.
- **MEDIUM, accepted as a documented residual, not fixed this round**: neither
  `callgraph-go/main.go` nor `callgraph-rust/src/main.rs` (the two other existing NDJSON
  producers that feed `bin/arch_load`) emit the new optional `language` field — their rows will
  read `functions.language = NULL` indefinitely unless a separate task updates them. Each
  producer trivially knows its own language (same reasoning that justified hardcoding `"ocaml"`
  in the CMT path), so this is a mechanical follow-up, not a design gap — but it means this
  item's stated goal (per-language coverage matrix, boundary edges) is NOT yet actually
  achievable for Go/Rust-analyzed code until that follow-up lands. Not fixed here: touching two
  other producer codebases in different languages is real scope beyond this item's own stated
  boundary (the OCaml-side schema/pipeline). Flagged, not silently dropped.
- **LOW × 2, already documented pre-review, independently reconfirmed by both specialists**: the
  CMT-path hardcode-`"ocaml"` deviation from the intake brief's literal design decision #1, and
  the `universe` `CHECK` constraint being a present-day tautology (only `'internal'` rows exist)
  until the deferred `ext:`-materialization work lands. Both already covered in this brief's
  "Points of attention" section below — no new action, both specialists' independent arrival at
  the same two residuals is corroborating evidence they're the right calls to leave as residuals
  rather than something overlooked.
`git status --porcelain` is empty.

## Modified files

| File | Type of change | Reason |
|---|---|---|
| `architecture-schema.sql` | addition | `modules.language`, `functions.language`/`functions.universe` (+indices), main schema — additive |
| `lib/arch_index/arch_index_db.ml`/`.mli` | modification | `current_schema_version` "1.2"→"1.3"; `insert_module`/`insert_function` gain `?language` |
| `lib/arch_index/arch_index.ml`/`.mli` | modification | `Db.insert_function`'s re-exported signature updated to match; new `schema_version` write for the main schema (previously never written at all) |
| `lib/arch_index/arch_index_cmt.ml` | modification | Both `insert_module`/`insert_function` call sites pass `~language:(Some "ocaml")` — this walker only ever processes .cmt/.cmti files |
| `lib/arch_index/runner.ml` | modification | Flat schema gains a `language` column; `write_functions` takes `~language`, threaded from `run`'s own `~language` param; `run_multi`'s cross-language merge SQL carries it through from each temp DB; `current_flat_schema_version` "1.0"→"1.1" |
| `bin/arch_load/arch_load.ml` | modification | `language` added to the `"function"` record's allowed-fields list, `fn` record type, schema DDL, and INSERT; **also fixes a genuinely separate, previously undiscovered bug**: this loader never wrote `schema_version` at all — added a local `schema_version = "1.1"` constant and `put_meta` call |
| `docs/schema.md` | addition | Documents all three version bumps (main 1.3, flat 1.1, arch_load 1.1) |
| `tezt/tests/multilang.ml` | addition | Ratchet check (roadmap's own acceptance criterion): asserts zero `functions.language` NULL rows, correct per-function language values for both languages the polyglot fixture exercises |
| `tezt/tests/insert_rowid_attribution.ml` | fix | The test's own hand-copied `functions_sql` (documented as "verbatim from arch_index.ml") was out of sync with the new 19-column INSERT — updated to match, or the test asserted nothing real |
| `test/fixtures/self-index-stats.txt` | regenerated | Per ADR 001 — calls 3500→3503 (no new functions this round, only modified signatures) |

## Decisions made

- **Three independent schemas, three independent fixes, not one shared mechanism.** The main
  schema (CMT path), the flat schema (LSP path, `runner.ml`'s own inline shape), and
  `bin/arch_load`'s NDJSON-consuming flat schema are three genuinely separate writers of
  (two of them) structurally identical table shapes. Rather than force a shared dependency
  (`bin/arch_load` deliberately has no dependency on the `arch_index` library — `sqlite3`+`yojson`
  only), each got its own fix on its own terms, consistent with the schema-versioning task's own
  precedent (`current_schema_version` vs `current_flat_schema_version`).
- **The CMT-based main-schema path (`arch_index_cmt.ml`) hardcodes `"ocaml"`, not
  `detect_language_roots`.** This deviates from the roadmap's literal phrasing ("wire
  `detect_language_roots` into `Arch_index.run`") — investigated and found that `.cmt`/`.cmti`
  files are structurally always OCaml (this walker cannot process anything else), so calling the
  detector here would be pure overhead for a value that's a structural invariant, not something
  needing detection. The detector's actual value applies to the LSP-based flat-schema path
  (`runner.ml`), which genuinely serves several languages and already receives the detector's
  result as an explicit parameter (`~language`/`~languages`, resolved by the caller,
  `arch_index_cli`) — "the detector exists and is discarded" describes THAT path's problem
  precisely (the language was already known, just never reaching the `functions` table), not a
  missing-detection problem in the CMT path.
- **A second, independent bug found and fixed in the same round:** `bin/arch_load` never wrote
  `comment_db_meta.schema_version` at all — a third, previously undiscovered instance of the
  exact silent-schema-drift bug class issue #51 was about (the other two, the main schema and
  `runner.ml`'s flat schema, were fixed in the prior `schema-versioning` task). Found while adding
  the `language` column here, since it's the same loader. In scope: it's the same "every Phase 1
  column must land in both schemas" discipline the roadmap's own architecture note calls for, and
  leaving it unfixed would have meant shipping a new column into a loader with zero version
  tracking at all.
- **`universe` gets a `CHECK` constraint documenting its eventual full domain (`internal`,
  `external`), even though every row this table can hold today is `internal`.** Materializing
  `ext:` leaves as real rows is explicitly deferred (roadmap's own scope note, relevant to items
  1.5/2.4) — the CHECK constraint states the invariant the column exists to eventually enforce
  without prematurely building the materialization logic.

## Quality Gates

- [x] Build: `dune build @all` ✅ clean, zero warnings
- [x] Tests: `dune test --force` ✅ 89/89 tezt tests pass (including the new ratchet assertions in
      `multilang.ml`, verified with real `gopls`/`typescript-language-server` on `PATH` — not
      skipped)
- [x] Self-index golden regenerated per ADR 001

## Points of attention for review

- The `arch_index_cmt.ml` hardcode-`"ocaml"` decision (above) — confirm this reasoning holds and
  isn't a misreading of what the roadmap actually wanted from wiring `detect_language_roots` into
  the CMT path specifically.
- `bin/arch_load`'s new `schema_version` constant is entirely independent from
  `Arch_index_db.current_flat_schema_version` despite both loaders having structurally identical
  schemas today — confirm this independence is the right call (matches the schema-versioning
  task's own established precedent of per-writer version identities) rather than something that
  should have been unified.
- Two other Claude sessions are working in parallel on this same repo (`arch-index-96`, items 3.4
  and the stacked `feat/error-channels`) and are aware `current_schema_version` is now `"1.3"` —
  coordinated directly, not a silent collision risk, but worth independently confirming no
  overlap exists in the actual committed diff.

## Identified out-of-scope (deferred, not silently dropped)

- Materializing `ext:` leaves as real `functions` rows (relevant to items 1.5/2.4) — explicitly
  scoped out in the intake brief.
- Items 1.2–1.6 (provenance, coverage matrix, ⊤-anchor taxonomy, witness paths, stable identity)
  — each its own roadmap item.
- Boundary-edge detection (3.6) — a later item this one unblocks.
- Updating `callgraph-go/main.go`/`callgraph-rust/src/main.rs` to emit the new optional
  `language` NDJSON field (found during review) — mechanical, but touches two other producer
  codebases in different languages, beyond this item's own scope of the OCaml-side
  schema/pipeline. A follow-up, not silently dropped — see the Review-round addendum above.

## Ratchet

_(first round, no loop-back yet)_
