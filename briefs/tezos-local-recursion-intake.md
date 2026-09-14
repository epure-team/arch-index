# Intake Brief — tezos-local-recursion

**Date:** 2026-09-15
**Status: VALIDATED**
**Type:** feature
**Trust boundary:** no

## Goal

Attempt4 of the user's existing five-iteration loop improves direct self-call
resolution for singleton local recursive bindings whose plain variable binds a
literal function. An exact same-CMT compiler identity may reach the existing
observed and stored synthetic body as MAY_ENUMERATED, never newly MUST.
Irmin source/retained DB examples include unix/io.ml32/44 and tree.ml41/45/48.
These are documentary examples, not an accepted gain estimate.

Prior PR107 is merged. Retained fixed410 totals are Irmin4781/protocol12046;
45,052canonical rows, digest9ab4e0b13457247fb93dc83bf80323fcc5cec67866a18f56995ac0ec4a20867e.
Require positive independently witnessed ordinary relation gains, zero losses,
zero unexplained changes and complete roster/guard verification before retention.
Exact-head required greenCI and rebase merge precede attempt5.

## Scope Boundary

Product scope: lib/arch_index/arch_index_cmt.ml only. Task-native tests, task-local
roster/spec/brief/checker artifacts, existing loop results and external roadmap.
Conditional exact self-reference refresh requires pristine crossed attribution
and an explicit exact-path manifest entry before edits; no threshold relaxation.

Explicitly OUT:
- Mutual groups (two or more value bindings), nonrecursive bindings and structural
  recursion already handled by the existing structural table.
- Wrapped/computed/aliased function RHSs, tuple/alias binding patterns, qualified
  invocations, let-operator heads, escapes and other non-head occurrences.
- General0CFA, closure-flow, functor expansion/substitution or linkage heuristics.
- Public collector API, schema, flat consumer, existing certainty/CFG/effect policy.
- Tezos source/CMT writes, old frozen baselines/checkers, heldPR93, foreign worktrees
  and the seven pre-existing unrelated untracked files.

## Relevant Files

| File | Role | Key snippet |
|---|---|---|
| lib/arch_index/arch_index_cmt.ml | private collector and body persistence | Texp_let RHS walk precedes local_lam_stamps insertion; lambda_name advances collision counter |
| lib/arch_index/arch_index.ml | read-only resolution/kind boundary | Head_enumerated stays MAY_ENUMERATED; failed local body becomes TOP |
| tezt/tests/callgraph_soundness.ml | existing local/lambda/recursion controls | ping/pong, shadow_bind, partial_bind, beta_redex |
| tezt/tests/open_body_targets.ml | native persistence/refusal test pattern | SQL body/parent insert rejection, exact flat compatibility |
| roster/tezos-open-bodies/check-native.js | read-only preservation-control pattern | paired current/predecessor SQLite with configured value channels |
| roster/tezos-open-bodies/prepare-baseline.js | read-only frozen baseline pattern | atomic no-overwrite, pinned producer/schema/CMT and neutral replay |
| roster/tezos-call-resolution/comparison.js | read-only canonical snapshot utilities | counted rows, exact digest, target relation keys |
| docs/edge-kind-contract.md | preserved certainty/ownership contract | bounded targets do not imply MUST execution |

## Architecture Notes

The new lookup must not seed the ordinary local_lam_stamps early: that table also
affects non-head occurrences and can create MUST. Keep invocation-only evidence
separate and scoped to the exact recursive RHS, including its nested callable
contexts while preserving each existing caller. Only a direct application whose
Path.Pident is the active binder may change. Existing calls after the let binding
and all unrelated previously resolved calls preserve their full facts.

Use the actual observed literal name/physical expression and existing collision
ordinals, not a guessed name or an extra call to the mutating name allocator.
The body must really be available in the indexed graph. Refused/ambiguous/missing
correspondence must not become a dangling known leaf. Syntactic arity and actual
supplied Some arguments determine partial/overapplication behavior; preserve one
unknown returned-call residual per overapplied invocation, with single-use native
occurrence capacity. Do not move calls/effects or widen global function recognition.

Independent native witnesses must bind artifact, compiler binder, exact literal,
caller, application range and counted source-line group capacity. Plain printed
callee names or locations alone are insufficient. Preserve all unadmitted rows,
old target relations, reexports, rich ownership/CFG/effects/channel facts and flat
multisets. New tests must be non-vacuous for configured channels, shadowing,
optional/refutable/default parameters, higher-order returns and duplicate positions.

Distinct PR107 baseline prepared by a read-only producer invocation plus copied
producer replay in improvement/2026-09-14-tezos-resolution/attempt4-baseline.
Actual exit0:45,052rows, exact retained digest,4781/12046, neutral replay. Immutable
producerSHA992f4b252fb14d62cc64616bc88292883b7706a87e39ca9927bd498d0f1c5391;
schemaSHA1dd2d909e1feb2582e8a13f717ef165b7be9b73b908f73f47983920bded580d0.
All410input hashes and source states remained unchanged; disposable selections
and replay DB/build artifacts were cleaned. This is setup, not attempt4 gain.

Trust keyword heuristic over task.md had no match (exit1), so no trust-boundary
flag is proposed. This remains full feature mode with explicit executable spec.
Claims reconciler/managed context and KB are absent; no stale projection used.
Standing user autonomy validates routine Type/Trust/scope gates; no fabricated
interactive response or formal proof claim. Material scope changes still escalate.

## Quality Gates

```sh
opam exec -- dune build
opam exec -- dune exec tezt/tests/main.exe -- --no-color
node scripts/review-bundle-verify.js
git diff --check
```

Formatter/full lint/coverage: not configured, not claimed passing. Task-specific
native admission/refusal, fixed410 baseline/replay/comparison and exact self-policy
checks are specification deliverables, not currently runnable commands.
Fresh pre-product full guard must pass before product editing, then full candidate
guard and independent review/QA runs; serialize all builds and snapshot checks.

## Open Questions

None in the contractual boundary. Detailed implementation/check decomposition is
next in roster-spec and roster-plan, not permission to broaden the scope.
