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

`decision_contract` is stamped only when decisions were supplied, so a consumer can tell
"computed nothing" from "computed nothing to report". The `decisions` table exists either way —
presence proves nothing, which is why every consumer checks whether it is **non-empty**.

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
| `1.3` | `modules.language`, `functions.language`/`functions.universe` — roadmap Phase 1 item 1.1, `SPEC-sound-callgraph.md` FR-001 ("node identity carries a language tag + internal/external universe flag") | `architecture-schema.sql` (additive columns) |

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
