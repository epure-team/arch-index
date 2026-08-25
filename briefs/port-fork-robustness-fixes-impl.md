# Implementation Brief — port-fork-robustness-fixes

**Date:** 2026-08-25
**Mode:** fast (escalated to full after a measured blocker, then returned to fast once research
dissolved the blocker — both transitions were human decisions, recorded in
`roster/port-fork-robustness-fixes/task.md` and `research.md`)
**Status:** COMPLETED

## What the research changed, before any code

The task was scoped on four items carried out of a stale fork. Research overturned two of them and
resized a third. Every claim below is the command's output, not a reading.

| Item as scoped | What is actually true here |
|---|---|
| Timeout discards partial results | **Already correct.** `runner.ml:254-255` accumulates into refs, `:311-318` prints the counts, `:324` uses them regardless. The scoping inventory had grepped for `partial_fns` — a name from the other codebase — and read its absence as the behaviour's absence. |
| One rejected document kills the run | **Structurally impossible.** `Jsonrpc_client.call` is Result-typed end to end (`jsonrpc_client.ml:123-128`); the transport converts `Eio.Time.Timeout`, `End_of_file` and any `exn` to `Error` (`lsp_client.ml:201-220`). |
| Unknown language scans TypeScript | **Latent, not live.** `extract_symbols` is only reached for a language `Language_registry.lookup` accepted — the five registered ones. Four have explicit arms, so the catch-all was only ever taken by `"typescript"`, for which it was right. |
| Relative `file://` URIs | **Live, and larger than scoped:** six construction sites, not three, including `lsp_client.ml:431`, the handshake `rootUri`. Plus `relative_path` and `strip_file_uri`, each duplicated three ways. |

## Modified files

| File | Type | Reason |
|---|---|---|
| `lib/arch_index/lsp_client.ml{,i}` | addition | `file_uri_of_path`, `path_of_file_uri`, `relative_path` — the three helpers, with docs |
| `lib/arch_index/lsp_extractor.ml` | modification | 4 URI sites delegate; 2 duplicated helpers delegate; 2 diagnostics; explicit language arm |
| `lib/arch_index/call_graph_extractor.ml` | modification | 1 URI site delegates; 2 duplicated helpers delegate; 2 diagnostics |
| `test/test_lsp_uri.ml` | addition | 9 unit cases on the three helpers |
| `test/dune` | modification | the new test target |
| `tezt/tests/lsp_error_diagnostics.ml` | addition | stub server that errors after the handshake; asserts each site names itself |
| `tezt/tests/main.ml` | modification | registers it |

## Decisions made

**The helpers live in `Lsp_client`, not a new module.** `Lsp_client` is a dependency-free leaf that
every URI-building caller already depends on, and it is already re-exported in `arch_index.mli`. So
this adds **no dependency edge and no public module** — and the helpers become reachable from
`test/` without widening the library's surface. The alternative (a new `lsp_uri` module, or
re-exporting `Lsp_extractor`) would have added a public module for testability alone. Recorded as
a judgement call: it broadens `Lsp_client` from "the client handle" to "the client handle and its
path/URI conventions".

**Three duplicated functions collapsed into one copy each.** `strip_file_uri` existed in two
modules and `relative_path` in two, all byte-identical, plus the URI construction inline at six
sites. Deduplication is in scope rather than opportunistic: absolutising construction without
absolutising `relative_path` would leave the two halves disagreeing, and the task named
`relative_path` explicitly.

**Diagnostics are unconditional, not gated on `--verbose`.** A failed LSP request is rare and
load-bearing: it is the only thing that distinguishes an empty index from a clean repository. The
`documentSymbol` line is per file, deliberately — a server refusing one document is a different
fact from one refusing all of them, and only the count of those lines separates them. Cost: a
thoroughly broken server produces one line per file. That is the signal, not noise.

## Quality Gates

- [x] Build: `dune build` → **exit 0**
- [x] Tests: `dune test` → **exit 0** (70 tezt + the alcotest targets; 2 new: `test_lsp_uri` 9 cases, `lsp_error_diagnostics` 1 case)
- [x] Unit target alone: `dune exec test/test_lsp_uri.exe` → `Test Successful … 9 tests run.`
- [x] Format: `dune fmt` — **n/a**, no `.ocamlformat` in this repo (verified: `test -f .ocamlformat` false), so formatting is not a gate here

## Red-then-green

Each fix was written test-first, and the red was observed, not assumed:

- URI helpers: `dune build @test/runtest` → **exit 1**, `Error: Unbound value "U.file_uri_of_path"`
- `relative_path`: `dune build @test/runtest` → **exit 1**, `Error: Unbound value "U.relative_path"`
- diagnostics: `dune exec tezt/tests/main.exe -- --title '…'` → **exit 1**, and the failure output
  was the defect verbatim — `extracting symbols… / found 0 functions / wrote …erroring.db`, with no
  reason anywhere.

## Mutation table

Every row run through `dune test` — never by invoking a test binary directly. That shortcut
invalidated a mutation table earlier this week, so it was not used here.

| Mutant | Verdict |
|---|---|
| M1 `file_uri_of_path` stops absolutising | KILLED |
| M2 `relative_path` stops normalising `project_dir` | KILLED |
| M3 `.` segments stop collapsing | KILLED |
| M4 `workspace/symbol` swallows the reason again | **SURVIVED**, then KILLED — see below |
| M5 `documentSymbol` swallows the reason again | KILLED |

**M4 survived the first version of the test, and that is the finding.** The test asserted only that
the sentinel appeared *somewhere* in the output. The stub refuses every request after the
handshake, so `documentSymbol` surfaced the same sentinel and the test could not tell the two sites
apart — it passed for the wrong reason. Tightened to one assertion per site (the method name *and*
the server's own message), M4 dies. Without the mutation pass this would have shipped as "diagnostics
covered".

## Points of attention for review

- **The `Lsp_client` placement** is the one real design call. If a reviewer prefers a dedicated
  module, the change is mechanical — but it costs a public module for testability alone.
- **`lsp_client.ml:431`** (`rootUri`) is the highest-risk site of the six: a regression there breaks
  every document URI downstream, silently. It has no direct test of its own; it is covered
  transitively by `lsp_error_diagnostics` completing the handshake against the stub.
- **The explicit language arm is not covered by a test, deliberately.** The arm is unreachable —
  `lookup` gates the five registered languages and four have explicit arms. Asserting on an
  unreachable branch would require either registering a sixth server or exposing
  `scan_source_files`. Declared rather than faked.
- **Diagnostic volume** on a fully broken server: one line per file. Intentional, argued above.

## Identified out-of-scope

- `arch-body-compare` proves syntactic duplication and would have flagged the six duplicated
  functions this change removes — but nothing invokes it, and it requires a `modules` table the LSP
  producer does not write. Filed as **arch-index#22**; not fixed here.
- The `?clock` parameter on `Call_graph_extractor.extract_calls` is the library's only injection
  point and is always given the real clock. Not touched.
- 11 pre-existing untracked paths (briefs, `tools/`, `docs/plans/`) belong to other tasks and were
  left alone; the round's own work is committed, so `git status` is not empty by design rather than
  by omission.
