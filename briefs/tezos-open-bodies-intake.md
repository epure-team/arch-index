# Intake Brief — tezos-open-bodies

**Date:** 2026-09-14
**Status: VALIDATED**
**Type:** feature
**Trust boundary:** yes

## Goal

Third bounded attempt in the approved five-attempt Tezos resolution loop:
identify the actual existing callable lambda for direct Pident applications of
structural variable bindings whose RHS is one path-only lexical open around a
literal function. Resolve qualifying ordinary invocations to that same-CMT body
without moving existing calls, changing effect ownership, or promoting new MUST.
Raw.step's181 unresolved applications motivate the slice; no gain is promised.

Validation uses the user's explicit standing autonomy for routine roster gates,
including the latest continuation. Type feature and Trust boundary yes are
accepted under that delegation, not represented as invented interactive answers.
The actual keyword check hits evidence/auth/authority in the task. Full spec follows.

## Scope Boundary

In scope: a separate invocation-only descriptor for Tstr_value/Tpat_var bindings,
exactly Texp_open with Tmod_ident followed directly by Texp_function; same-CMT
Pident head applications; syntactic arity and actual supplied argument count;
same-body identity, missing-target refusal, native evidence and regression checks.
Structural definitions include nested literal modules/functor definitions reached
by existing structure traversal; no instance-specific substitution is claimed.

Out of scope: global widening of is_function_rhs/local_fn_stamps; root peeling;
local Texp_let binding support; nested-open chains; computed/constrained module
expressions; qualified-member resolution; callback, letop, escape or alias gains;
point-free/value-alias changes; CFA; flat-format behavior changes; Tezos edits;
schema/public CLI changes; prior-task verifier/witness edits; held PR93.

Expected writable product area is arch_index_cmt.ml, with a narrowly scoped flat
consumer adjustment only if needed to preserve its existing output. Task-specific
Tezt/check/spec/brief artifacts and loop logs/roadmap are in scope. Exact self
reference refresh is allowed only after unchanged-policy pristine source/corpus
attribution; never relax assertions, allowed origin count or rule thresholds.
Freeze exact paths in the implementation manifest before product edits.

## Relevant Files

| File | Role | Key snippet |
|---|---|---|
| lib/arch_index/arch_index_cmt.ml | Rich collection, identity, arity and lambda ownership | is_function_rhs; build_local_fn_stamps; collect_calls_from_expr; walk_function_root |
| lib/arch_index/call_graph_extractor.ml | Flat fallback must preserve legacy behavior | shared collector discards lambdas/effect facts |
| tezt/tests/local_module_targets.ml | Existing identity/arity/flat regression pattern | exact SQL and standalone checker registration |
| roster/tezos-call-resolution/comparison.js | Read-only canonical multiset comparator | compareSnapshots rejects losses/unmatched changes/new MUST |
| roster/tezos-open-bodies/prepare-baseline.js | Distinct PR106 snapshot and neutral replay | --create / --check; separate immutable directory |
| roster/tezos-open-bodies/census.ml | Documentary compiler-only census | wrapped_function; same Ident.unique_name applications |

## Architecture Notes

Raw.step's binding parent has1 outgoing relation to Raw.step.<fun:639:5>, whose
body owns460 calls. New targets must use that existing body's canonical identity;
renaming/moving it is not an acceptable route. The rich path may use an explicit
new context; the flat path must not emit dangling synthetic names. The old body,
alias, callback, CFG and effect paths remain unchanged. Underapplication remains
conservative; no partial invocation may become MUST. Overapplication accounting
must retain an explicit unknown returned-call residual when required, independently
witnessed rather than hidden to improve a count.

Retained baseline reproduced by fresh production and copied-binary replay:
45052 canonical rows, digest00f1769d6db7f6ee91ee51becabccd7b4ce13975acb6610c95ace69a7f620e9b,
Irmin4781/protocol11730. Another actual --check from /tmp passes after source-state
validation repair. Source and410CMT hashes rechecked before/after; baseline is
improvement/2026-09-14-tezos-resolution/attempt3-baseline. Prior baselines untouched.
Native corpus admission must be independent of product target lookup. The census
is not that admission oracle. No KB, managed claims reconciler or hooks installed.

## Quality Gates

```sh
opam exec -- dune build
opam exec -- dune exec tezt/tests/main.exe -- --no-color
node scripts/review-bundle-verify.js
node roster/tezos-open-bodies/prepare-baseline.js --check
git diff --check
```

Fresh pre-product full guard already332/332, exit0. Formatter/coverage not
configured; no pass claimed. Spec must freeze native authentic/refusal checks,
flat/effect/old-row equality and candidate fixed410 witness comparison before
implementation. Those new check programs are not yet available or passed.
Retention requires strictly positive witnessed gain, zero lost retained relations,
no unexplained row movement, full roster review/QA, exact-head green required CI,
then rebase merge before next product attempt. Two of five attempts delivered.

## Open Questions

None requiring user direction. Spec challenges must resolve implementation-facing
details before plan; no implementation authority is implied by preparatory checks.
