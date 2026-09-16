# Plan — ocaml-cfa-propagation

**Date:** 2026-09-16
**Status: VALIDATED**

## Consensus Table

| Point | Voice 1 (Terra) | Voice 2 (Sol) | Status |
|---|---|---|---|
| Close lifecycle/reason/grammar findings first | Required prerequisite | Autonomous risky refactor, must be isolated | AGREE |
| Start with one saturated call end-to-end | Minimal vertical slice | Dynamic target activation is hidden complexity | AGREE |
| Use existing inclusion kernel | One solver only | Requires finite target-triggered constraints | AGREE |
| Preserve main/flat together | Integrate both in the first call slice | Divergence is a concrete risk | AGREE |
| Add captures/recursion after basic calls | Later bounded slice | Allocation order and ownership are high risk | AGREE |
| Add partial applications last | Needs frozen representation | Most likely 3× effort area | AGREE |
| Tezos replay is qualification, not semantics | Final structural gate | Necessary but insufficient | AGREE |
| Change the user’s five-stage direction | No | No | AGREE — keep direction |

## Sequential steps

1. **Harden the Stage-2 boundary** — In `arch_index_cfa` and
   `arch_index_cfa_cmt`, introduce the exhaustive CFA reason type, exhaustive
   persistence conversion, a single expression dispatcher with explicit
   root/local policies, complete finalized-session guards, and exception-atomic
   finalization. Extend CHECK-1/2 first with RED lifecycle, reason, parity and
   byte-identical foundation assertions. Completion: AC-1–3 green with no
   existing fixture movement.
2. **Land one saturated higher-order call end-to-end** — Preallocate callable
   formal/normal-return cells, physical application-result cells and a finite
   application-constraint registry. Extend the existing worklist so each newly
   discovered occurrence/candidate pair activates its precomputed
   actual→formal and return→result copy edges once. Thread the same slice through
   main and flat collectors. Completion: `id f = f` and `apply f x = f x`
   authentic fixtures resolve, retain TOP, metadata and direct-edge precedence,
   with no solver-time cell/identity allocation.
3. **Complete normal-result grammar and context-insensitive merging** — Add
   supported simple lets and application-result expressions to the shared
   transfer grammar; cover branch/match/sequence results and unsupported-result
   frontiers. Completion: disjoint sites intentionally merge at shared
   formals/returns, each application result/occurrence remains distinct, and
   known-plus-unknown flows transitively.
4. **Add supported recursion** — Predeclare every member/formal/return cell for
   an all-simple top-level or local recursive group before visiting RHSs, then
   register direct/mutual cyclic constraints. Mixed or unsupported groups stay
   callback-open. Completion: order/duplication-invariant cycles pass the
   independent oracle and authentic fixtures without unrolling.
5. **Add lexical capture flow** — Admit exact tracked immutable `Ident` reads
   across lexical callable owners within the CMT; use the lambda declaration as
   context-insensitive closure identity. Keep aggregate/mutable/module/import/
   cross-CMT sources open. Completion: repeated closure evaluations merge
   supported captures and excluded capture controls retain TOP.
6. **Add finite partial/residual callable flow** — Preallocate residual identities
   `(target, consumed-leading-slots)` up to each declared arity; propagate
   supplied actuals immediately, advance candidates independently, and attach
   return flow only on saturation. Preserve unknown label/arity and existing
   overapplication residuals; never feed extras into returned callables.
   Completion: staged, mixed-arity, same-location and overapplication fixtures
   satisfy AC-11–13.
7. **Qualification and delivery evidence** — Implement the three Stage-3
   checkers, run full Dune build/test, verify exact main/flat preservation and
   pinned410 zero-loss/no-new-MUST deltas, record Irmin/protocol gains and
   non-normative wall/RSS, and update the roadmap. Completion: all spec checks,
   review, QA, exact-head CI, and guarded merge gates can run without an
   unnecessary worktree.

## Dependencies

- Step 1 precedes every transfer change because stale finalization or a
  catch-all reason would make later evidence untrustworthy.
- Step 2 establishes the target-triggered constraint mechanism used by all
  later steps.
- Step 3 precedes recursion/captures/residuals because they all need application
  results as first-class cells.
- Step 4 precedes capture flow so recursive binders and peer identities exist
  before closure environments are inspected.
- Step 6 is last because it composes formal mapping, returns, recursion and
  captures and has the largest state-space risk.
- CHECK-3 never substitutes for CHECK-1/2; corpus qualification follows semantic
  fixtures.

## Identified risks

| Risk | Probability | Impact | Mitigation |
|---|---:|---:|---|
| Conditional call constraints fail to awaken on late targets | High | High | Finite occurrence/candidate activation set, late-seed/reordered independent oracle |
| Shared transfer refactor moves existing facts | Medium | High | RED byte-identical foundation snapshot before product flow |
| Context-insensitive cross-product creates false precision | High | High | Contractual merge tests plus independent unknown propagation; MAY only |
| Recursive group allocation misses forward peers | Medium | High | Predeclare complete supported group before any RHS traversal |
| Main/flat diverge | Medium | High | Same fixture and normalized semantic oracle for both paths |
| Partial state becomes unbounded or executes returns early | High | High | Target×slot bounded keys; preallocation census; no return edge before saturation |
| Direct and CFA paths duplicate edges | Medium | High | Direct edge remains authoritative; constraints are value-only at that occurrence |
| Corpus gains hide explosion | Medium | Medium | Exact row/relation deltas, multiplicity controls, wall/RSS observation; no performance claim |

## Decisions made

| Point | Decision | Reason |
|---|---|---|
| Dynamic discovery | Preallocate cells/identities and monotonically activate finite candidate constraints during the existing solve | Handles late operator targets without a second solver or post-finalize mutation |
| Supported parameters | Simple variable, nonoptional positional or exact labelled slots only | Faithful finite mapping; unsupported shapes remain explicit unknown |
| Context sensitivity | 0-context-sensitive shared formal/return cells | Required Stage-3 scope and finite convergence |
| Partial identity | Underlying target plus consumed leading-slot count | Finite, alias-stable and sufficient for the supported grammar |
| Existing direct calls | Keep one direct emitted edge while value constraints participate | Avoid duplicates and preserve current semantics |
| Storage work | Defer SQLite v2/unified-fact work until CFA/functors land | Storage is not the present bottleneck and is explicitly out of scope |

## Assumptions

- The existing OCaml 5.3 Typedtree argument list exposes stable flattened slots
  sufficient for exact nonoptional label matching.
- A preallocated finite application-constraint registry can be added to the
  existing worklist without changing its product-lattice semantics.
- Existing CHECK-3 corpus inputs remain locally available; absence is an honest
  setup failure, never green.
- The user’s prior authorization to run every stage autonomously validates this
  ordering and the non-disruptive rollback rule: no weakening of a gate to land.

## Validation quiz resolution

1. **Ordering:** partial applications follow basic calls, results, recursion and
   captures because they compose all four mechanisms.
2. **Implicit decision:** conditional constraints activate monotonically inside
   the existing fixed point from a finite preallocated registry; no second solve
   phase after finalization.
3. **Consistency check:** CHECK-3 cannot be moved before authentic CMT semantics
   or used to waive a relation loss; such a change bounces the stage.
