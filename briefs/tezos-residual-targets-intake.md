# Intake Brief — tezos-residual-targets

**Date:** 2026-09-14
**Status: VALIDATED**
**Type:** feature
**Trust boundary:** no

Validation: user's explicit five-attempt autonomous roster delegation. No quiz
answers or additional user decisions are claimed. Operational task description
keyword checks returned no trust/critical hit; this is static call resolution,
not protocol behavior, financial logic or vulnerability research.

## Goal

Attempt2 resolves a qualified member of an already-owned same-CMT literal
structure when that value is a bare identifier alias directly naming a known
same-CMT function body. Initial source examples: State.Monad.Syntax.let* in
sc_rollup_arith, Infix.>>=* in Irmin merge. Resolve by compiler binder identity,
not spelling; retain the existing body target and real syntactic arity.

Keep only with a strict relation gain against retained PR105 state
(Irmin4772/protocol11615), zero unexplained relation loss/row changes, native
refusal and partial-application tests, full guards, roster review/QA GO, exact-head
green PR CI and rebase merge. This is one-hop value provenance, not general0CFA,
module-alias expansion or functor instantiation. No numerical gain is promised.

## Scope Boundary

Writable product: lib/arch_index/arch_index_cmt.ml and .mli; shared caller
call_graph_extractor.ml only if threading/flat attribution requires it. Tests:
tezt/tests/local_module_targets.ml (reclassify its exact value_alias_call case,
preserve all other refusals), new tezt/tests/local_value_targets.ml, main.ml
registration and dune dependencies. Supporting: roster/tezos-residual-targets/**,
briefs/tezos-residual-targets-*, specs/tezos-residual-targets.md,
docs/edge-kind-contract.md, ignored improvement/**, skills-meta/friction.jsonl,
external roadmap. Existing task1 comparator/probe may be imported read-only;
do not rewrite its pinned baseline, historical spec or witnesses.

Only if measured product changes require exact self-oracle recalibration:
test/fixtures/self-index-stats.txt, test/fixtures/origin-consumer/reference.json,
checks/origin-recurring-consumer.js assertion coordinates. No thresholds,
allowlist widening, disabled gates or manufactured expected results.

Out of scope: multi-hop or recursive alias closure; unqualified alias-call
classification; qualified/persistent alias RHS; module aliases or application
results as owners; parameter/first-class modules; function-valued computations,
closures or partial applications as alias RHS; cross-CMT lookup; new schemas,
public CLI, dependencies, CFG/error-channel policy changes. Tezos remains
read-only, fixed410 input set unchanged, PR93/unrelated dirt/worktrees untouched.

## Relevant Files

| File | Role | Key snippet |
|---|---|---|
| lib/arch_index/arch_index_cmt.ml | Owned exports and collector | build_local_module_targets; local_module_target |
| lib/arch_index/arch_index_cmt.mli | Shared context contract | local_module_targets; local_fn_stamps |
| lib/arch_index/call_graph_extractor.ml | Flat consumer | same-file owned target attribution |
| tezt/tests/local_module_targets.ml | Existing refusal and emission tests | Value_alias.f currently refused |
| tezt/tests/dune | Test registration dependencies | main test and native checker deps |
| roster/tezos-call-resolution/verify.js | Read-only pinned verification primitives | readManifest; loadWitness |
| roster/tezos-call-resolution/comparison.js | Read-only exact relation/multiset rules | snapshotDatabase; compareSnapshots |

## Architecture Notes

The body table must stay body-only: an alias must never acquire MUST eligibility
or arity0 from its identifier expression. An owned export may instead carry the
actual directly named body's existing registered name/arity. Source-order masks
and binding-name ordinals still apply. Same-CMT binding stamps cannot escape
their compilation unit. Ordinary calls stay MAY_ENUMERATED; point-free alias rows
retain edge_form=value_alias and are excluded from the improvement metric.
For this attempt, existing point-free outputs are unchanged, including qualified
RHSs naming alias members. The new invocation shortcut must not turn an existing
immediate-predecessor edge into a direct-body edge. No new point-free resolution
is required. Invocation, callback and letop sites are the eligible consumers.
Resolved-body rejection must remain dropped_node TOP. Flat attribution requires
a same-file symbol, never a homonym in another file.

Before product edits, produce a fresh retained-state DB from the unchanged
merged producer, verify exact candidate SHA90e76d6... and410 input provenance,
then replay it neutrally. Retain both original baseline and this new one, with
distinct pinned records. New verifier/witness handling remains fail-closed;
one-hop compiler alias-to-body witnesses are not the old direct-UID witness.
Comparison tooling changes are setup, never a product gain or another iteration.
No KB/managed claims tooling is installed. Read-only residual-census.md is
prioritization, not a fresh-baseline approval or estimate of solvable TOPs.

Planning clarification: freeze a checked copy of the predecessor producer and
schema alongside the fresh DB in ignored
improvement/2026-09-14-tezos-resolution/attempt2-baseline/. This is necessary
replay data, not a disposable build worktree; delete only after the loop no
longer needs it. --check replays that pinned producer, never the changed current
binary. Candidate verification uses the current binary and the frozen DB.
Producer SHA c953970a15b64d026f7b502ba5d61be537c3ab5b51e219435b4a3483d57764b8;
schema SHA1dd2d909e1feb2582e8a13f717ef165b7be9b73b908f73f47983920bded580d0;
canonical SHA90e76d6b40b2d7f108fcc25523f85de1cb533a98565a8a7d6d284c1654939d4b.
New commands under roster/tezos-residual-targets/: prepare-baseline.js
--create/--check, check-native.js, check-comparison.js, verify.js --self or
--witness improvement/2026-09-14-tezos-resolution/attempt2-reviewed-witness.json.
One-hop witness must carry call occurrence -> alias declaration -> body identity,
with complete locations/arity and multiplicity, independently of product lookup.

## Quality Gates

```sh
rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune build --root .
rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune runtest --root . --force
rtk proxy node scripts/review-bundle-verify.js
rtk proxy git diff --check
```

New self-contained native and fixed410 Verify commands are specified before
implementation; distinguish assertion1 from setup>=2. Preflight READY with
build0, collection327, bundle22. No formatter/full-linter/coverage configured.
Pristine CI-only recalibration and exact-head hosted CI remain delivery gates.

## Open Questions

None requiring a new user choice. Exact native edge-form/arity witness scenarios
and baseline provenance encoding are settled in the feature spec before edits.
