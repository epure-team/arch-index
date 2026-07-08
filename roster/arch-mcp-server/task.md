# Task — arch-mcp-server

Add an MCP (Model Context Protocol) server to arch-index exposing the arch-query query surface over stdio, so AI agents (Claude Code, Cursor, etc.) can query an index DB via MCP tools instead of shelling out to bash. Reference implementation: ~/dev/epure/src/mcp_server/mcp_server_arch.ml (exposes architecture/search and conventions/validate tools). Scope intent: read-only query tools over an existing SQLite index (stats, find, callers-of/callees-of, reachability incl. sound unreachable/escapes verdicts, exported, fan-in, metrics); respect the edge-kind soundness contract (refuse unsound queries like the bash CLI does with exit 3).

Item 2 of the 5-item consolidation roadmap (item 1 arch-metrics-gate shipped as PR #3).
