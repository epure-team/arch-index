# Intake Brief — arch-health-queries

**Date:** 2026-07-08
**Status:** VALIDATED (autonomous mode — user pre-authorized gate decisions)
**Type:** feature

## Goal

Add a code-health query pack to arch-index, consolidating the health surface the sibling repos each reinvented: (1) duplicate-function detection — a global signature-duplicates query (octez shape) plus a per-name body-hash comparison CLI over the already-vendored `Arch_index_compare.compare_bodies` (currently library-only, no consumer); (2) an `unsafe-strings` heuristic query (string-typed fields repeated ≥N times across types → newtype candidates); (3) `god-modules` / `large-files` / `large-functions` / `missing-docs` queries with tunable thresholds; (4) `type-search` — find types by field names and/or field types. All as new `arch-query` bash subcommands over the existing schema, read-only, feature-detected.

Value: the health views in the schema exist but nothing consumes them; the siblings prove agents/reviewers use these queries constantly. This closes roadmap item 3.

## Scope Boundary

OUT of scope:
- The curated `unsafe_params` **ledger table** (octez/miaou gardening ledgers with fixed/github_issue tracking) — that is item 5 territory; this item ships the *query heuristic* only.
- Mutable-state tracking (subsumed by the effects layer — deliberate non-goal from the roadmap synthesis).
- New indexer/collection work — no schema changes, no new columns; queries feature-detect and refuse/omit.
- Adding new *tracked* metrics to the metrics gate (e.g. duplicate_groups) — would change gate semantics; noted as follow-up.
- MCP exposure of these queries (natural follow-up on item 2's registry; not here).
- missing-mli (octez-specific column `has_mli`; main schema stores it but only OCaml-LSP populates — include ONLY if trivially feature-detectable; spec decides).

## Relevant Files

| File | Role | Key snippet |
|---|---|---|
| `arch-query` | add case branches + header docs | house style: feature-detect + exit 3 refusal; `q()/qraw()`; `${1:-default}` threshold args |
| `architecture-schema.sql:233-362` | existing views (v_large_files, v_large_functions, v_undocumented, v_most_called, v_high_deps) — thresholds baked in; queries should parameterize thresholds directly on tables instead | `WHERE lines > 500` |
| `lib/arch_index/arch_index_compare.ml{,i}` | `compare_bodies db ~project_root name` → Not_found / Identical / Differs (MD5 of normalized body, reads sources at query time) | re-exported at `arch_index.ml:533`; zero consumers |
| `~/dev/octez-manager/tools/arch_query.ml:372-575` | reference SQL: type-search (:372, AND-composed subselects — but sprintf-interpolated, must be parameterized here), duplicates (:423, GROUP BY name,signature HAVING >1 module), missing-docs (:520), god-modules (:550), unsafe-strings (:562, ≥3 rule) | |
| `test/` + selftest scripts | Alcotest + e2e conventions | |
| `bin/` layout + `arch-compare` wrapper | convention for the new body-compare CLI binary | |

## Architecture Notes

- **Schema reality (research Q5):** flat NDJSON DBs have no signature/line ranges/type_fields/modules — every health query must feature-detect (xinfo/sqlite_master) and refuse with exit 3 + guidance (arch-query convention) when its source tables are absent. Signature-duplicates and type-search are effectively main-schema-only.
- **Duplicates, two levels:** (a) `duplicates` subcommand = pure SQL signature-groups (cheap, DB-only); (b) `compare-bodies <name>` = new small OCaml CLI (`bin/arch_body_compare/` or similar + top-level wrapper) invoking `Arch_index_compare.compare_bodies` with `--project-root` (needs sources on disk — document that). Rationale: the library exists, is epure-proven, and has zero consumers today.
- **Thresholds:** positional/flag args with octez defaults (500/50/30, unsafe ≥3), following the `fan-in [N]` convention (`${1:-25}`).
- **god-modules:** main schema groups by `module_id`; if modules table absent, fall back to `file_path` grouping when that column exists; else refuse.
- **Parameterization:** bash arch-query historically interpolates sanitized args; keep that convention for thresholds (integers — validate numeric) but sanitize LIKE inputs as existing branches do. Do NOT copy octez's raw sprintf of user strings without the quote-strip sanitizer.
- Branch base: `feat/arch-mcp-server` (stack continues; items 1–2 unmerged).

## Quality Gates

```bash
opam exec -- dune build
opam exec -- dune test
./selftest-contract.sh && ./selftest-load.sh && ./selftest-mcp.sh
# (selftest-effects.sh: pre-existing failure, excluded)
```

## Open Questions

- [ ] Include `missing-mli`? (Only if `modules.has_mli` exists in this schema — verify; spec decides include/drop.)
- [ ] `duplicates` output: include signature text (octez truncates at 70 chars) — spec fixes the exact output columns.

_(Delegated to spec; implementers must not assume.)_
