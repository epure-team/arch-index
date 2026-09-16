# Implementation Report — ocaml-cfa-propagation

**Mode:** full  
**Implemented SHA:** `c240e28fc788ea30d1bd94efdd4cebdae410acdd`  
**Status:** COMPLETED

## Delivered behavior

- Extended the finite inclusion domain with typed uncertainty and finite residual
  values, including late target/reason/residual activation and clone isolation.
- Made CMT-session finalization exception-atomic and every mutator reject use after
  finalization.
- Added same-CMT, context-insensitive actual-to-formal and normal-return-to-physical-
  application-result propagation for the explicitly supported callable grammar.
- Added all-simple recursive groups, exact immutable lexical captures and finite
  `(callable, consumed-leading-slots)` residuals for staged applications.
- Preserved direct edges as authoritative, CFA-derived targets as `MAY_ENUMERATED`,
  and independent callback frontiers without duplicate CFA rows.

## Modified product and test files

The implementation changes the CFA domain/session and CMT collector under
`lib/arch_index/`, extends `test/test_cfa.ml`, adds the authentic
`tezt/fixtures/ocaml_cfa/higher_order.ml` fixture, and extends
`tezt/tests/ocaml_cfa_foundation.ml`. Self-index reference updates are justified
by `roster/ocaml-cfa-propagation/self-reference-evidence.md` and reproduced by
`roster/ocaml-cfa-propagation/calibrate-self.js`.

## Verification evidence

- `opam exec -- dune build --root .`: exit 0.
- `opam exec -- dune test --root . --force`: exit 0; 345/345 Tezt scenarios and
  all OCaml test suites passed.
- CHECK-1: exit 0; 517 finite-domain oracle cases.
- CHECK-2: exit 0; authentic main/flat/metadata/identity/consumer controls.
- CHECK-3: exit 0; pinned 410-input Tezos corpus, Irmin 4849→4902, protocol
  12171→12299, 181 relation gains, zero relation losses and zero new `MUST`.
- Self-reference 2×2 calibration: the current engine adds two calls on the old
  corpus and six calls while removing one on the current corpus, with no origin
  changes attributable to the engine.

## Scope and residual limits

No cross-CMT resolution, functor/member matching, mutable or aggregate capture,
optional/default/destructured formal support, returned-callable overapplication,
query redesign, storage migration or whole-program completeness claim was added.
No new worktree was created and the seven pre-existing foreign paths in the
manifest remain untouched.

## Ratchet

No review finding exists yet; no loop-back ratchet check is declared.
