# Plan — arch-serve

**Date:** 2026-06-25
**Status:** VALIDATED

## Sequential steps

### Step 1 — OCaml server scaffold (server + static assets)
**Files:** `bin/arch_serve/arch_serve.ml`, `bin/arch_serve/dune`, `bin/arch_serve/static/index.html` (minimal shell only)

Implement:
- Cmdliner CLI: positional `db` arg, optional `--port` (default 7371)
- DB validation: open SQLite, verify it responds to a simple query — exit 1 with `arch-serve: cannot open database: <path>: <reason>` if it fails; do this BEFORE binding the port
- cohttp-eio `Server.make` + `Server.run` on `Eio_posix.run` environment — this is the **first use of cohttp-eio in server mode** in the project; study the API carefully before writing
- Signal handling: `Eio_unix.signal Sys.sigint` and `Sys.sigterm` → cancel the top-level switch → `Server.run` exits → process exits 0
- Serve `/` → embedded `index.html` (ppx_blob); serve `/static/<asset>` → dispatch by filename to embedded assets
- Print `Serving at http://localhost:7371 — press Ctrl-C to stop`, then attempt `xdg-open`/`open` silently
- `bin/arch_serve/dune` stanza: `(executable ...)` + `(preprocessor_deps (file static/index.html))` + `(preprocess (pps ppx_blob))`

**Completion criterion:** `opam exec -- dune build` passes; `curl http://localhost:7371/` returns HTTP 200 with `<title>` containing `arch-serve`; SIGINT kills the process with exit 0 and no stderr.

**Depends on:** nothing — this is the foundation.

---

### Step 2 — Data API layer (all 5 endpoints)
**Files:** `bin/arch_serve/arch_serve.ml` (extended)

Implement all API endpoints. Each endpoint opens the SQLite DB read-only and returns JSON:

- `GET /api/modules` — `SELECT id, path, lines, has_mli FROM modules ORDER BY path`; serialize `has_mli` as JSON boolean
- `GET /api/functions?module_id=N&exposed=N&min_score=N` — AND-combined WHERE clauses; missing param = no restriction; `min_score` inclusive; NULL score treated as 0; boolean fields as JSON `true`/`false`; node schema: `{id, module_id, name, signature, line_start, line_end, exposed, comment_quality_score, intent, has_pre, has_post, has_violators}`
- `GET /api/graph/neighborhood?name=X&depth=N` — bidirectional BFS (callers AND callees); N = hops in each direction independently; when node count exceeds 2000, drop outermost frontier first (closest-hop nodes kept); response: `{nodes, edges, truncated: bool}`; node schema: `{id, name, module_id, exposed, comment_quality_score, intent}`; edge schema: `{caller_id, callee_id, kind, call_site}`
- `GET /api/graph/module?module_id=N` — SELECT all functions in module; SELECT calls where both caller and callee are in that module; same `{nodes, edges}` schema
- `GET /api/reaches?from=X&to=Y` — resolve names to IDs (HTTP 404 + `{"error": "unknown function: <name>"}` if not found); BFS over MUST-kind edges only; return `{result: "PATH_EXISTS", path: [int IDs]}` (shortest path) or `{result: "NO_MUST_PATH", path: []}`

All error responses: JSON `{"error": "..."}` with appropriate HTTP status (400 for bad params, 404 for not found, 500 for unexpected).
Set `Content-Type: application/json` on all `/api/*` responses.

**Completion criterion:** All CHECK-1 through CHECK-8 from `specs/arch-serve.md` pass.

**Depends on:** Step 1 (server infrastructure).

---

### Step 3 — SPA foundation: shell + function table + filters
**Files:** `bin/arch_serve/static/index.html`, `bin/arch_serve/static/style.css`, `bin/arch_serve/static/app.js` (foundation), `bin/arch_serve/static/d3.min.js`; update `bin/arch_serve/dune` preprocessor_deps

Implement:
- `index.html`: static shell — 48px header (logo + search input + view toggle + depth controls), 320px sidebar (filters block + function table), main stage (`<svg>` fills remaining space), 360px details panel (hidden initially, `position:absolute; right:0`), 24px statusbar. No framework, plain HTML.
- `style.css`: CSS custom properties (`--bg-0` through `--bg-3`, `--fg-0` through `--fg-2`, `--accent`, `--accent-2`, `--edge-must/may/top`, `--warn`; module palette 12 colors); utility classes; component classes per UX spec §7.3
- `d3.min.js`: D3 v7 full build (vendored, committed to repo)
- `app.js` — foundation only:
  - Hash router: `window.onhashchange` → parse `#/n/<name>?depth=N` | `#/m/<id>` → dispatch
  - Boot: fetch `/api/modules` and `/api/functions` once (cache in `S.allFns`, `S.allModules`)
  - Sidebar filters: module dropdown, exposed checkbox, score slider — compose into one `/api/functions?...` request (debounced 200ms); render results into function table
  - Function table: 4 columns (colored dot / name / score micro-bar / flags); infinite scroll (pages of 100, append on scroll-near-bottom); row click → `focus(name)` → navigate to `#/n/<name>`
  - `h(tag, attrs, children)` DOM helper for safe rendering (all DB strings via `textContent`)
- Update `bin/arch_serve/dune` preprocessor_deps to list all 4 static files

**Completion criterion:** SPA loads, sidebar table shows all functions, all three filters compose correctly, row click updates URL hash.

**Depends on:** Step 2 (API must exist to test).

---

### Step 4 — Neighborhood graph
**Files:** `bin/arch_serve/static/app.js` (extended)

Implement D3 force graph in the stage SVG:

- `renderNeighborhood(name, depth)`: fetch `GET /api/graph/neighborhood?name=X&depth=N`, build D3 force sim
- Force sim params (from UX spec §9.2): link distance 60, charge -220 distanceMax 320, collide r+6, gentle center gravity (strength 0.04), alphaDecay 0.045, freeze on `'end'`
- Node encoding: hue = module color from 12-color palette (by `module_id % 12`); border ring = exposed; radius = `6 + (score/75)*8` (range 6–14px); focus node = accent halo pinned to center
- Edge encoding: MUST = solid `--edge-must` / filled arrowhead; MAY_ENUMERATED = dashed `4 3` amber; MAY_TOP = dotted violet + `⊤` glyph at midpoint; curved paths (quadratic bezier) so reciprocal pairs don't overlap
- SVG `<marker>` defs for 3 arrowhead styles
- **Incremental updates**: data join with stable key `d => d.id`; depth change → diff nodes/edges → add new with fade-in, remove out-of-range with fade-out; do NOT restart sim — call `simulation.nodes(newNodes)`, `.force('link').links(newEdges)`, `.alpha(0.3).restart()`
- Node interaction: single click → select (open details panel, dim non-1-hop-adjacent to 0.15); double click → `focus(newName)`; drag → pin `fx/fy`
- Zoom: `d3.zoom` scale `[0.2, 4]`; `[⊹ fit]` button; label LOD (hide hop-2+ at zoom < 0.6)
- Details panel: function name, module swatch, signature (mono), score bar, contract flags (has_pre/has_post/has_violators), intent text, callees/callers grouped by kind with kind glyph, "Reaches…" / "Reachable from…" quick-action links
- Autocomplete search: client-side filter of `S.allFns`; match substring on `name`; rank prefix > shorter > exposed; max 10 results; `/` shortcut (guard: `activeElement === body || null`)
- Depth controls: segmented `1 · 2 · 3` buttons; updates URL hash

**Completion criterion:** `#/n/find_tag_positions?depth=2` renders a force graph; depth change animates; single/double click work; details panel shows correct data.

**Depends on:** Step 3 (layout shell, style, router).

---

### Step 5 — Path queries + module view
**Files:** `bin/arch_serve/static/app.js` (extended)

**Path queries:**
- "Reaches…" quick action in details panel → autocomplete for target function → call `GET /api/reaches?from=X&to=Y`
- On `PATH_EXISTS`: ensure path nodes in view (fetch neighborhood union or render dedicated chain); apply `.edge--flow` CSS class to path edges (marching-ants via `stroke-dashoffset` keyframe); dim non-path to 0.15; show breadcrumb `A ▸ … ▸ B` in panel (clickable, each hop syncs canvas)
- Out-of-neighborhood path: render dedicated left-to-right chain (path nodes in order, layered strategy, `← back` chip)
- On `NO_MUST_PATH`: panel shows "No MUST path. `<from>` cannot definitely reach `<to>` through guaranteed calls." — MUST NOT say "no path exists"
- On HTTP 404 (unknown function): inline "Unknown function: `<name>`"

**Module view:**
- `renderModule(module_id)`: fetch `GET /api/graph/module?module_id=N`
- Client-side layered DAG layout:
  1. DFS → identify back-edges (edges to ancestor in DFS stack)
  2. Longest-path layer assignment on DAG (excluding back-edges): `layer(v) = 1 + max(layer(u) for u→v)`
  3. Barycenter ordering within each layer (one pass to reduce crossings)
  4. Position: `y = layer * 90`, `x = orderIndex * 120`, center each layer
  5. Render forward edges as straight/slightly-curved; back-edges as wide right-side bezier arcs (muted color)
- Node hue re-purposed: full-saturation = exposed, desaturated = internal (module is constant, so hue channel freed)
- Force↔layered toggle: layered → set `fx/fy`; force → release `fx/fy` from layered positions, run sim
- Module selector: dropdown in header listing all modules by path; selecting → `#/m/<module_id>`
- Empty module (0 functions): empty-state "No functions indexed in this module"

**Completion criterion:** Path highlighting with marching-ants; NO_MUST_PATH framing correct; module view renders layered DAG; back-edge shown as curved arc; toggle works.

**Depends on:** Step 4 (details panel infrastructure, node rendering code).

---

### Step 6 — Polish + shell wrapper
**Files:** `bin/arch_serve/static/app.js` (polish), `bin/arch_serve/static/style.css` (polish), `arch-serve` (new shell wrapper)

Implement:
- **Empty states:** isolated node message; first-load hint card (3 example links to highest-score exposed functions); empty filtered table "No functions match these filters" + `[clear filters]`
- **Keyboard shortcuts:** `j/k` table nav; `Enter` focus selected; `f` fit-to-view; `[` sidebar toggle; `1/2/3` depth; `n/m` switch views; `r` start reaches; `?` shortcuts overlay; `Esc` close panel/clear path
- **Toasts:** bottom-center, auto-dismiss 2s — for "copied `file:line`", "truncated render", etc.
- **Reduced motion:** `@media (prefers-reduced-motion)` → disable marching-ants, stagger, transitions
- **Legend:** persistent bottom-left legend (MUST/MAY/TOP rows with kind glyph); hover dims other kinds; edge-kind filter toggles
- **Statusbar:** global `modules · fns · calls` counts on load; current render counts updated on graph render
- **arch-serve shell wrapper:** `HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd); exec "$HERE/bin/arch_serve" "$@"`

**Completion criterion:** All keyboard shortcuts work; arch-serve wrapper executes binary correctly; empty states display; reduced motion respected.

**Depends on:** Step 5 (full SPA built).

---

## Dependencies

```
Step 1 (server scaffold)
  └─▶ Step 2 (data API)
        └─▶ Step 3 (SPA shell + table)
              └─▶ Step 4 (neighborhood graph)
                    └─▶ Step 5 (paths + module view)
                          └─▶ Step 6 (polish + wrapper)
```

Strictly sequential — each step requires the previous to be testable. Steps 4 and 5 are the largest; 1 and 2 are the riskiest (cohttp-eio server mode first used in step 1).

## Identified risks

| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| cohttp-eio server API unfamiliar — server mode vs. client mode are significantly different | HIGH | HIGH | Step 1 is small and focused specifically on the server; implement + test HTTP responses before touching DB |
| SIGINT/SIGTERM under eio requires `Eio_unix.signal` — naive try/catch will hang or exit non-zero | HIGH | HIGH | Research `Eio_unix` signal API before writing arch_serve.ml; test with explicit `kill -INT` in smoke test |
| `app.js` is the largest single artifact (~800-1200 LOC); D3 incremental updates, layered DAG, hash router all in one file | HIGH | MEDIUM | Build in the slice order defined above; each step adds to a working base |
| ppx_blob: no glob in preprocessor_deps — must list every static file explicitly | MEDIUM | LOW | Add each file to dune stanza as it is created; build will fail clearly if a file is missing |
| BFS bidirectional query: reverse-edge traversal (finding callers) requires querying `calls.callee_id = ?` — needs an index | MEDIUM | MEDIUM | Schema has `idx_calls_callee` — verify it exists before coding BFS; confirmed in architecture-schema.sql |
| D3 incremental sim update (no restart on depth change) requires stable data join by ID — easy to get wrong | MEDIUM | MEDIUM | Key all `.data(...)` calls by `d => d.id`; test by inspecting node positions persist across depth changes |
| Layered DAG layout: simplified longest-path (NOT Sugiyama) — may look poor for large modules | LOW | LOW | Acceptable for v1; UX spec explicitly calls for simplified version; note as known limitation |

## Decisions made

| Point | Decision | Reason |
|---|---|---|
| BFS node-drop at 2000-cap | Drop outermost frontier first (nodes discovered last by BFS are removed) | Preserves the most connected part of the graph around the focal function |
| Layer computation for module view | Client-side longest-path + one barycenter pass — no dagre dep | Dagre requires bundling (violates no-bundler constraint); ~50 lines of JS is sufficient for module-scale graphs |
| DB opened per-request vs. single connection | Single persistent connection opened at startup, shared across requests | SQLite read-only mode supports concurrent reads; per-request open would add latency |
| ppx_blob for SPA delivery vs. reading from filesystem | ppx_blob (compile-time embed) | Ensures binary is self-contained; filesystem approach would require distributing assets alongside the binary |
| Port collision check order | Check DB first, then bind port | Provides a better error if the DB path is wrong (more common mistake than port collision) |

## Assumptions

- `Cohttp_eio.Server.make` and `Server.run` are the correct entry points for an HTTP server; exact API to be confirmed against cohttp-eio documentation before writing Step 1
- `Eio_unix.signal` (or equivalent) is available in the pinned OCaml 5.3 / eio_posix environment for signal handling — to be verified
- D3 v7 UMD build is available for download and vendoring; no licensing issue for local tooling use
- The `idx_calls_callee` index exists in the deployed `architecture-schema.sql` (confirmed in research)
- All functions' `comment_quality_score` is 0–75; NULL values exist and are treated as 0 for filtering
- **`arch_index_db.ml` is `(private_modules ...)` in `lib/arch_index/dune`** — the serve binary cannot import it. The binary uses `Sqlite3` directly, following the same helper pattern (exec_exn, bind_text, etc.) without reusing the private module. No new library needed.
- **SQLite boolean columns** (`exposed`, `has_mli`, `has_pre`, `has_post`, `has_violators`) are stored as `INT 0/1`; every one must be explicitly converted to `\`Bool (v <> 0)` in the JSON serialization, NOT left as `\`Int v`. This is a correctness requirement that is easy to miss in boilerplate.
- **`/api/functions` returns the full matching set** (no offset/limit pagination) — the SPA fetches the full list once on boot for autocomplete. At target scale (few thousand functions) this fits comfortably in memory and a single HTTP response. The SPA handles display pagination via client-side infinite scroll.
- **NULL `kind` in `calls` table treated as MUST** — BFS query uses `kind = 'MUST' OR kind IS NULL`
- **D3 v7 full build** (~300KB) is embedded via ppx_blob for v1 simplicity; this inflates compile time (multi-second OCaml lexer pass on the string literal) and binary size. Acceptable for v1; a custom D3 subset could reduce this to ~80KB in a future iteration.
