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
`27acc8ac25f267c4326f7ff1003df2090927ffb4dbddd56befa8c7a1bff97869`:

| Measure | Count |
|---|---:|
| source files scanned | 80,541 |
| source-level records | 24,061 |
| OCaml externals | 18,669 |
| C `CAMLprim` definitions | 4,747 |
| Rust C-ABI exports | 446 |
| OCaml callbacks | 184 |
| dynamic-load occurrences | 15 |

These are intentionally **not linkage counts**. The checkout carries vendored
libraries and historical protocol families inside its canonical root; source
text alone cannot decide which are linked into a selected target. Stage 2 must
introduce build-target/artifact attribution before using any of these counts as
an improvement metric.
