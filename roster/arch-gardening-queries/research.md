# Research — arch-gardening-queries

_Generated: 2026-07-08. Mode: full (inline reads). Online: disabled._

## Q1: exact DDL + views

- `unsafe_params` (:125-137): FK `function_id`→functions (CASCADE), `param_name`, `current_type`, `target_type`, `fixed` BOOL default 0, `fixed_at`, `github_issue`; `UNIQUE(function_id, param_name)`; partial index on `fixed=0`.
- `coverage` (:140-152): FK `function_id`, `covered_lines`, `total_lines`, **`percentage` GENERATED STORED** (0 when total=0), `recorded_at` default now; `UNIQUE(function_id, recorded_at)` (history-keeping — repeated loads at different timestamps accumulate); partial index percentage<50.
- `gardening_tasks` (:155-168): `github_issue UNIQUE`, `category` NOT NULL ('split-file'/'type-safety'/'coverage'/…), `title`, FK target_module_id/target_function_id (SET NULL), `status` default 'open' ('open'|'in_progress'|'done'), created/completed timestamps.
- `gardening_log` (:171-180): date NOT NULL, contributor, category NOT NULL, description NOT NULL, pr_number, issue_number.
- Views: `v_unsafe_params` (:256 — unfixed only, joined to fn/module, ordered); `v_low_coverage` (:265 — <50 hardcoded, ASC); `v_open_tasks` (:311 — counts+issue list per category).
- All joins require functions.module_id + modules — **main-schema only**.

## Q2: arch-load conventions

NDJSON line stream → Yojson parse per line; malformed/missing `kind` → ABORT exit 2; zero call edges → ABORT exit 2 unless `--allow-empty` (observed in item-3); DROPs and recreates its own flat tables (`schema_ddl`, arch_load.ml:94-104) — NOT suitable shape for loading into an existing main-schema DB; stamps `callgraph_contract` meta; summary line to stdout.

## Q3: effects/sidecar loader conventions (load into EXISTING DB)

`lib/arch_effects/effects_db.ml:98-125`: guard statements `CREATE TABLE IF NOT EXISTS` + `CREATE UNIQUE INDEX IF NOT EXISTS` + prepared `INSERT OR IGNORE`, per-record validation with skip/abort counts, final `N written, M skipped` summary on stderr/stdout, exit 2 on malformed input records. Binaries in `bin/arch_effects_load/`, `bin/arch_sidecar_load/` with top-level wrapper scripts.

## Q4: sibling population practice

miaou schema (:88-144) mirrors this DDL (same lineage); rows inserted manually via sqlite3 (curation), `fixed`/`github_issue` updated by humans; octez `unsafe_params` same (its `unsafe-strings` QUERY is independent of the ledger). Nothing populates `coverage` automatically in either sibling (0 rows observed in octez live DB per earlier exploration).

## Q5: house conventions (current stack tip)

Health-branch helpers `hq_has/hq_tbl/hq_refuse/hq_num` (column-level xinfo detection, exit 3 guidance, RAW_A threshold validation); exit taxonomy 0/1/2/3; deterministic ORDER BY incl. inside aggregates; selftest-health.sh main-schema fixture pattern (canonical DDL + INSERTs); wrapper-script binary resolution; Alcotest suites in test/; loaders exit 2 on malformed NDJSON.

## Patterns found

| Pattern | File | Lines |
|---|---|---|
| load-into-existing-DB (IF NOT EXISTS + INSERT OR IGNORE) | lib/arch_effects/effects_db.ml | 98-125 |
| health-branch helpers | arch-query | ~510-530 |
| main-schema selftest fixture | selftest-health.sh | 15-31 |
| coverage history via UNIQUE(function_id, recorded_at) | architecture-schema.sql | 140-152 |

## Coverage gaps

- `coverage.function_id` is FK-by-id: a loader ingesting by function NAME must resolve ids (name→id ambiguity on duplicates: resolve via module path when provided).
