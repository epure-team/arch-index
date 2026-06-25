# Implementer Brief — arch-serve

**Date:** 2026-06-25
**Status:** VALIDATED
**Mode:** full
**Spec:** specs/arch-serve.md
**Plan:** briefs/arch-serve-plan.md

## Goal

Implement the `arch-serve` binary: a local HTTP server serving a SPA over localhost for call-graph exploration. 6 sequential steps. Each step produces a buildable, testable increment.

## Scope Boundary

- Read-only SQLite access only
- No new opam deps (reuse cohttp-eio, ppx_blob, sqlite3, eio_posix, cmdliner, yojson — already in dune-project)
- SPA is plain vanilla JS + D3; no build toolchain, no TypeScript, no bundler
- `arch_index_db.ml` is `(private_modules ...)` — do NOT import it; use `Sqlite3` directly in the binary

## Files to Create

| File | Purpose |
|---|---|
| `bin/arch_serve/arch_serve.ml` | CLI + HTTP server + all API endpoints + ppx_blob asset serving |
| `bin/arch_serve/dune` | Executable stanza with ppx_blob preprocessor_deps |
| `bin/arch_serve/static/index.html` | SPA HTML shell |
| `bin/arch_serve/static/style.css` | Dark theme CSS |
| `bin/arch_serve/static/app.js` | SPA logic (router, D3, table, graph, paths) |
| `bin/arch_serve/static/d3.min.js` | D3 v7 full minified build (committed to repo) |
| `arch-serve` | Shell wrapper script |

## Step 1 — OCaml server scaffold

**Files:** `bin/arch_serve/arch_serve.ml` (initial), `bin/arch_serve/dune`, `bin/arch_serve/static/index.html` (minimal)

### `bin/arch_serve/dune`
```dune
(executable
 (name arch_serve)
 (public_name arch_serve)
 (libraries cohttp-eio eio_posix cmdliner sqlite3 yojson uri)
 (preprocessor_deps
  (file static/index.html)
  (file static/app.js)
  (file static/style.css)
  (file static/d3.min.js))
 (preprocess
  (pps ppx_blob)))
```

Note: `ppx_deriving_yojson` is NOT needed — serialize JSON manually with `Yojson.Safe.t` constructors. This avoids type derivation complexity for what are essentially flat record-to-JSON mappings.

### `arch_serve.ml` — skeleton
```ocaml
open Cmdliner

let index_html = [%blob "static/index.html"]
let app_js     = [%blob "static/app.js"]
let style_css  = [%blob "static/style.css"]
let d3_js      = [%blob "static/d3.min.js"]

let serve db_path port =
  Eio_posix.run (fun env ->
    Eio.Switch.run (fun sw ->
      (* 1. Validate DB before binding port *)
      let db =
        match Sqlite3.db_open ~mode:`READONLY db_path with
        | db ->
          (match Sqlite3.exec db "SELECT 1;" with
           | Sqlite3.Rc.OK -> db
           | rc ->
             Printf.eprintf "arch-serve: cannot open database: %s: %s\n%!"
               db_path (Sqlite3.Rc.to_string rc);
             exit 1)
        | exception _ ->
          Printf.eprintf "arch-serve: cannot open database: %s: No such file or directory\n%!"
            db_path;
          exit 1
      in
      (* 2. Signal handling: SIGINT/SIGTERM → cancel switch *)
      let cancel () = Eio.Switch.fail sw (Exit) in
      Eio_unix.signal Sys.sigint  cancel;
      Eio_unix.signal Sys.sigterm cancel;
      (* 3. Start server *)
      let addr = `TCP (Eio.Net.Ipaddr.V4.loopback, port) in
      let socket = Eio.Net.listen ~sw ~backlog:5 ~reuse_addr:true
        (Eio.Stdenv.net env) addr in
      Printf.printf "Serving at http://localhost:%d — press Ctrl-C to stop\n%!" port;
      ignore (Eio.Fiber.fork_promise ~sw (fun () ->
        ignore (Sys.command (Printf.sprintf "xdg-open http://localhost:%d 2>/dev/null || open http://localhost:%d 2>/dev/null" port port))));
      let handler _conn request _body =
        let uri = Cohttp.Request.uri request in
        let path = Uri.path uri in
        (* Route dispatch — see Step 2 for API routes *)
        match path with
        | "/" -> Cohttp_eio.Server.respond_string
            ~status:`OK
            ~headers:(Cohttp.Header.of_list ["Content-Type","text/html; charset=utf-8"])
            index_html ()
        | "/static/app.js" -> Cohttp_eio.Server.respond_string
            ~status:`OK ~headers:(Cohttp.Header.of_list ["Content-Type","application/javascript"]) app_js ()
        | "/static/style.css" -> Cohttp_eio.Server.respond_string
            ~status:`OK ~headers:(Cohttp.Header.of_list ["Content-Type","text/css"]) style_css ()
        | "/static/d3.min.js" -> Cohttp_eio.Server.respond_string
            ~status:`OK ~headers:(Cohttp.Header.of_list ["Content-Type","application/javascript"]) d3_js ()
        | _ ->
          Cohttp_eio.Server.respond_string ~status:`Not_found
            ~headers:(Cohttp.Header.of_list ["Content-Type","application/json"])
            {|{"error":"not found"}|} ()
      in
      (try Cohttp_eio.Server.run socket ~on_error:(fun _ -> ()) handler
       with Exit -> ());
      Sqlite3.db_close db |> ignore))

let db_arg = Arg.(required & pos 0 (some file) None & info [] ~docv:"DB" ~doc:"Path to SQLite architecture DB")
let port_arg = Arg.(value & opt int 7371 & info ["port";"p"] ~docv:"PORT" ~doc:"HTTP port (default 7371)")

let cmd = Term.(const serve $ db_arg $ port_arg),
          Cmd.info "arch-serve" ~doc:"Serve call-graph SPA from a SQLite DB"

let () = exit (Cmd.eval (Cmd.v (snd cmd) (fst cmd)))
```

**IMPORTANT — verify before writing:** The `Cohttp_eio.Server` API must be checked against the installed version. The `run` function signature and the handler type have changed between cohttp-eio versions. Run `opam show cohttp-eio` to get the version, then check its documentation. The snippet above is illustrative — exact API may differ.

**IMPORTANT — signal handling:** `Eio_unix.signal` may not be the correct API. Check the installed `eio_posix` for the signal handler API. Alternative: use `Sys.set_signal Sys.sigint (Sys.Signal_handle (fun _ -> Eio.Switch.fail sw Exit))` — but this must be called from within the Eio event loop, not outside it.

**Completion criterion:** `opam exec -- dune build` passes; `curl http://localhost:7371/` returns HTTP 200 with HTML; `kill -INT <pid>` → process exits 0 with no stderr.

---

## Step 2 — Data API layer

**Files:** `bin/arch_serve/arch_serve.ml` (extended)

Add JSON helpers and API endpoint handlers. Insert into the `handler` match before the `_` catch-all.

### SQLite query helpers (add to arch_serve.ml)

Since `arch_index_db.ml` is private, define minimal helpers locally:

```ocaml
let bool_of_int = function 1 -> true | _ -> false

let json_bool b = if b then `Bool true else `Bool false

(* Execute a SELECT and collect rows as list of Sqlite3.Data.t arrays *)
let query_rows db sql bind_fn =
  let stmt = Sqlite3.prepare db sql in
  bind_fn stmt;
  let rows = ref [] in
  while Sqlite3.step stmt = Sqlite3.Rc.ROW do
    let n = Sqlite3.data_count stmt in
    let row = Array.init n (Sqlite3.column stmt) in
    rows := row :: !rows
  done;
  Sqlite3.finalize stmt |> ignore;
  List.rev !rows

let col_text stmt i = match Sqlite3.column stmt i with
  | Sqlite3.Data.TEXT s -> s | _ -> ""
let col_int stmt i = match Sqlite3.column stmt i with
  | Sqlite3.Data.INT n -> Int64.to_int n | _ -> 0
let col_int_opt stmt i = match Sqlite3.column stmt i with
  | Sqlite3.Data.INT n -> Some (Int64.to_int n) | Sqlite3.Data.NULL -> None | _ -> None
let col_bool stmt i = match Sqlite3.column stmt i with
  | Sqlite3.Data.INT n -> n <> 0L | _ -> false
```

### `/api/modules`
```ocaml
| "/api/modules" ->
  let rows = query_rows db
    "SELECT id, path, lines, has_mli FROM modules ORDER BY path"
    (fun _ -> ()) in
  let json = `List (List.map (fun row ->
    `Assoc [
      "id",      `Int  (col_int  row 0);
      "path",    `String (col_text row 1);
      "lines",   `Int  (col_int  row 2);
      "has_mli", json_bool (col_bool row 3);
    ]) rows) in
  respond_json json
```

### `/api/functions`
Parse query params (`module_id`, `exposed`, `min_score`). Build WHERE clause dynamically. Serialize with all boolean fields as JSON booleans.

**Boolean trap:** `exposed`, `has_pre`, `has_post`, `has_violators` come from SQLite as `INT 0/1`. Use `json_bool (col_bool row N)` — NEVER `\`Int (col_int row N)`.

### `/api/graph/neighborhood`
Bidirectional BFS — see algorithm below.

### `/api/graph/module`
```sql
SELECT id, name, module_id, exposed, comment_quality_score, intent
FROM functions WHERE module_id = ?
```
```sql
SELECT caller_id, callee_id, kind, call_site FROM calls
WHERE caller_id IN (SELECT id FROM functions WHERE module_id = ?)
  AND callee_id IN (SELECT id FROM functions WHERE module_id = ?)
```

### `/api/reaches`
BFS over MUST-kind edges only (`kind = 'MUST' OR kind IS NULL`). Return shortest path as integer IDs.

### `/api/reaches` — unknown function → HTTP 404
```ocaml
| Sqlite3.Data.NULL ->
  Cohttp_eio.Server.respond_string ~status:`Not_found
    ~headers:json_headers
    (Printf.sprintf {|{"error":"unknown function: %s"}|} name) ()
```

---

## BFS Algorithm — bidirectional neighborhood

```
Input: seed function name, depth N
Output: {nodes, edges, truncated}

1. Resolve name → id (SELECT id FROM functions WHERE name = ?)
   If not found → HTTP 404

2. Initialize:
   visited_nodes = {seed_id}
   frontier = {seed_id}
   edges_seen = {}

3. For hop = 1 to N:
   next_frontier = {}
   
   For each node_id in frontier:
     -- Outgoing edges (callees)
     SELECT callee_id, caller_id, callee_id, kind, call_site
     FROM calls WHERE caller_id = node_id
     
     -- Incoming edges (callers)  
     SELECT caller_id, caller_id, callee_id, kind, call_site
     FROM calls WHERE callee_id = node_id
     
     For each edge:
       Add edge to edges_seen (dedup by caller_id+callee_id+kind)
       If other_node not in visited_nodes:
         Add to next_frontier
         Add to visited_nodes
         If |visited_nodes| >= 2000: set truncated=true, stop expanding

   frontier = next_frontier
   If frontier is empty: break

4. Fetch node metadata for all visited_nodes:
   SELECT id, name, module_id, exposed, comment_quality_score, intent
   FROM functions WHERE id IN (...)

5. Return {nodes, edges, truncated}
```

Key: the 2000-node cap drops the outermost frontier — nodes closest to seed are always included.

---

## MUST-path BFS for `/api/reaches`

```
Input: from_name, to_name
Output: {result, path}

1. Resolve both names → IDs; 404 if either unknown

2. BFS queue = [(from_id, [from_id])]
   visited = {from_id}

3. While queue not empty:
   (current_id, path) = dequeue
   If current_id == to_id: return {result: "PATH_EXISTS", path: path}
   
   SELECT callee_id FROM calls
   WHERE caller_id = current_id
     AND (kind = 'MUST' OR kind IS NULL)
   
   For each callee_id not in visited:
     visited.add(callee_id)
     enqueue (callee_id, path ++ [callee_id])

4. If queue exhausted: return {result: "NO_MUST_PATH", path: []}
```

---

## Step 3 — SPA foundation (index.html, style.css, app.js skeleton, d3.min.js)

### index.html (structure)
```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>arch-serve</title>
  <link rel="stylesheet" href="/static/style.css">
</head>
<body class="app">
  <header class="app__header">
    <span class="app__logo">arch-serve</span>
    <input id="search" class="search" type="search" placeholder="⌕ search function…" autocomplete="off">
    <nav class="view-toggle">
      <button id="btn-neighborhood" class="btn btn--active">Neighborhood</button>
      <button id="btn-module" class="btn">Module</button>
    </nav>
    <div id="depth-controls" class="depth-controls">
      <span class="depth-label">depth</span>
      <button class="depth-btn" data-depth="1">1</button>
      <button class="depth-btn depth-btn--active" data-depth="2">2</button>
      <button class="depth-btn" data-depth="3">3</button>
    </div>
  </header>
  <div class="app__body">
    <aside class="sidebar" id="sidebar">
      <div class="sidebar__filters">
        <select id="module-filter" class="filter-select"><option value="">all modules</option></select>
        <label class="filter-check"><input type="checkbox" id="exposed-filter"> exposed only</label>
        <div class="filter-score">
          score ≥ <input type="range" id="score-filter" min="0" max="75" value="0">
          <span id="score-value">0</span>
        </div>
      </div>
      <div class="sidebar__header">FUNCTIONS (<span id="fn-count">…</span>)</div>
      <div class="ftable" id="ftable"></div>
    </aside>
    <main class="stage" id="stage">
      <svg id="graph-svg" width="100%" height="100%"></svg>
      <div id="legend" class="legend">
        <div class="legend__row" data-kind="MUST">━━▶ <strong>MUST</strong> definite call</div>
        <div class="legend__row" data-kind="MAY_ENUMERATED">┅┅▶ <strong>MAY</strong> possible, known</div>
        <div class="legend__row" data-kind="MAY_TOP">⌁⌁▶ <strong>⊤</strong> possible, unknown</div>
      </div>
    </main>
    <aside class="panel" id="panel">
      <button class="panel__close" id="panel-close">×</button>
      <div id="panel-content"></div>
    </aside>
  </div>
  <footer class="statusbar" id="statusbar"></footer>
  <script src="/static/d3.min.js"></script>
  <script src="/static/app.js"></script>
</body>
</html>
```

### style.css — CSS custom properties (root)
```css
:root {
  --bg-0: #0d1117; --bg-1: #161b22; --bg-2: #21262d; --bg-3: #30363d;
  --fg-0: #e6edf3; --fg-1: #9da7b3; --fg-2: #6e7681;
  --accent: #58a6ff; --accent-2: #2dd4bf;
  --edge-must: #adbac7; --edge-may: #e3b341; --edge-top: #bc8cff;
  --warn: #f0883e;
  --mod-0: #58a6ff; --mod-1: #3fb950; --mod-2: #e3b341; --mod-3: #ff7b72;
  --mod-4: #bc8cff; --mod-5: #39c5cf; --mod-6: #db61a2; --mod-7: #f0883e;
  --mod-8: #6cb6ff; --mod-9: #8ddb8c; --mod-10: #f2cc60; --mod-11: #ffb3ba;
}
```

Include the full layout styles (48px header, 320px sidebar, stage fills remaining, 360px panel overlay, 24px statusbar) as described in UX spec §1.

### d3.min.js
Obtain D3 v7 minified from https://d3js.org/d3.v7.min.js and commit it to `bin/arch_serve/static/d3.min.js`. **Do not link to an external CDN** — the binary must be self-contained.

### app.js — foundation
```javascript
// State
const S = {
  allFns: [],       // [{id, name, module_id, exposed, comment_quality_score, intent, signature}]
  allModules: [],   // [{id, path, lines, has_mli}]
  view: 'neighborhood',  // 'neighborhood' | 'module'
  focus: null,      // current function name
  depth: 2,
  selectedId: null,
  filters: { module_id: null, exposed: false, min_score: 0 },
  sim: null,        // D3 force simulation
};

// API helper
const api = (path) => fetch(path).then(r => r.json());

// Safe DOM helper (XSS-safe via textContent)
function h(tag, attrs, children) { /* ... */ }

// Boot
async function boot() {
  [S.allModules, S.allFns] = await Promise.all([
    api('/api/modules'),
    api('/api/functions'),
  ]);
  populateModuleDropdown();
  renderTable(S.allFns);
  updateStatusbar();
  window.addEventListener('hashchange', onHashChange);
  onHashChange();
}

// Hash router
function onHashChange() {
  const hash = location.hash;
  const nMatch = hash.match(/^#\/n\/([^?]+)(?:\?depth=(\d))?$/);
  const mMatch = hash.match(/^#\/m\/(\d+)$/);
  if (nMatch) {
    S.view = 'neighborhood';
    S.focus = decodeURIComponent(nMatch[1]);
    S.depth = parseInt(nMatch[2] || '2');
    renderNeighborhood(S.focus, S.depth);
  } else if (mMatch) {
    S.view = 'module';
    renderModule(parseInt(mMatch[1]));
  }
}
```

**Completion criterion:** SPA loads; table shows all functions; module filter, exposed checkbox, score slider all apply AND-combined filters; row click navigates to `#/n/<name>`.

---

## Step 4 — Neighborhood graph

Implement `renderNeighborhood(name, depth)` in app.js:

1. Fetch `GET /api/graph/neighborhood?name=${encodeURIComponent(name)}&depth=${depth}`
2. Build D3 force sim with params from UX spec §9.2 (see below)
3. Node/edge visual encoding per UX spec §2.2 and §2.3
4. **Incremental update** (critical): use `selection.data(nodes, d => d.id)` stable key join — existing nodes keep their positions, new nodes fade in, removed nodes fade out. Do NOT restart the sim; call `sim.nodes(newNodes); sim.force('link').links(newEdges); sim.alpha(0.3).restart()`.
5. Details panel: `renderPanel(node)` — function name, module swatch, signature (mono), score bar, contract flags, intent, callees/callers grouped by kind

### Force sim params
```javascript
const sim = d3.forceSimulation()
  .force('link', d3.forceLink().id(d => d.id).distance(60).strength(0.5))
  .force('charge', d3.forceManyBody().strength(-220).distanceMax(320))
  .force('collide', d3.forceCollide(d => d.r + 6))
  .force('center', d3.forceCenter(W/2, H/2))
  .force('x', d3.forceX(W/2).strength(0.04))
  .force('y', d3.forceY(H/2).strength(0.04))
  .alphaDecay(0.045)
  .on('tick', ticked)
  .on('end', () => sim.stop());
```

### Edge SVG markers (3 defs)
```javascript
const defs = svg.append('defs');
// MUST: solid filled arrowhead in --edge-must color
// MAY_ENUMERATED: hollow arrowhead in --edge-may color
// MAY_TOP: hollow arrowhead in --edge-top color
// Each <marker> has id="arrow-must", "arrow-may", "arrow-top"
```

### Node radius
```javascript
const nodeRadius = d => 6 + ((d.comment_quality_score || 0) / 75) * 8;
```

### Module color
```javascript
const modColor = d => `var(--mod-${d.module_id % 12})`;
```

### Edge path (quadratic bezier for reciprocal pairs)
```javascript
// Offset reciprocal pairs: A→B and B→A get mirrored control points
```

---

## Step 5 — Path queries + module view

### Path queries
```javascript
async function runReaches(fromName, toName) {
  const url = `/api/reaches?from=${encodeURIComponent(fromName)}&to=${encodeURIComponent(toName)}`;
  const data = await api(url);
  if (data.result === 'PATH_EXISTS') {
    highlightPath(data.path);  // marching-ants on path edges, dim others to 0.15
    showBreadcrumb(data.path, fromName, toName);
  } else {
    // MUST NOT say "no path exists"
    showInPanel(`No MUST path. \`${fromName}\` cannot definitely reach \`${toName}\` through guaranteed calls.`);
  }
}
```

Marching-ants CSS:
```css
@keyframes march {
  to { stroke-dashoffset: -20; }
}
.edge--flow {
  stroke-dasharray: 6 4;
  animation: march 0.8s linear infinite;
  stroke: var(--accent-2);
}
@media (prefers-reduced-motion) {
  .edge--flow { animation: none; }
}
```

### Module view — layered DAG layout
```javascript
function computeLayers(nodes, edges) {
  // 1. DFS to find back-edges
  const visited = new Set(), stack = new Set(), backEdges = new Set();
  function dfs(id) {
    visited.add(id); stack.add(id);
    for (const e of edges.filter(e => e.caller_id === id)) {
      if (stack.has(e.callee_id)) { backEdges.add(`${e.caller_id}-${e.callee_id}`); }
      else if (!visited.has(e.callee_id)) dfs(e.callee_id);
    }
    stack.delete(id);
  }
  nodes.forEach(n => { if (!visited.has(n.id)) dfs(n.id); });

  // 2. Longest-path layer assignment on DAG (excluding back-edges)
  const layer = {}, memo = {};
  const dagEdges = edges.filter(e => !backEdges.has(`${e.caller_id}-${e.callee_id}`));
  function getLayer(id) {
    if (id in memo) return memo[id];
    const incoming = dagEdges.filter(e => e.callee_id === id);
    memo[id] = incoming.length === 0 ? 0 :
      1 + Math.max(...incoming.map(e => getLayer(e.caller_id)));
    return memo[id];
  }
  nodes.forEach(n => { layer[n.id] = getLayer(n.id); });

  // 3. Group by layer, position
  const byLayer = {};
  nodes.forEach(n => {
    const l = layer[n.id];
    byLayer[l] = byLayer[l] || [];
    byLayer[l].push(n);
  });
  const LAYER_H = 90, NODE_W = 120;
  Object.entries(byLayer).forEach(([l, ns]) => {
    const totalW = ns.length * NODE_W;
    ns.forEach((n, i) => {
      n.fx = -totalW/2 + i * NODE_W + NODE_W/2;
      n.fy = parseInt(l) * LAYER_H;
    });
  });
  return { layer, backEdges };
}
```

---

## Step 6 — Shell wrapper + polish

### arch-serve (shell wrapper)
```bash
#!/usr/bin/env bash
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$HERE/bin/arch_serve" "$@"
```
Make executable: `chmod +x arch-serve`.

### Polish items
- Empty states: isolated node message, empty module message, first-load hint card
- Keyboard shortcuts: `/`, `j/k`, `1/2/3`, `f`, `[`, `r`, `?`, `Esc`
- Statusbar: counts from boot-time API data + current render counts
- `← back` chip for path chain view
- Toasts (bottom-center, 2s auto-dismiss)

---

## Quality Gates

```bash
# Build
opam exec -- dune build

# Existing tests must still pass
opam exec -- dune test

# Smoke test (run after building)
BIN="./_build/default/bin/arch_serve/arch_serve.exe"
opam exec -- "$BIN" /tmp/self.db --port 7372 &
PID=$!
sleep 1
curl -sf http://localhost:7372/ | grep -q '<title>.*arch-serve' && echo "OK: root"
curl -sf http://localhost:7372/api/modules | python3 -c "import sys,json; d=json.load(sys.stdin); assert all(isinstance(m['has_mli'],bool) for m in d); print('OK: booleans')"
curl -sf 'http://localhost:7372/api/functions?exposed=1' | python3 -c "import sys,json; d=json.load(sys.stdin); assert all(m['exposed']==True for m in d); print('OK: filter')"
curl -sf 'http://localhost:7372/api/graph/neighborhood?name=parse&depth=1' | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'nodes' in d and 'edges' in d and 'truncated' in d; print('OK: neighborhood')"
kill $PID; wait $PID 2>/dev/null; echo "exit: $?"
```

## Points of Attention for Review

1. **cohttp-eio server API** — verify exact function signatures before writing Step 1; the project has never used cohttp-eio in server mode
2. **Signal handling** — test with `kill -INT <pid>` and `kill -TERM <pid>`; must exit 0 with no stderr
3. **Boolean fields** — every `exposed`, `has_mli`, `has_pre`, `has_post`, `has_violators` must be `\`Bool` not `\`Int` in all JSON responses
4. **BFS bidirectionality** — both `caller_id = node` and `callee_id = node` queries at each hop, no double-counting of nodes
5. **`kind IS NULL` treated as MUST** in all BFS queries
6. **D3 incremental update** — stable data join by `d.id`; do not re-create the simulation on depth change
7. **`encodeURIComponent`** on function names in all API URLs (OCaml operators like `(>>=)` are URL-unsafe)
8. **ppx_blob**: all 4 static files must be listed in `(preprocessor_deps ...)` before the first `[%blob ...]` reference
