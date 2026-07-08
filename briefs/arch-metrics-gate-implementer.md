# Implementer Brief — arch-metrics-gate

**Status:** VALIDATED
**Spec (contract):** specs/arch-metrics-gate.md — FR-001..FR-020 are binding. Read it first.
**Plan:** briefs/arch-metrics-gate-plan.md

## Goal

Three vertical slices, in order:
1. `arch-compare` OCaml engine (lib + cmdliner bin + Alcotest suite) — port of `~/dev/octez-manager/tools/arch_compare.ml` with spec deltas.
2. `arch-query <db> metrics [-o FILE]` bash subcommand emitting flat JSON metrics.
3. Dogfood: committed `metrics-baseline.json` + `.metrics-accept`, CI gate step, `docs/adr/002-metrics-gate.md`, README + arch-query header updates.

## Scope boundary (do NOT)

- No hard floors, no DB access in arch-compare, no multi-component baselines, no consumer hook installation, no indexer/schema changes, no new metric collection.

## Key facts (verified by research — re-verify column names in code before writing SQL)

- `arch-query` is bash: `q()`/`qraw()` helpers (:62-63), `case "$CMD"` dispatch (:96-494), `*)` → exit 2; feature-detect + `exit 3` refusal pattern (e.g. :154-158); header comment block :1-57 is the usage doc — extend it.
- Exit contract: 0 ok, 1 gate failure, 2 usage/malformed input, 3 refuse.
- Schema sources: `modules.lines` (architecture-schema.sql:11), `functions.line_count` GENERATED (:30), `comment_quality_score` on functions, `exposed` (main) vs `exported` (flat NDJSON path — READ `lib/arch_db/arch_load.ml` and the schema to confirm exact names/types before coding).
- Existing OCaml layout to mirror: `lib/arch_effects/` + `bin/arch_serve/` + `test/dune` (Alcotest, sqlite3, Yojson available).
- Reference engine `~/dev/octez-manager/tools/arch_compare.ml`: direction sets :47-76, JSON parse :87-97, accept parse :109-243 (reason priority: inline `#` > trailing text > preceding comment block; blank line clears), evaluate :294-319, render :382-459, has_failures :461-464. Port tests from `~/dev/octez-manager/tools/test_arch_compare.ml`.

## Spec deltas vs octez (do not copy blindly)

- Direction table: worse_when_higher = {large_files, large_functions, undocumented_exposed, may_top_edges}; worse_when_lower = {doc_coverage_pct}. Informational (never block): modules, total_functions, exported_functions, call_edges.
- Duplicate accept entry for a metric ⇒ invalid (FR-014). |current−baseline| < 1e-9 ⇒ unchanged (FR-011). `--accept FILE` flag; absent file ⇒ empty policy, no error (FR-016). Malformed JSON input ⇒ exit 2 naming the file (FR-009). Report rows + JSON keys sorted by metric name (FR-001, FR-010).

## Metrics SQL (Slice B)

Always (given `functions`; absent ⇒ exit 3): `modules` (count modules table if present, else omit), `total_functions`, `exported_functions` (via detected exposed/exported col), `call_edges`. Conditional: `may_top_edges` (calls.kind='MAY_TOP'), `large_files` (modules.lines>500), `large_functions` (functions.line_count>50), `undocumented_exposed` (exposed AND (comment_quality_score IS NULL OR =0)), `doc_coverage_pct` (ROUND(100.0*(1−undoc/exposed),1); 100.0 when exposed=0 — EC-1).
Emission: probe `SELECT json_object('a',1)` via qraw; if OK build one `SELECT json_object(<sorted k/v pairs>)`; else printf fallback. `-o FILE`: write file, nothing on stdout; unwritable ⇒ exit 2.

## Steps + completion criteria

1. Slice A: `lib/arch_compare/{arch_compare.ml,arch_compare.mli,dune}`, `bin/arch_compare_cli/{arch_compare_cli.ml,dune}` (public exe name `arch-compare` wrapper script at repo root like `arch-query`? — repo convention: top-level wrapper scripts exist for arch-index/arch-query; add `./arch-compare` wrapper invoking the built exe), `test/test_arch_compare.ml` wired into `test/dune`. TDD: port octez tests, add EC-4 (bound inclusive), EC-5 (unused waiver harmless), duplicate-entry, missing-metric, malformed-JSON→exit-2 (CLI test via selftest). Done when `dune test` green + CHECK-2/3/4/6 pass.
2. Slice B: `metrics` branch in `arch-query` + header doc line. Done when CHECK-1 passes on self-index DB and CHECK-7 passes on a flat DB built like `selftest-load.sh` does; AC-2 verified.
3. Slice C: generate baseline from self-index, write `.metrics-accept` (only `#` header comments documenting format + empty policy), CI step in `.github/workflows/ci.yml` after golden diff (reuse `/tmp/self.db`), `docs/adr/002-metrics-gate.md` (regeneration procedure combined with golden-file procedure, waiver workflow, C-5 missing-metric semantics, consumer `git show HEAD:metrics-baseline.json` pre-commit pattern), README section. Done when AC-7 verified locally (clean pass + artificial regression fails).

## Quality gates (run all before handing to review)

```bash
opam exec -- dune build
opam exec -- dune test
./selftest-contract.sh && ./selftest-load.sh && ./selftest-effects.sh
# self-gate end-to-end:
./arch-callgraph-ocaml --build-dir=_build/default/lib/arch_index --db-path=/tmp/self.db --schema-path=architecture-schema.sql
./arch-query /tmp/self.db metrics | jq -e 'type=="object" and (to_entries|all(.value|type=="number"))'
```

## Risks to respect

- Verify flat-schema column names in code first (top plan risk).
- json_object probe/fallback (older sqlite3).
- Do not let `set -euo pipefail` turn a feature-detect miss into a crash — follow the existing qraw error-swallowing pattern.
