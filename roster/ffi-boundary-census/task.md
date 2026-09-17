# Roster intake — FFI Stage 1: Tezos boundary census

## Objective

Create a reproducible, read-only inventory of the OCaml ↔ C ↔ Rust boundaries
in the canonical Octez checkout. The inventory must say what can be linked by
evidence and what must remain an FFI frontier; it does not create call-graph
edges or change the database schema.

## Fixed scope

- Root: `/home/mathias/dev/tezos/tezos` only.
- OCaml `external` declarations, excluding `%` compiler primitives.
- C definitions using OCaml runtime entry conventions, C-ABI Rust exports and
  explicit callbacks/dynamic loading constructs.
- Build declarations sufficient to associate an input with a library/target
  when they are available as source text.

The parent `/home/mathias/dev/tezos` contains unrelated worktrees, mirrors and
vendors. It is explicitly not a corpus root; scanning it would duplicate or
mix revisions and invalidate any count.

## Acceptance evidence

1. The output records corpus root and revision, tool/version/digest, exclusions
   and a deterministic sorted inventory.
2. Each record has a mechanism (`ocaml_external`, `camlprim`, `rust_c_abi`,
   `callback`, `dynamic_load`), path and location; no link is inferred by name.
3. Counts distinguish candidates for OCaml→C, C→Rust and callback work from
   unresolved/unsupported boundary forms.
4. Fixture controls prove `%` primitives and excluded nested worktrees cannot
   inflate the census.

## Non-goals

- No source modification in Tezos and no compilation there.
- No FFI binding, no call edge, no MUST claim and no automatic source discovery
  outside the selected root.
