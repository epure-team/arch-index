# DB schema reference

The full schema is in [`architecture-schema.sql`](../architecture-schema.sql). This page describes the key tables.

## Core tables

### `functions`

One row per indexed function or value.

| Column | Type | Description |
|---|---|---|
| `id` | INTEGER | Primary key |
| `module_id` | INTEGER | FK → `modules` |
| `name` | TEXT | Qualified name (e.g. `Arch_index_db.exec_exn`) |
| `signature` | TEXT | Type signature (nullable) |
| `line_start`, `line_end` | INTEGER | Source location |
| `exposed` | BOOLEAN | Appears in `.mli` (public API) |
| `intent` | TEXT | Human-written description |
| `comment_quality_score` | INTEGER | 0–100 doc-comment score |
| `has_pre`, `has_post`, `has_violators`, `has_violates` | BOOLEAN | Structured comment presence |
| `violators_raw`, `violates_raw` | TEXT | Raw violator/violates section |
| `tests_raw` | TEXT | Linked test cases |
| `quint_raw` | TEXT | Quint action fragment |

### `calls`

One row per call site.

| Column | Type | Description |
|---|---|---|
| `id` | INTEGER | Primary key |
| `caller_id` | INTEGER | FK → `functions` |
| `callee_id` | INTEGER | FK → `functions` (nullable if unresolved) |
| `callee_name` | TEXT | Callee qualified name |
| `call_site` | TEXT | `file:line` location |
| `kind` | TEXT | Edge kind: `MUST`, `MAY_ENUMERATED`, `MAY_TOP`, or NULL (legacy) |

### `modules`

One row per source file.

| Column | Type | Description |
|---|---|---|
| `id` | INTEGER | Primary key |
| `path` | TEXT | Relative file path |
| `lines` | INTEGER | Line count |
| `has_mli` | BOOLEAN | Has interface file |
| `quint_module_raw` | TEXT | Module-level Quint preamble |

### `comment_db_meta`

Key/value store for index metadata.

| Key | Value |
|---|---|
| `callgraph_contract` | `v1` when the index is ⊤-marked |
| `decision_contract` | `v1` when a producer actually ran the decision analysis |
| `built_by` | the producing tool, e.g. `arch-load` |
| `producer` | (flat schemas only — roadmap 1.2, ADR 002) declared producer identity, e.g. `arch_index_lsp` |
| `producer_version` | (flat schemas only) declared producer version, absent if not declared |
| `soundness_class` | (flat schemas only) `sound_with_top` \| `heuristic` \| `asserted` — ADR 002's rigour classes |
| `invocation_digest` | (flat schemas only) an MD5 identity fingerprint over the invocation |

`decision_contract` is stamped only when decisions were supplied, so a consumer can tell
"computed nothing" from "computed nothing to report". The `decisions` table exists either way —
presence proves nothing, which is why every consumer checks whether it is **non-empty**.

### Provenance (roadmap 1.2, ADR 002)

The **main schema** records provenance as data, not per-row text: a `producer_runs` table (one
row per invocation — `producer`, `producer_version`, `invocation_digest`, `soundness_class`) and a
nullable `producer_run_id` FK on `functions`/`calls`. This is a join, not five denormalised
columns repeated per row — at Octez scale (1.4M+ calls) the latter is a ~200 MB mistake for data
that never varies within one run. `Arch_index.run` (the CMT path) inserts exactly one
`producer_runs` row per invocation, claiming `soundness_class = 'sound_with_top'` — the one
producer in this codebase that marks unresolvable targets ⊤ rather than dropping them.

The two **flat schemas** (`runner.ml`'s LSP-based path, and `bin/arch_load`'s NDJSON loader) use
`comment_db_meta` keys instead of a `producer_runs` table — see the table above. `runner.ml`
always writes `producer = 'arch_index_lsp'` and `soundness_class = 'heuristic'` (it never marks
⊤ — see `lsp_edge_kind`'s own comment in `runner.ml`), since this backend is always the same
producer at the same rigour: nothing per-row to distinguish, unlike `language`, which genuinely
varies after `run_multi`'s merge. `bin/arch_load` is producer-agnostic by design (Go, Rust, or any
NDJSON producer can feed it), so it cannot hardcode an identity — `producer`/`producer_version`
are written only when declared via `--producer=NAME`/`--producer-version=V`, and absent means "not
declared", never a guess; `soundness_class` always writes, defaulting to the conservative
`'heuristic'` per ADR 002's governing rule (only an explicit `--soundness-class=` flag can claim
`sound_with_top`). An out-of-vocabulary `--soundness-class` value aborts the load, matching this
loader's own strictness discipline for an invalid `kind`.

`invocation_digest` is Stdlib `Digest` (MD5) over `(producer, producer_version, argv)` in every
writer — an identity fingerprint so two reports of the same invocation can be compared without
re-running, not a security boundary, so a heavier hash was not worth a new dependency. It does not
hash project content (a full tree walk); that is a documented simplification, a follow-up if a
future consumer needs content-sensitivity, not a silently dropped requirement. `argv` here is the
literal `Sys.argv` only for `bin/arch_load` (a real CLI process); `Arch_index.run` and
`Runner.run`/`run_multi` are library entry points, so a caller's own process argv would not vary
between two calls with different parameters — they hash their own parameters
(`build_dir`/`db_path`/`schema_path`, and `project_dir`/`language(s)`, respectively) instead
(review-round fix — the first draft used `Sys.argv` unconditionally).

**Residual:** `producer_version` is written only by `bin/arch_load` (from its `--producer-version=`
flag, when a caller declares it). `Arch_index.run` and `runner.ml` both pass `producer_version =
None` unconditionally — neither has a build-time version string to report (this project has no
`VERSION` file). Not silently dropped: a future item that adds one should populate this argument.

### Analysis coverage (roadmap 1.3)

`analysis_coverage` is the honest-absence guarantee: one row per (language, analysis) pair a run
against a TARGET project could have attempted, written by `arch-coverage-matrix`
(`bin/arch_coverage_matrix`, logic in `lib/arch_index/coverage_matrix.ml`). A language/analysis
with no invocable producer is recorded as `not_analysed` with a build/install instruction in
`detail`, never left as silent zero rows — the honest version of #23 (a missing LSP binary
producing an empty database with exit 0). `status ∈ {covered, not_analysed, failed, partial}`.
`language` is `NULL` for a cross-language analysis (`coverage`, `decisions`) not scoped to one
language. Snapshot semantics: each run deletes and re-inserts every row — this table describes the
run that just computed it, not accumulating history.

The roadmap's own vocabulary of six analysis kinds
(`callgraph`/`effects`/`cfg`/`decisions`/`coverage`/`types`) is **not** uniformly invocable, and
`arch-coverage-matrix` does not pretend otherwise:

- `callgraph` and `effects` are real, independently invocable producers, detected on genuinely
  different terms per language: OCaml (both) — a bundled dune executable, "available" once built;
  Go `callgraph` — the DRIVER the repo-root wrapper script (`arch-callgraph-go`) itself gates
  internally (`repo_root/bin/arch-callgraph-go`), not the wrapper's own existence; Rust
  `callgraph` — the SAME, but the wrapper (`arch-callgraph-rust`) has TWO gates, not one: the
  driver itself (one of 4 candidate build paths) AND the whole-program merge pass
  (`bin/arch_callgraph_rust_merge`) it unconditionally requires — both need to be built for
  `covered`, only the first for a distinct `not_analysed` reason. Neither wrapper's own existence
  is checked (both are checked into git and always present, so checking either would report
  `covered` on every checkout regardless of whether the driver/merge-pass behind it is built) —
  every other language registered in `Language_registry` — `Language_registry.lookup`, with
  `lsp_install_instruction` filling `detail` on failure. Every detected language gets an
  `effects` row, `not_analysed` with an honest reason unless it is OCaml or Go — Go's own
  `effects` producer exists only as test-harness infrastructure today (built into a temp dir by
  `tezt/lib/arch_tezt.ml`'s own helper), not a shipped binary, so it too reports `not_analysed`
  rather than being silently promoted to `covered`.
- `cfg` and `types` are **not** independently invoked — they are facts the `callgraph` producer
  for a language already emits as part of its own output (post-dominance/CFG; the `types` table).
  Their coverage rows mirror that language's own `callgraph` row's status rather than being
  probed a second time.
- `coverage` (test-line coverage, an unrelated meaning from the `coverage` SQL table documented
  above) requires an externally-supplied LCOV tracefile this tool cannot discover on its own —
  `not_analysed` unless `--lcov <path>` names an existing file.
- `decisions` (`poc/decision-lint`) is a proof-of-concept outside the main dune build graph
  entirely — always `not_analysed`.

`arch-coverage-matrix --project <dir> --db-path <out.db> [--allow-partial] [--lcov <path>]` exits 1
if any **language-scoped** row (`callgraph`/`effects`/`cfg`/`types`, `language IS NOT NULL`) is
`not_analysed`/`failed`/`partial` and `--allow-partial` was not given, per the roadmap's own
ratchet ("a non-zero exit unless `--allow-partial` is given"). The two cross-language rows
(`coverage`, `decisions`) never gate the exit code: neither can become `covered` by anything this
tool run alone could fix (an LCOV tracefile is supplied externally or it is not; `decisions` is a
standing fact about this codebase's own build graph), so counting them would make every
invocation without `--allow-partial` exit 1 unconditionally — a gate that always fires carries no
signal. `partial` (an OCaml `_build/default` present but containing no `.cmt`/`.cmti` files —
about to silently index nothing) counts as a gap, same as `not_analysed`/`failed`.

The repo-root marker search (`find_repo_root`) looks for a directory containing BOTH
`architecture-schema.sql` and a `_build` subdirectory, not the marker file alone: dune mirrors
every file it depends on into `_build/default/` as part of its own build sandbox, so
`_build/default/architecture-schema.sql` is a real, separate file — a marker-alone search
starting from inside `_build/default/bin/...` (where this and every other executable this project
builds lives) finds that mirrored copy first, one directory short of the genuine root.

## Additional tables

`types`, `type_fields`, `type_constructors` — indexed type definitions.
`module_deps` — import/open dependencies between modules.
`type_usage` — function-level type usage tracking.
`decisions`, `conditions` — dead-logic analysis (`v_useless_branches`).
`dead_code_sites` — call sites in CFG-unreachable blocks (`v_dead_code`).
`coverage` — written by [`arch-coverage`](coverage.md) from an LCOV tracefile:
`covered_lines` / `total_lines` per function, where `total_lines` counts **instrumented** lines
only. A function with no instrumentation gets no row rather than a 0% one — "no data" and
"never executed" are different facts and must not be merged.

## The flat schema

`arch-load` builds a deliberately smaller schema for NDJSON producers: `functions(name,
file_path, exported, line_start, line_end)` and `calls(caller_name, caller_file, callee_name,
callee_file, call_site, kind)`. Names are global there, so the graph is keyed by name; in the
main schema `functions` is `UNIQUE(module_id, name)`, so a name is unique only within its module
and the graph must be keyed by row id. Consumers get this right via `Arch_tools.Arch_graph` (`lib/arch_tools/arch_graph.ml`)
rather than each re-deriving it: it keys nodes by `#<rowid>` on the main schema and by name on
the flat one, behind one node type.

`line_start`/`line_end` are optional on the wire but required for any per-diff or per-line join
(`arch-impact`, `arch-mutants`, `arch-coverage`). A **half** span aborts the load: it would
mis-map every hunk in the file, which is worse than having no span at all.

See [`architecture-schema.sql`](../architecture-schema.sql) for full column definitions, indices, and triggers.

## Schema version history

`comment_db_meta.schema_version` is stamped `"<major>.<minor>"` at every index run — read from
`Arch_index_db.current_schema_version` (re-exported as `Arch_index.schema_version`), the single
source of truth every write site uses. Bump the **minor** component for an additive change (new
nullable column, table, or index — every version below is this kind); bump the **major** component
for a breaking one (a column/table removal, or a type change an existing consumer's query could
not survive unmodified). A consumer that only understands version `N.x` can safely read a `N.y`
database (every `N.*` schema is a superset of `N.0`); it must refuse a database whose major version
it does not recognize, since some table or column it depends on may be gone.

This versions the **main** schema (`architecture-schema.sql`, above) only — written by
`Arch_index.run` (the CMT-based path). The flat schema (see "The flat schema" above, the LSP-based
path's own inline 3-table shape — the actual entry point `arch_index_cli` uses) is structurally
different; it gets its **own** version identity,
`Arch_index_db.current_flat_schema_version` (currently `"1.1"` — bumped from `"1.0"` for roadmap
item 1.1's optional `functions.language` column, re-exported nowhere yet since no consumer has
asked for it), written by `runner.ml`'s two `comment_db_meta.schema_version` call
sites — never `current_schema_version`. **Both write into the same `comment_db_meta.schema_version`
key**, so a consumer must check WHICH schema it opened (`Arch_db.schema` probes for
`calls.caller_name`, per [`lib/arch_tools/arch_db.ml`](../lib/arch_tools/arch_db.ml)) before
treating the number it reads as meaning anything about that shape — the two version spaces are
otherwise incomparable (a flat-schema `"1.0"` and a main-schema `"1.0"` describe unrelated table
sets). A first draft of this fix stamped every database with `current_schema_version` regardless of
which schema it actually was — caught and fixed by a fresh review round, since it would have let a
flat-schema consumer read `"1.2"` and wrongly conclude `function_effects`/`attack_edges` exist.

A THIRD writer of this same structural flat shape exists — `bin/arch_load/arch_load.ml`, a generic
NDJSON loader for other producers (Go, Rust, ...), deliberately independent of the `arch_index`
library (no shared dependency, so no shared version constant either — see its own version history
below). Since `Arch_db.schema` only distinguishes `Flat` from `Main` (not WHICH flat-schema writer
produced a given database), two flat-schema databases can carry the identical `schema_version`
string while describing genuinely independent evolution — a real, caught-in-review instance of the
same silent-drift risk class #51 was about, one level up from the original bug. The mitigation:
both `runner.ml` and `bin/arch_load/arch_load.ml` write `comment_db_meta.built_by` (already an
established, documented meta key — `arch_index_lsp` and `arch-load` respectively); a consumer that
needs to know which flat-schema numbering space a `schema_version` value belongs to can check
`built_by` first. This is a proxy, not a merge of the two version spaces into one — accepted as a
residual rather than unifying them, since the two schemas are only COINCIDENTALLY identical today
and forcing a shared constant across two intentionally-independent binaries would be the wrong fix.

| Version | Added | Migration |
|---|---|---|
| `1.0` | The base 16-table schema (`functions`, `calls`, `modules`, `comment_db_meta`, and the rest listed above) | `architecture-schema.sql` (baseline) |
| `1.1` | `function_effects`, `value_kinds` — mutation/effect tracking (Phase 1 capability A) | `effects-schema-migration.sql` |
| `1.2` | `reachability_class`, `actor_role`, `temporal_class`, `gating`, `value_touched`, `precondition` columns on `function_effects`; `attack_edges` table and `from_path`/`to_path` columns — attack-surface capability layer (Phase 2) | `capabilities-schema-migration.sql` |
| `1.3` | `exn_origins.channel`, `exn_scopes.channel`, `exn_edges`, `channel_carriers` — error-channels (specs/error-channels.md). Slices 0-1: re-tag only, no behaviour change (producer emitted only `channel = 'exception'` rows). Slice 2 (spine): the producer additionally writes `result`/`option` value-channel rows through the SAME tables/columns (`channel_carriers` new, additive within this version — a node's c-carrier marker) | `architecture-schema.sql` (in place; no separate migration file) |
| `1.8` | `exn_origins.channel`, `exn_scopes.channel`, `exn_edges` — error-channels re-tag, no behaviour change (the producer still emits only `channel = 'exception'` rows; value channels start writing in a later slice) | `architecture-schema.sql` (in place; no separate migration file) |
| `1.8` | `modules.language`, `functions.language`/`functions.universe` — roadmap Phase 1 item 1.1, `SPEC-sound-callgraph.md` FR-001 ("node identity carries a language tag + internal/external universe flag") | `architecture-schema.sql` (additive columns) |
| `1.8` | `producer_runs` table; `functions.producer_run_id`/`calls.producer_run_id` — roadmap Phase 1 item 1.2, ADR 002 | `architecture-schema.sql` (additive table + columns) |
| `1.8` | `analysis_coverage` table — roadmap Phase 1 item 1.3, the honest-absence guarantee | `architecture-schema.sql` (additive table); also embedded standalone in `arch-coverage-matrix` |
| `1.8` | `calls.top_reason`/`calls.top_anchor` — roadmap Phase 1 item 1.4, the ⊤-anchor taxonomy (see `docs/edge-kind-contract.md`) | `architecture-schema.sql` (additive columns); `bin/arch_load` gets its own `top_reason` in its NDJSON contract, version 1.1→1.2 |

Versions `1.1` and `1.2` are retroactive: both migrations were applied to `main` before this
versioning mechanism existed, so `schema_version` never actually recorded them at the time — this
table is the authoritative record now. Every schema change from here on must add a row before
merging, per `docs/schema.md`'s own discipline: a query written against an earlier assumption must
have a version to refuse against, not degrade silently into a null or a zero (#51 part 1).

For out-of-band inspection (without opening a database), the exact schema text a given library
build promises is also available at compile time as `Arch_index.schema_sql : string`.

### Flat schema version history (`runner.ml`'s own 3-table shape, `Arch_index_db.current_flat_schema_version`)

| Version | Added |
|---|---|
| `1.0` | The base 3-table shape (`comment_db_meta`, `functions`, `calls`) — baseline, has been stable since introduction. |
| `1.1` | `functions.language` (optional) — roadmap Phase 1 item 1.1, threaded from `runner.ml`'s already-known `~language`/`~languages` parameter (never re-detected — the caller, `arch_index_cli`, already resolved it via `Language_registry.detect_language_roots`). |

### `bin/arch_load/arch_load.ml`'s own version history (independent constant — see the note above)

| Version | Added |
|---|---|
| `1.0` | The schema as it existed before this loader ever tracked a version — `comment_db_meta.schema_version` was never written at all until `1.1` (a third, previously undiscovered instance of #51's bug class, found and fixed alongside this table). |
| `1.1` | `functions.language` (optional NDJSON field on the `"function"` record type) — roadmap Phase 1 item 1.1. |
| `1.2` | `calls.top_reason`/`calls.top_anchor` (optional NDJSON fields on the `"call"` record type, meaningful only on a `MAY_TOP` edge) — roadmap Phase 1 item 1.4. |
