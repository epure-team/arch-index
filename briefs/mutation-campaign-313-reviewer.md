# Reviewer sub-brief — mutation-campaign-313

**Date:** 2026-09-05T14:45:00+02:00
**Status: DRAFT**

Self-contained. You are not assumed to have seen anything else in this session.

## What was built

An execution layer for mutation campaigns in arch-index, on top of static targeting that already
shipped. Five vertical slices: drive and persist a campaign, derive a sound published verdict,
scope selection to a diff, produce a per-added-test defect list, and load test-invocation profiles.

Contract: `specs/mutation-campaign-313.md`. Plan and reasoning:
`briefs/mutation-campaign-313-plan.md`. Inherited operational facts:
`roster/mutation-campaign-313/task.md`. Worktree
`/mnt/ssd-external-2to/arch-index-mutation-313`, branch `feat/mutation-campaign-313`.

## Audit these first, in this order

1. **The verdict derivation.** The single place where engine status and selection provenance become
   a published verdict. This is the correctness core and the reason the task took the critical
   route.
2. **The four table definitions and their constraints**, in the schema migration.
3. **`arch-mutants run`'s argument handling**, in `bin/arch_mutants/arch_mutants.ml`.
4. **The wrapper that resolves `MUTAML_MUTANT`** to a per-mutant test set.
5. **Every new tezt case in `tezt/tests/mutants.ml`**, against the reachability rule below.

## What to verify, and how each can fail silently

**A survivor must never be published as `SURVIVED` under a bounded selection.** `proved_superset`
requires **both** a closed test cone and a soundness contract. Check that the implementation reuses
the predicate at `bin/arch_mutants/arch_mutants.ml:122` rather than recomputing a weaker one. A
recomputation that drops the contract half looks identical in every fixture whose index happens to
carry a contract.

**A kill must stay a kill regardless of provenance.** If a `KILLED` is ever downgraded because the
selection was bounded, the tool is now hiding real findings. The asymmetry is deliberate: a kill is
a proof, a survivor is not.

**The verdict and `PENDING` must be derived, never stored.** Grep the migration for a column that
could hold either. Storing a verdict means a later change to the derivation leaves old rows
disagreeing with new ones, with nothing to signal it.

**No emitter may write a status without its provenance in the same record.** `CHECK-7` greps for
this; verify the grep actually covers every emitter rather than the one the author remembered.

**Attribution must never be inferred.** A `mutant_kills` row may exist only when the executed set
was a singleton or the engine named the killer. An implementation that writes a row whenever a
mutant was killed and the executed set was small is wrong in exactly the way that produces a
confident, false answer to the deleted-test rule.

**Total matches, no catch-all.** Wherever a schema `CHECK` declares a closed vocabulary, the OCaml
consumer must match totally. A `| _ ->` there means the next value added to the column is dropped
with no error at all — no crash, no log, only a smaller answer. Precedents in this repository:
`top_reason = 'ambiguous_unit'` at schema 1.9, `form = 'inferred_bind'` at 1.8.

**Exit code 3 means refused, not failed.** Check that a subprocess returning 3 is not folded into
an error or into an empty result.

**Each of CHECK-4's three arms must be reachable and red-verified separately.** Removing the
expected verdict from one arm must fail that arm and no other. A three-arm assertion over a fixture
that can only produce one arm passes while checking a third of what it claims — this happened in a
peer's gate the same day, where a closed-cone fixture made the branch every real index produces
unreachable by the test that claimed to cover it.

**No mutation score, ratio, percentage or threshold**, anywhere, including in prose.

**No number without its corpus, its commit and its build state.** One quantity was derived three
times in a day at 78.5 %, 6.7 % and 3.1 %, all three correct, because the rate measured which units
had been compiled.

**No zero without what would have made it non-zero.**

## Risks the plan named, to confirm were handled

- alcotest addresses tests by group regex plus index, never by exact case name, so a
  `group`-granularity profile re-runs a whole group per mutant. Slice 1's exit criterion is a
  measured pilot run. **Verify the measurement exists and names its corpus** — if selection is not
  cheaper than the naive path, that must be reported, not omitted.
- The `mutants` key probe must count **rejected inserts** under the UNIQUE constraint, not run a
  `GROUP BY … HAVING count(*) > 1`. The latter is the locally obvious pattern, at
  `bin/arch_body_compare/arch_body_compare.ml:82`, and it is the wrong one: under a constraint a
  duplicate never becomes a group.
- The key probe must also say **what its population is made of**. A key can be perfectly
  discriminating and still measure a fabricated population.
- Slice 3 shells out to `arch-impact --format json` rather than extracting its logic. Confirm no
  library extraction crept in.

## Files that must not have been touched

`bin/arch_rules/arch_rules.ml`, `lib/arch_tools/arch_sel.ml`, `lib/arch_tools/arch_graph.ml`.
Verify with `git diff --stat origin/main..HEAD`. Any change there is an automatic NO-GO regardless
of quality — another session owns them.
