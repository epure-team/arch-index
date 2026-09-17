# FFI Stage 1 research — initial evidence

## Current project capabilities

`architecture-schema.sql` already represents unresolved FFI as
`MAY_TOP`/`ffi`. Rust has a MIR-backed call-graph producer and an explicit
whole-workspace dispatch merge pass. Neither is a cross-language linker.
There is no durable relation that binds an OCaml `external` declaration to a C
or Rust definition, so the graph must not currently traverse that boundary.

## Corpus boundary correction

An exploratory text search under `/home/mathias/dev/tezos` returned material
from nested worktrees, vendors and unrelated projects. It is unsuitable for
measurements. The Stage-1 corpus is fixed to
`/home/mathias/dev/tezos/tezos`; nested `.git`, `worktrees`, `vendor(s)` and
generated directories must be excluded by the census implementation.

## Concrete source examples in the selected checkout

The Octez tree contains direct OCaml externals in
`etherlink/lib_wasm_runtime/ocaml-api/wasm_runtime_gen.ml`, including native and
bytecode primitive spellings such as `wasm_runtime_run_bytecode` /
`wasm_runtime_run`. It also contains C-facing bindings such as
`etherlink/bin_node/lib_dev/sqlite_receipt_bloom/sqlite_receipt_bloom.ml`.
These are candidates for the later OCaml→C stage, not evidence of a resolved
definition yet.

## Required evidence ladder

1. Text declaration or export: census candidate only.
2. Matched build target plus ABI and target compatibility: link candidate.
3. Definition in the exact linked object/archive: bounded FFI link.
4. Dynamic lookup, unbounded registration, missing object or conflicting
   definitions: retained `MAY_TOP(ffi)` with a reason.

The first implementation must stop at level 1 and report its inability to
reach levels 2–3; otherwise a source-name match could be mistaken for linkage.

## First reproducible raw census

`node roster/ffi-boundary-census/census.js /home/mathias/dev/tezos/tezos`
completed on the selected root with source-record digest
`164138c7e366dd4b0354b534724556d9bbf187ceae4da200d6198a172c6effad`:

| Measure | Count |
|---|---:|
| source files scanned | 20,445 |
| source-level records | 2,326 |
| OCaml externals | 1,672 |
| C `CAMLprim` definitions | 207 |
| Rust C-ABI exports | 446 |
| OCaml callbacks | 0 |
| dynamic-load occurrences | 1 |

These are intentionally **not linkage counts**. The first raw run accidentally
entered the checkout's `_opam` build switch, yielding 24,061 records. `_opam`
and `.opam-switch` are now explicit exclusions; the corrected result above is
the only retained observation. The checkout still carries vendored libraries and
historical protocol families, so source text alone cannot decide which inputs a
selected target links. Stage 2 must introduce build-target/artifact attribution
before using any of these counts as an improvement metric.
