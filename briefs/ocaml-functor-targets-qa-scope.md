# QA Scope — ocaml-functor-targets

**Status: VALIDATED**

## Commands

```bash
# Build
opam exec -- dune build --root .

# New deterministic contracts
opam exec -- node roster/ocaml-functor-targets/check-cmt.js
opam exec -- node roster/ocaml-functor-targets/check-native.js
opam exec -- node roster/ocaml-functor-targets/check-tezos.js

# Explicit exit-code controls: each assertion command must exit 1 and each setup
# command must exit at least 2 (the ordinary commands above must exit 0).
opam exec -- node roster/ocaml-functor-targets/check-cmt.js --test-control=assertion
opam exec -- node roster/ocaml-functor-targets/check-cmt.js --test-control=setup
opam exec -- node roster/ocaml-functor-targets/check-native.js --test-control=assertion
opam exec -- node roster/ocaml-functor-targets/check-native.js --test-control=setup
opam exec -- node roster/ocaml-functor-targets/check-tezos.js --test-control=assertion
opam exec -- node roster/ocaml-functor-targets/check-tezos.js --test-control=setup

# Focused authentic coverage
opam exec -- dune exec --root . tezt/tests/main.exe -- --job-count 1 --match 'functor|CFA'

# Existing independent functor contracts
opam exec -- node scripts/check-functor-bindings.js inventory
opam exec -- node scripts/check-functor-bindings.js lifecycle
opam exec -- node scripts/check-functor-bindings.js query
opam exec -- node scripts/check-functor-bindings.js compatibility

# Existing CFA producer and frozen-corpus controls
opam exec -- node roster/ocaml-cfa-foundation/check-cmt.js
opam exec -- node roster/ocaml-cfa-foundation/check-tezos.js

# Full deterministic suite, single job
opam exec -- dune exec --root . tezt/tests/main.exe -- --job-count 1

# Repository hygiene
rtk git diff --check
```

No standalone lint/format gate is documented.

## Behaviors to Validate

- Main direct `F(A)` has one concrete MAY target, retained module-parameter TOP and a
  complete artifact-local witness; it has no MUST or clone.
- Repeated/curried/nested/include/one-hop cases union only correct formal/member targets,
  deduplicate relations without losing witness multiplicity and remain order-invariant.
- All unsupported/opaque/ambiguous cases add no target or extra TOP.
- Same-location physical occurrences remain distinct.
- Exact copies reuse graph rows but retain artifact witnesses; nonidentical variants
  contribute only after unique stable-field reconciliation and never borrow compiler IDs.
- Flat LSP remains unknown and gains no Stage-4 target.
- Partial/old/wrong schema and failed collection refuse or fail; they never render an
  empty result as complete.
- CHECK-3 revalidates frozen/current hashes, reports global and per-slice sets, has zero
  loss/new MUST, at least one combined gain, and validates every candidate-only gain's
  exact witness chain.
- Checker controls demonstrate 0 pass, 1 assertion, at least 2 setup/timeout/crash.
- Documentation and reports retain the three explicit limitations.

## Non-applicable Matrices

- TUI: none in scope.
- Browser/UI/accessibility: none in scope.
- Network/API compatibility: none in scope.
- Flat-schema feature parity: explicitly excluded; only regression/non-inference applies.
