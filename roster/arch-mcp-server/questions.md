# Research Questions — arch-mcp-server

_Generated: 2026-07-08_
_DO NOT include the task description in this file or share it with the researcher._

1. How is the MCP server in /home/mathias/dev/epure/src/mcp_server/ implemented — transport and JSON-RPC framing, tool registration and dispatch, input validation, dependencies, and how `mcp_server_arch.ml` exposes its tools and formats their results?
2. What query surface does arch-index's `arch-query` CLI (bash, /home/mathias/dev/arch-index/arch-query) expose — every subcommand, its SQL shape, argument sanitization, the soundness gating (`require_contract`, exit-3 refusals), and output formats?
3. What JSON-RPC or stdio protocol utilities already exist in /home/mathias/dev/arch-index (e.g. lib/jsonrpc_client/) — what framing, request/response types, and transport do they implement, and who uses them?
4. How does `arch-serve` (bin/arch_serve/) expose index data programmatically — endpoints, SQL reuse or duplication relative to arch-query, DB-path configuration, and how sound/unsound verdicts are represented in its responses?
5. What dune/OCaml conventions do arch-index binaries follow — executable layout, cmdliner usage, Yojson usage, sqlite3 bindings, wrapper scripts at repo root, and release packaging in CI?
6. How do arch-index query implementations detect schema variants (main vs flat) and feature tables (effects, capabilities), and what error-reporting conventions (exit codes, stderr messages) do the binaries use?
