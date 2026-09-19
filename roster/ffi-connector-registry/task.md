# Roster intake — user-configurable FFI connector registry

## Objective

Define the safe product boundary for user-selected FFI connectors after the
five delivered FFI evidence stages. The registry must support OCaml/C/Rust
project anchors without pretending that Java, OCaml and Rust share one generic
source matching rule.

## Scope

Design/specification only: closed v1 configuration envelope, mechanism
vocabulary, proof/refusal rules, output/provenance contract and staged delivery.
No parser, scanner, schema migration, call edge or reachability change.

## Acceptance

- Configuration selects bounded roots/targets, never witness kinds or a result
  ceiling.
- Unknown/malformed/ambiguous state is refused or retained as a frontier.
- A connector cannot create a MUST edge or a security verdict.
- The current OCaml-C and Rust-archive readers are explicitly identified as the
  only v1 resolved mechanism families; callback remains a frontier.
