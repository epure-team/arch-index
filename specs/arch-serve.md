---
name: roster-spec
type: spec
status: live
feature: arch-serve — local call-graph web dashboard
brief: briefs/arch-serve-intake.md
date: 2026-06-25
version: 1.0.0
---

# Spec — arch-serve

## Clarifications

| Q | A |
|---|---|
| Does "no new opam deps" mean zero additions to dune-project? | Yes — no new entries in `dune-project` or `.opam`; adding existing packages to the new binary's `(executable …)` stanza is fine. |
| CLI interface for DB path: positional or `--flag`? | Positional argument — intake brief specifies `./arch-serve <db-path>`. |
| Asset embedding strategy for ppx_blob? | Plain hand-written JS/CSS/HTML committed under `bin/arch_serve/static/`; embedded via `[%blob "static/…"]` with `preprocessor_deps` in dune stanza. No transpiler/bundler. |
| Does `/api/reaches` with a MAY-only path return `PATH_EXISTS`? | No. `PATH_EXISTS` requires at least one all-MUST-edge path. Any other case returns `NO_MUST_PATH`, including MAY-only paths. |
| Is the 400-node render cap server-side or client-side? | Client-side visual cap (400 nodes rendered). Server caps the BFS response at 2000 nodes with `truncated: true`. |
| Module view: intra-module function graph or inter-module DAG? | Intra-module: all functions of one module with their intra-module call edges. "DAG" refers to the layered layout algorithm, not inter-module topology. |
| Does `comment_quality_score` column exist in the schema? | Confirmed: `comment_quality_score` is in the `functions` table per `architecture-schema.sql`. |
| Shell wrapper: what does it do? | Thin `exec "$HERE/bin/arch_serve" "$@"` wrapper, identical pattern to `arch-index`. |

## User Stories

### US-1: Server startup and SPA delivery (Priority: P0)

As an engineer running arch-serve on a local machine, I want to run `./arch-serve self.db` and have the SPA available at `http://localhost:7371`, so I can open my browser and start exploring my codebase immediately.

**Why this priority**: Everything else in the feature depends on the server running and the SPA loading. Without this, nothing is demoable.

**Scope**: This story does NOT cover the interactive graph views, API data queries, or the SPA's internal behavior — only that the server starts, delivers static assets correctly, and shuts down cleanly.

**Independent Test**: `opam exec -- dune build && ./_build/default/bin/arch_serve/arch_serve.exe /tmp/self.db &; sleep 1; curl -sf http://localhost:7371/ | grep -q 'arch-serve'; kill $!`

**Acceptance Scenarios**:
1. **Given** `self.db` exists and is a valid SQLite DB and port 7371 is free, **When** `./arch-serve self.db` is run, **Then** the server starts, prints `Serving at http://localhost:7371 — press Ctrl-C to stop` to stdout, and `curl http://localhost:7371/` returns HTTP 200 with HTML whose `<title>` contains `arch-serve`.
2. **Given** `self.db` does not exist, **When** `./arch-serve self.db` is run, **Then** the binary exits immediately with code 1 and writes `arch-serve: cannot open database: self.db: No such file or directory` (or equivalent) to stderr.
3. **Given** `self.db` exists but is not a valid SQLite file (e.g., a text file), **When** `./arch-serve self.db` is run, **Then** the binary exits with code 1 and writes a message to stderr that distinguishes this from a missing file (e.g., `arch-serve: cannot open database: self.db: not a database`).
4. **Given** DB validation succeeds but port 7371 is already bound, **When** `./arch-serve self.db` is run, **Then** the binary exits with code 1 and writes a message to stderr naming port 7371 as the conflict.
5. **Given** the server is running, **When** SIGINT (Ctrl-C) is sent, **Then** the server exits with code 0 and no error output on stderr.

---

### US-2: Read-only data API (Priority: P0)

As the SPA client, I want all API endpoints to return correctly shaped JSON from the indexed SQLite DB, so I can render views without additional round-trips or schema guesses.

**Why this priority**: The SPA is entirely data-driven. Incorrect or underspecified JSON shapes would break every view. Defining the shapes here makes frontend and backend independently implementable.

**Scope**: This story does NOT cover the SPA rendering logic, pagination beyond 100 rows (infinite scroll is a client concern), or write operations.

**Independent Test**: After server start, `curl -sf http://localhost:7371/api/modules | python3 -m json.tool | grep '"path"'` succeeds; `curl -sf http://localhost:7371/api/functions | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'comment_quality_score' in d[0]"` passes.

**Acceptance Scenarios**:
1. **Given** a DB with 18 modules, **When** `GET /api/modules` is called, **Then** the response is HTTP 200 with a JSON array of 18 objects, each with fields `{id: int, path: string, lines: int, has_mli: bool}` (booleans as JSON `true`/`false`).
2. **Given** functions in the DB, **When** `GET /api/functions?module_id=3&exposed=1&min_score=30`, **Then** HTTP 200 with a JSON array where every element satisfies all three filters simultaneously; each element has fields `{id, module_id, name, signature, line_start, line_end, exposed, comment_quality_score, intent, has_pre, has_post, has_violators}` with booleans as JSON `true`/`false`.
3. **Given** the DB, **When** `GET /api/graph/neighborhood?name=find_tag_positions&depth=2`, **Then** HTTP 200 with `{nodes: [...], edges: [...], truncated: false}`; nodes include all functions within 2 edges in either direction (caller and callee) from `find_tag_positions`; each node has `{id, name, module_id, exposed, comment_quality_score, intent}`; each edge has `{caller_id, callee_id, kind, call_site}`.
4. **Given** functions A→B→C via MUST edges, **When** `GET /api/reaches?from=A&to=C`, **Then** HTTP 200 with `{result: "PATH_EXISTS", path: [id_A, id_B, id_C]}` where IDs are integers and the path is the shortest MUST-only path.
5. **Given** functions X and Y with no MUST path between them, **When** `GET /api/reaches?from=X&to=Y`, **Then** HTTP 200 with `{result: "NO_MUST_PATH", path: []}`.
6. **Given** a function name "nonexistent_fn" not in the DB, **When** `GET /api/reaches?from=nonexistent_fn&to=Y`, **Then** HTTP 404 with JSON `{"error": "unknown function: nonexistent_fn"}`.
7. **Given** a neighborhood BFS that would exceed 2000 nodes, **When** the endpoint is called, **Then** the response contains at most 2000 nodes and includes `"truncated": true`.

---

### US-3: Neighborhood graph exploration (Priority: P0)

As an engineer using arch-serve in a browser, I want to search for a function and explore its N-hop call graph interactively, with nodes colored by module and edges styled by call kind (MUST/MAY_ENUMERATED/MAY_TOP), so I can visually trace call paths and understand the module structure.

**Why this priority**: This is the primary value of the tool. An arch-serve without the neighborhood graph is just a function table.

**Scope**: This story does NOT cover path queries (US-5), module view (US-4), or the details panel content beyond selection state.

**Independent Test**: Load `http://localhost:7371/#/n/find_tag_positions?depth=2` — a D3 SVG graph renders with at least one node bearing an accent halo and edges with at least one of three distinct visual styles (solid/dashed/dotted).

**Acceptance Scenarios**:
1. **Given** the SPA is loaded and no input is focused, **When** the user presses `/`, **Then** the search input in the header receives focus.
2. **Given** the search input is focused and the user types "find_tag", **When** the autocomplete dropdown renders, **Then** it shows functions whose names contain "find_tag", with each row showing the function name left-aligned and its module basename right-aligned in a dimmed style.
3. **Given** the user selects "find_tag_positions" from search, **When** the selection is confirmed, **Then** the URL hash becomes `#/n/find_tag_positions?depth=2` and a D3 force graph renders with `find_tag_positions` as the focus node (accent halo, pinned to canvas center initially).
4. **Given** a graph is rendered at depth 2, **When** the depth control is changed to 3, **Then** new nodes and edges fade-animate into the canvas without resetting existing node positions, and the URL hash updates to `?depth=3`.
5. **Given** a graph is rendered at depth 3, **When** the depth control is changed to 1, **Then** nodes now outside the 1-hop neighborhood fade out and are removed, without restarting the force simulation.
6. **Given** a graph is rendered, **When** the user single-clicks a non-focus node, **Then** that node is selected (details panel opens), and all nodes/edges with no direct edge to the selected node dim to 0.15 opacity.
7. **Given** a graph is rendered, **When** the user double-clicks a non-focus node, **Then** the URL hash changes to `#/n/<that_node_name>?depth=<current>` and the graph re-centers on that node.

---

### US-4: Module view (Priority: P1)

As an engineer, I want to select a module and see all its functions arranged as a layered DAG with intra-module call edges, so I can understand the internal call structure of a single file.

**Why this priority**: Complements the neighborhood view. A layered DAG for a single module is far more readable than a force graph for understanding file-level structure.

**Scope**: This story does NOT cover inter-module dependencies, cross-module edges, or the path query feature.

**Independent Test**: Select any module with ≥2 functions in the module dropdown — a layered SVG DAG renders with nodes positioned on discrete horizontal layers and back-edges rendered as curved arcs.

**Acceptance Scenarios**:
1. **Given** the SPA is in Module view, **When** the user selects a module from the dropdown, **Then** `GET /api/graph/module?module_id=N` is called and a layered DAG renders showing all functions from that module with intra-module call edges; the URL becomes `#/m/<module_id>`.
2. **Given** a module containing a mutually recursive pair of functions (back-edge cycle), **When** the layered DAG renders, **Then** the back-edge is drawn as a curved arc (e.g., right-side bezier) visually distinct from forward edges, without crashing or infinite-looping.
3. **Given** a module view is rendered, **When** the user clicks the `[force ⇄ layered]` toggle, **Then** the view switches to a D3 force layout starting from the nodes' current layered positions; no new API request is made.
4. **Given** a module with zero functions (e.g., a module containing only type definitions), **When** the module view is requested, **Then** the canvas shows an empty-state message: "No functions indexed in this module."

---

### US-5: Path queries with soundness framing (Priority: P1)

As an engineer auditing code safety, I want to ask "does function A reach function B via guaranteed calls?" and receive either a highlighted MUST path or a soundness-correct explanation, so I can make confident, falsifiable reachability claims.

**Why this priority**: This is the differentiating feature that makes arch-serve more than a pretty graph viewer — it answers reachability questions in a way that respects the soundness invariant of the index.

**Scope**: This story does NOT cover MAY-only path visualization, the `/api/reaches` response for reflexive queries, or multi-hop path animation in v1.

**Independent Test**: In the details panel for function A, trigger "Reaches…", select function B. If a MUST path exists, marching-ants animate on the path edges. If not, the "No MUST path" banner appears with both function names.

**Acceptance Scenarios**:
1. **Given** function A has a MUST call path to function B, **When** the user selects "Reaches…" in A's details panel and picks B from autocomplete, **Then** the path edges receive a marching-ants CSS animation, non-path nodes/edges dim to 0.15 opacity, and the details panel shows a clickable breadcrumb `A ▸ … ▸ B`.
2. **Given** function X has no MUST call path to function Y, **When** the reaches query is run, **Then** the panel shows exactly: "No MUST path. `<X>` cannot definitely reach `<Y>` through guaranteed calls." — the word "exists" MUST NOT appear in the "no path" framing.
3. **Given** the MUST path from A to C passes through nodes not in the current neighborhood, **When** the path is returned, **Then** the current graph view is replaced by a dedicated left-to-right chain view showing only the path nodes and edges, with a "← back" chip to return to the previous view.
4. **Given** function name `from` or `to` is unknown to the DB, **When** the reaches query is submitted, **Then** an inline error message in the panel reads "Unknown function: `<name>`" and no path animation is triggered.

---

## Challenges

| ID | Story | Challenge | Resolution |
|---|---|---|---|
| C-1 | US-1 | HTML test checks "contains arch-serve" — too loose for a structural test | `<title>` must contain `arch-serve` literally; committed HTML asset includes this in the template |
| C-2 | US-1 | Error message for missing vs invalid SQLite file is unspecified | Message format: `arch-serve: cannot open database: <path>: <reason>`; OS/SQLite reason string distinguishes the two cases |
| C-3 | US-1 | Order of startup checks (DB vs port) is unspecified | Fixed order: (1) validate DB, (2) bind port; errors are emitted distinctly |
| C-4 | US-1 | eio may write fiber cancellation exceptions on SIGINT | Caught at top level; SIGINT and SIGTERM both produce exit 0 with no stderr |
| C-5 | US-2 | `has_mli` integer vs JSON boolean representation | All boolean DB columns serialized as JSON `true`/`false`, never as integers |
| C-6 | US-2 | Filter AND-semantics, missing param behavior, NULL score handling | AND-combined; missing param = no restriction; `min_score` inclusive; NULL score treated as 0 |
| C-7 | US-2 | `/api/functions` response schema not specified | Schema: `{id, module_id, name, signature, line_start, line_end, exposed, comment_quality_score, intent, has_pre, has_post, has_violators}` |
| C-8 | US-2 | BFS traversal direction (callers only, callees only, or both) | Bidirectional: both callers and callees within depth N |
| C-9 | US-2 | Node and edge schemas in graph responses not specified | Node: `{id, name, module_id, exposed, comment_quality_score, intent}`; Edge: `{caller_id, callee_id, kind, call_site}` |
| C-10 | US-2 | `path` in `/api/reaches` uses names (ambiguous across modules) or IDs | Integer function IDs; SPA resolves display names from the cached function list |
| C-11 | US-2 | `/api/reaches` with unknown function name — status code not specified | HTTP 404 with JSON `{"error": "unknown function: <name>"}` |
| C-12 | US-3 | `/` shortcut may conflict with focused input field | Guard: fires only when `document.activeElement` is `body` or `null` |
| C-13 | US-3 | Hash-fragment `?depth=N` is non-standard query-in-fragment syntax | Intentional SPA routing; client JS parses the fragment; URL updates on depth change |
| C-14 | US-3 | Behavior of depth decrease (node removal) not specified | Fade-out animation removes out-of-range nodes; force sim not restarted |
| C-15 | US-3 | "Adjacent" predicate for dimming not specified | 1-hop adjacency (direct edge in either direction from selected node) |
| C-16 | US-4 | `/api/graph/module` response format same as neighborhood? | Same `{nodes, edges}` format; layer computation performed client-side via topological sort in JS |
| C-17 | US-4 | Back-edge detection: server-side flag or client-side DFS | Client-side DFS during layer assignment (no `is_back_edge` field in API response needed) |
| C-18 | US-4 | Force↔layered toggle: starting positions for force sim | Force sim initializes node positions from current layered x/y (sets `fx/fy`) |
| C-19 | US-5 | Marching-ants scope (edges only, nodes only, both) + interaction with dimming | Marching-ants on path edges; non-path nodes/edges dim to 0.15 (same dimming mechanic as US-3) |
| C-20 | US-5 | "No MUST path" message: server-generated or client-composed | Client-composed from `NO_MUST_PATH` result code + function names from cache; API returns structured code only |
| C-21 | US-5 | "Current neighborhood" undefined if no neighborhood view active | Path chain view renders unconditionally regardless of prior view state |

## Functional Requirements

#### Server Startup and Database Validation
- **FR-001** [US-1]: The server MUST validate that the database file exists and is a valid SQLite file before attempting to bind the network port.
- **FR-002** [US-1]: When the database file cannot be opened, the server MUST exit with code 1 and write a message of the form `arch-serve: cannot open database: <path>: <reason>` to stderr.
- **FR-003** [US-1]: The error message on database failure MUST include the file path and a reason that distinguishes a missing file from an invalid SQLite file.
- **FR-004** [US-1]: When port 7371 is already bound, the server MUST exit with code 1 and write a message naming the port conflict to stderr.
- **FR-005** [US-1]: The port-conflict error MUST NOT be emitted until after database validation succeeds.

#### Server Shutdown
- **FR-006** [US-1]: Upon receiving SIGINT, the server MUST shut down cleanly and exit with code 0.
- **FR-007** [US-1]: Upon receiving SIGTERM, the server MUST shut down cleanly and exit with code 0.
- **FR-008** [US-1]: On clean shutdown, the server MUST NOT write any error output to stderr.

#### SPA Delivery
- **FR-009** [US-1]: A GET request to `/` MUST return HTTP 200 with an HTML response whose `<title>` element contains the string `arch-serve`.

#### Module API
- **FR-010** [US-2]: GET `/api/modules` MUST return HTTP 200 with a JSON array where each element contains `{id: int, path: string, lines: int, has_mli: bool}`.
- **FR-011** [US-2]: The `has_mli` field MUST be serialized as a JSON boolean (`true`/`false`), not as an integer.

#### Function API
- **FR-012** [US-2]: GET `/api/functions` MUST return HTTP 200 with a JSON array where each element contains `{id, module_id, name, signature, line_start, line_end, exposed, comment_quality_score, intent, has_pre, has_post, has_violators}`.
- **FR-013** [US-2]: The boolean fields `exposed`, `has_pre`, `has_post`, and `has_violators` MUST be serialized as JSON booleans, not as integers.
- **FR-014** [US-2]: When `module_id` is provided, the response MUST contain only functions belonging to that module.
- **FR-015** [US-2]: When `exposed` is provided, the response MUST contain only functions matching that exposed value.
- **FR-016** [US-2]: When `min_score` is provided, the response MUST contain only functions with `comment_quality_score ≥ min_score`, treating NULL score as 0.
- **FR-017** [US-2]: Multiple query parameters MUST be combined with AND logic.
- **FR-018** [US-2]: An absent query parameter MUST NOT restrict the result set on that dimension.

#### Neighborhood Graph API
- **FR-019** [US-2]: GET `/api/graph/neighborhood` MUST accept `name` and `depth` parameters and return `{nodes, edges, truncated}`.
- **FR-020** [US-2]: The BFS MUST be bidirectional, traversing both callers and callees up to the specified depth.
- **FR-021** [US-2]: Each node MUST contain `{id, name, module_id, exposed, comment_quality_score, intent}`.
- **FR-022** [US-2]: Each edge MUST contain `{caller_id, callee_id, kind, call_site}`.
- **FR-023** [US-2]: When BFS exceeds 2000 nodes, the response MUST cap at 2000 nodes and include `"truncated": true`.

#### Module Graph API
- **FR-024** [US-4]: GET `/api/graph/module` MUST accept `module_id` and return `{nodes, edges}` using the same node/edge schema as the neighborhood endpoint, containing only functions from that module.

#### Reachability API
- **FR-025** [US-2]: GET `/api/reaches` MUST accept `from` and `to` as function name strings.
- **FR-026** [US-2]: When a MUST-edge path exists, the response MUST be `{result: "PATH_EXISTS", path: [<int IDs>]}` using the shortest such path.
- **FR-027** [US-2]: When no MUST-edge path exists, the response MUST be `{result: "NO_MUST_PATH", path: []}`.
- **FR-028** [US-2]: When either name is unknown, the response MUST be HTTP 404 with `{"error": "unknown function: <name>"}`.

#### Keyboard Navigation
- **FR-029** [US-3]: Pressing `/` when no input is focused MUST move focus to the search input.
- **FR-030** [US-3]: Pressing `/` when an input element is focused MUST NOT redirect focus.

#### URL and Navigation State
- **FR-031** [US-3]: Selecting a function from search MUST update the URL hash to `#/n/<name>?depth=2`.
- **FR-032** [US-3]: Changing the depth control MUST update the URL hash without full page reload.

#### Neighborhood Graph Rendering
- **FR-033** [US-3]: Loading `#/n/<name>?depth=N` MUST render a D3 force graph with the focus node highlighted with an accent halo.
- **FR-034** [US-3]: Increasing depth MUST add new nodes/edges with entry animation without restarting the force simulation.
- **FR-035** [US-3]: Decreasing depth MUST remove out-of-range nodes/edges with fade animation without restarting the force simulation.
- **FR-036** [US-3]: Single-clicking a node MUST open the details panel and dim non-1-hop-adjacent nodes/edges to 0.15 opacity.
- **FR-037** [US-3]: Double-clicking a node MUST navigate to `#/n/<that_name>?depth=<current>`.

#### Module Graph Rendering
- **FR-038** [US-4]: Selecting a module MUST render a layered DAG with layer computation performed client-side.
- **FR-039** [US-4]: Back-edges detected client-side MUST be rendered as curved arcs visually distinct from forward edges.
- **FR-040** [US-4]: The force↔layered toggle MUST switch layout without re-fetching data.
- **FR-041** [US-4]: Switching to force layout MUST initialize node positions from the current layered x/y positions.

#### Path Visualization
- **FR-042** [US-5]: When a MUST path exists, path edges MUST receive marching-ants animation and non-path nodes/edges MUST dim to 0.15 opacity.
- **FR-043** [US-5]: When a MUST path exists, the details panel MUST display a clickable breadcrumb `A ▸ … ▸ B`.
- **FR-044** [US-5]: When `NO_MUST_PATH` is returned, the panel MUST display a message stating that `<from>` cannot definitely reach `<to>` through guaranteed calls, composed client-side.
- **FR-045** [US-5]: The no-path message MUST NOT use the phrasing "no path exists" or any equivalent absolute claim.
- **FR-046** [US-5]: When path nodes are outside the current neighborhood, the client MUST replace the current view with a left-to-right path chain view with a `← back` chip.

## Acceptance Criteria

- AC-1 [US-1, S1]: Server starts with valid DB on free port → `GET /` returns HTTP 200 with `<title>` containing `arch-serve`
- AC-2 [US-1, S2]: Missing DB file → exit 1, stderr message includes file path and "No such file or directory" (or equivalent)
- AC-3 [US-1, S3]: Invalid SQLite file → exit 1, stderr message distinguishes from missing file
- AC-4 [US-1, S4]: Port conflict → exit 1, stderr names port 7371; DB was validated first
- AC-5 [US-1, S5]: SIGINT → exit 0, no stderr output
- AC-6 [US-2, S1]: `GET /api/modules` → HTTP 200 JSON array with `has_mli` as boolean
- AC-7 [US-2, S2]: `GET /api/functions?module_id=3&exposed=1&min_score=30` → only matching functions with full schema
- AC-8 [US-2, S3]: `GET /api/graph/neighborhood?name=X&depth=2` → bidirectional BFS, correct node/edge schemas, `truncated: false` when under cap
- AC-9 [US-2, S4]: MUST path A→B→C → `{result: "PATH_EXISTS", path: [id_A,id_B,id_C]}`
- AC-10 [US-2, S5]: No MUST path → `{result: "NO_MUST_PATH", path: []}`
- AC-11 [US-2, S6]: Unknown function → HTTP 404 JSON error
- AC-12 [US-2, S7]: BFS exceeds 2000 nodes → response has at most 2000 nodes and `"truncated": true`
- AC-13 [US-3, S3]: Search + select → URL `#/n/<name>?depth=2`, D3 graph rendered, focus node has accent halo
- AC-14 [US-3, S4]: Depth increase → new nodes animate in, no sim restart, URL updates
- AC-15 [US-3, S5]: Depth decrease → removed nodes fade out, no sim restart
- AC-16 [US-3, S6]: Single click → details panel opens, non-adjacent dims to 0.15
- AC-17 [US-4, S1]: Module selected → layered DAG with intra-module functions only, URL `#/m/<id>`
- AC-18 [US-4, S2]: Module with back-edge → curved arc rendered, no crash
- AC-19 [US-4, S3]: Force↔layered toggle → no re-fetch, force starts from layered positions
- AC-20 [US-4, S4]: Empty module → empty-state message shown
- AC-21 [US-5, S1]: MUST path → marching-ants on path edges, non-path dims, breadcrumb shown
- AC-22 [US-5, S2]: No MUST path → panel shows message without "no path exists"; message includes both function names
- AC-23 [US-5, S3]: Path includes out-of-neighborhood nodes → path chain view with `← back` chip
- AC-24 [US-5, S4]: Unknown function in reaches → inline error "Unknown function: `<name>`"

## Edge Cases

- EC-1 [US-1]: DB file uses incompatible schema (missing columns) → runtime error on first API call; no schema version check in v1 (known limitation)
- EC-2 [US-1]: DB file path contains spaces or Unicode → `cmdliner` positional arg and shell wrapper's `"$@"` quoting handle this correctly
- EC-3 [US-4]: Module with zero functions → `{nodes: [], edges: []}` → client shows "No functions indexed in this module"
- EC-4 [US-3]: Function with no calls (isolated node) → neighborhood is `{nodes: [focus], edges: []}` → D3 renders single node (force sim handles n=1 correctly)
- EC-5 [US-2, US-3]: Function name contains URL-unsafe characters (e.g., OCaml operators `(>>=)`) → client percent-encodes in URL (`encodeURIComponent`); server URL-decodes query params (cohttp handles this)
- EC-6 [US-2, US-3]: Dense neighborhood BFS would return > 2000 nodes → server caps at 2000, `truncated: true`; client caps visual render at 400 with statusbar warning
- EC-7 [US-4]: Module with only one self-recursive function → single node with self-loop; self-loop rendered as a small curved arc back to the same node
- EC-8 [US-5]: Multiple valid MUST paths exist → BFS returns shortest; no preference specified when multiple equally-short paths exist (first BFS-found is acceptable)
- EC-9 [US-5]: Reflexive reaches query (A reaches A) → `{result: "PATH_EXISTS", path: [id_A]}`
- EC-10 [US-1]: ppx_blob cannot find static assets at build time → dune preprocessor_deps causes compile-time failure with a clear dune error; static files must be committed to the repo before building

## Runnable Checks

- CHECK-1 [AC-1]: `opam exec -- dune build && ./_build/default/bin/arch_serve/arch_serve.exe /tmp/self.db & sleep 1; curl -sf http://localhost:7371/ | grep -q '<title>.*arch-serve' && echo PASS; kill %1` → expected: PASS
- CHECK-2 [AC-2]: `./_build/default/bin/arch_serve/arch_serve.exe /nonexistent.db 2>&1; echo "exit:$?"` → expected: exit:1, stderr contains "cannot open database" and file path
- CHECK-3 [AC-6]: `curl -sf http://localhost:7371/api/modules | python3 -c "import sys,json; d=json.load(sys.stdin); assert all(isinstance(m['has_mli'],bool) for m in d); print('PASS')"` → expected: PASS
- CHECK-4 [AC-7]: `curl -sf 'http://localhost:7371/api/functions?exposed=1&min_score=40' | python3 -c "import sys,json; d=json.load(sys.stdin); assert all(m['exposed']==True and (m['comment_quality_score'] or 0)>=40 for m in d); print('PASS')"` → expected: PASS
- CHECK-5 [AC-8]: `curl -sf 'http://localhost:7371/api/graph/neighborhood?name=parse&depth=1' | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'nodes' in d and 'edges' in d and 'truncated' in d; assert all('module_id' in n for n in d['nodes']); assert all('kind' in e for e in d['edges']); print('PASS')"` → expected: PASS
- CHECK-6 [AC-9/10]: `curl -sf 'http://localhost:7371/api/reaches?from=X&to=Y' | python3 -c "import sys,json; d=json.load(sys.stdin); assert d['result'] in ('PATH_EXISTS','NO_MUST_PATH'); assert isinstance(d['path'],list); print(d['result'])"` → expected: one of PATH_EXISTS or NO_MUST_PATH, no exception
- CHECK-7 [AC-11]: `curl -s 'http://localhost:7371/api/reaches?from=nonexistent_fn&to=anything' | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'error' in d; print('PASS')"` → expected: PASS (HTTP 404 with error JSON)
- CHECK-8 [AC-5]: `kill -INT <server-pid>; wait <server-pid>; echo "exit:$?"` → expected: exit:0

## Entities

- `arch-serve`: The compiled binary at `_build/default/bin/arch_serve/arch_serve.exe` and its shell wrapper `arch-serve`; serves the SPA and data API over localhost.
- `neighborhood graph`: A subgraph of functions within N bidirectional hops of a focal function, rendered as a D3 force-directed layout.
- `module view`: A layered DAG layout of all functions within a single module with their intra-module call edges.
- `call kind`: One of `MUST`, `MAY_ENUMERATED`, or `MAY_TOP`; represents the soundness class of a call edge in the index.
- `MUST path`: A call path where every edge has `kind = MUST`; the only kind of path for which `PATH_EXISTS` is returned.
- `MAY_TOP edge`: A call edge representing a call whose target was unknown at compile time (higher-order function, dynamic dispatch); a soundness marker, not a bug.
- `SPA`: The single-page application embedded in the binary via `ppx_blob`; consists of `index.html`, `app.js`, `style.css`, `d3.min.js` under `bin/arch_serve/static/`.
