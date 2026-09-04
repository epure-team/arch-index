(lang dune 3.15)
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
  caqti
  (caqti-driver-sqlite3 (>= 3.0))
  ocaml-compiler-libs
  otoml
  ; FR-024's SHA-256 config digest (lib/arch_index/arch_errors_config.ml).
  digestif
  ; ppx_inline_test and ppx_assert are NOT test-only despite their names: they
  ; appear in the (preprocess (pps ...)) of lib/arch_index and lib/arch_effects,
  ; so the library cannot be built without them. Marking them with-test would
  ; break a plain `opam install`.
  (ppx_inline_test (>= v0.16))
  (ppx_assert (>= v0.16))
  ; alcotest and tezt are used only under test/ and tezt/. Unconditional, they
  ; made every consumer of this package pull a test framework.
  (alcotest (and (>= 1.7) :with-test))
  (tezt (and (>= 4.0) :with-test))
  ; ocaml-lsp-server is a REAL test dependency, not a developer convenience.
  ; tezt/tests/point_free_aliases.ml (S5) and every other test reaching
  ; Arch_tezt.index_project drive the flat producer, which spawns the command
  ; named by language_registry.ml for "ocaml" -- `ocamllsp`. With no server the
  ; producer still writes a database, so the tests do not fail as "no server":
  ; they fail as an empty result set, or worse, pass vacuously. CI installs
  ; gopls, typescript-language-server and rust-analyzer explicitly because opam
  ; cannot; this one opam CAN, so declaring it here is what stops the gap from
  ; recurring silently in any job that runs `opam install --deps-only
  ; --with-test`.
  ;
  ; Pinned exactly, for the same reason the other three servers are pinned in
  ; .github/workflows/ci.yml: the assertions in point_free_aliases.ml are
  ; derived from what this server actually reports, so a server-side change must
  ; arrive as a deliberate bump here rather than as a mystery failure on an
  ; unrelated PR.
  (ocaml-lsp-server (and (= 1.23.1) :with-test))))
