# Strict OCaml `external` → C primitive resolution

This Stage 3 sidecar emits `RESOLVED_STRICT` only for one OCaml runtime
primitive spelling with a unique three-part witness: exact Dune target/source
membership, a `CAMLprim` definition in that source, and an `nm`-observed export
in that target's Dune stub archive or shared object.  Its source mirror under
`_build/default` must digest-identically match the source definition.

Every missing or multiple witness is retained as `MAY_TOP` with a reason.
`RESOLVED_STRICT` means a declared runtime primitive binding; it does not mean
full ABI type compatibility, a loaded final executable, a call-graph edge or a
`MUST` relation.  `foreign_archives`, Rust, callbacks and dynamic loading are
outside this stage.
