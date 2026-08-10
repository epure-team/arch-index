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

`decision_contract` is stamped for a completed run even when it produces zero findings.
Presence and non-emptiness prove nothing: consumers recompute canonical source-universe,
current-index, and result-row digests, require every result row to carry the current run ID,
and reject stale, mixed, replayed, or edited evidence.

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
# Completed Analysis Contracts

Decision and effect rows authorize a clean gate only with the corresponding
`*_contract=v1` metadata plus `outcome=complete`, `failures=0`, a non-negative
analyzed `universe`, and non-empty run, producer, source-digest, index-digest,
and result-digest fields. Legacy `decision_analysis` metadata and table non-emptiness are not
completion evidence. A complete run may produce zero result rows.

Decision runs populate `decision_analysis_files` and bind `decisions.analysis_run_id`.
Each analyzed file record contains its repository-relative path, content digest,
and permission mode. `arch-impact --repo` recomputes those values from the live
repository before treating even a zero-finding run as available.
Effect runs bind `function_effects.analysis_run_id` and populate
`effect_analysis_functions` with run ID, function ID, name, and module path; an effect rule is
computed only when every function in its evaluated cone is present there.
`arch-effects-load --complete` creates this evidence, while `--allow-skip` is
incompatible with completion and never stamps a complete run.
Every main-schema reindex deletes decision/effect results, universes, and
completion metadata in the rebuild transaction; producers must restamp against
the new index.

# Curation Identity

`coverage` and `unsafe_params` retain stable module-path/function-name identity
alongside nullable live IDs. Gardening targets retain the same durable identity.
Reindex snapshots all four ledgers inside the rebuild transaction, remaps
surviving symbols, and preserves removed symbols with a null live ID. Existing
databases are migrated by the corrected rebuild, which recreates the ledger
tables from their transactional snapshots.
