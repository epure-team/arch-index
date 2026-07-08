# ADR 002 — Metrics regression gate (`arch-query metrics` + `arch-compare`)

**Status:** accepted — 2026-07-08
**Spec:** `specs/arch-metrics-gate.md`

## Decision

arch-index carries a CI-enforceable architecture-quality ratchet:

1. `arch-query <db> metrics [-o FILE]` emits a flat JSON object of metrics computed
   from an existing index DB (no new collection — only tables/columns already present).
2. `arch-compare [--accept FILE] <baseline.json> <current.json>` classifies tracked
   metrics and exits 1 on any blocking regression, missing tracked metric, or invalid
   waiver entry; 2 on malformed input; 0 otherwise.
3. `.metrics-accept` holds reviewed waivers: `<metric> <op> <bound>  # reason`.
   The reason is mandatory; one entry per metric; the bound is inclusive.

Tracked (directional) metrics: `large_files`, `large_functions`, `may_top_edges`,
`undocumented_exposed` (worse when higher); `doc_coverage_pct` (worse when lower).
Informational metrics (`modules`, `total_functions`, `exported_functions`,
`call_edges`) are emitted but never block — routine code growth cannot fail CI.

A metric whose source table/column is absent from the DB is **omitted** from the
JSON, never emitted as 0. Consequence: if a tracked metric present in the baseline
disappears from the current output (e.g. the index was rebuilt with a producer that
lacks that column), the gate fails with "missing tracked metric". This is deliberate
— a silent schema downgrade would otherwise un-track a ratchet. It cannot be waived;
recovering requires deliberately regenerating the baseline (below).

## Baseline regeneration

When the self-index legitimately changes, regenerate the golden file (ADR 001) and
the metrics baseline together:

```sh
opam exec -- dune build
BIN="./_build/default/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe"
opam exec -- "$BIN" --build-dir=_build/default/lib/arch_index \
  --db-path=/tmp/self.db --schema-path=architecture-schema.sql
# golden (ADR 001):
sqlite3 /tmp/self.db "SELECT 'modules: ' || count(*) FROM modules; \
  SELECT 'functions: ' || count(*) FROM functions; \
  SELECT 'calls: ' || count(*) FROM calls;" > test/fixtures/self-index-stats.txt
# metrics baseline:
./arch-query /tmp/self.db metrics -o metrics-baseline.json
git add test/fixtures/self-index-stats.txt metrics-baseline.json
git commit -m "chore: update self-index golden + metrics baseline (<reason>)"
```

Improving a tracked metric (e.g. doc coverage rises) does not fail the gate, but
regenerate the baseline in the same PR so the ratchet advances.

## Waiver workflow

1. CI fails with `REGRESSIONS (CI will fail): <metric>: a -> b`.
2. Either fix the regression, or add a reviewed entry to `.metrics-accept`:
   `large_functions <= 12  # parser refactor tracked in #42`.
3. The entry is itself reviewed in the PR; the gate re-passes only while the current
   value stays within the bound. Remove the entry once the debt is paid.

## Consumer wiring (pre-commit pattern)

Consumers should pin the baseline to `HEAD` so a commit cannot loosen it in the same
change that regresses (pattern proven in epure):

```sh
BASELINE_TMP=$(mktemp); trap 'rm -f "$BASELINE_TMP"' EXIT
git show HEAD:metrics-baseline.json > "$BASELINE_TMP" 2>/dev/null || exit 0  # no baseline yet: skip
arch-query "$DB" metrics -o /tmp/current-metrics.json
arch-compare "$BASELINE_TMP" /tmp/current-metrics.json || {
  echo "Fix the regression or update .metrics-accept with a justification."; exit 1; }
```

## Alternatives considered

- **epure name-only waivers + hard floors**: name-only waivers are unbounded (a
  listed metric can regress forever); rejected in favor of octez-style bounds with
  mandatory reasons. Hard floors (unwaivable minima) deferred — they complicate the
  grammar and can be emulated by refusing waiver PRs in review.
- **Pure-bash compare**: rejected; the waiver parser and report logic are
  unit-tested OCaml (`lib/arch_compare`, 25 Alcotest cases).
