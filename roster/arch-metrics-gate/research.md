# Research — arch-metrics-gate

_Generated: 2026-07-08_
_Mode: full (3 specialists: locator/haiku, analyzer/sonnet-tier, pattern-finder/haiku)_
_Online research: disabled (no external-context questions)_

## Question 1: How is the `arch-query` CLI structured — subcommand registration, argument parsing, conventions?

**Finding:** `arch-query` is a standalone **Bash script**, not OCaml — a thin SQL front-end over SQLite. Invocation contract: `arch-query <db> <subcommand> [args]`; DB path and subcommand are shifted off, up to two remaining args captured as `A`/`B` and sanitized by stripping single quotes. Subcommands are branches of one `case "$CMD" in … esac` dispatch with `*)` → `unknown subcommand`, `exit 2`. Conventions per branch:
- Helpers `q()` (`sqlite3 -box` boxed output) and `qraw()` (raw, error-swallowing) run all SQL.
- Feature detection: branches probe `pragma_table_info`/`sqlite_master` and refuse with `exit 3` + guidance if a required migration table is missing.
- Schema dualism: branches detect "flat" callgraph schema (`calls.caller_name` TEXT) vs "main" schema (`calls.caller_id` FK) and pick SQL accordingly.
- Soundness gate: `require_contract` enforces ⊤-marking (meta flag + valid `kind` values), `exit 3` on unsound DBs.
- The header comment block (lines 1–57) is the de-facto usage doc.
- The separate OCaml indexer CLI uses cmdliner (`bin/arch_index_cli/arch_index_cli.ml:34-68`) — that is the repo's OCaml-CLI convention.

**References:**
- `arch-query:58-63` — arg shifting, `set -euo pipefail`, `q`/`qraw`
- `arch-query:65-94` — contract detection + `require_contract`
- `arch-query:96-494` — `case` dispatch (all subcommands); `:493` unknown → exit 2
- `bin/arch_index_cli/arch_index_cli.ml:34-68` — cmdliner convention

## Question 2: Machine-readable output formats and serialization helpers

**Finding:** Four formats in use: (1) **NDJSON** on stdout from effect/callgraph producers, piped to loaders; (2) **JSON via Yojson.Safe** in OCaml (`comment_parser.ml:269` serializes violator lists); (3) **boxed text tables** via `sqlite3 -box` (default for all arch-query subcommands); (4) plain rows via raw sqlite3 for piping/diffing. No arch-query subcommand currently emits JSON.

**References:**
- `arch-query:62` — `q() { sqlite3 -box "$DB" "$1"; }`
- `lib/arch_index/comment_parser.ml:269` — `Yojson.Safe.to_string`
- `selftest-load.sh:15-26` — NDJSON function/call record shapes
- `selftest-effects.sh:146-149` — NDJSON effect records

## Question 3: Aggregate statistics currently computed/stored

**Finding:** Per-row structural data is stored; aggregates are derived via views and the `stats` subcommand. **No persisted metrics-summary table exists.**
- Stored: `modules.lines` (per-module LOC, `architecture-schema.sql:11`, populated via `arch_index_line_counter.ml:10-114`); `functions.line_count` as a `GENERATED ALWAYS AS (line_end - line_start + 1) STORED` column (`:30`).
- Views: `v_most_called` (fan-in, `HAVING caller_count > 5`, `:274-281`), `v_callers`/`v_callees` (`:284-308`), `v_high_deps` (module dep fan-out `>10`, `:356-362`), `v_large_files` (`lines > 500`, `:233-237`), `v_large_functions` (`line_count > 50`, `:240-245`), `v_undocumented` (`:248-253`), `v_low_coverage` (`:265-271`), `v_open_tasks` (`:311-316`).
- `stats` subcommand (`arch-query:138-146`): contract status + counts of functions/exported/calls; edge counts by kind if `kind` exists; effect-row counts if `function_effects` exists.
- `fan-in` subcommand (`arch-query:134`): `count(DISTINCT caller_name)` grouped by callee.
- `lib/arch_index/arch_index_compare.ml:8-13` does duplicate-body detection, unrelated to metrics.

## Question 4: octez-manager `cmd_metrics` / `cmd_compare` / `.metrics-accept`

**Finding — cmd_metrics** (`tools/arch_query.ml:614-734`): scalar-SQL helpers `get`/`geti` (exit 1 on SQL error), collecting a fixed name/value list: `modules, total_functions, exposed_functions, documented_functions, doc_coverage_pct (1-decimal), total_types, record_fields, variant_constructors, duplicate_groups, large_files, large_functions, missing_docs, missing_mli, god_modules (>30 fns), unsafe_string_fields, mutable_fields, functions_with_mutables, atomic_usages`. Hand-serialized **flat JSON object**, `-o FILE` or stdout.

**Finding — cmd_compare** (`:893-916`): delegates to `Arch_compare`: loads `.metrics-accept` from CWD, parses baseline + current JSON, `evaluate`, optionally attaches per-item detail lines (max 10, `:747-884`), prints report, `exit 1` if `has_failures`.

**Finding — arch_compare.ml engine:**
- Direction sets: `worse_when_higher` (9 metrics) and `worse_when_lower = ["doc_coverage_pct"]` (`:47-60`); untracked metrics ignored (`:73`).
- JSON via Yojson, flat `{key: number}` only (`:87-97`).
- `compare_metrics` (`:248-292`): classify regression/improvement/unchanged per direction; `missing` = tracked metrics in baseline absent from current.
- `.metrics-accept` (`:109-243`): line format `<metric> <op> <bound>` + reviewable reason. Op must be `<=` for worse-when-higher, `>=` for doc_coverage_pct (`:75-76`). Comments: blank line clears pending `#` comment block; reason priority = inline `#` > trailing text > preceding comment block (`:191-201`). Invalid entries: untracked metric, bad bound/op, missing reason (`:202-236`).
- `evaluate` (`:303-319`): a regression is accepted only if an entry exists AND current is within the reviewed bound (`acceptance_covers`, `:299-301`); else blocking.
- `has_failures` (`:461-464`): any blocking regression OR missing tracked metric OR invalid accept entry. `render_report` (`:382-459`): baseline table, blocking, missing, improvements, accepted (bound+reason), invalid, final OK/FAILED.
- Baseline documented in waiver header as a committed JSON; default policy = empty acceptance (`octez-manager/.metrics-accept:1-23`).
- cmdliner wiring `:1055-1084` (baseline/current positionals). Standalone `arch_compare.ml` has its own Alcotest suite (`test_arch_compare.ml`).

## Question 5: epure metrics/compare + pre-commit integration

**Finding — compare** (`tools/arch_query_impl.ml:832-943`): simpler than octez. `.metrics-accept` is **name-only** (first token; no bounds/reasons — listing a name unconditionally waives, `:802-823`). Regex-based JSON parsing (`:776-794`). Direction lists include `comment_quality_pct` in worse-when-lower (`:446-469`); 0.5 float tolerance (`:840`).
- **Hard floors** (`:825-830`): `comment_quality_pct >= 70.0` — floor violations block and CANNOT be waived; lowering requires ADR + code change (`:898-910`).
- Report sections: HARD FLOOR VIOLATIONS / REGRESSIONS (CI will fail) / Improvements / Accepted regressions. `exit 1` on any floor violation or blocking regression (`:934-937`).

**Finding — pre-commit** (`scripts/pre-commit:84-108`): baseline is `metrics-baseline.json` at repo root, **read from `git show HEAD:…`** — never the working tree — so a commit that loosens the baseline cannot bypass the check (`:85-92`); missing-in-HEAD → check skipped (`:106-107`). Flow: rebuild index → `metrics -o tmp` → `compare baseline tmp`; each sub-step wrapped with a specific ERROR + `exit 1`; `mktemp` + `trap EXIT` cleanup; git env vars unset around dune (`:5,7-16`).

## Question 6: aegis-cloth baseline JSON structure

**Finding:** metadata + per-component stats + thresholds:

```json
{
  "generated_at": "2026-06-20T00:00:00Z",
  "arch_index_path": "...",
  "backend":  { "index_db": "...", "index_status": "ok",
                "stats": {"functions":137,"exported":137,"call_edges":0},
                "loc_violations": [{"file":"backend/lib/router.ml","loc":1177}],
                "top_callers": [] },
  "frontend": { "...": "same shape" },
  "thresholds": { "max_file_loc": 500,
                  "loc_violation_count_baseline": 3,
                  "max_fan_in_growth_pct": 20 }
}
```

Semantics: `max_file_loc` = hard per-file LOC cap feeding `loc_violations`; `loc_violation_count_baseline` = tolerated violation count; `max_fan_in_growth_pct` = allowed fan-in growth per cycle. (Reference: `~/dev/aegis-cloth/kb/arch-metrics-baseline.json`.)

## Question 7: Golden/baseline handling, exit codes, CI integration in arch-index

**Finding:**
- Golden file: `test/fixtures/self-index-stats.txt` (plain text: `modules: 18 / functions: 148 / calls: 2455`), regeneration procedure in ADR `docs/adr/001-self-index-golden.md`, diffed in CI (`.github/workflows/ci.yml:29-42`) with `diff … || { echo "Golden file mismatch …"; exit 1; }`.
- CI: `dune build` → `dune test` (Alcotest: `test/test_parsers.ml`, `test_effects.ml`, `test_capabilities.ml`) → `./selftest-contract.sh` + `./selftest-load.sh` → golden diff → release packaging. **No Makefile, no pre-commit hooks in this repo.**
- Exit-code contract: 0 = success; 1 = failure/diff mismatch; 2 = loader ABORT on malformed input (`selftest-load.sh:40-44`) and unknown subcommand; 3 = arch-query REFUSE on unsound/missing-migration DBs (`arch-query:74-94`).
- Idempotent migrations pattern: `CREATE TABLE IF NOT EXISTS` + `CREATE UNIQUE INDEX IF NOT EXISTS` + `INSERT OR IGNORE` (`lib/arch_effects/effects_db.ml:98-125`).

## Patterns found

| Pattern | File | Lines | Notes |
|---|---|---|---|
| case-dispatch subcommand | `arch-query` | 96–494 | branch per subcommand, exit 2 unknown |
| feature-detect + refuse (exit 3) | `arch-query` | 154–158, 378–383 | probe sqlite_master before running |
| soundness gate | `arch-query` | 74–94 | `require_contract` |
| flat-vs-main schema dualism | `arch-query` | 160–211 | detect `caller_name` vs `caller_id` |
| golden diff in CI | `.github/workflows/ci.yml` | 29–42 | plain-text diff, exit 1 |
| bounds+reason waiver parsing | `octez-manager/tools/arch_compare.ml` | 109–243 | strictest reference |
| HEAD-pinned baseline | `epure/scripts/pre-commit` | 84–108 | `git show HEAD:` anti-bypass |
| hard floors (unwaivable) | `epure/tools/arch_query_impl.ml` | 825–830 | floor beats waiver |
| flat JSON metrics emit | `octez-manager/tools/arch_query.ml` | 614–734 | fixed metric list, `-o FILE` |

## Coverage gaps

- None material. All 7 questions answered from code. Note: aegis-cloth has no comparison *engine* — only the baseline data file; its thresholds are enforced manually/by agents.
