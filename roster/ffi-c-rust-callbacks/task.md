# Roster intake — FFI Stage 4: C ↔ Rust and callback connectors

## Objective

Add the next read-only evidence layer for Octez C↔Rust boundaries and describe
the first configurable connector contract.  A Rust C-ABI export is linked only
when a declared Rust archive target and an exact exported symbol artefact agree;
callback types/registrations are inventoried separately and remain unresolved
unless their closed receiver set is proved.

## Scope

- Restrict Rust candidates to crate roots that are declared by Octez manifest/
  Dune `foreign_archives` targets, rather than all vendored Rust source.
- Require source-export, source/build mirror and `nm` archive/shared-object
  evidence for a C↔Rust exported symbol result.
- Define a versioned connector descriptor: anchors, build artefacts, required
  witnesses, permitted result kind and explicit refusal reasons.
- Record Rust callback function-pointer types and C/OCaml registration points
  as frontier inventory only.

## Non-goals

- No automatic mapping from an OCaml external to a Rust export; Stage3's C
  primitive binding and the C bridge must each be independently witnessed.
- No callback edge, closure-flow result, schema mutation or MUST claim.
- No coverage claim for crates that are merely vendored or a final executable's
  dynamic loading.

## Acceptance evidence

1. A positive result carries source, target, artefact and symbol witnesses;
   source-only Rust exports cannot qualify.
2. Descriptor validation rejects unknown witness kinds and a connector that
   would allow a name-only result.
3. Callback presence is reported with a reason for non-resolution, never
   interpreted as a target function.
