# ADR 001 — Self-index golden file

**Status:** Active
**Date:** 2026-06-25

## Decision

The CI self-index step diffs `arch-query`-equivalent stats output against a committed golden file at `test/fixtures/self-index-stats.txt`. Any change to the output fails CI until the golden file is updated.

## Update procedure

When the self-index output legitimately changes (new module added, function renamed, etc.):

```bash
opam exec -- dune build
BIN="./_build/default/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe"
opam exec -- "$BIN" \
  --build-dir=_build/default/lib/arch_index \
  --db-path=/tmp/self.db \
  --schema-path=architecture-schema.sql
sqlite3 /tmp/self.db \
  "SELECT 'modules: ' || count(*) FROM modules; \
   SELECT 'functions: ' || count(*) FROM functions; \
   SELECT 'calls: ' || count(*) FROM calls;" \
  > test/fixtures/self-index-stats.txt
git add test/fixtures/self-index-stats.txt
git commit -m "chore: update self-index golden file (<reason>)"
```

## Rationale

Arbitrary thresholds (≥N functions) give no regression signal — they pass after a catastrophic failure as long as the number stays above the floor. A golden diff catches any unexpected change in the indexed output without requiring manual bookkeeping.
