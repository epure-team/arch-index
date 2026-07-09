# QA Scope — cfg-postdom-dominance

**Status:** VALIDATED

## Deterministic gates (in order; all under the local switch)

```bash
eval $(opam env --switch=/home/mathias/dev/arch-index --set-switch)   # EVERY shell
which dune   # must be /home/mathias/dev/arch-index/_opam/bin/dune

# Gate 1: clean build
rm -rf _build && dune build

# Gate 2: unit + integration tests
dune test

# Gate 3: shell selftests (all)
./selftest-contract.sh
./selftest-load.sh
./selftest-effects.sh
./selftest-callgraph-ocaml.sh
STRICT=1 ./selftest-callgraph-soundness.sh
./selftest-callgraph-go.sh

# Gate 4: self-index golden + kind integrity + determinism
BIN=./_build/default/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe
$BIN --build-dir=_build/default/lib/arch_index --db-path=/tmp/qa1.db --schema-path=architecture-schema.sql
$BIN --build-dir=_build/default/lib/arch_index --db-path=/tmp/qa2.db --schema-path=architecture-schema.sql
sqlite3 /tmp/qa1.db "SELECT 'modules: '||count(*) FROM modules; SELECT 'functions: '||count(*) FROM functions; SELECT 'calls: '||count(*) FROM calls;" | diff test/fixtures/self-index-stats.txt -
test "$(sqlite3 /tmp/qa1.db 'SELECT count(*) FROM calls')" = "$(sqlite3 /tmp/qa2.db 'SELECT count(*) FROM calls')"
sqlite3 /tmp/qa1.db "SELECT count(*) FROM calls WHERE kind IS NULL OR kind NOT IN ('MUST','MAY_ENUMERATED','MAY_TOP');"   # must be 0
sqlite3 /tmp/qa1.db "SELECT value FROM comment_db_meta WHERE key='callgraph_contract';"   # must be v1

# Gate 5: Go build/vet
( cd callgraph-go && go build ./... && go vet ./... )
```

## Manual records (in the QA brief, not CI-gated)

- CHECK-6: self-index kind distribution (`SELECT kind, count(*) …`) — expectation MAY_TOP well under 40% (was 77.9%).
- CHECK-7: the 15-subcommand audit table (from step 7) is present in the review artifacts.
- Population-diff artifact from step 2 exists and shows zero drops.

## Behaviors to validate (spot queries on the soundness-corpus DB)

- `reaches invoked island` → PATH EXISTS; `reaches lam_map island` → no MUST path.
- `unreachable lam_map island` → REACHABLE (may-reach); `unreachable cond_if island` → UNREACHABLE.
- `escapes lam_map` → empty.
- Unused-lambda fixture: node present, no incoming edge.
- `exported` lists no `<fun:` names; `find '<fun:'` returns lambda nodes.

## TUI

None in scope.

## Cross-runtime QA

codex available → mandatory independent re-run of Gates 1–4 + spot behaviors; discrepancy = NO-GO.
