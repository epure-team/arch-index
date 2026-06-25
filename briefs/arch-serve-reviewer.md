# Reviewer Brief — arch-serve

**Date:** 2026-06-25
**Status:** VALIDATED
**Spec:** specs/arch-serve.md

## What Was Implemented

A new `arch-serve` binary and SPA:
- `bin/arch_serve/arch_serve.ml` — Cmdliner CLI + cohttp-eio HTTP server + 5 API endpoints + ppx_blob static asset serving
- `bin/arch_serve/dune` — executable stanza with ppx_blob preprocessor_deps
- `bin/arch_serve/static/{index.html, app.js, style.css, d3.min.js}` — SPA assets
- `arch-serve` — shell wrapper

## Files to Audit First (highest risk)

1. `bin/arch_serve/arch_serve.ml` — everything: server setup, signal handling, BFS, boolean serialization
2. `bin/arch_serve/static/app.js` — D3 incremental updates, layered DAG, path highlighting
3. `bin/arch_serve/dune` — preprocessor_deps completeness

## Risks to Verify

### R1 — Boolean serialization (CRITICAL)
Every SQLite boolean column (`exposed`, `has_mli`, `has_pre`, `has_post`, `has_violators`) must serialize as JSON `true`/`false`, NOT `0`/`1`. Check every `Yojson.Safe.t` construction for any `\`Int` where a `\`Bool` should appear. One miss violates FR-013.

### R2 — SIGINT/SIGTERM clean shutdown (CRITICAL)
Verify the server exits with code 0 and zero stderr output when killed. The eio signal handler must be wired to the top-level switch. Test: `kill -INT <pid>; wait <pid>; echo $?` → should print `0`.

### R3 — BFS bidirectionality (HIGH)
At each BFS hop, both `caller_id = current` AND `callee_id = current` must be queried. Verify no node is double-counted. The two queries must union into a single deduplication step before adding to the frontier.

### R4 — DB validated before port bind (HIGH)
Verify startup order: DB open/validate happens BEFORE `Eio.Net.listen`. If port is bound before DB validation, a missing DB file causes a port leak.

### R5 — D3 incremental update — no sim restart (HIGH)
Verify depth change in the SPA does NOT call `d3.forceSimulation()` again. It must call `sim.nodes(newNodes).force('link').links(newEdges).alpha(0.3).restart()` with stable data joins keyed by `d.id`. Look for any `const sim = d3.forceSimulation(...)` call inside `renderNeighborhood`.

### R6 — `kind IS NULL OR kind = 'MUST'` in BFS (MEDIUM)
The `/api/reaches` BFS and the neighborhood BFS must both treat NULL kind as MUST. Check SQL: `WHERE kind = 'MUST' OR kind IS NULL` — NOT just `WHERE kind = 'MUST'`.

### R7 — ppx_blob file list completeness (MEDIUM)
All 4 files (index.html, app.js, style.css, d3.min.js) must appear in `(preprocessor_deps ...)` in `bin/arch_serve/dune`. A missing entry causes a stale-cache build that silently serves old content.

### R8 — NO_MUST_PATH copy (MEDIUM)
Verify the "no path" message in the SPA does NOT contain the phrase "no path exists" or any equivalent absolute claim. It must say "cannot definitely reach ... through guaranteed calls." (spec FR-045).

### R9 — URL encoding for function names (MEDIUM)
Verify `encodeURIComponent()` is applied to all function names in API URLs (e.g., `#/n/${encodeURIComponent(name)}`). OCaml operators like `(>>=)` contain URL-unsafe characters.

## Expected Behaviors to Confirm

- `GET /` → HTTP 200, `<title>` contains `arch-serve`
- `GET /api/modules` → JSON array, `has_mli` is boolean
- `GET /api/functions?exposed=1&min_score=30` → only matching functions, all booleans correct
- `GET /api/graph/neighborhood?name=X&depth=2` → `{nodes, edges, truncated}`, bidirectional BFS
- `GET /api/reaches?from=A&to=B` (MUST path exists) → `{result:"PATH_EXISTS", path:[...int IDs...]}`
- `GET /api/reaches?from=A&to=B` (no MUST path) → `{result:"NO_MUST_PATH", path:[]}`
- `GET /api/reaches?from=nonexistent&to=Y` → HTTP 404 JSON `{"error":"unknown function: nonexistent"}`
- Missing DB file → exit 1, stderr contains "cannot open database" and the file path
- SIGINT → exit 0, no stderr
- Module selected in SPA → layered DAG renders with back-edges as curved arcs
- Path query with out-of-neighborhood nodes → dedicated path chain view with `← back` chip
