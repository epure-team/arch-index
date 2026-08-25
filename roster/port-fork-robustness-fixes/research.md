# Research — port-fork-robustness-fixes

_Generated: 2026-08-25_
_Mode: full (4 parallel specialists: locator/haiku, analyzer/sonnet, pattern-finder/haiku, external/sonnet)_
_Online research: enabled_
_Step 1a (graph orientation) skipped: no acked research-orientation code-intel pack in this repo — blind flow used._

## Decisive findings, up front

Three facts overturned the premise the task was scoped on. Each is cited below.

1. **The timeout already returns genuinely partial results.** `runner.ml:254-255` initialises
   `fn_rows_ref`/`call_rows_ref`; `:289-304` fills them as extraction proceeds; `:311-318` prints
   `using partial results (%d functions, %d calls)`; `:324` uses them regardless of whether the
   timeout fired. The scoping inventory had grepped for the identifier `partial_fns` — a name
   chosen in a different codebase — and read its absence as the behaviour's absence.
2. **A per-document server error cannot take the run down.** `Lsp_client.request` never raises:
   `Jsonrpc_client.call` is Result-typed end to end (`jsonrpc_client.ml:123-128`) and the transport
   closure converts `Eio.Time.Timeout`, `End_of_file` and any other `exn` into `Error`
   (`lsp_client.ml:201-220`). All four LSP call sites already continue on `Error`.
3. **A fake LSP server harness already exists here.** `tezt/tests/lsp_readiness.ml:54-105` writes a
   bash stub server, schedules its `$/progress` with `sleep`, runs the real CLI against it with
   `EPURE_ARCH_INDEX_TIMEOUT_S` set, and asserts on marker-file ordering. An earlier
   `grep -rln 'ocamllsp\|run_lsp\|OCAMLLSP' test/ tezt/` returned nothing and was read as "no LSP
   harness" — a stub does not mention `ocamllsp`, and the harness drives the CLI binary, not
   `run_lsp`.

## Question 1: LSP extraction entry points; abstract client interface vs implementation

**Finding:** Public entry points are `Arch_index.run_lsp` / `run_lsp_multi`, delegating to
`Runner.run` / `run_multi`. `Lsp_client.t` is abstract; the only constructor is `start`, which
spawns the server subprocess and performs the initialize/initialized handshake. The interface
exposes `start`, `request`, `notify`, `readiness`, `readiness_to_string`, `shutdown`, and a
`readiness` variant (`Reported | Quiescent | No_progress | Timed_out | Stream_ended`).
`Call_graph_extractor.extract_calls` takes an optional `?clock:_ Eio.Time.clock` — the only
injection point of its kind in the library.

**References:**
- `lib/arch_index/arch_index.mli` — `run_lsp`, `run_lsp_multi`, and the module re-exports
- `lib/arch_index/lsp_client.mli:10` — `type t` (abstract)
- `lib/arch_index/lsp_client.mli` — `start`, `request`, `notify`, `readiness`, `shutdown`
- `lib/arch_index/call_graph_extractor.mli:25` — `?clock:_ Eio.Time.clock` parameter
- `bin/arch_index_cli/arch_index_cli.ml` — the sole CLI caller of `run_lsp`

## Question 2: Public re-exports vs internal modules

**Finding:** 19 modules in `lib/arch_index/`. Seven are re-exported in `arch_index.mli`
(`Lsp_client`, `Ocaml_enricher`, `Comment_parser`, `Language_registry`, `Arch_index_compare`,
`Arch_index_git`, `Arch_index_cfg`). Two are `(private_modules …)` in dune (`arch_index_db`,
`arch_index_cmt`). The remaining ten — including `runner`, `lsp_extractor`,
`call_graph_extractor`, `lsp_types` — are neither private nor re-exported: reachable inside the
library, not part of its published surface. Unit tests under `test/` depend on `arch_index`,
`arch_effects` or `arch_tools`; the tezt suite depends on `arch_tezt` + `tezt` and on the built
`bin/*` executables, i.e. it exercises the tool through its CLI rather than through the library.

**References:**
- `lib/arch_index/arch_index.mli` — the seven `module X = Y` lines
- `lib/arch_index/dune` — `(private_modules arch_index_db arch_index_cmt)`
- `test/dune` — per-test `(libraries …)`
- `tezt/tests/dune` — `(libraries arch_tezt tezt)` plus executable deps on `bin/*`

## Question 3: How the existing suite bootstraps fixtures, and its shared helpers

**Finding:** Two suites. Alcotest under `test/` for pure functions (parsers, cfg, compare) with
custom `testable` formatters and no fixtures. Tezt under `tezt/` for anything that touches a
process or a database — this is the authoritative pattern. Shared helpers live in
`tezt/lib/arch_tezt.ml`: `with_fixture` writes a throwaway project and builds it with
`dune build --root`; `locate ~env_var` resolves a built binary with an env override where a wrong
override is fatal rather than silently falling back; `run_command` / `run_command_split` shell out
with merged or separated streams through temp files; `temp_db` registers the `-wal`/`-shm`
sidecars for cleanup; `Batch` collects all assertion failures instead of stopping at the first;
`free_port` binds port 0; `Db` reads results through the sqlite3 binding so a column typo fails at
`prepare`. Skipping is explicit and asymmetric: `not_exercised` warns locally but **fails** when
`ARCH_TEZT_REQUIRE_SERVERS=1`, so a missing toolchain is tolerated on a workstation and forbidden
in CI.

**References:**
- `tezt/lib/arch_tezt.ml:327-333` — `with_fixture ~name ~files k`, `dune build --root`
- `tezt/lib/arch_tezt.ml:27-49,86` — `find_upwards`, `locate ~env_var`, `arch_index_cli ()`
- `tezt/lib/arch_tezt.ml:202-259` — `run_command`, `run_command_split`
- `tezt/lib/arch_tezt.ml:279-309` — `not_exercised` / `external_failure` and their env guards
- `tezt/lib/arch_tezt.ml:338-341,400-489,575-649` — `temp_db`, `Batch`, `Db`
- `tezt/tests/main.ml:8-78` — every module exposes `register ()`; tags drive selection
- `test/test_parsers.ml:27-48` — the alcotest style for pure functions

## Question 4: Per-document errors vs propagation; what a timed-out run returns

**Finding:** See decisive findings 1 and 2. Every LSP call site treats a failed request as "no
data for this item" and returns `[]`. The only real exception boundary is the pipeline-wide
`Eio.Time.with_timeout_exn`, caught in the runner, which falls back to the accumulated refs. A
timed-out run still returns `Ok ()`: the timeout is never surfaced to the caller as an error, it
only produces a smaller — possibly empty — database.

**References:**
- `lib/arch_index/lsp_extractor.ml:67-68,174-177` — `| Error _ -> []`
- `lib/arch_index/call_graph_extractor.ml:86-90,156-159` — same
- `lib/jsonrpc_client/jsonrpc_client.ml:123-128` — Result-typed `call`
- `lib/arch_index/lsp_client.ml:201-220` — every exception converted to `Error`
- `lib/arch_index/runner.ml:254-255,260,311-318,324,362` — refs, timeout wrapper, fallback, `Ok ()`

## Question 5: Path→URI conversion; language→file-set selection; project_dir provenance

**Finding:** URIs are built by bare string concatenation at six sites, and stripped back by a
`strip_file_uri` duplicated in two modules. File selection dispatches on the language name with a
TypeScript-shaped fallback for every unrecognised value. `project_dir` originates as a required
Cmdliner `dir` argument and is **never normalised**: Cmdliner's `dir` converter only checks
existence and returns the string exactly as typed, so whether every URI in the run is absolute or
relative is decided entirely by what the invoker passed to `--project`.

**References:**
- `lib/arch_index/lsp_client.ml:431` — `"file://" ^ project_dir` as the handshake `rootUri`
- `lib/arch_index/lsp_extractor.ml:221,253,279,306` — `"file://" ^ abs` / `^ path`
- `lib/arch_index/call_graph_extractor.ml:75` — `"file://" ^ abs_path`
- `lib/arch_index/lsp_extractor.ml:30-33,125-129` and `call_graph_extractor.ml:19-22` — duplicated strip
- `lib/arch_index/lsp_extractor.ml:315-321` — `scan_source_files`, `| _ -> scan_ts_files`
- `lib/arch_index/lsp_extractor.ml:232-259,265-284,290-311` — the three scanners and their exclusions
- `lib/arch_index/language_registry.ml:112-125` and `runner.ml:230-234` — detection, and `None` → hardcoded `"ocaml"`
- `bin/arch_index_cli/arch_index_cli.ml:54-56` — `Arg.(required & opt (some dir) None …)`, no default
- cmdliner 1.3.0 `cmdliner_base.ml:230-234` — `dir` returns the literal string, no realpath

## Question 6: Eio timeouts/switches/cancellation; clock injection in tests

**Finding:** All timing reads the real clock from `Eio.Stdenv.clock env`. `Eio.Switch` is used for
subprocess and pipe lifetime, not for cancellation control flow beyond the timeout wrapper. There
is **no** fake-time or clock-substitution anywhere: `eio_mock`, `Eio_mock`, `mock_clock` and
`fake.*clock` have no hits in `lib/`, `bin/`, `test/`, `tezt/`, `poc/`. The one `?clock` parameter
that could accept a substitute is always given the real clock at its sole call site. Timing is
instead controlled from outside the process — a bash stub server with `sleep`, and the
`EPURE_ARCH_INDEX_TIMEOUT_S` env var — which is what makes the timeout path reachable from a test
without touching the code.

**References:**
- `lib/arch_index/runner.ml:213-218` — `get_timeout_s ()`, `EPURE_ARCH_INDEX_TIMEOUT_S`, default 30.0
- `lib/arch_index/runner.ml:260,299` — pipeline timeout; real clock passed to `extract_calls`
- `lib/arch_index/lsp_client.ml:107,120-122,184,255-355` — clock, switch cleanup, per-request timeout, readiness deadlines
- `lib/arch_index/call_graph_extractor.ml:311-317` — bounded retry `sleep`, `attempt 20`
- `tezt/tests/lsp_readiness.ml:54-105,110-119,128,144-159` — bash stub server, `sleep`-scheduled phases, env-var timeout, ordering assertions

## Question 7: Configuration surface and its readers

**Finding:** There is no central config module; each module reads its own environment variable
with an inline default. Malformed values fall back silently. Tool discovery walks `PATH` directly
rather than spawning a subprocess.

| Knob | Default | Read at |
|---|---|---|
| `EPURE_ARCH_INDEX_TIMEOUT_S` | 30.0 | `runner.ml:213-218`, used `:226` |
| `ARCH_DB_PATH` | `docs/architecture.db` | `arch_index_db.ml:17-25` |
| `ARCH_SCHEMA_PATH` | `docs/architecture-schema.sql` | `arch_index_db.ml:17-25` |
| `ARCH_LSP_TRACE` | unset | `lsp_client.ml:292` |
| `PATH` | — | `language_registry.ml:21-30`, `ts_enricher.ml:23-28` |
| `ARCH_QUERY`, `ARCH_INDEX_CLI`, … | upward search | `tezt/lib/arch_tezt.ml:40-86` |

`Language_registry.default ()` hardcodes five servers and degrades explicitly: TypeScript falls
back to `npx typescript-language-server` when the direct binary is absent, and injects a
project-local `tsserver.js` path as init options when one exists.

**References:** as tabulated, plus `language_registry.ml:32-108`, `:58-68`

## Question 8: [ecosystem] Testing LSP clients without a real server

**Finding:** No single dominant approach; five patterns coexist, and most named "LSP test"
tooling actually tests *servers* by driving them as a client. The patterns: (a) in-memory
transport fed by the test, (b) an in-process or subprocess fake server implementing a subset,
(c) recorded-transcript replay, (d) a real server behind a CI skip-guard, (e) dependency-injecting
the request function as a swappable service.

What bears on this repo: the TypeScript reference client — the most mature LSP client in
existence — tests itself with **(b), a scripted fake server launched as a real subprocess over
stdio**, which is the pattern `lsp_readiness.ml` already uses here. And the in-memory-pipe
alternative (a) carries a maintainer-acknowledged flakiness cost: LSP4J's own suite has an open
issue that `PipedInputStream`/`PipedOutputStream` misbehave under concurrent writes.

On timeouts, the specification is explicit that a request must always be answered and must not be
left hanging, and equally explicit — by silence — about client-side timeouts: it defines none.
Every harness therefore invents its own mechanism (`lsp-test`'s `Timeout`/`withTimeout`, Tower's
mock/timeout middleware, ad hoc session configs). Controlling the timeout from outside the
process, as this repo does with an env var, is a legitimate member of that family rather than a
workaround.

**References:**
- https://github.com/RustDT/MockLS — a fake server purpose-built for testing LSP *clients* (rare)
- https://github.com/microsoft/vscode-languageserver-node/blob/main/client-node-tests/src/servers/testServer.ts — scripted fake server as a subprocess (pattern b/d)
- https://github.com/microsoft/vscode-languageserver-node/blob/main/protocol/src/node/test/connection.test.ts — paired in-memory streams for the jsonrpc layer (pattern a)
- https://github.com/haskell/lsp/tree/master/lsp-test — subprocess-driven session framework; `SessionException`/`Timeout`, `withTimeout`
- https://github.com/haskell/lsp/blob/master/lsp-test/src/Language/LSP/Test/Replay.hs — recorded-transcript replay (pattern c)
- https://github.com/lukel97/lsp-test/issues/8 — maintainer issue: a test hangs indefinitely without an explicit timeout combinator
- https://github.com/eclipse-lsp4j/lsp4j/issues/510 — maintainer issue: piped-stream transport unstable under concurrent writes
- https://pygls.readthedocs.io/en/v0.12/pages/testing.html — client and server in threads over an `os.pipe()` pair
- https://pkg.go.dev/golang.org/x/tools/internal/jsonrpc2/servertest — `net.Pipe`-backed in-memory listener
- https://docs.rs/async-lsp/latest/async_lsp/trait.LspService.html and https://docs.rs/tower-test/latest/tower_test/mock/spawn/ — pattern (e); **flagged by the researcher as plausible-by-construction, no worked LSP example found**
- https://github.com/ocaml/ocaml-lsp/discussions/409 — documented *absence* of a named harness in the OCaml ecosystem
- https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/ — a request must always be answered; client-side timeout is implementation-defined
