# FFI Stage 2 research

The fixed Octez checkout uses Dune widely. Initial source evidence shows direct
C ownership declarations in `brassaia/index/src/unix/dune`:
`(foreign_stubs (language c) (names pread pwrite))`. This is the desired narrow
fixture: it can prove that the target compiles these C sources, but it cannot by
itself prove a particular OCaml external resolves to `caml_index_pread_int`.

Etherlink has explicit target naming and dependency declarations. For example,
`etherlink/bin_node/lib_dev/sqlite_receipt_bloom/dune` names the library and
declares foreign stubs, while `etherlink/bin_node/lib_dev/dune` lists both wasm
runtime and sqlite libraries. Many Dune stanzas name `octez-rust-deps` or
`evm_node_rust_deps`; they are evidence of build dependency only, not a symbol
link to one of the 446 Stage-1 Rust C-ABI candidates.

The parser therefore needs a deliberately small, lossless Dune subset: stanza
location, `name`/`public_name`, `foreign_stubs` source names and library tokens.
Any unparsed form is an unattributed record, not a guessed association.

## First reproducible attribution

The Stage-2 reader consumes the retained Stage-1 census and only parses direct
Dune fields. On the fixed root it reports 2,326 candidates, of which 1,024 have
one or more same-directory target associations and 1,302 remain unattributed;
it finds 1,136 supported target stanzas and 136 targets that declare a Rust
dependency. The record digest is
`6ec772eca453844c05d28333da611b9351af3961575fcd25c6eff4fa3b336584`.

An association means either `same_dune_directory` or, for a C source named in a
`foreign_stubs` stanza, `foreign_stub_source`. It does **not** mean that an
OCaml external invokes that C source, nor that a Rust dependency links any Rust
C-ABI export. These counts are a build-attribution baseline, not FFI resolution
or precision gains.
