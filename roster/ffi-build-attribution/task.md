# Roster intake — FFI Stage 2: build and artifact attribution

## Objective

Attribute Stage-1 source candidates to declared build targets and artifacts,
without treating a declaration/export as a cross-language binding. This produces
the admissible input set for the later ABI/link resolver.

## Scope

- Read Dune stanzas for library/executable names, `foreign_stubs` and explicit
  Rust dependency declarations under the fixed Octez root.
- Join a candidate only to its owning source directory/stanza, preserving zero,
  one or multiple target associations.
- Report unresolved ownership or generated/build-only artifacts explicitly.
- Establish fixtures for direct C stubs (`brassaia/index/src/unix`) and the
  Etherlink wasm/sqlite target declarations.

## Non-goals

- No ABI compatibility, archive/object inspection or symbol matching yet.
- No cross-language graph edge and no change to Tezos sources.
- No inference from similarly named libraries or directory suffixes.

## Acceptance evidence

1. Every target association has the exact Dune file and stanza position that
   declared it; a source candidate without an owning target is retained as
   unattributed.
2. `foreign_stubs` names create C ownership evidence but do not prove the OCaml
   primitive name matches a function in that source.
3. Rust dependency names are target dependencies, not proof of a Rust C-ABI
   export being linked.
4. Replays remain deterministic and reject roots outside the canonical checkout.
