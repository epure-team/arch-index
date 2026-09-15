# Implementer — tezos-recursive-typed-bodies

**Status: VALIDATED**
**Date:** 2026-09-15

Fifth/final attempt: resolve only singleton local recursive Pident self-heads
whose plain variable RHS is exactly Texp_open(Tmod_ident, Texp_function).
Read the validated intake and task spec fully before implementation. The goal is
positive independently witnessed distinct Tezos relations with zero loss, not
merely passing new fixtures or converting fourteen observed occurrences.

## Scope and source seam

Product edits only lib/arch_index/arch_index_cmt.ml, private Texp_let singleton
recursive admission (`recursive_expected_body`, `fn_arity`). Descriptor points
to the original inner function object. Preserve Ident.same dynamic scope and
default traversal. Reuse physical observation and successful-storage gating.
Never insert this new shape into binding_literals or local_lam_stamps; never
change continuation/non-head behavior or remove parent-to-lambda occurrences.
No new MUST. No mutual recursion, additional wrappers, non-path module operands,
aliases/tuple patterns, global classifiers, public mli, schema, flat API, effects
or CFG policy changes. Existing direct recursive behavior remains unchanged.

Supporting writes: dedicated Tezt module plus main.ml registration and dune only
if needed; roster/tezos-recursive-typed-bodies/**; matching briefs/spec; friction;
ignored improvement evidence/results; named external roadmap. Preserve unrelated
files, old baselines/checkers, Tezos sources/CMTs, PR93 and foreign worktrees.

## Execution order

1. Capture scope manifest and phase state. Build runnable compiler-only witness,
   native fixtures, immutable-v2 loader and comparator before product edits.
   Establish authentic assertion RED, not setup-error RED; witness targets must
   be independent of candidate SQL. Tests cover exact positives, neighboring
   refusals, nested callable contexts, optional/default/refutable, partial and
   overapplication/legacy hidden-arrow residuals, collisions, dropped/storage
   refused roots, and nonempty context/effect/exception/channel preservation.
2. Minimal private product admission change; run native GREEN and all refusals.
   Do not rewrite existing observation/storage/accounting machinery by default.
3. Full pinned410 candidate comparison, independent native witness, complete
   duplicate-group agreement and single-use head/residual capacities. Require
   positive distinct relations and zero losses, no unexplained rich/flat delta.
4. Run all integrated gates, document actual outcomes, scoped commit for roster
   review, then QA and exact-head CI. Never claim KEEP or merge before gates.

## Exact gates and risks

Run with rtk proxy: `opam exec -- dune build`;
`opam exec -- dune exec tezt/tests/main.exe -- --no-color`;
`node scripts/review-bundle-verify.js`; `git diff --check`;
`node roster/tezos-recursive-typed-bodies/prepare-baseline.js --check`.
Implement the task checks specified by the spec and freeze their commands before
editing product source. Serialize every build/check against all writes.
Native evidence proves semantic identity; candidate SQL proves storage only.
Real sealed baseline opens read-only. Invalid original baseline is audit-only;
never repin it. Use v2 provenance d05dc367bd0ad8db2c1f63939cb85431a19830caa6cf04caa332a6e1b2f97182
and DB c45f4d08cafaaa764b32fc092609ad7d44b52edd2bc7bc17fae1e27fd4754198.
Fourteen heads may yield zero distinct gain; do not weaken KEEP criteria.
Self-reference edits require pristine attribution and explicit path authorization.
No formatter/lint/coverage success claimed where unconfigured. No new worktree
needed. Routine phase approval uses standing autonomy, not invented quiz answers.
