# QA Scope — ocaml-cfa-propagation

**Status: VALIDATED**

## Deterministic gates

```bash
opam exec -- dune build --root .
eval "$(opam env)"
dune test --root .
rtk proxy node roster/ocaml-cfa-propagation/check-domain.js
rtk proxy node roster/ocaml-cfa-propagation/check-cmt.js
rtk proxy node roster/ocaml-cfa-propagation/check-tezos.js
```

## Behaviors to validate

- Complete post-finalize mutation rejection, idempotent finalize, pre-finalize
  query rejection and injected finalization atomicity.
- Exact two-kind reason semantics, same-kind deduplication and separate
  overapplication residual.
- Root/local shared grammar parity and byte-identical Stage-2 controls.
- Saturated higher-order identity/apply, late candidate activation and physical
  result cells.
- Intentional context-insensitive merging and independent known/TOP propagation.
- Direct/mutual recursion under reordered/duplicated constraints.
- Supported exact captures and all excluded capture boundaries.
- Multi-stage partial flow, no premature return, mixed arity, unknown labels/
  arity, overapplication and same-location occurrence identity.
- Exact metadata, only `MAY_ENUMERATED`, no CFA `MUST`, no duplicate direct edge.
- Pinned410 provenance, exact row/relation deltas, separate Irmin/protocol counts,
  zero relation losses, zero new `MUST`, and honest resource observations.
- Diff contains no functor Stage-4, query Stage-5 or backend migration work.

There is no TUI scenario in scope. Missing corpus/tooling is setup error >=2,
never a passing skip.
