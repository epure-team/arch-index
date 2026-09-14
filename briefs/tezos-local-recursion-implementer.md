# Implementer — tezos-local-recursion

**Status: VALIDATED**

## Goal and scope

Attempt4/5: exact same-CMT singleton local Recursive plain-variable/direct-function
RHS self-invocation targets, including nested contexts, to actual stored synthetic
bodies as MAY_ENUMERATED only. No general0CFA, wrappers/aliases, mutual groups,
non-head/qualified/letop discovery, ordinary timing changes, public API/schema/flat
changes or new MUST. Do not touch Tezos, old baselines/checkers, heldPR93, foreign
worktrees or seven unrelated untracked files. Main owns scheduling and git.

Product file: lib/arch_index/arch_index_cmt.ml. Relevant existing sequence:
Texp_let RHS traversal precedes local_lam_stamps insertion; lambda_name mutates
collision counters. Do not pre-seed the ordinary table or predict body names.
New private evidence must observe the exact literal and preserve caller/context.
Refuse dropped/missing/ambiguous storage; no dangling known target.

Task tests/checkers/spec/briefs are in scope, including native test registration.
Exact self-reference files are NOT writable until main establishes pristine
crossed attribution and explicitly amends the exact-path manifest.

## Sequence and completion

1. Verify frozen attempt4-baseline: producer992f4b25…,schema1dd2d909…,
   45052rows,digest9ab4e0b1…,Irmin4781/protocol12046 and410 pinned CMTs.
   Pre-product full336 guard passed243853ms; do not replace that evidence.
2. Before product editing, make native tests, independent CMT witness and six
   task-local checker commands executable; obtain actual semantic RED.
3. Implement only the bounded private invocation path, then same assertions GREEN.
4. Run full native and fixed410 verification, preservation and guards. No speculative
   second capability. Positive attributable gain is required to retain; no gain is
   DISCARD, incomplete work stays pending. Full review/QA and greenCI precede merge.

Required controls: same/different binder; entire singleton/mutual cardinality;
exp_extra vs constructor wrapper; physical root/collision ordinal; actual SQL body
and parent refusal; optional/default/refutable/nested contexts; supplied Some arity,
partial/result-arrow, one residual per overapplication with single-use capacity;
complete configured channels/CFG/scopes/effects/origins/reexports and flat multisets;
wrong artifact/binder/root/caller/range/count witnesses; count-neutral retarget/loss.
No candidate-derived native target proof; every ambiguous group member must agree.

## Exact quality gates

- `opam exec -- dune build`
- `opam exec -- dune exec tezt/tests/main.exe -- --no-color`
- `node scripts/review-bundle-verify.js`
- `git diff --check`
- `node roster/tezos-local-recursion/check-native.js`
- `node roster/tezos-local-recursion/check-witness-inputs.js`
- `node roster/tezos-local-recursion/check-baseline.js`
- `node roster/tezos-local-recursion/check-comparison.js`
- `node roster/tezos-local-recursion/check-compatibility.js`
- `node roster/tezos-local-recursion/check-residual-capacity.js`

Last six are deliverables, not existing PASS. Exit0pass/1assertion/2+runtime.
Serialize builds/snapshots against all writes. No formatter/coverage configured.
Risks and assumptions: actual stored body observation, correct RHS scoping and
non-vacuous preservation must be empirically verified; never infer from counts.
