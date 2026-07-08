# Research — arch-health-queries

_Generated: 2026-07-08_
_Mode: full (inline reads; subagent budget exhausted)_
_Online research: disabled_

## Q1: lib/arch_index/arch_index_compare.ml

**Finding:** Already present (epure lineage) and **wired into the library**: `arch_index.ml:533` re-exports it (`module Arch_index_compare = Arch_index_compare`). API (`arch_index_compare.mli`): `compare_bodies : Sqlite3.db -> project_root:string -> string -> result` — looks up ALL functions with an exact name, reads source lines via DB `line_start/line_end` + module path, normalizes whitespace (strip/drop-blank/rejoin), groups by hex MD5 digest; returns `Not_found | Identical of occurrence list | Differs of (digest * occurrence list) list`. **Per-name only — no global duplicate-groups scan.** Needs source files on disk (reads them at query time), DB gives ranges/paths. No CLI or binary invokes it today (only `arch_index_git.ml:54` shares the normalization). This repo also already vendors `language_registry.ml`, `ts_enricher.ml`+`ts_shim.js`, `arch_index_git.ml` — relevant to roadmap item 4.

## Q2: existing health views/columns in architecture-schema.sql

**Finding:** `v_large_files` (:233, lines>500), `v_large_functions` (:240, line_count>50), `v_undocumented` (:248, intent IS NULL AND exposed=1), `v_most_called` (:274, HAVING>5), `v_high_deps` (:356, dep_count>10), plus `types`/`type_fields`(:with field_name, field_type, position)/`type_constructors`/`type_usage`. **No arch-query subcommand reads any v_ view today** (grep: zero references). `type_fields` is populated by the LSP/enricher path (`arch_index.ml:181` INSERT). Thresholds are baked into view definitions (not tunable).

## Q3: octez health commands (tools/arch_query.ml)

- `type-search` (:372-421): `--field`/`--field-type` repeated flags; conditions `t.id IN (SELECT type_id FROM type_fields WHERE field_name LIKE '%…%')` (NOTE: **sprintf-interpolated**, not bound); AND-combined; errors if no flag; output = module.type + GROUP_CONCAT of `field: type`.
- `duplicates` (:423-449): **signature-based**, not body-hash: `GROUP BY f.name, f.signature HAVING count(DISTINCT module_id) > 1` — same name+signature in >1 module.
- `large-files`/`large-functions` (:~500): threshold via `--min` flag (defaults 500/50).
- `missing-docs` (:520): exposed functions without doc. `missing-mli` (modules.has_mli=0 — octez schema only). `god-modules` (:550): modules with `> min_fns` functions (default 30).
- `unsafe-strings` (:562-575): `SELECT field_name, COUNT(*), GROUP_CONCAT(DISTINCT module.type) FROM type_fields WHERE field_type='string' GROUP BY field_name HAVING cnt >= 3 ORDER BY cnt DESC` — repetition rule = same field NAME with string type in ≥3 types. **Pure query over type_fields — the octez `unsafe_params` table is a separate curated/gardening ledger (fixed/github_issue tracking), populated manually**; miaou's schema (:88-101) is the same curated-ledger shape (param_name, suggested type, fixed flag). The *query* needs no table; the *ledger* is curation.

## Q4: unsafe_params modeling

**Finding:** two distinct things in the siblings: (a) the **query heuristic** (octez `unsafe-strings`, pure SELECT over type_fields, ≥3 rule); (b) the **curated ledger table** (`unsafe_params` in octez/miaou with `fixed`, `github_issue` columns — populated by humans/gardening flows, not by the indexer). Nothing populates (b) automatically in either repo.

## Q5: signature/body data per ingest path

**Finding:** main schema has `functions.signature` (LSP path populates; CMT enricher partially); **flat NDJSON schema has no signature column** (functions = name/file_path/exported only), so signature-duplicate queries are main-schema-only → feature-detect. No path stores body text or hash in the DB — `compare_bodies` reads sources at query time using `line_start`/`line_end` (absent in flat schema too). `type_fields` only populated on enriched main-schema DBs.

## Q6: house style for query additions (items 1–2 branches)

**Finding:** bash `arch-query` case-branch + `q`/`qraw`; feature-detect via `pragma_table_xinfo`/`sqlite_master` with exit-3 refusal or silent omission per spec; exit codes 0/1/2/3; bound params in OCaml (arch_mcp), interpolation-with-quote-strip in bash (pre-existing); limit+1 truncation pattern (arch_mcp); header comment block documents each subcommand; Alcotest suites in test/; selftest-*.sh for e2e; metrics gate must be regenerated when tracked metrics change (`metrics-baseline.json` + ADR 002 procedure).

## Patterns found

| Pattern | File | Lines | Notes |
|---|---|---|---|
| per-name body-hash compare | lib/arch_index/arch_index_compare.ml | all | exposed but CLI-less |
| signature-duplicates SQL | octez arch_query.ml | 423-449 | GROUP BY name,signature HAVING >1 module |
| unsafe-strings heuristic | octez arch_query.ml | 562-575 | ≥3 same-named string fields |
| type-search AND-composed subselects | octez arch_query.ml | 372-421 | LIKE per field/type |
| threshold flags | octez arch_query.ml | ~500,550 | --min with defaults 500/50/30 |
| health views (unused) | architecture-schema.sql | 233-362 | thresholds baked in |

## Coverage gaps

- None blocking. Note: adding new *tracked* metrics later (e.g. duplicate_groups) would touch the metrics gate direction table — out of this item unless specced.
