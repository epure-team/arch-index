# Implementer — tezos-open-bodies

**Date:** 2026-09-14
**Status: VALIDATED**
**Mode:** full

## Goal and scope boundary

Attempt3 of5, two already delivered. Resolve only same-CMT direct Pident
invocations of structural Tstr_value/Tpat_var bindings with exactly one path-only
Texp_open(Tmod_ident) immediately enclosing Texp_function, to the already existing
actual lambda body. Separate invocation context; no new MUST. Preserve all old
body/caller/CFG/effect ownership and flat behavior. Follow validated intake and
specs/tezos-open-bodies.md (implementation must read both fully).

No global is_function_rhs/local_fn_stamps widening, root peeling, local Texp_let,
nested/computed/constrained opens, alias/callback/letop/escape/qualified gains,
point-free changes, CFA, instance substitution, Tezos/schema/CLI edits, prior
verifier/witness edits or PR93. Never relax guards or self allowances.

## Files

- lib/arch_index/arch_index_cmt.ml — existing is_function_rhs,
  build_local_fn_stamps, collect_calls_from_expr, walk_function_root are the
  intake's reference snippets; do not globally widen or reparent them.
- lib/arch_index/call_graph_extractor.ml — conditional narrow preservation only;
  shared collector currently discards lambdas/effect facts.
- tezt/tests/open_body_targets.ml — new native fixtures and actual producer checks.
- tezt/tests/main.ml and tezt/tests/dune — register new native tests if necessary.
- roster/tezos-open-bodies/ — task-specific native evidence/checkers, baseline
  tooling and verification; prior task comparators are read-only reuse.
- briefs/ — this task's pipeline documents/control files only; preserve other tasks.
- specs/tezos-open-bodies.md — this task's check correspondence only.
- test/fixtures/self-index-stats.txt — conditional exact self golden refresh.
- test/fixtures/origin-consumer/reference.json — conditional exact self reference.
- test/fixtures/origin-consumer/self.allow — conditional coordinate-only move of
  an existing allowance, never a new allowance or count/threshold increase.
- checks/origin-recurring-consumer.js — conditional collateral refresh of its
  two duplicated exact reference assertions only (totals and the same sole
  allowed source assertion identity), after the same pristine attribution;
  no assertion removal, fixture-policy change or relaxed comparison.
- skills-meta/friction.jsonl — append-only task phase records.
- improvement/2026-09-14-tezos-resolution/ — owned logs/results/evidence, but
  never overwrite attempt3-baseline or older frozen baselines.
- /home/mathias/notes/2026-09-01-arch-index-roadmap.md — actual progress update.

Self reference refresh is conditional on pristine unchanged-policy source
attribution; the three reference files were frozen before edits. The duplicated
constants in the consumer check were identified by the actual full-guard failure
and added as one exact collateral path before any edit to them. The sole allowed
assertion moves with the collector's private implementation name and source
coordinates, but must remain the identical source assertion with multiplicity1.
No
additional product path is assumed. Manifest header must capture original HEAD
and dirt before baseline builds. Active task slot absent or same slug only.

## Sequential steps

1. Freeze manifest; preflight/baseline gates, then genuine native failing test.
2. Deliver narrow invocation resolution with identity, availability, arity,
   residual and flat/effect compatibility in one tested vertical slice.
3. Independent native occurrence witness and fixed410 comparison, with refusal
   controls. Require positive witnessed gain, zero old relation loss, no
   unexplained movement and no new MUST. Discard neutral owned product changes.
4. Full verification, bounded correction, commit owned round before review;
   retain unrelated seven untracked paths rather than fake global cleanliness.

## Exact quality gates

```sh
opam exec -- dune build
opam exec -- dune exec tezt/tests/main.exe -- --no-color
node scripts/review-bundle-verify.js
node roster/tezos-open-bodies/prepare-baseline.js --check
git diff --check
```

Run every runnable check frozen by the validated spec; report which actually
executed, assertion failure separately from setup errors. Baseline is45052rows,
digest00f1769d6db7f6ee91ee51becabccd7b4ce13975acb6610c95ace69a7f620e9b,
Irmin4781/protocol11730. Baseline directory attempt3-baseline is immutable.
No formatter or coverage configured, no pass claimed. Serialize source-state
checks against artifact edits and all root builds. No extra worktrees needed.

## Risks and assumptions

Both fresh voices flag body availability, exact shadow identity, optional argument
counting, overapplication residuals, flat leakage and false corpus gains. Deriving
a name is not availability. An assumption failure requiring scope expansion
returns to intake. No gain guaranteed; the181 Raw.step sites are motivation only.
Missing specialist/hooks/claims tools use documented manual fallback, not passes.
