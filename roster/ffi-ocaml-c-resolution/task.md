# Roster intake — FFI Stage 3: strict OCaml external → C primitive resolution

## Objective

Resolve an OCaml `external` to a C `CAMLprim` only when one exact primitive
symbol is witnessed in the same declared Dune foreign-stub target **and** in a
read-only artefact produced for that target.  Preserve every other external as
an explicit FFI frontier; this sidecar creates no call-graph edge yet.

## Fixed scope

- Consume the Stage 1 census and Stage 2 direct Dune target attribution for
  `/home/mathias/dev/tezos/tezos`.
- Admit one result only when all of these agree: the external spelling, one
  unique `CAMLprim` definition from a `foreign_stubs` source of the same target,
  and an `nm --defined-only` witness in that target's Dune stub archive/shared
  object under `_build/default`.
- Record paths, line positions, target stanza and the exact artefact/symbol
  witness.  A missing, stale/unmirrored, ambiguous or absent witness is an
  explicit `MAY_TOP(ffi)` reason.

## Non-goals

- No compilation, source mutation, schema write, graph edge or MUST claim.
- No name-only join, no inference across targets, and no ABI-signature proof
  beyond the OCaml-runtime entry convention recorded by `CAMLprim`.
- No Rust matching or callback closure; those are Stage 4.

## Acceptance evidence

1. A positive fixture needs all three independent witnesses; removing either
   the target source membership or the artefact symbol makes it unresolved.
2. Duplicate C definitions or duplicate eligible targets are refused rather
   than selected arbitrarily.
3. Artefact source mirrors must have the same digest as their checked-in
   source; a mismatch is reported, never treated as a current build proof.
4. The Tezos replay is deterministic, distinguishes resolved and retained
   frontiers, and makes no graph-precision claim.
