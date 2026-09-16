# Implementer Brief — ocaml-functor-targets

**Status: VALIDATED**

## Goal

Implement Stage 4 of the approved OCaml roadmap: for an explicitly authenticated
same-artifact local functor application/formal/actual/member chain, add concrete
actual-member targets to the original formal-member call as `MAY_ENUMERATED`, retain
the independent `MAY_TOP/module_param`, persist attribution witnesses, and handle
exact-copy plus uniquely reconciled nonidentical same-source variants without
cross-artifact compiler-identity joins.

## Scope Boundary

- No general defunctorization, closed-world claim, body/instance cloning, `MUST`,
  `Path.Papply`, anonymous/unpacked/persistent actuals, Shapes/UID, cross-unit target
  resolution, flat/LSP inference, query redesign or backend replacement.
- Never remove an independent unknown contribution or guess from display names,
  basename, source spelling, compiler stamps across artifacts, or ambiguous locations.
- Stage 4 must itself produce at least one witnessed pinned410 resolved-relation gain;
  this is not deferred to Stage 5.

## Files and Responsibilities

- `lib/arch_index/arch_index_bindings.ml`: expose complete same-artifact application,
  declaration/formal and actual-path proof without weakening existing refusal reasons.
- `lib/arch_index/arch_index_functors.ml`: retain stable application ordinals/provenance.
- `lib/arch_index/arch_index_cmt.ml`: match formal-member occurrences, reuse concrete
  module exports, preserve TOP, discriminate physical occurrences, and collect variant
  proofs before insertion loss.
- `lib/arch_index/arch_index.ml`: resolve representative occurrences/targets, persist
  call rows and witnesses transactionally, and finalize/refuse the new contract.
- `architecture-schema.sql`: versioned artifact-local witness tables/constraints/indexes.
- `tezt/tests/functor_bindings.ml`, `tezt/tests/ocaml_cfa_foundation.ml`, and
  `tezt/fixtures/ocaml_cfa/`: authentic positive/negative/variant fixtures.
- `roster/ocaml-functor-targets/check-cmt.js`: CHECK-1 authentic producer/DB/query gate.
- `roster/ocaml-functor-targets/check-native.js`: CHECK-2 full-suite/independent-check gate.
- `roster/ocaml-functor-targets/check-tezos.js`: CHECK-3 Stage3-vs-candidate attributed replay.
- Roadmap/public docs named in the intake: exact contract, results and limits.

## Sequential Implementation

1. RED direct `F(A)` fixture at producer, witness, SQL and query boundaries; then make
   only that complete vertical slice GREEN.
2. RED/GREEN repeated/curried/nested/include/one-hop cases and all refusal, equal-location,
   TOP-retention, no-MUST and flat non-inference controls.
3. RED/GREEN exact-copy artifact provenance, nonidentical variant proof-before-drop,
   unique representative reconciliation, ambiguity/refusal and discovery-order controls.
4. Implement checker 0/1/>=2 controls and a hash-validated frozen Stage-3 CHECK-3 whose
   every candidate-only relation is joined to a complete persisted witness.
5. Run focused and full gates, repeat CHECK-3, update both roadmap artifacts and prepare
   implementation evidence for independent review.

## Non-negotiable Invariants

- Exact compiler identity is compared only inside one artifact.
- Relation cardinality and witness cardinality are distinct and deterministic.
- Zero/multiple variant occurrence matches contribute nothing.
- Every target is `MAY_ENUMERATED`; original `MAY_TOP/module_param` remains; no `MUST`.
- No positive corpus claim without an exact persisted identity-chain witness.
- No test may turn missing corpus, timeout, crash, partial LSP or malformed schema into pass.

## Quality Gates

```bash
opam exec -- dune build --root .
rtk proxy node roster/ocaml-functor-targets/check-cmt.js
rtk proxy node roster/ocaml-functor-targets/check-native.js
rtk proxy node roster/ocaml-functor-targets/check-tezos.js
opam exec -- dune exec --root . tezt/tests/main.exe -- --job-count 1 --match 'functor|CFA'
rtk proxy node scripts/check-functor-bindings.js inventory
rtk proxy node scripts/check-functor-bindings.js lifecycle
rtk proxy node scripts/check-functor-bindings.js query
rtk proxy node scripts/check-functor-bindings.js compatibility
opam exec -- dune exec --root . tezt/tests/main.exe -- --job-count 1
```

No standalone lint/format command is documented. Run `git diff --check`. Every new
checker uses 0 pass, 1 assertion, at least 2 setup/error and must prove its three controls.

## Risks and Assumptions

- Highest risk: stable physical occurrence and witness identity across graph reuse and
  nonidentical variants. Fail closed rather than widening reconciliation.
- Persist a dedicated contract only after complete input collection; partial/old DBs
  must refuse rather than appear empty.
- Keep joins indexed by declaration/formal and requested member path; do not enumerate
  every export for every application.
- If the supported pinned corpus produces no gain, inspect authentic refusal categories;
  do not relax identity, TOP, loss, MUST or attribution gates.
