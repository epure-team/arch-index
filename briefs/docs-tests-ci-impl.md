# Implementation Brief — docs-tests-ci

**Date:** 2026-06-25
**Mode:** full
**Status:** COMPLETED

## Modified files

| File | Type of change | Reason |
|---|---|---|
| `dune-project` | Modification | Added `ppx_inline_test`, `ppx_assert`, `alcotest` deps |
| `lib/arch_index/dune` | Modification | Added `(inline_tests)` stanza; added `ppx_inline_test ppx_assert` to pps |
| `lib/arch_index/comment_parser.ml` | Modification | Added 18 inline tests for internal helpers |
| `lib/arch_index/arch_index_comment_parser.ml` | Modification | Added 15 inline tests for internal helpers |
| `lib/arch_index/arch_index_db.ml` | Modification | Added 7 inline tests (happy paths, `:memory:` DB) |
| `test/dune` | Creation | Alcotest test stanza |
| `test/test_parsers.ml` | Creation | 10 alcotest tests for `Comment_parser` public API |
| `test/fixtures/self-index-stats.txt` | Creation | Golden file: 18 modules, 144 functions, 2376 calls |
| `.github/workflows/ci.yml` | Modification | Removed `|| true`; fixed OCaml to 5.3; added shell tests + self-index step |
| `docs/edge-kind-contract.md` | Creation | Edge-kind / ⊤-marking / soundness + agent use cases |
| `docs/schema.md` | Creation | DB schema reference |
| `docs/install.md` | Creation | LSP backend install instructions |
| `docs/adr/001-self-index-golden.md` | Creation | ADR for golden file policy |
| `README.md` | Modification | Rewritten: 3 Mermaid diagrams, quick start, agent use cases, doc links |

## Decisions made

- **`arch-query stats` incompatible with architecture DB**: `arch-query` expects `comment_db` schema (`exported` column); `arch_callgraph_ocaml` writes the full architecture schema (`exposed` column). Used raw `sqlite3` queries for the golden diff instead.
- **Golden file uses raw sqlite3 counts**: `modules:`, `functions:`, `calls:` — stable, environment-independent, catches regressions.
- **OCaml 5.2 → 5.3 in CI**: `dune-project` requires `>= 5.3.0`; CI was pinned to 5.2 (would have failed silently).
- **Alcotest suite tests only `Comment_parser`**: `Arch_index_comment_parser` is not in `arch_index.mli`'s public exports — covered by inline tests instead.
- **`arch-callgraph-ocaml` wrapper not used in CI**: it requires `bin/arch-callgraph-ocaml` binary on disk; CI uses the `_build/` binary directly.

## Quality Gates

- [x] Build: `opam exec -- dune build` ✅
- [x] Tests: `opam exec -- dune test` ✅ (43 inline + 10 alcotest = 53 tests)
- [x] Shell selftests: `./selftest-contract.sh` ✅, `./selftest-load.sh` ✅
- [x] Self-index golden: `diff test/fixtures/self-index-stats.txt` ✅

## Points of attention for review

- CI OCaml compiler bumped from 5.2 to 5.3 — verify this is available in `ocaml/setup-ocaml@v3`
- The `|| true` suppression is fully removed; first CI run with real test failures will now surface them
- Golden file must be updated when `lib/arch_index/` modules are added/removed (see ADR 001)
- README removed all references to internal project context (bounty/campaign terminology, private tooling)

## Identified out-of-scope

- `selftest-callgraph-go.sh` and `selftest-callgraph-ocaml.sh` in CI — require live LSP; left as local selftests
- Testing error paths in `arch_index_db.ml` — `exec_exn` calls `exit 1`; would require refactoring which is out of scope
- `Arch_index_comment_parser` alcotest tests — module is not public; covered inline
