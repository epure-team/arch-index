# FFI Stage 4 research

Octez does have declared Rust archive products, not just incidental Rust C-ABI
source.  The generated manifest defines `octez_rustzcash_deps`,
`octez_rust_deps` and `octez_rollup_node_rust_deps` as foreign archives; the
corresponding Dune rules name archive/shared-object targets.  The
`rustzcash_deps` crate is a useful positive corpus: it contains many
`#[no_mangle] pub extern "C"` exports, headers and a named archive product.

This differs from Stage3 in two important ways.  A Rust export is not a C
`CAMLprim`, so an exact symbol can establish only a C↔Rust boundary endpoint;
it cannot by itself show which C wrapper or OCaml external invokes it.
Furthermore, callback *types* such as the `unsafe extern "C" fn` receiver
types in rustzcash describe a capability for reverse control flow, not a closed
set of registered callbacks.  They must remain a separately measured frontier.

The connector descriptor should be data, not a generic source regex: name and
version, source anchors, eligible target/artifact selectors, mandatory witness
kinds, result ceiling, and refusal vocabulary.  The OCaml-C strict connector
will be encoded first; the Rust archive connector then uses the same envelope
with different anchors.  User configuration can add selectors/proofs for a
repository convention but may not lower the mandatory-witness set to symbol
name equality.
