# Implementation Brief — arch-mcp-server

**Date:** 2026-07-08
**Mode:** full
**Status:** COMPLETED

## Modified files

| File | Type of change | Reason |
|---|---|---|
| `lib/arch_mcp/arch_mcp.ml{,i}` + `dune` | addition | engine: schema detection (xinfo), prepared-stmt SQL, contract check, declarative arg specs (schema+validator from one source), tool registry (11 tools), JSON-RPC/MCP dispatch, framing |
| `bin/arch_mcp/arch_mcp_main.ml` + `dune` | addition | binary: --db validation (exit 2), read-only open + NOTADB probe, stdio loop, stderr-only logging |
| `arch-mcp` | addition | wrapper script (install/build path resolution) |
| `test/test_arch_mcp.ml` + `test/dune` | addition | 24 Alcotest cases over 4 fixtures (flat ⊤-marked, legacy, malformed lowercase-kind, FK/main with generated line_count) |
| `selftest-mcp.sh` | addition | e2e session: string ids, initialized notification, nested arguments, garbage recovery, stdout purity, legacy refusal, startup exit codes |
| `README.md` | modification | MCP section + claude mcp add example + smoke command |
| `.github/workflows/ci.yml` | modification | selftest-mcp step; release packaging now includes arch_mcp_main + arch_compare_cli (Voice-2 objection #11 — arch_compare_cli was also missing from item 1) |

## Decisions made

- Sound tools implemented as recursive-CTE SQL (closure_cte) with bound seeds — bash parity per plan; FK schemas get the same CTE with a caller join (`edges_from`/`caller_expr` fragments computed from trusted schema detection, never user input).
- `doc_coverage_pct` emitted via `Intlit "%.1f"` when fractional: Yojson prints 86.4 as 86.40000000000001, which broke byte-parity with the CLI (CHECK-5); Intlit writes the literal verbatim.
- BUSY handling: one 50ms retry inside step, then Sql_error → isError (spec C-28).
- `arch_fan_in` counts DISTINCT callers via caller_expr (caller_id on FK schema — equivalent to name-distinct there).

## Quality Gates

- [x] Build: `opam exec -- dune build` ✅
- [x] Tests: `opam exec -- dune test --force` ✅ (87 total across 5 suites; 26 new in test_arch_mcp — 24 at implement time, +2 regression tests added during review) _(count corrected after cross-runtime QA dispute)_
- [x] `./selftest-contract.sh` ✅ `./selftest-load.sh` ✅ `./selftest-mcp.sh` ✅ (new)
- [x] Spec checks: CHECK-1 (11 tools + protocolVersion), CHECK-2 (garbage recovery), CHECK-5 (metrics byte-parity vs CLI on self-index), CHECK-6 (exit 2) verified live; CHECK-3/4 covered by unit fixtures + selftest legacy refusal; CHECK-7 = dune test.
- [ ] `./selftest-effects.sh` — pre-existing failure (see item-1 brief), unrelated.

## Points of attention for review

- `closure_cte`/`top_frontier_sql` string composition: fragments are internal literals keyed off schema detection; verify no user input reaches SQL text (all user values via `?` binds).
- `handle_tools_call` catches Sql_error only around the handler — confirm no other exception path can escape to the loop.
- Metrics parity: side-by-side SQL vs arch-query `metrics)` branch; the `modules` count key is emitted whenever the table exists (CLI same).
- The self-index DB has NULL kinds + no meta ⇒ arch_unreachable REFUSES on it (correct per contract; noted in case QA wonders).

## Identified out-of-scope

- Effects/capability MCP tools (roadmap later items).
- arch-serve's kind-blind `/api/reaches` divergence — pre-existing, worth a follow-up fix task.
- `arch_compare_cli` missing from release packaging was an item-1 gap — fixed here in ci.yml.
