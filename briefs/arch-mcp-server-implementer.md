# Implementer Brief — arch-mcp-server

**Status:** VALIDATED
**Contract:** specs/arch-mcp-server.md (FR-001..022) — binding; read first.
**Plan:** briefs/arch-mcp-server-plan.md

## Setup

- `git checkout feat/arch-metrics-gate && git checkout -b feat/arch-mcp-server` — the metrics CLI, arch-compare wrapper convention, and metrics spec live there, NOT on main.
- Baseline gates: `opam exec -- dune build && opam exec -- dune test` must be green before starting.

## Goal (4 slices, in order — see plan for full detail)

A. `lib/arch_mcp/` engine + `bin/arch_mcp/` + `arch-mcp` wrapper + protocol unit tests.
B. Core tools over a `schema_info` record (stats, find, exported, fan_in, callers_of, callees_of, reachable_from).
C. Sound tools (reaches, unreachable, escapes) — **verbatim SQL CTE port from arch-query:102-132 with bound params**; shared ContractCheck (arch-query:74-94 parity, case-sensitive kinds).
D. arch_metrics (mirror the `metrics)` branch SQL in arch-query, xinfo detection, omission semantics) + `selftest-mcp.sh` + README + ci.yml (selftest step + add arch_mcp to release packaging loop).

## Hard requirements (traps found in planning)

- ALL logging → stderr; stdout carries only JSON-RPC lines.
- Declarative per-tool arg spec generates BOTH inputSchema JSON and runtime validator (never write them separately).
- `handle_message : ctx -> Yojson.Safe.t -> Yojson.Safe.t option` — ctx carries db + schema_info; None for notifications/blank.
- limit+1 fetch for every `truncated` flag. LIKE args escaped (%, _, \) with ESCAPE clause.
- Tool failures → isError:true content; NEVER JSON-RPC errors. -32700 parse (id null) / -32600 batch/non-request / -32601 unknown method.
- Errors distinct: startup (exit 2) vs no-functions-table (isError "not an arch-index index") vs BUSY (1 retry) vs SQL error (isError w/ message).
- Integer args: JSON int or integral float; reject strings; n/limit ∈ [1,10000].
- DB opened SQLITE_OPEN_READONLY.
- MCP result text = compact JSON string; shapes per spec US-2/US-3 scenarios (matches/truncated arrays, {verdict,from,to,from_found,to_found,explanation}, {escapes:[…]}, legacy:true on kind-less reaches).

## Quality gates

```bash
opam exec -- dune build
opam exec -- dune test        # incl. new test_arch_mcp
./selftest-contract.sh && ./selftest-load.sh && ./selftest-mcp.sh
# spec runnable checks CHECK-1..7 (specs/arch-mcp-server.md)
```

## Out of scope

Effects/capability tools, HTTP transport, resources/prompts, client auto-registration, write ops.
