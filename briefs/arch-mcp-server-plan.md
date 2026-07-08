# Plan — arch-mcp-server

**Date:** 2026-07-08
**Status:** VALIDATED (autonomous mode; Voice 1 = inline architect, Voice 2 = codex exec; quiz waived per user pre-authorization)

## Sequential steps

1. **Slice A — protocol skeleton** — `lib/arch_mcp/` (protocol types; `handle_message : ctx -> Yojson.Safe.t -> Yojson.Safe.t option` where `ctx = {db; tools}`; JSON-RPC error taxonomy -32700/-32600/-32601; MCP content/isError wrapping; declarative per-tool arg spec from which BOTH the inputSchema JSON and the runtime validator are generated — single source, cannot diverge), `bin/arch_mcp/` (argv parsing, read-only sqlite open, startup validation exit 2, line loop, ALL logging to stderr), `arch-mcp` wrapper, `test/test_arch_mcp.ml` protocol cases. Done: FR-001..009 unit-tested; CHECK-2/6 pass.
2. **Slice B — core tools** — `schema_info` detected once at open (xinfo columns: exposed/exported, caller_name vs FK, kind, line_count, modules.lines, comment_quality_score); handlers for stats/find/exported/fan_in/callers_of/callees_of/reachable_from as prepared-statement SQL; limit+1 fetch → `truncated`; LIKE escaping; fixtures for BOTH schema flavors in tests. Done: FR-010..015; CHECK-3.
3. **Slice C — sound tools** — reaches/unreachable/escapes implemented by porting the bash CLI's recursive-CTE SQL **verbatim** with bound params (NOT OCaml BFS — arch-serve's kind-blind BFS is the anti-pattern); shared `ContractCheck`; REFUSED mapping. Done: FR-016..020; CHECK-4 incl. legacy/malformed fixtures, from==to, lowercase-kind refusal.
4. **Slice D — metrics tool, e2e, docs, distribution** — `arch_metrics` (same xinfo feature-detection as `arch-query metrics`); `selftest-mcp.sh` (initialize + initialized notification + string ids + nested arguments + garbage-line recovery + stdout-purity assertion: every stdout line parses as JSON); README section with `claude mcp add arch-index -- <abs-path>/arch-mcp --db <db>` example; CI: run selftest-mcp.sh + add `arch_mcp` to release packaging list. Done: FR-021/022; CHECK-1/5/7.

## Dependencies

A → B → C → D (registry/validator from A; schema_info from B feeds C; D needs all tools for tool-count checks). **Branch base: `feat/arch-metrics-gate`** — see Decisions.

## Identified risks

| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| Sound-verdict divergence from bash semantics | Medium | Core-contract damage (worst failure mode) | Port SQL text verbatim as CTEs with ? params; fixture tests mirror selftest-contract.sh cases incl. EC-13/15 |
| Validator/schema drift | Medium | Client-visible inconsistency | Generate both from one declarative arg spec (Voice 2 objection 5) |
| MCP client incompatibility despite passing pipe tests | Medium | Feature looks broken in Claude/Cursor | selftest covers initialized notification, string ids, nested arguments, stdout purity; manual `claude mcp add` verification in QA |
| Stdout contamination corrupts protocol | Low | Hard-to-debug hangs | All logs to stderr; selftest asserts every stdout line is JSON |
| Truncated flag false confidence | Low | Wrong agent conclusions | limit+1 fetch pattern everywhere |
| Release packaging omits new binary | High (Voice 2 #11) | Ships broken | Add arch_mcp to ci.yml release loop in Slice D |
| SQLite error conflation | Medium | Misleading tool errors | Distinct paths: startup not-sqlite → exit 2; no functions table → isError not-an-index; BUSY → 1 retry; other SQL errors → isError with message |

## Decisions made

| Point | Decision | Reason |
|---|---|---|
| Branch base (deviation from intake) | Stack on `feat/arch-metrics-gate`; PR base = that branch (rebase to main once PR #3 merges) | Both voices converge: CHECK-5/AC-5 require `arch-query metrics` and the wrapper conventions, which exist only there. The intake's "no code dependency" claim was wrong (mechanical necessity, not a direction change) |
| Sound tools implementation | Verbatim SQL CTE port with bound params | Only way to guarantee bash parity (Voice 2 #6) |
| Validation approach | Declarative per-tool arg spec → schema + validator generated | Kills drift (Voice 2 #5) |
| handle_message purity | Takes explicit `ctx` record | No globals (Voice 2 #1) |
| Truncation | Fetch limit+1 | Honest `truncated` (Voice 2 #7) |

## Assumptions

- `claude mcp add` example can be smoke-verified locally by the QA phase only if a Claude Code session is available; otherwise the pipe-based CHECK-1 stands in.
- Effects/capability tools remain out (intake scope) — registry design must make adding them later trivial, but no stubs.

## Consensus Table

| Point | Voice 1 | Voice 2 (codex) | Status |
|---|---|---|---|
| 4 vertical slices A→D | ✅ | ✅ | AGREE |
| Sound tools = the real risk; verbatim SQL port | ✅ | ✅ (#6) | AGREE |
| Branch must stack on feat/arch-metrics-gate | (missed) | ✅ (#2,#3) | AGREE after verification — intake corrected |
| Declarative arg spec for schema+validator | ✅ | ✅ (#5) | AGREE |
| Release packaging update needed | (missed) | ✅ (#11) | AGREE |
| stdout purity + client-compat tests | ✅ | ✅ (#8,#9) | AGREE |
| No USER-CHALLENGE items | — | — | — |
