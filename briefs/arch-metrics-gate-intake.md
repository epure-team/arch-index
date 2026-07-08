# Intake Brief — arch-metrics-gate

**Date:** 2026-07-08
**Status:** VALIDATED (autonomous mode — user pre-authorized gate decisions)
**Type:** feature

## Goal

Add a metrics/compare regression gate to arch-index: (1) an `arch-query <db> metrics` subcommand that emits a flat, machine-readable JSON object of codebase metrics computed from an existing index DB; (2) a `compare` capability that diffs a current metrics JSON against a committed baseline JSON and exits non-zero on regression; (3) a `.metrics-accept` reviewed-waiver protocol — per-metric bounds with mandatory inline reasons — so intentional regressions can be accepted explicitly and auditable-y.

This upstreams a pattern independently reinvented in three downstream repos (octez-manager, epure, aegis-cloth), letting them converge on the canonical tool. Value: any repo indexed by arch-index gets a CI-enforceable architecture-quality ratchet (doc coverage, large files/functions, god modules, fan-in growth) with a reviewed escape hatch.

## Scope Boundary

Explicitly OUT of scope:
- Pre-commit hook installation in consumer repos (they wire the gate themselves; we document the pattern incl. `git show HEAD:` baseline pinning).
- New metric *collection* infrastructure — metrics are computed from tables/columns that already exist in the schema (`modules.lines`, `functions.line_count`, `comment_quality_score`, `exposed`, `calls`, views). No indexer changes.
- Items 2–5 of the consolidation roadmap (MCP server, health-query pack, language registry, gardening tables).
- Multi-component baselines (aegis-cloth's backend/frontend split) — one DB, one metrics object; consumers compose.
- epure-style hard floors — considered in spec; if adopted, minimal.

## Relevant Files

| File | Role | Key snippet |
|---|---|---|
| `arch-query` | bash CLI to extend; `case "$CMD"` dispatch at :96–494 | `q() { sqlite3 -box "$DB" "$1"; }` / `qraw()`; `stats` at :138–146 computes functions/exported/call_edges + per-kind counts; feature-detect + `exit 3` refusal pattern; `exit 2` unknown subcommand |
| `architecture-schema.sql` | metric sources | `modules.lines` (:11), `functions.line_count` GENERATED (:30), views `v_most_called` (:274), `v_large_files` (:233), `v_large_functions` (:240), `v_undocumented` (:248), `v_high_deps` (:356) |
| `lib/arch_index/comment_parser.ml:269` | existing Yojson usage in OCaml lib | `Yojson.Safe.to_string (\`List lst)` |
| `test/` + `test/dune` | Alcotest suites (test_parsers, test_effects, test_capabilities) | pattern for a new `test_metrics_compare.ml` |
| `.github/workflows/ci.yml:29-42` | CI gate surface; golden-diff pattern | `diff test/fixtures/self-index-stats.txt … || exit 1` |
| `docs/adr/001-self-index-golden.md` | ADR pattern for baseline regeneration procedure | update-procedure doc style to mirror |
| `~/dev/octez-manager/tools/arch_compare.ml` | reference engine (strictest): direction sets :47–76, `.metrics-accept` parse :109–243, evaluate :303–319, render :382–459, `has_failures` :461–464; own Alcotest suite | port target |
| `~/dev/octez-manager/tools/arch_query.ml:614-916` | reference `cmd_metrics` (fixed metric list, flat JSON, `-o`) + `cmd_compare` (exit 1) | metric list source |
| `~/dev/epure/scripts/pre-commit:84-108` | reference consumer wiring: baseline pinned via `git show HEAD:metrics-baseline.json` | documentation material |
| `~/dev/epure/tools/arch_query_impl.ml:825-830` | hard-floor variant (unwaivable floor beats waiver) | spec consideration |

## Architecture Notes

- `arch-query` is bash; all subcommands are `case` branches using `q`/`qraw` over sqlite3. The **metrics emission** fits this convention (sqlite3 `json_object()` or hand-assembled flat JSON). The **compare engine** (waiver parsing, direction classification, report rendering) is string/logic-heavy — octez implements it as a standalone OCaml module (`arch_compare.ml`) with a unit-test suite; arch-index already has the OCaml lib + Alcotest + Yojson infrastructure to host a port. Exact split (pure-bash vs bash `metrics` + OCaml `compare` binary) is a spec/plan decision.
- Exit-code contract to respect: 0 success, 1 gate failure (regression/diff), 2 usage/malformed input, 3 refuse (missing feature tables / unsound index). `compare` failing on regression should use exit 1 (CI-failure semantics, consistent with golden diff), not 2/3.
- Metrics must only use always-present schema objects, or feature-detect and omit (existing arch-query convention) — the gate must work on flat (NDJSON/CMT) and main (LSP) schemas, which differ (`caller_name` TEXT vs `caller_id` FK).
- Waiver semantics adopted from octez (per task statement): `<metric> <op> <bound>` + mandatory reason; op fixed per metric direction (`<=` worse-when-higher, `>=` worse-when-lower); invalid entry ⇒ gate failure; regression accepted only if within bound.
- Baseline is a committed flat JSON (`metrics-baseline.json` convention); regeneration procedure documented ADR-style; arch-index should self-apply the gate in its own CI (dogfood).

## Quality Gates

```bash
# Build
opam exec -- dune build

# Tests
opam exec -- dune test
./selftest-contract.sh && ./selftest-load.sh && ./selftest-effects.sh

# Lint/Format
# not documented (no fmt/lint gate in CI)

# CI extras (self-index golden)
# see .github/workflows/ci.yml:29-42
```

## Open Questions

- [ ] Should epure-style unwaivable hard floors be included in v1? (Spec phase decides; default lean = include a minimal optional floor mechanism only if it doesn't complicate the waiver grammar.)
- [ ] Implementation split: pure-bash compare vs OCaml `arch-compare` binary. (Plan decides; lean = OCaml port of octez `arch_compare.ml` with Alcotest suite, bash `metrics` subcommand.)

_(Both questions are design choices delegated to spec/plan under autonomous mode — no implementer may silently assume; the spec must resolve them explicitly.)_
