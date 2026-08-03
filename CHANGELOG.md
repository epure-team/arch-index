# Changelog

## [Unreleased]

### Added
- `arch-impact`: per-diff change-impact briefing over the sound call graph — touched functions,
  affected exported API, blast radius, ⊤ frontier, reaching tests, effects crossed, and findings
  on touched lines. Text / Markdown / JSON output. `--fail-on-new-findings` implements the R5
  ratchet and is off by default.
- NDJSON contract: optional `line_start` / `line_end` on `function` records, so a diff hunk maps
  to a function on the flat schema too. A **half** span aborts the load — it would mis-map every
  hunk, which is worse than no span.
- `arch-callgraph-go` emits source spans for every function that has syntax. Synthetic functions
  (wrappers, thunks, `init`) carry none by design.
- `arch-rules`: architecture fitness functions over the sound graph — layering, export-surface,
  effect and declared-dependency rules. Four verdicts (`VIOLATION` / `POSSIBLE` / `UNKNOWN` /
  `PASS`) instead of the pass-fail every declared-import checker reports; `PASS` is refused on an
  index that is not ⊤-marked, and a rule matching no code fails as VACUOUS.
- `arch-rules.txt`: arch-index's own layering rules, checked in CI.
- `lib/arch_tools`: the read model shared by every tool — schema detection, the graph (keyed
  by row id on the main schema, by name on the flat one), selectors, path resolution, the LCOV
  reader, the diff reader, and the sqlite3-compatible output formatter — so no two tools can
  drift on how the graph is keyed or which edges are in a closure. On Caqti, so a query's
  parameter arity and row shape are checked by the compiler.
- `arch-mutants`: mutation testing targeted by the call graph. `plan` decides what is worth
  mutating (test-reachable code, with the tests that must rerun for each target) and partitions
  every indexed function into exactly one bucket with a reconciliation count; `report` attributes
  each surviving mutant to the innermost enclosing function and the tests that failed to kill it.
  Generic NDJSON input plus a Mutaml adapter. No mutation engine of its own, and deliberately no
  mutation score.
- `arch-coverage`: reachability-weighted coverage from an LCOV tracefile — API-relative
  never-exercised functions, covered-but-only-⊤-reachable functions, and (with `--mutants`) the
  covered-yet-unkilled pairing that replaces a coverage percentage. `--write` finally populates
  the `coverage` table. LCOV in, so every ecosystem is covered by one parser.
- `arch_mcp`: an MCP server (stdio JSON-RPC) built on mcp-kit, exposing reachability, escapes,
  findings, change impact, architecture rules and the mutation plan to agents. Every result
  carries a `provenance` block — contract stamps, producing backend, and whether a negative is
  evidence at all. It SHELLS OUT to the command-line tools rather than reimplementing any
  verdict, so an agent and a reviewer cannot be told different things. Marked `(optional)` in
  dune because mcp-kit is not on opam yet; a dedicated `mcp` CI job pins it and asserts the
  binary was actually built rather than silently skipped.
- `selftest-impact.sh`, `selftest-rules.sh`, `selftest-mutants.sh`, `selftest-coverage.sh` and
  `selftest-mcp.sh`, wired into CI.

### Fixed
- A legacy index with no `calls.kind` column crashed the closure queries — the column cannot be
  named in SQL when it does not exist. Every edge now reads as MUST there, as `arch-query` does.

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
