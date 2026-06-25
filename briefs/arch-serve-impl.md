# Implementation Brief — arch-serve

**Date:** 2026-06-25
**Mode:** full
**Status:** COMPLETED

## Modified files

| File | Type of change | Reason |
|---|---|---|
| `bin/arch_serve/arch_serve.ml` | addition | New server binary |
| `bin/arch_serve/dune` | addition | Dune build config with ppx_blob |
| `bin/arch_serve/static/index.html` | addition | SPA shell |
| `bin/arch_serve/static/app.js` | addition | Full SPA (search, graph, table, reaches) |
| `bin/arch_serve/static/style.css` | addition | SPA stylesheet |
| `bin/arch_serve/static/d3.min.js` | addition | Vendored D3 v7 |

## Decisions made

**Browser opening dropped.** `Eio.Process.spawn` in any fiber — including daemon fibers and fibers on inner switches — prevents `Eio.Promise.resolve` (called from a SIGINT signal handler) from waking `Server.run`. Confirmed via a series of minimal reproducer tests (test_stop1–8): any `Eio.Process.spawn` call in the same `Eio_posix.run` domain causes the stop promise to never wake the scheduler. Root cause: `Eio_unix.Process.sigchld` condition interacts with the eio scheduler state in a way that prevents the SIGINT stop-promise from firing. Per the spec ("attempt silently — failing silently is valid") and user guidance about eio/Unix mixing, the opener is simply omitted. The URL is printed to stdout instead.

**Schema target.** arch_serve queries the `architecture-schema.sql` format (with `modules` table, `module_id` FK, integer `caller_id`/`callee_id`). This matches the spec FRs and the architecture-schema.sql file in the repo root.

**Stop signal.** SIGINT and SIGTERM both resolve the same `Eio.Promise.t`. Signal handler calls `Promise.resolve` with a try/ignore for the already-resolved case.

**DB opened read-only.** `Sqlite3.db_open ~mode:\`READONLY` ensures the server cannot accidentally modify the index.

**BFS depth cap.** Neighborhood BFS caps at 2000 visited nodes (`truncated: true` flag in response).

**MUST-only reachability.** `/api/reaches` follows only `kind = 'MUST'` or NULL (legacy) edges, per the edge-kind contract.

## Quality Gates

- [x] Build: `opam exec -- dune build bin/arch_serve/arch_serve.exe` ✅
- [x] CHECK-1: server starts ✅
- [x] CHECK-2: GET / returns HTML ✅
- [x] CHECK-3: /api/functions returns JSON array ✅
- [x] CHECK-4: /api/modules has_mli as boolean ✅
- [x] CHECK-5: /api/graph/neighborhood returns nodes+edges ✅
- [x] CHECK-6: /api/reaches unknown function returns error JSON ✅
- [x] CHECK-6b: /api/reaches MUST path found ✅
- [x] CHECK-7: unknown path → 404 ✅
- [x] CHECK-8: SIGINT terminates server ✅

## Points of attention for review

- **Eio.Process.spawn is absent** — the SIGINT investigation showed it breaks the scheduler's stop-promise wakeup; any future browser-open attempt must use a self-pipe or pre-fork approach outside Eio supervision.
- **Schema assumption** — `arch_serve.ml` queries `modules`, `functions` with `module_id`/`exposed`/`comment_quality_score`, and `calls` with `caller_id`/`callee_id`/`kind`. A DB without these columns (e.g. older miaou.db) produces empty responses from `query_rows` (SQLite prepare fails, exception swallowed by catch-all). Consider surfacing this as a startup validation error.
- **BFS path concat** — `reaches_bfs` uses `path @ [callee_id]` which is O(n²). Fine for the expected depth (<20 hops) but worth noting.
- **`query_rows` swallows all exceptions** — including SQLite prepare errors from schema mismatches. The `(try ... with _ -> ())` in the while loop is intentional for robustness, but hiding prepare errors is a diagnostic blind spot.

## Identified out-of-scope

- ppx_forbid integration (suggested by user for future hardening — would catch any reintroduction of `Sys.command`/`Unix.sleep` etc.)
- Browser open (dropped; see Decisions)
- Startup schema validation (would improve DX for mismatched DBs)
