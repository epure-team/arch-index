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

## Additional tables

`types`, `type_fields`, `type_constructors` — indexed type definitions.
`module_deps` — import/open dependencies between modules.
`type_usage` — function-level type usage tracking.

See [`architecture-schema.sql`](../architecture-schema.sql) for full column definitions, indices, and triggers.
