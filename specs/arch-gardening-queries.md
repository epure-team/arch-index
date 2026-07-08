---
name: roster-spec
type: spec
status: live
feature: curation-layer activation (gardening/coverage/unsafe-params queries + coverage loader)
brief: briefs/arch-gardening-queries-intake.md
date: 2026-07-08
version: 1.0.0
---

# Spec — arch-gardening-queries

## Clarifications

| Q | A |
|---|---|
| `gardening open` vs v_open_tasks? | `open` = `status != 'done'` (includes in_progress, with status column shown) — deliberately broader than the view; documented in docs and header. The view is untouched. |
| Latest coverage record? | Per function: row with `MAX(recorded_at)`; `UNIQUE(function_id, recorded_at)` makes ties impossible. Threshold `[N=50]` applied on that latest row. |
| Loader snapshot semantics? | One `recorded_at` stamp per invocation: `--stamp TS` optional (ISO-8601), default = current UTC time. Same stamp re-run → `INSERT OR IGNORE` dedups (reported as `ignored`); new stamp → new snapshot (history by design). |
| Loader validation? | `covered_lines`/`total_lines` must be integers ≥ 0 and `covered ≤ total`; `total=0` allowed (generated pct = 0). Violations = malformed → transaction ROLLBACK + exit 2 (nothing partially written). |
| Ambiguity resolution? | function name + optional `module` path; ambiguous name w/o module, unknown name, unknown module → skip + stderr warn + counted. |
| Doc drift protection? | selftest executes the documented INSERT examples verbatim from docs/curation-workflow.md fixtures (copy in selftest) so schema drift breaks CI. |

## User Stories

### US-1: Curation query subcommands (P0)
`low-coverage [N=50]`, `gardening [open|log]`, `unsafe-params [unfixed|fixed|all]` in arch-query.
**Scenarios**: 1) Given a main DB with 2 coverage snapshots for `f` (30% then 80%), When `low-coverage 50`, Then `f` is NOT listed (latest wins). 2) Given tasks open/in_progress/done, When `gardening open`, Then open+in_progress rows with status column; `gardening log` lists log rows date DESC. 3) Given unsafe_params rows fixed=0 and 1, When `unsafe-params` → unfixed only; `unsafe-params all` → both with fixed column; bad filter arg → exit 2. 4) Flat DB → exit 3 for all three. 5) Empty tables → exit 0 empty output.

### US-2: arch-coverage-load (P0)
NDJSON loader into an existing main-schema DB.
**Scenarios**: 1) Two valid records (one with module, one unique-name-only) → `2 written, 0 skipped, 0 ignored`, rows visible in `low-coverage 101`. 2) Ambiguous name w/o module + unknown name → both skipped with warnings, exit 0. 3) `covered > total` or negative → exit 2, NOTHING written (rollback). 4) Same file re-run with `--stamp` fixed → `0 written, N ignored`. 5) Flat DB → exit 3 refuse. 6) `--db` missing / unknown flag → exit 2 usage.

### US-3: Curation docs + selftest (P1)
`docs/curation-workflow.md`: ledger INSERT examples (unsafe_params via function lookup, gardening_tasks, gardening_log), the coverage NDJSON contract + `--stamp`, and the heuristic→ledger flow (`unsafe-strings` output feeds curated `unsafe_params` rows). Selftest extension runs documented INSERTs + all US-1/US-2 scenarios.

## Challenges (codex pass — 32 ECs; key resolutions)

| ID | Resolution |
|---|---|
| EC-22 rollback | loader runs inside BEGIN/COMMIT; abort → ROLLBACK (US-2.3) |
| EC-23/24/25 idempotency | `ignored` count for OR-IGNORE hits; `--stamp` gives deterministic re-runs; new stamp = new snapshot (history table by design) |
| EC-26/27/28 validation | covered≤total, ≥0 enforced; total=0 legal |
| EC-31 open semantics | status != 'done', documented (Clarifications) |
| EC-30/32 doc drift | documented SQL executed in selftest |
| EC-19/20/21 resolution | skip+warn+count; module path must match modules.path exactly when given |

## Functional Requirements

- **FR-001** [US-1]: arch-query MUST provide `low-coverage [N=50]` listing functions whose LATEST coverage row has percentage < N, ordered pct ASC then name, with module path, pct, covered/total.
- **FR-002** [US-1]: `gardening open` MUST list tasks with status != 'done' (id, category, title, status, github_issue, target module path when set), ordered by category then id; `gardening log` MUST list gardening_log ordered date DESC then id DESC.
- **FR-003** [US-1]: `unsafe-params [unfixed|fixed|all]` MUST default to unfixed and show module path, function, param, current→target type, github_issue (+fixed flag for `all`); invalid filter → exit 2.
- **FR-004** [US-1]: All three MUST use column-level feature detection and exit 3 with guidance on DBs lacking their tables/joins; empty results exit 0; deterministic ORDER BY.
- **FR-005** [US-2]: `arch-coverage-load --db DB [--stamp TS] < ndjson` MUST insert coverage rows resolving function_id by name (+`module` path when provided), one stamp per run.
- **FR-006** [US-2]: Unresolvable records (ambiguous/unknown name, unknown module) MUST be skipped with a stderr warning and counted; the run still exits 0.
- **FR-007** [US-2]: Malformed input (bad JSON, wrong types, negative values, covered>total, missing required fields) MUST abort with exit 2 and MUST NOT leave partial writes (transaction rollback).
- **FR-008** [US-2]: Re-runs with an identical stamp MUST be idempotent via INSERT OR IGNORE, reported as `ignored`; the summary line MUST report `written`, `skipped`, `ignored`.
- **FR-009** [US-2]: The loader MUST refuse (exit 3) DBs lacking functions/modules/coverage tables and exit 2 on usage errors/nonexistent DB.
- **FR-010** [US-3]: docs/curation-workflow.md MUST contain runnable INSERT examples for the three ledgers, the NDJSON contract, and the heuristic→ledger flow; the selftest MUST execute the documented INSERT statements.
- **FR-011** [US-3]: arch-query header and README MUST document the new subcommands and loader.

## Acceptance Criteria / Runnable Checks

- CHECK-1 [US-1]: selftest scenario: two-snapshot fixture → `low-coverage 50` excludes the improved function; `gardening open` includes in_progress; `unsafe-params` filters correctly; flat DB → exit 3.
- CHECK-2 [US-2]: pipe 2-record NDJSON → `2 written`; re-run with same --stamp → `0 written, 2 ignored`; bad record → exit 2 and `SELECT count(*) FROM coverage` unchanged.
- CHECK-3 [US-2]: ambiguous/unknown records → skips counted, exit 0.
- CHECK-4 [US-3]: documented INSERTs execute cleanly against a canonical-DDL fixture.
- CHECK-5 [all]: `dune build && dune test --force` + all selftests + metrics self-gate green.

## Edge Cases

EC-19..29 as resolved above; empty ledgers → exit 0 (EC-32); `low-coverage 0` → nothing listed (pct < 0 impossible); `low-coverage 101` → all covered functions listed (useful as "coverage report").

## Entities

- `coverage snapshot`: the set of coverage rows sharing one recorded_at stamp from one loader run.
- `latest coverage`: per function, the row with MAX(recorded_at).
- `curation ledger`: human-maintained rows in unsafe_params/gardening_tasks/gardening_log (documented SQL, no CLI writes).
- `arch-coverage-load`: NDJSON→coverage loader; transactional; skip-vs-abort taxonomy per FR-006/007.
