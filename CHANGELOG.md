# Changelog

## [0.2.0] - 2026-06-25

### Added
- `arch-serve`: local HTTP server serving a D3 force-graph SPA from a SQLite DB
  - Neighborhood BFS view (depth 1/2/3), Module view, Reachability query
  - Function search and module filter sidebar
- CMT-based call graph extraction fallback for OCaml projects
  - Walks `_build/default/**/*.cmt` typed ASTs when LSP call hierarchy is unavailable
  - ocamllsp ≤1.23.1 does not implement `textDocument/prepareCallHierarchy`

### Fixed
- OCaml projects producing 0 functions — 5 root causes:
  - `language_id_of_uri` always returned `"typescript"` for `.ml` files
  - `scan_ts_files` used as fallback for OCaml (0 `.ts` files found)
  - `_opam/` local switch (~30k `.ml` files) not excluded from scan
  - `workspace/symbol` cold-start corruption on ocamllsp (stale response in read buffer)
  - `symbol_kind_of_int` table had kinds 6↔12 and 7↔13 swapped vs LSP spec
- LSP call hierarchy bugs: wrong method name, missing `callHierarchy` client capability, `character:0` pointing at `let` keyword instead of function name token
- Timeout in `runner.ml` discarded already-collected function rows

## [0.1.0] - 2026-06-25

### Added
- Initial release extracted from epure
- Sound ⊤-marked call-graph index for Go (go/ssa + CHA) and OCaml (cmt typedtree)
- `arch-index` CLI: build symbol + call-graph database from source
- `arch-query` CLI: query reachability (reaches/unreachable/callers-of/fan-in/exported/find/escapes)
- Three-verdict reachability: REACHABLE / UNKNOWN: MAY_TOP / UNREACHABLE: no path
- Standalone dune project + arch-index.opam
