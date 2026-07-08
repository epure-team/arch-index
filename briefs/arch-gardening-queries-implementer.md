# Implementer Brief — arch-gardening-queries

**Status:** VALIDATED. Contract: specs/arch-gardening-queries.md (FR-001..011). Plan decisions binding (stamp format, rollback-all, exactly-one resolution, helper hoist, doc-SQL extraction).

## Setup
`git checkout feat/arch-health-queries && git checkout -b feat/arch-gardening-queries`; baseline green.

## Slices
A. Hoist hq_has/hq_tbl/hq_refuse/hq_num/hq_like to script level in `arch-query` (verify health branch still green); add branches:
   - `low-coverage [N=50]`: `SELECT m.path, f.name, c.percentage, c.covered_lines, c.total_lines FROM coverage c JOIN functions f ... JOIN modules m ... WHERE c.recorded_at = (SELECT MAX(recorded_at) FROM coverage c2 WHERE c2.function_id = c.function_id) AND c.percentage < N ORDER BY c.percentage ASC, f.name` (needs coverage+functions.module_id+modules → else refuse).
   - `gardening open|log` (default open; other args exit 2): open → tasks status != 'done' LEFT JOIN modules for target path, ORDER BY category, id; log → gardening_log ORDER BY date DESC, id DESC.
   - `unsafe-params [unfixed|fixed|all]` (default unfixed; else exit 2 on unknown): join functions+modules; show fixed col only for `all`.
   - Header docs. Selftest fixture: coverage 2 snapshots for tiny_fn (30→80) + one low fn; tasks open/in_progress/done; unsafe_params fixed 0/1; assertions per spec US-1.
B. `bin/arch_coverage_load/arch_coverage_load.ml` (+dune, public_name arch_coverage_load; wrapper `arch-coverage-load`): args `--db DB [--stamp TS]`; stamp regex `^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$`; read NDJSON stdin; record `{"type":"coverage","function":str,"module":str?,"covered_lines":int>=0,"total_lines":int>=0}` with covered<=total; unknown type field → malformed; resolution: `SELECT f.id FROM functions f JOIN modules m ON f.module_id=m.id WHERE f.name=? [AND m.path=?]` — exactly 1 row → insert, 0 or >1 → skip+warn+count; INSERT OR IGNORE INTO coverage(function_id,covered_lines,total_lines,recorded_at) — changes()=0 → ignored++; BEGIN before first insert, COMMIT at EOF, malformed anywhere → ROLLBACK + exit 2 (no summary); summary `arch-coverage-load: N written, M skipped, K ignored`; exit 3 when functions/modules/coverage tables absent (xinfo/sqlite_master probe); exit 2 usage/nonexistent db. Tests: test_arch_coverage_load? — loader logic in a lib? Keep binary thin + testable core in `lib/arch_coverage/` (mirrors arch_compare pattern) with Alcotest suite (parse/validate/resolve semantics against :memory: DB).
C. `docs/curation-workflow.md` with `<!-- selftest:begin -->` fenced sql blocks `<!-- selftest:end -->` (INSERTs for the 3 ledgers using SELECT-based function lookup); selftest awk-extracts and executes them, failing if extraction yields 0 statements; README bullet + CI: package arch_coverage_load, chmod wrapper.

## Gates
dune build/test + all selftests (contract/load/mcp/health) + metrics self-gate. selftest-effects excluded (pre-existing).

## Do NOT
Schema changes; write subcommands; tool-specific coverage adapters; MCP tools.
