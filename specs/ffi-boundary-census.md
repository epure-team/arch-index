# FFI boundary census v1

## Purpose

This specification defines a read-only source inventory for candidate OCaml ↔ C
↔ Rust boundaries. It is evidence for prioritisation, not a linker and not a
call-graph producer.

## Contract

The executable accepts exactly one corpus-root directory and emits one JSON
object. The object contains a schema version, canonical root, exclusions, scope,
file count, sorted records, summary counts and a digest of those records.

Each record has `mechanism`, source-relative `path`, positive `line` and
`symbol`. The supported mechanisms are:

- `ocaml_external`: non-`%` primitive spellings from an OCaml external;
- `camlprim`: a C OCaml-runtime entry declaration;
- `rust_c_abi`: a Rust C-ABI export carrying `no_mangle` or `export_name`;
- `callback`: a C OCaml runtime callback operation;
- `dynamic_load`: an explicit dynamic loader operation.

## Refus and boundaries

- The root must be an existing directory; malformed arguments exit 2.
- Symbolic links and excluded nested build/vendor/worktree directories are not
  traversed. A record path is always relative to the selected root.
- An OCaml compiler primitive beginning `%` is deliberately absent: it is not an
  FFI symbol.
- Same spelling at two endpoints is not a binding. The output makes no
  `MUST`, `MAY_ENUMERATED`, target, ABI or linkage claim.
- The presence of source in a tree does not prove that a build target consumes
  it; target/artifact attribution is Stage 2.

## Determinism

Records are ordered by mechanism, path, line and symbol. Summary counts are
computed only from that ordered record list; the digest is SHA-256 over its JSON
serialization. A rerun over unchanged inputs must reproduce the same object
apart from no field (there is intentionally no timestamp).

## Acceptance checks

1. The built-in self-test has one external, one `%` primitive, C entry, callback,
   dynamic load, Rust export and nested excluded worktree; exactly the five
   supported candidate records remain.
2. A real selected-root run validates object shape, ordering, record-to-summary
   agreement, root confinement and absence of `%` symbols.
3. The Octez raw census is recorded as an observation only and is never used as
   an FFI-link or call-graph precision claim.
