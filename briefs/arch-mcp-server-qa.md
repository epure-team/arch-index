# QA Brief — arch-mcp-server

**Date:** 2026-07-08
**Status:** GO ✅

## Quality Gates

| Gate | Command | Result | Duration |
|---|---|---|---|
| Build | `opam exec -- dune build` | ✅ PASS (exit 0) | <1s |
| Tests | `opam exec -- dune test --force` | ✅ 87 passed, 0 failed (26+8+17+26+10) | <1s |
| Format | — | not documented (no fmt/lint gate in this repo) | — |
| Shell selftests | `./selftest-contract.sh && ./selftest-load.sh && ./selftest-mcp.sh` | ✅ PASS (0,0,0) | ~2s |

`./selftest-effects.sh`: pre-existing failure on clean main (item-1 QA brief) — excluded.

## Spec Runnable Checks (specs/arch-mcp-server.md)

| Check | Result |
|---|---|
| CHECK-1 initialize + tools/list → 2024-11-05, 11 tools | ✅ PASS |
| CHECK-2 garbage-line recovery (-32700 then result) | ✅ PASS |
| CHECK-3 arch_find on flat fixture | ✅ PASS (unit + selftest) |
| CHECK-4 sound verdict + legacy REFUSED | ✅ PASS (unit fixtures + selftest legacy DB) |
| CHECK-5 arch_metrics byte-parity vs `arch-query metrics` on self-index | ✅ PASS |
| CHECK-6 `--db /nonexistent` → exit 2 | ✅ PASS |
| CHECK-7 dune test (test_arch_mcp suite) | ✅ PASS |

## Extra probes

- String integer arg (`{"n":"25"}`) → isError invalid arguments ✅
- Determinism (same session twice, byte-identical) ✅
- stdout purity + notification silence + string-id echo ✅ (selftest-mcp.sh assertions)

## Tests: detail

- New tests: 26 (test_arch_mcp: protocol 8, core tools 10, sound tools 5, metrics 3)
- Existing tests: 61 pass, 0 fail — no regression.

## Cross-runtime QA (codex exec, workspace-write sandbox)

- GATE-1..4 (build, dune test, selftest-mcp, initialize pipe): **all PASS**, matching the primary run.
- Tree integrity: porcelain hash identical before/after.
- DISPUTED: impl brief claimed "24 new / 85 total" tests; codex measured 26/87. **Resolution:** stale count — review phase added 2 regression tests after the brief was written; brief corrected in place. No gate divergence; codex NO-GO rested solely on this doc claim (same failure mode as item 1 — brief counts should be finalized post-review; noted for friction log).

## Verdict

**GO** — ready for `/roster-ship`
