# Reviewer Brief — docs-tests-ci

**Status:** VALIDATED

## What Was Implemented

1. OCaml unit tests added inline (`ppx_inline_test`) to `comment_parser.ml`, `arch_index_comment_parser.ml`, `arch_index_db.ml` (happy paths, `:memory:` DB)
2. Alcotest integration suite in `test/test_contract.ml` covering the public `arch_index` API
3. CI fixed: `|| true` removed; shell selftests wired; Go setup + self-indexing golden diff step added
4. `docs/` files created: `edge-kind-contract.md`, `schema.md`, `install.md`, `adr/001-self-index-golden.md`
5. README rewritten: ≤ 50 lines, two Mermaid diagrams, links to docs/

## Files to Audit First

- `lib/arch_index/dune` — did `(inline_tests)` land in the right stanza? Does `(pps ...)` include all four ppx processors without conflicts?
- `lib/arch_index/arch_index_db.ml` — are inline tests using `:memory:` only? Does any test call an error path that would invoke `exit 1`?
- `.github/workflows/ci.yml` — is `|| true` fully removed? Are all new steps in the right position (after build, before release)?
- `test/fixtures/self-index-stats.txt` — is this file committed? Does it have a non-trivial function count?
- `README.md` — is it ≤ 50 lines of prose? Do all `docs/` links resolve? Do Mermaid diagrams render on GitHub?

## Risks to Verify

| Risk | Verification |
|---|---|
| ppx pps chain conflict | Run `dune build` from scratch; confirm no ppx driver errors |
| `arch_index_db` inline tests hit `exit 1` | Grep tests for error-path coverage; confirm only `:memory:` happy paths |
| `_build/` CMT path in CI is wrong | Check golden file is non-empty and function count is plausible (expect ≥ 50) |
| `arch-callgraph-ocaml` wrapper binary name mismatch | Verify CI build step names the binary to match what the wrapper script expects |
| `dune test` still has `|| true` anywhere | `grep -n '|| true' .github/workflows/ci.yml` should return nothing |
| README links to docs/ files that don't exist | Check all Markdown links resolve on the branch |

## Expected Behaviors to Confirm

- `opam exec -- dune test` exits 0 with test output visible (not suppressed)
- `./selftest-contract.sh` exits 0
- `./selftest-load.sh` exits 0
- `diff test/fixtures/self-index-stats.txt <(./arch-query /tmp/self.db stats)` exits 0 after self-index run
- README renders correctly on GitHub (Mermaid diagrams visible, not raw text)
- `docs/adr/001-self-index-golden.md` documents how to update the golden file
