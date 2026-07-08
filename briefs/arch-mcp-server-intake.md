# Intake Brief — arch-mcp-server

**Date:** 2026-07-08
**Status:** VALIDATED (autonomous mode — user pre-authorized gate decisions)
**Type:** feature

## Goal

Add an MCP (Model Context Protocol) server binary to arch-index that exposes the arch-query read-only query surface over stdio, so AI agents (Claude Code, Cursor, Codex, …) can query an index DB through typed MCP tools instead of shelling out to bash. This is the main distribution gap identified against graphify and the epure sibling: the epure MCP server (`mcp_server_arch.ml`) proves the pattern; arch-index generalizes it over any index DB with the edge-kind soundness contract preserved — tools that would be unsound on a non-⊤-marked DB refuse with a structured error, exactly as the bash CLI refuses with exit 3.

## Scope Boundary

Explicitly OUT of scope:
- Write operations of any kind (indexing, sidecar loading, annotations) — read-only tools only.
- HTTP/SSE transport — stdio only (arch-serve remains the HTTP surface).
- Effects/capability-layer tools (mutators-of, capabilities-of, compose, …) — deferred; the core call-graph + metrics surface first.
- MCP resources/prompts/completions — tools capability only.
- Registering the server in any client config (documented, not automated).
- Items 3–5 of the roadmap.

## Relevant Files

| File | Role | Key snippet |
|---|---|---|
| `~/dev/epure/src/mcp_server/mcp_server.ml:520-789` | reference server: line-delimited JSON-RPC loop, initialize/tools-list/tools-call dispatch, content/isError wrapping, inactivity timeout | `("protocolVersion", `String "2024-11-05")`; tool errors are `isError:true` content, not RPC errors |
| `~/dev/epure/src/mcp_server/mcp_server_arch.ml:11-100` | reference arch tools with parameterized `LIKE ?1` SQL | bound params, never interpolation |
| `arch-query:74-146` | the query surface to mirror + `require_contract` soundness gate + `stats`/`metrics` SQL | tri-verdict `unreachable` SQL :111-132 is the sound reference |
| `bin/arch_serve/arch_serve.ml:215-259` | existing OCaml prepared-statement + BFS patterns (kind-blind — do NOT copy for sound verdicts) | `Sqlite3.prepare db "SELECT id FROM functions WHERE name = ? LIMIT 1"` |
| `lib/jsonrpc_client/jsonrpc_client.mli` | hand-rolled JSON-RPC 2.0 protocol types (client-side) — precedent for not adding the `jsonrpc` opam dep | `type rpc_error = {code; message; data}` |
| `bin/arch_compare_cli/`, `arch-compare` | newest executable + wrapper-script conventions to mirror | wrapper resolves `_build/install/...` then `_build/default/...` |
| `test/test_capabilities.ml` + `test/dune` | Alcotest patterns incl. building throwaway SQLite DBs in tests | |
| `arch-index.opam:7-29` | dependency set: yojson, eio, eio_posix, sqlite3, cmdliner present; **no `jsonrpc` lib** | |

## Architecture Notes

- **Transport:** newline-delimited JSON-RPC 2.0 over stdio (epure-proven; matches MCP stdio transport). Hand-roll the tiny server-side protocol with Yojson — do not add the `jsonrpc` opam dependency (repo precedent: `lib/jsonrpc_client` hand-rolls the client side). Blocking stdio loop is sufficient; Eio optional.
- **Structure:** engine as a testable library (`lib/arch_mcp/`) with pure `handle_message : Yojson.Safe.t -> Yojson.Safe.t option` (None for notifications) + tool handlers `db -> args -> (Yojson.Safe.t, string) result`; thin `bin/arch_mcp/` executable (`--db PATH` required; optional `--timeout`); top-level `arch-mcp` wrapper script.
- **Tool naming:** MCP tool-name pattern is conservative (`[a-zA-Z0-9_-]`); use underscore names (`arch_stats`, `arch_find`, …) NOT epure's slash style.
- **Soundness:** `arch_unreachable`/`arch_escapes` must run the same contract checks as `require_contract` (meta flag present, kind column present, zero NULL/invalid kinds) and return a structured refusal (`isError:true`, message mirroring the bash wording) when unsound. `arch_reaches` stays MUST-only under-approximation. Do NOT copy arch-serve's kind-blind BFS for these.
- **SQL:** prepared statements with bound parameters everywhere (improvement over the bash CLI's interpolation; epure precedent).
- **Metrics tool:** reimplements the item-1 `metrics` SQL (feature-detect via `pragma_table_xinfo`) in OCaml; no dependency on the unmerged `feat/arch-metrics-gate` branch — the two meet at the JSON shape, not at code.
- **Branch base:** `main` (item 1's PR #3 is unmerged; no code dependency).

## Quality Gates

```bash
# Build
opam exec -- dune build

# Tests
opam exec -- dune test
./selftest-contract.sh && ./selftest-load.sh
# (selftest-effects.sh has a pre-existing failure on main — excluded, see item-1 QA brief)

# Lint/Format
# not documented

# End-to-end smoke (once built): pipe initialize + tools/list + tools/call lines into arch-mcp --db <db>
```

## Open Questions

- [ ] Exact v1 tool set: proposed `arch_stats, arch_find, arch_callers_of, arch_callees_of, arch_reachable_from, arch_reaches, arch_unreachable, arch_escapes, arch_exported, arch_fan_in, arch_metrics` (11). Spec must fix the list and each input schema.
- [ ] `reachable_from` result size on big graphs — spec must define a `limit` parameter + truncation flag (arch-serve precedent: `truncated` bool).

_(Both delegated to spec under autonomous mode; implementers must not assume.)_
