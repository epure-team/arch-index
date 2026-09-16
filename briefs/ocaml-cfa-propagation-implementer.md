# Implementer Brief — ocaml-cfa-propagation

**Status: VALIDATED**

## Goal

Implement `specs/ocaml-cfa-propagation.md` as a same-CMT,
context-insensitive OCaml callable-value analysis. Extend the existing finite
inclusion kernel; do not build a second solver.

## Scope boundary

No cross-CMT linking, functor/member correspondence, independent variant reuse,
objects/effects/continuations, aggregate or mutable capture, optional/default or
destructured formals, overapplication into returned callables, query redesign,
storage migration, new `MUST`, or full-OCaml/whole-program claim.

## Files to modify first

- `lib/arch_index/arch_index_cfa.ml/.mli`: typed reasons and finite
  target-triggered constraint activation in the existing worklist.
- `lib/arch_index/arch_index_cfa_cmt.ml/.mli`: session lifecycle, shared transfer
  policy, callable/formal/return/result/residual registries.
- `lib/arch_index/arch_index_cmt.ml`: main collector registrations and occurrence
  expansion.
- `lib/arch_index/call_graph_extractor.ml`: flat collector parity.
- `test/test_cfa.ml`: independent fixed-point/activation oracle.
- `tezt/tests/ocaml_cfa_foundation.ml` and `tezt/fixtures/ocaml_cfa/`: authentic
  Stage-3 fixtures without weakening Stage-2 controls.
- `roster/ocaml-cfa-propagation/check-{domain,cmt,tezos}.js`: runnable spec gates.

## TDD sequence

1. RED then GREEN for lifecycle guards, exception-atomic finalize, typed reasons,
   shared dispatcher and identical foundation output.
2. RED then GREEN for one saturated actual→formal→return→result call in main and flat.
3. RED then GREEN for late-discovered candidate activation, direct-edge precedence,
   context-insensitive merging and known-plus-unknown flow.
4. RED then GREEN for all-simple direct/mutual recursion with predeclared cells.
5. RED then GREEN for exact supported captures and excluded capture controls.
6. RED then GREEN for finite residual stages, saturation, mixed arity and overapplication.
7. Run/check all scope, build, test and pinned corpus gates; update roadmap evidence.

For each step preserve physical occurrence tokens and all caller/site/partial/
conditional/dead/exception/result/residual metadata. Cells, callable identities
and residual identities must exist before solve; candidate edges may activate
monotonically once per finite occurrence/candidate pair.

## Quality gates

```bash
opam exec -- dune build --root .
eval "$(opam env)"
dune test --root .
rtk proxy node roster/ocaml-cfa-propagation/check-domain.js
rtk proxy node roster/ocaml-cfa-propagation/check-cmt.js
rtk proxy node roster/ocaml-cfa-propagation/check-tezos.js
```

Each checker: 0 pass, 1 assertion, >=2 setup/execution error. No standalone lint
or format gate is documented. Preserve foreign untracked files and create no
long-lived worktree/build copy.

## Risks and stop conditions

- If a correct conservative change requires a pinned relation loss, stop/bounce;
  do not weaken CHECK-3.
- If finite residual identity cannot encode a case, keep it callback-open; do not
  broaden grammar.
- If main/flat cannot represent the same bounded identity faithfully, flat must
  remain its prescribed unknown tuple rather than select a homonym.
- If work requires Stage-4 functor semantics or a backend migration, it is out of scope.
