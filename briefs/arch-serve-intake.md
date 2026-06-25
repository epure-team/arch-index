# Intake Brief — arch-serve

**Date:** 2026-06-25
**Status:** VALIDATED
**Type:** feature

## Goal

Add an `arch-serve` command to arch-index: a local HTTP server that takes a SQLite DB path and serves a single-page app (SPA) over `localhost` for exploring call graphs and code metrics. The SPA is fully self-contained — all HTML, CSS, and JavaScript assets are embedded in the binary at compile time via `ppx_blob` (already a project dep).

The SPA provides two views:
1. **Neighborhood view** (primary): start from a function search or click; render an interactive N-hop call graph around the selected node using D3.js force-directed layout. Supports reachable-from and reaches queries with visual path highlighting.
2. **Module view** (secondary): select a module and render all its functions as a DAG with edges for intra-module calls.

The function table (sidebar) supports filtering by module, `exposed` flag, and `comment_quality_score` threshold. No write operations, no auth, no hosted infra — `./arch-serve /tmp/self.db` opens a browser tab and serves until Ctrl-C.

## Scope Boundary

Out of scope:
- Write operations on the DB (read-only)
- Authentication or multi-user support
- Hosted / remote deployment
- Live reload on DB file change
- Mobile / responsive layout
- The `comment_db` LSP schema (only the architecture schema is supported — `exposed` column, `caller_id` FK)
- Cross-DB comparison or diff views
- Type graph visualization (types/type_fields/type_constructors tables)

## Relevant Files

| File | Role | Key snippet |
|---|---|---|
| `bin/arch_index_cli/arch_index_cli.ml` | Pattern for CLI entry point | `open Cmdliner; let run ... = Eio_posix.run (fun env -> ...)` |
| `bin/arch_index_cli/dune` | Pattern for binary dune stanza | `(executable (name arch_index_cli) (libraries arch_index eio_posix cmdliner))` |
| `dune-project` | Package deps (cohttp-eio, ppx_blob already listed) | `cohttp-eio`, `ppx_blob`, `eio_posix` |
| `architecture-schema.sql` | DB schema — all tables | `functions(id, module_id, name, exposed, comment_quality_score, ...)` `calls(id, caller_id, callee_id, callee_name, kind, ...)` |
| `arch-index` | Shell wrapper pattern | `HERE=...; BIN=$HERE/bin/arch_index_cli; exec "$BIN" "$@"` |
| `lib/arch_index/` | Library containing DB query logic to reuse | SQLite helpers in `arch_index_db.ml` |

## Architecture Notes

**HTTP layer:** `cohttp-eio` is already a project dep. The server will use it to handle GET requests on `localhost:PORT` (default 7371). Routes:
- `GET /` → serve embedded `index.html`
- `GET /static/<asset>` → serve embedded JS/CSS (d3.min.js, app.js, style.css)
- `GET /api/modules` → `SELECT id, path, lines, has_mli FROM modules ORDER BY path`
- `GET /api/functions?module_id=N&exposed=1&min_score=N` → function list with pagination
- `GET /api/graph/neighborhood?name=X&depth=N` → N-hop subgraph as `{nodes, edges}` JSON
- `GET /api/graph/module?module_id=N` → all functions + intra-module calls as `{nodes, edges}`
- `GET /api/reaches?from=X&to=Y` → `{result: "PATH_EXISTS"|"NO_MUST_PATH", path: [...]}`

**Asset embedding:** Write SPA assets as plain files under `bin/arch_serve/static/` (index.html, app.js, style.css, d3.min.js). Use `ppx_blob` to embed them at compile time. The `app.js` handles routing, D3 rendering, and API calls — no build toolchain needed.

**Binary structure:**
- `bin/arch_serve/arch_serve.ml` — CLI (cmdliner), starts server, opens browser
- `bin/arch_serve/dune` — executable stanza with ppx_blob preprocessor_deps
- `bin/arch_serve/static/` — SPA assets (embedded via ppx_blob)
- `arch-serve` — shell wrapper (same pattern as `arch-index`)

**No new opam deps needed** — cohttp-eio, ppx_blob, eio_posix, cmdliner, sqlite3 are all already declared in `dune-project`.

**Browser open:** print `Serving at http://localhost:7371 — press Ctrl-C to stop` and attempt `xdg-open` / `open` (macOS) silently, ignoring failure.

## Quality Gates

```bash
# Build
opam exec -- dune build

# Tests (existing suite must still pass)
opam exec -- dune test

# Smoke test: server starts and responds
opam exec -- dune build
BIN="./_build/default/bin/arch_serve/arch_serve.exe"
opam exec -- "$BIN" --db /tmp/self.db --port 7372 &
PID=$!
sleep 1
curl -sf http://localhost:7372/ | grep -q "arch-serve" && echo "OK: root serves HTML"
curl -sf http://localhost:7372/api/modules | python3 -m json.tool | grep -q "path" && echo "OK: /api/modules returns JSON"
kill $PID
```

## Open Questions

_(none — all resolved during intake)_
