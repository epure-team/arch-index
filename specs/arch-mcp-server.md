---
name: roster-spec
type: spec
status: live
feature: MCP stdio server exposing the arch-query read-only surface
brief: briefs/arch-mcp-server-intake.md
date: 2026-07-08
version: 1.0.0
---

# Spec — arch-mcp-server

## Clarifications

| Q | A |
|---|---|
| Transport/framing? | Newline-delimited JSON-RPC 2.0 over stdio, one JSON document per line. Blank lines skipped; trailing CR stripped; pretty-printed multi-line JSON unsupported (→ -32700); batch arrays → -32600. Strictly sequential handling; responses in request order. |
| Dependency policy? | Hand-rolled protocol with Yojson (repo precedent `lib/jsonrpc_client`); no `jsonrpc` opam dep. Engine = `lib/arch_mcp` with pure `handle_message`; thin `bin/arch_mcp`; wrapper script `arch-mcp`. |
| Tool naming / result convention? | Underscore names (`arch_stats`, …). Tool results: `content:[{type:"text", text:<compact JSON string>}]`, `isError` bool (epure parity). Tool-level failures are `isError:true`, never RPC errors. |
| Startup vs per-call validation? | Startup: `--db` required (usage → exit 2); path must exist, not be a directory, and open as SQLite read-only (else stderr + exit 2). Schema problems are per-call: missing `functions` table → every tool returns `isError` "not an arch-index index". |
| Function identity? | Name-based (bash-CLI parity). Duplicate names across modules are a documented limitation; results carry `file_path` where available. |
| Schema detection precedence? | `calls.caller_name` TEXT used when present, else FK join via `functions.id`. Exposed column: `exposed` first, else `exported` (metrics-gate parity). All column probes via `pragma_table_xinfo`. |
| Integer args? | JSON integers, or floats with integral value; anything else → `isError` invalid arguments. `n`/`limit` ≥ 1, capped at 10000. |
| SQLite concurrency? | DB opened read-only (`SQLITE_OPEN_READONLY`); on BUSY, one retry then `isError` "database busy". |

## User Stories

### US-1: Protocol skeleton (Priority: P0)
As an MCP client (Claude Code), I want arch-mcp to speak the MCP stdio protocol so tools are discoverable and callable.
**Why this priority**: nothing works without it.
**Scope**: does NOT cover any query logic; does NOT cover HTTP/SSE, resources, or prompts.
**Independent Test**: pipe initialize + tools/list lines into the binary; assert JSON responses.
**Acceptance Scenarios**:
1. **Given** a valid DB, **When** `{"jsonrpc":"2.0","id":1,"method":"initialize"}` is written to stdin, **Then** stdout carries one line with `result.protocolVersion == "2024-11-05"`, `serverInfo.name == "arch-mcp"`, and `capabilities.tools`.
2. **Given** the server is initialized, **When** `tools/list` is called, **Then** the result lists all v1 tools, each with `name`, `description`, and an `inputSchema` object with `additionalProperties:false` and `required` fields.
3. **Given** a line `not json`, **When** processed, **Then** the server replies with JSON-RPC error `-32700` (id null) and continues serving.
4. **Given** an unknown method `foo/bar` as a request, **Then** error `-32601`; **Given** any notification (no id), **Then** no response is written.
5. **Given** stdin reaches EOF, **Then** the server exits 0.
6. **Given** `--db /no/such.db` (or a directory path), **Then** the binary prints an error to stderr and exits 2 before serving.

### US-2: Core graph query tools (Priority: P0)
As an AI agent, I want name-based graph queries (`arch_stats`, `arch_find`, `arch_exported`, `arch_fan_in`, `arch_callers_of`, `arch_callees_of`, `arch_reachable_from`) so I can navigate the index without bash.
**Why this priority**: the everyday query surface.
**Scope**: does NOT cover soundness-gated verdicts (US-3) or metrics (US-4); does NOT cover effects/capability tools.
**Independent Test**: Alcotest over a throwaway SQLite DB per schema flavor.
**Acceptance Scenarios**:
1. **Given** a flat-schema DB with 3 functions and 2 calls, **When** `arch_stats` is called, **Then** text is JSON with `functions:3`, `call_edges:2`, `contract` status string, and `edges_by_kind` when `kind` exists.
2. **Given** `arch_find {"substr":"cle"}`, **Then** matches with `name`, `file_path`, `exported` flag, sorted by name, ≤ limit, `truncated` flag present.
3. **Given** `arch_find {"substr":"100%"}`, **Then** the `%` is escaped (literal match, not wildcard).
4. **Given** `arch_reachable_from {"name":"clean","limit":1}` on a DB where clean reaches 2 nodes, **Then** result has 1 node and `truncated:true`; the start node is excluded.
5. **Given** `arch_fan_in {"n":0}`, **Then** `isError:true` invalid arguments.
6. **Given** a main-schema DB (FK calls, `exposed` column), **Then** the same tools work via the FK join and `exposed`.

### US-3: Sound reachability tools (Priority: P0)
As a security reviewer, I want `arch_reaches`, `arch_unreachable`, `arch_escapes` with the edge-kind contract enforced so MCP verdicts are as trustworthy as the bash CLI's.
**Why this priority**: soundness is the product differentiator; an unsound MCP verdict poisons agent conclusions.
**Scope**: does NOT weaken or extend contract semantics — bash `require_contract` parity, case-sensitive kinds.
**Independent Test**: Alcotest with ⊤-marked, legacy, and malformed DBs.
**Acceptance Scenarios**:
1. **Given** a ⊤-marked DB where A→B via MUST edges, **When** `arch_reaches {"from":"A","to":"B"}`, **Then** JSON `{"result":"PATH_EXISTS", …}`; when no MUST path, `{"result":"NO_MUST_PATH"}` with a note it is not proof of unreachability.
2. **Given** a legacy DB with no `kind` column, **When** `arch_reaches`, **Then** all edges are treated as MUST and the result carries `"legacy":true`.
3. **Given** a ⊤-marked DB, **When** `arch_unreachable {"from":"A","to":"Z"}` where Z is outside the MUST∪MAY_ENUMERATED closure and no MAY_TOP is reachable, **Then** `{"verdict":"UNREACHABLE"}`; when a MAY_TOP is reachable, `{"verdict":"UNKNOWN"}`; when Z is in the closure, `{"verdict":"REACHABLE"}`.
4. **Given** a DB with no `callgraph_contract` meta (or NULL/invalid/lowercase kinds), **When** `arch_unreachable` or `arch_escapes` is called, **Then** `isError:true` with text JSON `{"error":"REFUSED","reason":…}` mirroring the bash wording — never a verdict.
5. **Given** `arch_escapes {"from":"A"}` on a valid ⊤-marked DB with no reachable ⊤ edges, **Then** `{"escapes":[]}` with `isError:false`.
6. **Given** `arch_unreachable` with `from == to`, **Then** `REACHABLE` (bash parity: the seed is in its own closure).

### US-4: Metrics tool + docs (Priority: P1)
As a CI author or agent, I want `arch_metrics` returning the same flat metrics object as `arch-query metrics`, and docs showing how to register arch-mcp in Claude Code.
**Why this priority**: closes the loop with the metrics gate (item 1); docs drive adoption.
**Scope**: does NOT implement compare/waivers (that is `arch-compare`); does NOT auto-register in any client.
**Independent Test**: call `arch_metrics` on the self-index; diff key-set against `arch-query metrics` output.
**Acceptance Scenarios**:
1. **Given** the CMT self-index DB, **When** `arch_metrics` is called, **Then** the text is a flat `{string: number}` JSON object whose key-set and values equal `arch-query <db> metrics` output (same feature-detected omissions, `pragma_table_xinfo` probing).
2. **Given** a DB lacking `comment_quality_score`, **Then** `doc_coverage_pct`/`undocumented_exposed` are absent, not 0.
3. **Given** the README, **Then** it contains an `arch-mcp` section with a `claude mcp add` registration example and a one-line stdio smoke command.

## Challenges

| ID | Story | Challenge (codex adversarial pass, 30 raised) | Resolution |
|---|---|---|---|
| C-7 | US-1 | Startup failure taxonomy conflated | Split: usage/missing flag → exit 2 + usage; nonexistent/directory/not-sqlite → stderr + exit 2; schema issues → per-call isError (EC-6) |
| C-8 | US-1 | Concurrency unspecified | Strictly sequential, single-threaded, responses in request order |
| C-9/EC-11 | US-2 | Schema detection precedence | `caller_name` TEXT preferred when present; else FK join. Disagreement between both is out of scope (no known producer emits both) |
| C-10/EC-7 | US-2 | Name-based identity vs duplicates | Bash parity: name-based; rows carry file_path; documented limitation |
| C-11/C-16 | US-2 | Result shapes / MCP text convention | Fixed per-tool JSON shapes (below); serialized compact into content[0].text |
| C-12/EC-8 | US-2 | find semantics | SQLite LIKE (ASCII case-insensitive) with `%`/`_`/`\` escaped via ESCAPE; empty substr → invalid args; limit 200 default + truncated |
| C-13 | US-2 | exported ambiguity | `exposed=1` or `exported=1` per detected column; unresolved callees never included |
| C-14/EC-9 | US-2 | n validation | int ≥1, cap 10000; ties → count DESC, name ASC; DISTINCT callers per callee (bash parity) |
| C-15/EC-10 | US-2 | reachable_from semantics | All edge kinds (bash parity); recursive CTE (cycle-safe); excludes seed; name order; `truncated` = row count hit limit; callee names not in functions ARE included (bash parity) |
| C-17/EC-14 | US-3 | reaches on legacy DB | All-edges-as-MUST + `legacy:true` flag (bash must_filter parity) |
| C-18 | US-3 | verdict envelope | `{verdict, from, to, explanation}`; escapes → `{escapes:[{escaping_fn, call_site, kind}]}` |
| C-19/EC-12 | US-3 | contract variants | Presence of any non-empty `callgraph_contract` value = flag on (bash parity); key is PK so no multi-row case; zero call rows with contract = valid |
| C-20 | US-3 | unknown names | Bash parity: verdict computed from closure regardless; result adds `from_found`/`to_found` booleans for UX |
| C-21 | US-3 | exit-3 → MCP mapping | `isError:true`, text = `{"error":"REFUSED","reason":<bash message>}` |
| C-22..24/EC-17/18 | US-4 | metrics shape authority | Authoritative: specs/arch-metrics-gate.md FR-002/FR-003 (omit absent sources; xinfo detection). AC-1 pins MCP output to CLI output by diff |
| C-26 | all | inputSchema strictness | JSON Schema: `type:"object"`, typed `properties`, `required`, `additionalProperties:false`; runtime validation must reject exactly what the schema rejects |
| C-27 | US-2/3 | payload size | Every list-returning tool takes `limit` (defaults: find 200, reachable_from 500, escapes 500, exported 1000, callers/callees 500) + `truncated` flag |
| C-28 | all | SQLite busy | Read-only open; 1 retry on BUSY then isError |
| C-29 | all | arg coercion | Ints or integral floats only; strings rejected |
| C-30/EC-1/3 | US-1 | framing edge cases | Blank lines skipped; CRLF stripped; batch array → -32600; one doc per line |
| EC-2 | US-1 | unknown notification | Ignored silently (never answered) |
| EC-4 | US-1 | unknown tool | isError:true "Unknown tool: X" (epure parity) |
| EC-13 | US-3 | lowercase kind | Contract refusal — kinds are case-sensitive literals |
| EC-15 | US-3 | from==to | REACHABLE (parity) |
| EC-16 | US-3 | no escapes | `{"escapes":[]}`, isError:false |

## Functional Requirements

#### Protocol (US-1)
- **FR-001** [US-1]: The server MUST speak newline-delimited JSON-RPC 2.0 over stdio: one document per line in and out; blank lines skipped; CR stripped.
- **FR-002** [US-1]: `initialize` MUST return protocolVersion `2024-11-05`, `serverInfo{name:"arch-mcp", version}`, and `capabilities.tools`.
- **FR-003** [US-1]: `tools/list` MUST return every v1 tool with `name`, `description`, and a strict `inputSchema` (`additionalProperties:false`, `required`).
- **FR-004** [US-1]: `tools/call` MUST wrap handler success as `{content:[{type:"text",text:<compact JSON>}], isError:false}` and handler failure as the same shape with `isError:true`; tool failures MUST NOT be JSON-RPC errors.
- **FR-005** [US-1]: The server MUST answer parse errors with `-32700` (id null), non-request/batch shapes with `-32600`, unknown request methods with `-32601`, and MUST NOT answer notifications.
- **FR-006** [US-1]: The server MUST process requests strictly sequentially and exit 0 on stdin EOF.
- **FR-007** [US-1]: The binary MUST exit 2 with a stderr message when `--db` is missing, nonexistent, a directory, or not openable as SQLite; it MUST open the DB read-only.
- **FR-008** [US-1]: The engine MUST expose a pure `handle_message` (Yojson in → Yojson option out) unit-testable without a process.
- **FR-009** [US-1]: On a DB without a `functions` table, every tool call MUST return `isError:true` ("not an arch-index index"), and the server MUST NOT crash.

#### Core tools (US-2)
- **FR-010** [US-2]: v1 tool set MUST be exactly: `arch_stats, arch_find, arch_exported, arch_fan_in, arch_callers_of, arch_callees_of, arch_reachable_from, arch_reaches, arch_unreachable, arch_escapes, arch_metrics`.
- **FR-011** [US-2]: All SQL MUST use prepared statements with bound parameters; user input MUST NOT be interpolated into SQL text; LIKE patterns MUST escape `%`, `_`, `\`.
- **FR-012** [US-2]: Tools MUST work on both schema flavors: `caller_name` TEXT when present else FK join; `exposed` else `exported` column.
- **FR-013** [US-2]: Every list-returning tool MUST accept an optional integer `limit` (defaults per C-27, cap 10000), return rows sorted by name (fan_in: count DESC, name ASC), and include a `truncated` boolean.
- **FR-014** [US-2]: Integer arguments MUST accept JSON ints and integral floats and reject all else with `isError:true`; `limit`/`n` < 1 MUST be rejected.
- **FR-015** [US-2]: `arch_stats` MUST report function/exported/call counts, contract status, and `edges_by_kind` when `kind` exists.

#### Sound tools (US-3)
- **FR-016** [US-3]: `arch_unreachable` and `arch_escapes` MUST run the contract check (meta flag present + `kind` column present + zero NULL/invalid case-sensitive kinds) before querying and MUST return `isError:true` with `{"error":"REFUSED","reason":…}` when it fails.
- **FR-017** [US-3]: `arch_unreachable` MUST compute the MUST∪MAY_ENUMERATED closure and return verdict REACHABLE / UNKNOWN (⊤ reachable) / UNREACHABLE with the same semantics as `arch-query unreachable`.
- **FR-018** [US-3]: `arch_reaches` MUST use MUST-only edges when `kind` exists and all edges otherwise, flagging the latter with `legacy:true`.
- **FR-019** [US-3]: `arch_escapes` MUST return the ⊤-frontier rows `{escaping_fn, call_site, kind}` reachable over resolved edges, `[]` when none.
- **FR-020** [US-3]: Verdict payloads MUST include `from_found`/`to_found` booleans; unknown names MUST NOT change verdict semantics (bash parity).

#### Metrics + docs (US-4)
- **FR-021** [US-4]: `arch_metrics` MUST produce a flat `{string: number}` object with the same key-set, values, and omission semantics as `arch-query metrics` (specs/arch-metrics-gate.md FR-002/FR-003), using `pragma_table_xinfo` detection.
- **FR-022** [US-4]: README MUST document building, wrapper usage, a `claude mcp add` registration example, and a pipe-based smoke command.

## Acceptance Criteria

- AC-1 [US-1]: initialize/tools-list/parse-error/unknown-method/notification/EOF behaviors → as FR-001..006 (scripted stdio session).
- AC-2 [US-1]: startup failures → exit 2 with stderr (missing, nonexistent, directory).
- AC-3 [US-2]: core tools correct on flat AND main schema fixtures, limits + truncation enforced, wildcard escaping verified.
- AC-4 [US-3]: sound verdicts on ⊤-marked fixture; REFUSED on legacy/malformed fixtures; escapes empty-array case.
- AC-5 [US-4]: `arch_metrics` output equals `arch-query metrics` on the self-index (jq key/value diff).
- AC-6 [US-1]: server survives a garbage line followed by a valid request in the same session.

## Edge Cases

- EC-1 [US-1]: blank line → skipped, no response. EC-2: unknown notification → silent. EC-3: batch array → -32600.
- EC-4 [US-1]: unknown tool → isError "Unknown tool: X". EC-5: `--db` directory → exit 2. EC-6: no functions table → per-call isError.
- EC-7 [US-2]: duplicate names → name-based union (documented). EC-8: empty substr → invalid args. EC-9: n=1000000 → capped/rejected per FR-013/14. EC-10: callees missing from functions → included.
- EC-12 [US-3]: contract value `v2` → treated as flag-on (presence check). EC-13: lowercase kind → REFUSED. EC-14: legacy reaches → legacy:true. EC-15: from==to → REACHABLE. EC-16: no escapes → [].
- EC-17/18 [US-4]: absent sources omitted; generated columns detected via xinfo.

## Runnable Checks

- CHECK-1 [AC-1]: `printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' | ./arch-mcp --db /tmp/self.db | jq -s -e '.[0].result.protocolVersion=="2024-11-05" and (.[1].result.tools|length==11)'` → exit 0.
- CHECK-2 [AC-6]: session with `garbage` line then valid initialize → first response `.error.code==-32700`, second `.result` present.
- CHECK-3 [AC-3]: `tools/call arch_find {"substr":"clean"}` on a flat fixture → `.result.isError==false` and text parses as JSON with a `matches` array.
- CHECK-4 [AC-4]: `tools/call arch_unreachable` on the ⊤-marked selftest fixture (from selftest-contract.sh DB) → verdict string; same call on a legacy DB → `isError==true` and text contains `REFUSED`.
- CHECK-5 [AC-5]: `diff <(./arch-query /tmp/self.db metrics) <(… tools/call arch_metrics … | jq -r '.result.content[0].text')` → empty.
- CHECK-6 [AC-2]: `./arch-mcp --db /nonexistent 2>/dev/null; test $? -eq 2` → passes.
- CHECK-7 [US-1..4 unit]: `opam exec -- dune test` → new `test_arch_mcp` Alcotest suite passes.

## Entities

- `arch-mcp`: the stdio MCP server binary (`bin/arch_mcp`) + wrapper script; read-only.
- `handle_message`: pure engine function Yojson → Yojson option; None for notifications/blank input.
- `ToolHandler`: `Sqlite3.db -> Yojson.Safe.t -> (Yojson.Safe.t, string) result`; success/failure maps to isError false/true.
- `ContractCheck`: the ⊤-marking validation (meta flag + kind column + all kinds valid, case-sensitive) shared by arch_unreachable/arch_escapes.
- `truncated`: boolean present on every list-returning tool result indicating the limit was hit.
