# Implementer Brief — arch-health-queries

**Status:** VALIDATED
**Contract:** specs/arch-health-queries.md (FR-001..015). Plan: briefs/arch-health-queries-plan.md.

## Setup

`git checkout feat/arch-mcp-server && git checkout -b feat/arch-health-queries`. Baseline gates green first.

## Slices

A. Six health branches in `arch-query` + `selftest-health.sh` (main-schema fixture built inline from architecture-schema.sql DDL; flat DB for refusal cases). Column-level detection requirements:
   - large-files: modules.lines; large-functions: functions.line_count (xinfo! generated col); god-modules: modules+module_id join, else functions.file_path fallback, else exit 3; missing-docs: exposed/exported col + intent col; missing-mli: modules.has_mli; unsafe-strings: type_fields.
   - Thresholds `^[0-9]+$` else exit 2. Empty results exit 0. Deterministic ORDER BY. Header doc block entries.
B. `duplicates` (name+signature groups, non-empty sigs, HAVING count(DISTINCT module)>1, sig truncated ~70) + `type-search <field|-> [type]` (AND-composed LIKE with escape helper: sed 's/[\\%_]/\\\\&/g' style + ESCAPE '\\'; ≥1 real value else exit 2; requires signature/type_fields cols else exit 3).
C. `bin/arch_body_compare/arch_body_compare.ml` + `dune` (libraries arch_index sqlite3) + top-level `arch-body-compare` wrapper (copy arch-compare wrapper shape). CLI: `--db DB --project-root DIR NAME`; verdicts IDENTICAL/DIFFERS/NOT FOUND; sort Differs groups by digest; flag occurrences where `not (Sys.file_exists (root/path))` or body="" as `(empty body — source missing?)`; exit 0 verdict / 1 not-found / 2 usage / 3 when DB lacks line_start/line_end/modules path data (probe via xinfo). Verify the library's SQL uses a bound param for the name (FR-014) — if not, fix in library with .mli unchanged. `test/test_arch_index_compare.ml`: tmpdir project with two identical + one differing copy of a function, missing-file case, not-found case.

## Gates

```bash
opam exec -- dune build && opam exec -- dune test
./selftest-contract.sh && ./selftest-load.sh && ./selftest-mcp.sh && ./selftest-health.sh
```

## Do NOT

- No schema changes, no metrics-gate changes, no curated unsafe_params ledger, no MCP tools, no library rewrite of arch_index_compare (only the bound-param fix if needed).
