# QA Scope — docs-tests-ci

**Status:** VALIDATED

## Quality Gates

```bash
# Build (must pass clean)
opam install --deps-only --yes .
opam exec -- dune build

# OCaml unit + integration tests (must pass, no suppression)
opam exec -- dune test

# Shell selftests
./selftest-contract.sh   # must exit 0
./selftest-load.sh       # must exit 0

# Self-indexing golden diff
./arch-callgraph-ocaml _build/default/lib/arch_index/ /tmp/self.db
diff test/fixtures/self-index-stats.txt <(./arch-query /tmp/self.db stats)  # must exit 0

# No || true anywhere in CI
grep '|| true' .github/workflows/ci.yml && echo "FAIL: suppression found" || echo "OK"
```

## Behaviors to Validate

1. **`dune test` output is visible**: running `opam exec -- dune test` shows test names and results (not silently suppressed)
2. **Inline tests run**: `dune test` output includes inline test results from `comment_parser`, `arch_index_comment_parser`, `arch_index_db`
3. **Alcotest suite runs**: `dune test` output includes named Alcotest test cases from `test_contract`
4. **Golden file is non-trivial**: `test/fixtures/self-index-stats.txt` function count is ≥ 50 (confirms CMT extraction worked)
5. **README is short**: `wc -l README.md` ≤ 70 (50 prose + ~20 for two Mermaid diagrams)
6. **All docs/ links work**: each link in README to `docs/*.md` resolves to an existing file
7. **ADR exists**: `docs/adr/001-self-index-golden.md` is present and explains the update procedure
8. **CI workflow is correct**: `.github/workflows/ci.yml` has Go setup step, shell test step, self-index step, and no `|| true`
