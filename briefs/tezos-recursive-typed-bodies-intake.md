# Intake Brief — tezos-recursive-typed-bodies

**Date:** 2026-09-15
**Status: VALIDATED**
**Type:** feature
**Trust boundary:** yes

## Goal

Fifth and final attempt in the user's existing five-iteration resolution loop.
Refine exact singleton local recursive self-heads whose RHS is exactly one
Texp_open with a Tmod_ident operand and an immediate Texp_function body. Reuse
the physically observed and stored synthetic body as MAY_ENUMERATED; never add
MUST. This is not general wrapper interpretation or 0CFA.

Actual compiler-only observations identify seven such binders, with 14 retained
callback_param self-head occurrences, in Tezos script_ir_translator and
storage_description. These occurrences are not a promise of distinct relation
gains. Retention requires independently witnessed positive gain, zero loss and
complete roster/guard/CI verification against the separately frozen PR108 state.

## Scope Boundary

Product: lib/arch_index/arch_index_cmt.ml only. Supporting: a dedicated native
Tezt file, its registration in tezt/tests/main.ml and dependencies in
tezt/tests/dune if needed; roster/tezos-recursive-typed-bodies/**; matching briefs
and spec; skills-meta/friction.jsonl; existing ignored improvement results; the
named external roadmap. Self-reference changes are conditional on exact pristine
attribution and an explicit path authorization, never threshold relaxation.

OUT:
- Mutual groups, nonrecursive locals, new structural recursion rules, alias or
  tuple patterns, multiple opens, non-path module operands, other wrappers and
  computed/aliased RHSs. Existing direct recursive behavior is preserved.
- Continuation calls and non-head uses: no ordinary local-table admission for
  the new open-wrapped shape, no early insertion, no changed binder-literal mask.
- Removal of any existing parent-to-lambda occurrence. Preserve legacy traversal
  and naming, even when a broader future semantics might choose differently.
- Qualified applications, general closure/value flow, functor substitution,
  global arity/function classifiers, certainty or CFG/effect policy changes.
- Public collector interface, schema, flat consumer, Tezos source/CMT writes,
  old baselines/checkers, held PR93, foreign worktrees and unrelated user files.

## Relevant Files

| File | Role | Key snippet |
|---|---|---|
| lib/arch_index/arch_index_cmt.ml | private recursive admission | Texp_let singleton branch; recursive_expected_body; fn_arity |
| lib/arch_index/arch_index_cmt.mli | read-only public boundary | collect_calls_from_expr has no recursive descriptor parameter |
| tezt/tests/local_recursion_targets.ml | preserved native controls | direct singleton, nested/default/optional/refutable, dropped root, flat |
| tezt/tests/open_body_targets.ml | structural open-body precedent | Tmod_ident body, storage refusal and flat compatibility |
| tezt/tests/main.ml | native registration | Local_recursion_targets.register () |
| tezt/tests/dune | test dependencies | main executable and authoritative CLI build dependencies |
| roster/tezos-local-recursion/verify.js | read-only comparator flow | counted canonical deltas plus independent witness permissions |
| roster/tezos-open-bodies/prepare-baseline.js | read-only setup precedent | frozen producer/schema, no-overwrite, neutral replay |
| docs/edge-kind-contract.md | preserved graph semantics | bounded target is not proof of execution |

## Architecture Notes

Bind the descriptor to the original inner function expression, not the outer
open and not a reconstructed copy. Its arity comes from the existing function
chain/cases rule. Keep default traversal through the original RHS and exact
Ident.same recursive scope, including nested callable contexts. Observe the
actual allocated collision-qualified root, require exactly one physical
observation and successful storage, and otherwise retain conservative TOP.

The descriptor is invocation-only and private to rich processing. No new
binding_literals entry and no new local_lam_stamps entry may be introduced for
open-wrapped binders: either would change predecessor facts outside the selected
self-heads. A design agent suggested both; root rejected them against the
preservation contract before implementation. Keep parent occurrences,
continuations, escapes and all public flat output unchanged.

Count supplied Some arguments, preserve result-arrow partiality and the existing
single returned-call residual rule, including conservative legacy hidden-arrow
residuals. Preserve caller/CFG/exceptions/channels/effects and all non-call shape
facts. Native witness must establish artifact, binder/group, path-open shape,
physical root/allocation ordinal, caller, full application range and arity;
candidate SQL must not teach the witness the target. Duplicate indistinguishable
groups require full agreement and single-use occurrence capacities.

This new version explicitly extends the constructor-exclusion boundary in
specs/tezos-local-recursion.md FR-002/AC-7 for this exact single path-open only;
the historical spec and its negative computed-wrapper tests remain unchanged.
No shared entity definition is silently redefined.

Baseline setup completed before product changes: full 340/340 guard exit0 in
297880ms; product SHA22473f70e669c7850284b666fc746e9e4d2364a2fc905458675f9e1105c48519.
Distinct attempt5-baseline-v2 creation and copied predecessor replay exit0 reproduce
45052 rows, digest082bdce92c6cab7b654f87a90db59ca9979d7004f45a42997a33718f6cd7c67a,
Irmin4849/protocol12157. Producer SHA48f1412002321dca745040a70f00f04c440fb4086d61bc2efb09482cc1af2136.
All410 hashes and source state stayed unchanged; disposable selections/replay
artifacts were cleaned. This is neutral setup, not a fifth retained gain.
The initial attempt5-baseline was invalidated as an immutable package because
unsealed WAL allowed a subsequent SELECT to checkpoint and change its main hash.
It is retained for audit, never rehashed into acceptance. V2 checkpoints staging
and uses DELETE journal mode before hashing; complete SQL data/schema equality
across sealing and writable-SELECT byte stability on a disposable copy pass.
V2 provenance SHAd05dc367bd0ad8db2c1f63939cb85431a19830caa6cf04caa332a6e1b2f97182;
DB SHAc45f4d08cafaaa764b32fc092609ad7d44b52edd2bc7bc17fae1e27fd4754198.

Task-text trust heuristic matched authorization/evidence vocabulary (actual
exit0). Conservatively retain yes: the spec will freeze the native-evidence
admission boundary. No runtime authentication change is implied. Full feature
mode applies regardless. KB, project claims reconciler and managed context are
absent; no generated claims projection is trusted or fabricated.

Routine Type/Trust/scope approval is exercised under the user's explicit standing
autonomy, renewed by the latest continue instruction. No fresh interactive answer
or comprehension quiz is claimed. Material scope expansion still requires input.

## Quality Gates

```sh
opam exec -- dune build
opam exec -- dune exec tezt/tests/main.exe -- --no-color
node scripts/review-bundle-verify.js
git diff --check
node roster/tezos-recursive-typed-bodies/prepare-baseline.js --check
```

Formatter/full lint/coverage not configured, not claimed passing. Task-native
admission/refusal, non-vacuous preservation, independent witness/capacity and
fixed410 comparison commands are spec/implementation deliverables. They must be
runnable before product edits, with real assertion RED distinct from setup
errors. Serialize builds/checks against source/report/git writes. Required CI
must be green on the exact PR head before guarded rebase merge.

## Open Questions

None in this contractual boundary. Detailed test/witness decomposition belongs
to the forthcoming spec and plan, not permission to broaden the feature.
