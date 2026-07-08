# Research — arch-mcp-server

_Generated: 2026-07-08_
_Mode: full (executed inline — subagent budget exhausted; direct file reads)_
_Online research: disabled_

## Question 1: epure MCP server implementation

**Finding:** `~/dev/epure/src/mcp_server/mcp_server.ml` is a **newline-delimited JSON-RPC 2.0 server over stdio** using Eio:
- Main loop (`run`, :694-789): buffered stdin reader (1 MiB max), `read_line_with_timeout` (inactivity timeout → clean shutdown; EOF → exit), parse line with `Yojson.Safe.from_string`, decode via the **`jsonrpc` opam library** (`Jsonrpc.Packet.t_of_yojson`), handle Requests, **ignore Notifications**, write `Yojson.Safe.to_string response ^ "\n"` to stdout. Optional file logging (`--log-file`, 0600).
- Dispatch (`handle_request`, :520-690): `"initialize"` → `{protocolVersion: "2024-11-05", serverInfo{name,version}, capabilities:{tools:{listChanged:false}}}`; `"tools/list"` → array of `{name, description, inputSchema}` (schemas in `mcp_tool_schemas.ml` as Yojson values); `"tools/call"` → extract `params.name`/`params.arguments`, look up handler in `(name, handler) assoc`, wrap handler `Ok json` as MCP `{content:[{type:"text", text:<json-string>}], isError:false}` and `Error msg` as same shape with `isError:true` (:644-687); unknown tool → isError:true content (not protocol error); unknown method → JSON-RPC error (-32000 via `make_response`, :505-518).
- Handlers have signature `~db ~args -> (Yojson.Safe.t, string) result`; args validated with `Yojson.Safe.Util.member` (`mcp_server.ml:14-24`).
- `mcp_server_arch.ml:11-100`: `architecture/search` runs parameterized `LIKE ?1` SQL over functions/types (name/signature/intent), i.e. **bound parameters, not string interpolation**.

## Question 2: arch-query CLI surface

**Finding:** (verified in item-1 cycle; unchanged) Bash `case` dispatch, `arch-query <db> <cmd> [A] [B]`; quote-stripping sanitization then **string-interpolated SQL**; `q()`=boxed output, `qraw()`=error-swallowing. Subcommands: callers-of, callees-of, reachable-from, reaches (MUST-only positive), unreachable (sound tri-verdict REACHABLE/UNKNOWN/UNREACHABLE, gated), escapes (⊤ frontier, gated), fan-in, exported, unresolved, find, stats, metrics (new, item 1), effects (mutators-of/effects-of/pure-fns), dead-code, capability layer (capabilities-of/compose/removes-guard/actor-paths/prune). Soundness gate `require_contract` (`arch-query:74-94`): refuses (exit 3) when no `callgraph_contract` meta, missing `kind` col, or NULL/invalid kinds. Exit codes: 0/1(gate)/2(usage)/3(refuse). Feature-detect via `sqlite_master`/`pragma_table_xinfo`; flat-vs-main schema dualism per branch.

## Question 3: existing JSON-RPC utilities in arch-index

**Finding:** `lib/jsonrpc_client/` is a **client**, not a server: spec-compliant JSON-RPC 2.0 client over abstract transports (`jsonrpc_client.mli:8-40`: `params` Positional/Named, `rpc_error`, `response`, transport_error), with `stdio_transport.ml` (spawn child, **line-delimited framing**: `payload ^ "\n"` write, `Buf_read.line` read, Eio mutex + timeout, :42-59) and `http_transport.ml`. Used by the LSP extractor. **No `jsonrpc` opam dependency** — protocol types are hand-rolled with Yojson (`arch-index.opam:7-29` lists cmdliner/yojson/eio/eio_posix/cohttp-eio/sqlite3 etc.; no jsonrpc).

## Question 4: arch-serve data API

**Finding:** `bin/arch_serve/arch_serve.ml` — cohttp-eio HTTP server with routes `/api/modules`, `/api/functions`, `/api/graph/neighborhood`, `/api/graph/module`, `/api/reaches` (:278-393). Query logic is **reimplemented in OCaml** (not shared with bash): prepared statements with `?` binding (`name_to_id`, :215-221), BFS over `calls` by name (`reaches_bfs`, :223-259) with comment "no kind column — all calls treated as MUST" (:210) — i.e. arch-serve does **not** implement the sound unreachable/escapes verdicts and ignores edge kinds. DB path from CLI arg; SPA assets embedded via ppx_blob.

## Question 5: dune/OCaml conventions

**Finding:** executables in `bin/<name>/` with `(public_name …)`; libraries in `lib/<name>/`; Alcotest tests in `test/` (one stanza per suite); top-level bash wrapper scripts (`arch-compare` pattern: try `_build/install/default/bin/<exe>` then `_build/default/bin/<dir>/<exe>.exe`, else exit 2 with build hint); CI packages `arch_index_cli arch_serve arch_callgraph_ocaml` binaries on tag (ci.yml:73-83). cmdliner used by arch_index_cli (`Arg.required & opt`, `Cmd.v`, `Cmd.eval`); arch_serve/arch_compare_cli parse argv by hand. Yojson used in comment_parser and arch_compare.

## Question 6: schema detection + error conventions

**Finding:** (item-1 verified) main schema: `functions(id, module_id, name, signature, line_start, line_end, exposed, intent, comment_quality_score, …)`, `calls(caller_id/callee_id FK …)` variant AND text-name variant; flat schema (arch-load): `functions(name, file_path, exported)`, `calls(caller_name, …, kind)`, `comment_db_meta` with `callgraph_contract='v1'`. NOTE: the CMT self-index producer writes main-schema tables but **NULL `kind` and no `comment_db_meta`** — `require_contract` refuses on it. Generated columns (line_count) visible only via `pragma_table_xinfo`. Binaries report errors on stderr, exit codes 0/1/2/3 as above; `arch-compare` maps malformed input → 2, gate failure → 1.

## Patterns found

| Pattern | File | Lines | Notes |
|---|---|---|---|
| NDJSON-line JSON-RPC server loop | epure mcp_server.ml | 694-789 | stdin line → handle → stdout line |
| MCP tool result wrapping (content/isError) | epure mcp_server.ml | 644-687 | tool errors are isError:true, not RPC errors |
| tool (name, handler) assoc + Yojson schemas | epure mcp_server.ml / mcp_tool_schemas.ml | 501, 540-625 | schemas are plain Yojson values |
| parameterized SQL in tool handlers | epure mcp_server_arch.ml | 11-100 | `LIKE ?1` bound params |
| prepared-stmt binding in arch-index | bin/arch_serve/arch_serve.ml | 215-221 | Sqlite3.bind_text |
| sound-verdict SQL (tri-state) | arch-query | 111-132 | the only sound implementation; OCaml side lacks it |
| wrapper script binary resolution | arch-compare | 11-17 | reuse for new binaries |

## Coverage gaps

- epure's server depends on the `jsonrpc` opam package; arch-index does not have it. Both hand-rolled (lib/jsonrpc_client types) and adding the dependency are viable — a design decision for spec/plan, not a research gap.
- arch-serve's reachability ignores edge kinds — relevant precedent: the sound verdicts exist only as SQL inside the bash CLI today.
