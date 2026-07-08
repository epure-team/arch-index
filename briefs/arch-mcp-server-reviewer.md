# Reviewer Brief — arch-mcp-server

**Status:** VALIDATED
**Contract:** specs/arch-mcp-server.md (FR-001..022, AC-1..6, EC set) — cite IDs in findings.

## Audit first (ranked by risk)

1. **Sound tools** (`lib/arch_mcp/` handlers for unreachable/escapes/reaches): must be SQL-CTE ports of arch-query:102-132, NOT OCaml BFS; ContractCheck parity with arch-query:74-94 (presence-only contract flag, kind column required, case-sensitive kind validation, refusal wording); EC-13 lowercase kind → REFUSED; EC-15 from==to → REACHABLE; legacy reaches → legacy:true.
2. **Schema/validator generation**: confirm inputSchema and runtime validation derive from ONE spec structure; probe rejects (string where int, unknown field with additionalProperties:false, missing required).
3. **stdout purity**: grep the server code for any print to stdout outside the response writer.
4. **Error taxonomy**: tool failure vs RPC error separation (FR-004/005); startup exit 2 paths; no-functions-table isError; BUSY retry.
5. **truncated**: limit+1 pattern actually used everywhere.
6. **SQL injection**: zero string interpolation of user input; LIKE ESCAPE correctness.
7. **Distribution**: ci.yml release loop includes arch_mcp; selftest-mcp.sh wired into CI test steps; wrapper script resolves both build paths.
8. **arch_metrics parity**: same xinfo probes and omission semantics as the arch-query metrics branch (compare SQL side by side).

## Expected behaviors to spot-run

CHECK-1 (initialize+tools/list pipe, 11 tools), CHECK-2 (garbage recovery), CHECK-4 (REFUSED on legacy DB), CHECK-5 (metrics diff vs CLI), CHECK-6 (exit 2).
