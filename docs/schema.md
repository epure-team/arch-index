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
