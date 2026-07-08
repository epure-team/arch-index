# Intake Brief — arch-gardening-queries

**Date:** 2026-07-08
**Status:** VALIDATED (autonomous mode)
**Type:** feature

## Goal

Activate the schema's dormant curation layer (roadmap item 5, rescoped — tables/views pre-exist): (1) read-only arch-query subcommands `low-coverage [N=50]`, `gardening [open|log]`, `unsafe-params [all|fixed|unfixed]`; (2) `arch-coverage-load` — NDJSON loader populating `coverage` in an EXISTING main-schema DB (function name+module-path resolution to ids, INSERT OR IGNORE idempotency per effects-loader conventions); (3) curation-workflow docs (documented INSERT SQL for the ledgers, matching sibling practice). No schema changes.

## Scope Boundary

OUT: write subcommands in arch-query (ledgers stay human-curated via documented SQL); coverage extraction from specific tools (bisect_ppx/istanbul adapters — the NDJSON contract is the interface); GitHub-issue sync; metrics-gate changes; MCP exposure.

## Relevant Files

| File | Role | Key snippet |
|---|---|---|
| `architecture-schema.sql:125-180,256-316` | DDL + views (see research Q1 — verbatim) | `percentage GENERATED`; `UNIQUE(function_id, recorded_at)`; `UNIQUE(function_id, param_name)`; status vocab open/in_progress/done |
| `arch-query` health branch | hq_* helpers to reuse; add branches beside them | column-level detection, exit 3 |
| `lib/arch_effects/effects_db.ml:98-125` | load-into-existing-DB pattern | IF NOT EXISTS guards + INSERT OR IGNORE + written/skipped summary |
| `bin/arch_effects_load/` + wrapper | loader binary conventions | exit 2 malformed |
| `selftest-health.sh` | fixture pattern to extend or mirror | canonical-DDL main-schema fixture |

## Architecture Notes

- All three query families join functions+modules → main-schema only → hq_refuse on flat DBs.
- `low-coverage [N]`: parameterize threshold on the `coverage` table directly (view hardcodes 50, keep 50 as default); use the LATEST record per function (`MAX(recorded_at)` — the UNIQUE(fn,recorded_at) history means naive joins double-count).
- `gardening open`: rows (id, category, title, status, github_issue, target path) status != 'done'; `gardening log`: recent gardening_log rows ordered date DESC.
- `unsafe-params [filter]`: default unfixed (v_unsafe_params semantics) with fixed/all variants; joined output with target_type + github_issue.
- Loader NDJSON record: `{"type":"coverage","function":"name","module":"src/x.ml"?,"covered_lines":N,"total_lines":N}` — resolve function_id by name (+module path when given; ambiguous name without module → skip with warning, count skipped); malformed line → ABORT exit 2 (arch-load convention); summary `N written, M skipped`. `--db` required arg. Timestamp: single run stamp (one recorded_at per invocation) so a run is one coverage snapshot.
- Docs: `docs/curation-workflow.md` — INSERT examples for unsafe_params/gardening_tasks/gardening_log, the coverage NDJSON contract, and how `unsafe-strings` (heuristic) feeds `unsafe_params` (ledger).

## Quality Gates

```bash
opam exec -- dune build && opam exec -- dune test
./selftest-contract.sh && ./selftest-load.sh && ./selftest-mcp.sh && ./selftest-health.sh
# selftest-effects.sh: pre-existing failure, excluded
```

## Open Questions

- [ ] Coverage loader binary: OCaml (`bin/arch_coverage_load/`) mirroring effects-load, vs bash+sqlite3. (Plan decides; lean OCaml — id resolution + NDJSON validation is logic.)

_(Branch: stack on feat/arch-health-queries.)_
