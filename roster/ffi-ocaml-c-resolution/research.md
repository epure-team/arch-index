# FFI Stage 3 research

Stage 2 deliberately stopped at target ownership.  The Brassaia Unix target
provides the smallest real positive case: `syscalls.ml` declares four exact
`caml_index_{pread,pwrite}_{int,int64}` symbols; `pread.c`/`pwrite.c` define
them with `CAMLprim`; their names are declared in the target's
`foreign_stubs`; and the existing Dune output contains both
`libbrassaia_index_unix_stubs.a` and `dllbrassaia_index_unix_stubs.so`.
`nm --defined-only` exposes all four symbols in each artefact.

The proof unit must therefore be stronger than a spelling equality:

1. source declaration: the OCaml external's quoted primitive spelling;
2. target membership: the defining C source is named by that exact target's
   `foreign_stubs`, while the external has that same target association;
3. build witness: a conventional Dune stub archive or shared object for the
   target exports the exact spelling, and its source mirror below
   `_build/default` has the same digest as the source scanned for `CAMLprim`.

The artefact only witnesses an exported entrypoint.  It cannot establish full
C type compatibility from source text, nor demonstrate that a particular final
executable loaded the shared object.  Stage 3 will consequently call a result
`RESOLVED_STRICT` only for the declared OCaml runtime primitive binding, retain
its evidence, and make no call-graph or `MUST` statement.  Missing artefacts
are normal on a clean checkout and must be reported as `MAY_TOP(ffi)` rather
than cause a build or a guessed result.

The BLS target also demonstrates why `foreign_archives` is excluded here:
its
`blst` archive is a distinct build mechanism.  Handling it requires archive
provenance beyond the target's direct `foreign_stubs`, so it remains a Stage 4+
case rather than weakening this first strict resolver.
