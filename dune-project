(lang dune 3.13)
(name arch-index)
(generate_opam_files true)

(package
 (name arch-index)
 (synopsis "Standalone architecture indexer — LSP + CMT + call-graph extraction")
 (description "Extracts function definitions, doc comments, and call graphs from OCaml, TypeScript, Go, Rust, and Python projects via LSP and CMT analysis.")
 (depends
  (ocaml (>= 5.3.0))
  cmdliner
  yojson
  eio
  eio_posix
  cohttp-eio
  tls
  tls-eio
  ca-certs
  mirage-crypto-rng
  uri
  ppxlib
  ppx_blob
  ppx_deriving_yojson
  sqlite3
  ocaml-compiler-libs))
