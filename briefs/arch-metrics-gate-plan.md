# Plan — arch-metrics-gate

**Date:** 2026-07-08
**Status:** VALIDATED (autonomous mode — dual-voice run inline, subagent budget exhausted; quiz waived per user pre-authorization)

## Sequential steps

1. **Slice A — `arch-compare` OCaml engine + tests** — new `lib/arch_compare/arch_compare.ml{,i}` (pure: JSON parse, direction table, accept-file parse, evaluate, render) + `bin/arch_compare_cli/` (cmdliner: `arch-compare [--accept FILE] <baseline.json> <current.json>`) + `test/test_arch_compare.ml` (Alcotest). Port semantics from `~/dev/octez-manager/tools/arch_compare.ml` with spec deltas: our metric direction table, duplicate-entry ⇒ invalid (FR-014), 1e-9 unchanged tolerance (FR-011), `--accept` override + absent-file-is-empty-policy (FR-016), exits {0,1,2} (FR-007/FR-009). Completion: CHECK-2,3,4,6 pass; `dune test` green.
2. **Slice B — `arch-query metrics` bash branch** — new `case` branch in `arch-query` before `*)`. Feature-detect (`pragma_table_info`/`sqlite_master`): `functions` absent → exit 3 guidance; `exposed` vs `exported` column; `calls.kind`; `modules.lines`; `functions.line_count`; `comment_quality_score`. Build one `SELECT json_object(...)` with lexicographically-ordered keys from the detected set (FR-001..005); `-o FILE` writes file (unwritable → exit 2). Completion: CHECK-1,7 pass on self-index (CMT) and flat (NDJSON) DBs.
3. **Slice C — dogfood gate + docs** — generate `metrics-baseline.json` from the self-index; commit it + `.metrics-accept` (header-documented empty policy); add CI step after the golden diff reusing `/tmp/self.db`: `./arch-query /tmp/self.db metrics -o /tmp/m.json && ./_build/default/bin/arch_compare_cli/arch_compare_cli.exe metrics-baseline.json /tmp/m.json`; write `docs/adr/002-metrics-gate.md` (regeneration, waiver workflow, missing-metric semantics C-5, consumer `git show HEAD:` pattern — FR-018..020). Update README + arch-query header doc block. Completion: AC-7 verified locally.

## Dependencies

Step 3 needs 1 and 2 (gate consumes both). Steps 1 and 2 are independent; 1 first because it is pure and unit-testable, de-risking the comparison semantics before wiring.

## Identified risks

| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| `json_object()` missing in target sqlite3 builds (<3.38 non-JSON builds) | Low | metrics emission broken | Detect at runtime (`SELECT json_object('a',1)` via qraw); fall back to printf hand-assembly; selftest validates output with `jq -e` in CI |
| Accept-file parser edge cases (comment priority, blank-line clearing) eat time | Medium | Slice A overrun | Port octez tests verbatim, add duplicate/EC-4/EC-5 cases first (TDD) |
| Flat-schema column realities differ from research (e.g. `exported` type/name) | Medium | wrong metrics on NDJSON DBs | Implementer must read `lib/arch_db/arch_load.ml` + `architecture-schema.sql` before writing SQL; CHECK-7 exercises a real flat DB |
| Baseline churn friction (2 files to regenerate: golden + baseline) | Medium | maintainer annoyance | ADR gives one combined regeneration procedure; only ratchet metrics tracked (FR-020) so routine growth never blocks |
| CI ordering/duplication of self-index build | Low | slow CI | Reuse existing `/tmp/self.db` from the golden step |

## Decisions made

| Point | Decision | Reason |
|---|---|---|
| JSON emission method (DISAGREE: `sqlite3 -json` row-array vs `json_object()` vs printf) | `json_object()` single query, printf fallback behind runtime probe | row-array needs jq to flatten (new hard dep); json_object gives correct types/escaping for free; probe keeps old sqlite working |
| Hard floors | Excluded from v1 | Spec clarification; grammar complexity |
| Compare engine language | OCaml lib+bin with Alcotest | Logic-heavy, unit-testable; repo already has Yojson/Alcotest; octez port is proven |
| Duplicate accept entries | Invalid (fail) | Stricter than octez; silent last-wins hides review errors |
| Slicing | Vertical (engine / emission / gate) | Each slice independently demoable; no layered plan flagged by either voice |

## Assumptions

- `dune` project accepts a new public lib `arch_compare` and executable without opam re-pinning (mirrors existing `lib/arch_effects` + `bin/arch_serve` layout).
- CI runner (ubuntu-latest) sqlite3 ≥3.38 (json_object available) and has `jq` for validation checks.
- octez-manager code is the user's own — porting is unencumbered.
- The CMT self-index populates `modules` rows (golden says 18) but `modules.lines` population is unverified — baseline simply contains whatever `metrics` emits (C-10); implementer records the actual emitted key set in the QA scope.

## Consensus Table

| Point | Voice 1 (architect) | Voice 2 (skeptic) | Status |
|---|---|---|---|
| 3 vertical slices, engine first | ✅ | ✅ | AGREE |
| Accept-parser is the hidden time sink | ⚠️ noted | ✅ "3x longer" candidate | AGREE (TDD mitigation) |
| JSON emission method | json_object() | printf-only (no sqlite JSON dep) | DISAGREE → resolved: json_object + probe/fallback |
| Reuse /tmp/self.db in CI | ✅ | ✅ (flags duplicate-build waste) | AGREE |
| Brief direction (bash metrics + OCaml compare) | keep | keep | AGREE — no USER-CHALLENGE |
| Flat-schema assumptions need verification in-code, not from research | ✅ | ✅ | AGREE (implementer instruction) |
