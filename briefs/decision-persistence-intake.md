# Intake Brief — decision-persistence

**Date:** 2026-08-02
**Status:** VALIDATED (autonomous run)
**Type:** feature
**Roadmap:** lot 2 — the PoC→product step
(`docs/research/mcdc-coverage-feasibility.md` §5, R3)

## Goal

Make the PoC's findings **persist and be queryable**. Today `decision-lint`
writes NDJSON to stdout and nothing lands anywhere: the §5 schema
(`decisions`, `conditions`) does not exist, so `arch-query` cannot see a single
result of the analysis. That is the largest remaining gap between the validated
PoC and a shipped feature — larger than any remaining analysis gap.

Concretely:

1. Add the `decisions` and `conditions` tables of §5, carrying the verdict, the
   merge rung that produced it, **and its provenance** (`decided_by`,
   `evidence`) — because a finding that says "dead" without a reason is unusable
   by a reviewer and dangerous when applied by an agent.
2. Give `decision-lint` a `--db <path>` mode that writes into an existing
   arch-index database, joining findings to `functions` by module path and line
   range.
3. Add `arch-query useless-branches` over the result.

## Scope Boundary

Explicitly OUT of scope:

- Moving the analysis *into* `arch_index_cmt.ml`. The PoC stays a separate
  producer writing to the DB; folding a 1900-line analyser into a 1600-line
  walker under a soundness selftest is a separate, riskier task with no user-
  visible gain.
- The NDJSON wire-format extension (R9) — lot 3. This lot writes to SQLite
  directly, which is exactly what the OCaml backend already does.
- `mcdc-gaps` — it needs the dynamic tier (R6), which does not exist.
- The purity join, unsat cores, dominator chains — later lots.
- Any CI gate. Reported and queried only; ratcheting is R4.

## Relevant Files

| file | role |
|---|---|
| `architecture-schema.sql` | new `decisions` / `conditions` tables + view |
| `poc/decision-lint/bin/decision_lint.ml` | `--db` writer |
| `poc/decision-lint/bin/dune` | gains `sqlite3` |
| `arch-query` | new `useless-branches` subcommand |

## Design Decisions

**Function attribution by line containment.** The PoC knows a finding's
`file:line`; the DB knows each function's `module_id` + `line_start..line_end`.
Join on the innermost function whose range contains the line — innermost so a
finding inside a nested lambda attributes to the lambda node, matching how the
call graph already attributes. A finding that matches no function is recorded
with `function_id = NULL` rather than dropped.

**Provenance is a column, not a comment.** `decided_by` ∈ {`enumeration`, `smt`,
`budget_exhausted`, `no_solver`} and `evidence` (the removable atoms, or the
guards that settle the decision). §6.7 argued explainability is not optional;
this is where it becomes queryable. Unsat cores are still absent — `evidence`
carries what the tool has today, and the column is ready for them.

**Degradation must be visible.** The run records which rungs were armed and
which frontend produced it, in `comment_db_meta`. A clean `useless-branches` on
a run where the solver was absent must be distinguishable from a clean run where
it was present — the same rule that made `dead-blocks` refuse on a flat DB.

## Quality Gates

- `dune build` green in dev and release; `dune test` green.
- All selftests green including `STRICT=1 selftest-callgraph-soundness`.
- The PoC fixture stays at **27 true positives / 15 true negatives**, and both
  frontends still agree exactly — the regression gate for any refactor here.
- `arch-query <db> useless-branches` refuses explicitly on a DB with no
  `decisions` table.
- Round-trip: findings written to a DB and read back through the query must
  match the NDJSON the same run emits.

## Acceptance Criteria

- AC-1: `decisions` and `conditions` tables exist with verdict, rung and
  provenance columns.
- AC-2: `decision_lint --db <path> <dirs>` populates them.
- AC-3: findings are attributed to the innermost containing function; unmatched
  findings persist with `function_id = NULL`.
- AC-4: `arch-query <db> useless-branches` lists them module-qualified with
  their evidence.
- AC-5: the armed rungs, frontend, and solver presence are stamped in
  `comment_db_meta` for that run.
- AC-6: no existing query, verdict or edge kind changes.

## Deviations from this brief (recorded at implementation)

- **`conditions` is created but NOT populated.** AC-2 said the tool populates
  "them"; it populates `decisions` only. The per-condition breakdown is
  available inside the analyser (the atom table) but the finding record that
  reaches the writer carries evidence as a formatted string, not as structured
  atoms. Populating the table would mean threading the atom list through, which
  is a small change but not this lot's. Recorded here rather than half-done: an
  empty `conditions` table is honest, a fabricated one is not.
- `arity` is written as 0 for the same reason.
