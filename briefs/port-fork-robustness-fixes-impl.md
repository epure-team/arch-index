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

**Duplicated functions collapsed.** `strip_file_uri` existed in **three** places — two named
copies plus a fourth inline body in `read_file_text` that round 1 missed while the comment above
it claimed the dedup was complete — and `relative_path` in two, all byte-identical, plus the URI
construction inline at six sites. All now delegate; `grep -c 'String.sub uri 0 7 = "file://"'`
across `lib/arch_index/*.ml` returns 0 outside the definition. Deduplication is in scope rather than opportunistic: absolutising construction without
absolutising `relative_path` would leave the two halves disagreeing, and the task named
`relative_path` explicitly.

**Diagnostics are unconditional, not gated on `--verbose`.** A failed LSP request is rare and
load-bearing: it is the only thing that distinguishes an empty index from a clean repository. The
`documentSymbol` line is per file, deliberately — a server refusing one document is a different
fact from one refusing all of them, and only the count of those lines separates them. Cost — measured twice, wrong twice before this. Round 1 claimed "one line per file". Round 2
"corrected" the figure to ~40x in its changelog and left both sentences that state it untouched.
Review then measured the truth: the diagnostic sat inside the warm-up retry loop (`attempt 20`), so
a refusing server re-emitted the identical line up to **21 times per function** — 315 lines on a
15-function fixture, ~9000 on this repo. That destroyed the very rationale for per-item
granularity, which is that the *count* distinguishes "one document refused" from "all of them".

Round 3 bounds it: `report_once` memoises `(method, path)` in a table created per run in
`extract_calls` and threaded down — not a module-level table, which would leak between runs in a
process indexing more than one project. Measured after the bound, on a 3-file / 6-function fixture
whose stub refuses every `prepareCallHierarchy`: **3 lines**, one per file. Round 1's claim is true
now; it was false when made.

## Quality Gates

Round 1 of this table listed the gates I knew about and called them all. Review found a CI gate
I had never looked for, and it was red. The list is now derived from `.github/workflows/ci.yml`
rather than from memory.

- [x] Build: `dune build` → **exit 0**
- [x] Tests: `dune test` → **exit 0** (70 tezt + the alcotest targets; 2 new files: `test_lsp_uri` 12 cases, `lsp_error_diagnostics` 1 case with 6 assertions)
- [x] Unit target alone: `dune exec test/test_lsp_uri.exe` → `Test Successful … 12 tests run.`
- [x] **Self-index golden** (`.github/workflows/ci.yml:74-87`): `arch_callgraph_ocaml --build-dir=_build/default/lib/arch_index` then `diff test/fixtures/self-index-stats.txt` → **exit 0** after regenerating the golden per `docs/adr/001-self-index-golden.md`. It was **exit 1** in round 1 (`functions: 426` golden vs `431` actual) and `dune build`/`dune test` were both 0, so this was the only gate that saw it. `calls` also moved 3391 → 3382, consistent with the deduplication removing duplicated bodies.
- [x] `arch-rules /tmp/self.db arch-rules.txt --on-vacuous fail` → **exit 0** (`4 rule(s), 0 failing`)
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
| N1 `path_of_file_uri` strips unconditionally | KILLED (review) |
| N2 `normalise_absolute` drops the leading `/` | KILLED (review) |
| N3b `"typescript"` arm scans `.nope` | KILLED by the polyglot index test (review) |
| **N4 `relative_path` `>` → `>=`** | **SURVIVED round 1** → KILLED (round 2) |
| **N5 `relative_path` drops the `'/'` boundary check** | **SURVIVED round 1** → KILLED (round 2) |
| N6 `rootUri` back to raw concatenation | not expressible in round 1 (byte-identical) → **KILLED** (round 2) |
| N7 `".."` no longer resolved | KILLED (round 2) |
| A/B/C/D/E fold: pop-above-root, `List.rev` dropped, `..` not popping, empty segments unfiltered, leading `/` dropped | KILLED (review) |
| G stub stops recording the handshake | KILLED (review) — proves the rootUri assertions cannot pass vacuously |
| **F-5 `path_of_file_uri` `>` → `>=`** | **SURVIVED round 2** → KILLED (round 3) |
| F-2m `abs_path` no longer normalised | KILLED (round 3) |
| F-2r the filesystem-root case removed | KILLED (round 3) |

**M4 survived the first version of the test, and that is the finding.** The test asserted only that
the sentinel appeared *somewhere* in the output. The stub refuses every request after the
handshake, so `documentSymbol` surfaced the same sentinel and the test could not tell the two sites
apart — it passed for the wrong reason. Tightened to one assertion per site (the method name *and*
the server's own message), M4 dies. Without the mutation pass this would have shipped as "diagnostics
covered".

## Round 2 — what review found and what changed

Two blocking findings, both mine, both of the same shape: a claim about coverage that the coverage
did not support.

1. **A CI gate I never looked for was red.** The self-index golden. My gate table listed what I
   knew and called it complete.
2. **Two mutants survived `relative_path`'s guard.** N5 (dropping the `'/'` boundary check) is the
   serious one: `project_dir=/home/me/proj` with `abs_path=/home/me/project-docs/x.ml` yields
   `ct-docs/x.ml` — a silently corrupted path written to the database, reachable whenever a server
   returns a symbol from a sibling directory sharing the root's prefix. My existing test used
   `/elsewhere/x.ml`, which shares no prefix, so it exercised only one conjunct of the guard.

Also fixed this round, from review's MEDIUM/LOW findings:

- the three helpers had been inserted **inside the copyright banner**, splitting it; moved below
  the banner and the module docstring as a named section
- the **fourth inline copy** of the strip in `read_file_text`, while the comment above it and the
  `.mli` both asserted the dedup was complete
- **`..` was not resolved**, so `--project ../sibling` kept the exact defect the helper exists to
  remove — the filter dropped `"."` and left `".."`. Now folded, with a test (N7)
- `relative_path` normalised only one side. **Round 2 claimed to have fixed this and did not** —
  review diffed the function and found it byte-identical to round 1. Cause: a scripted edit whose
  anchor no longer matched, and `str.replace` silently does nothing when the pattern is absent.
  Every edit in round 3 asserts its anchor, and one of those assertions fired. Fixed for real now,
  and the test review asked for found a **fourth** case the fix still missed: at the filesystem
  root, `/` *is* the separator, so demanding one after it meant a project rooted at `/`
  relativised nothing — contradicting the `.mli`'s own `{post}`. Handled explicitly
- one of the nine unit cases asserted the **same input twice** under a label claiming two-slash
  support the code does not have; replaced with an honest single assertion
- the diagnostic-volume figure, understated ~40×

Left as declared judgement calls: the unencoded URIs that `test_round_trip` pins (noted in the
test — the coupling is intentional), and the `Lsp_client` placement, which review approved.

Filed rather than folded in: **#23**, the runner's own failure diagnostics are all `--verbose`
gated, so a missing LSP binary writes an empty database and exits 0 in silence — a strictly larger
instance of this branch's own defect class, but outside its scope.

## Points of attention for review

- **The `Lsp_client` placement** is the one real design call. If a reviewer prefers a dedicated
  module, the change is mechanical — but it costs a public module for testability alone.
- **`rootUri` now has real coverage, and round 1's claim about it was false.** Round 1 said it was
  "covered transitively by `lsp_error_diagnostics` completing the handshake". Review proved that to
  be *zero* coverage, not merely weak: the stub answers `initialize` without reading `rootUri`, no
  assertion inspected extracted content, and the test passed an absolute `Temp.dir` as `--project`
  — so reverting the fix produced **byte-identical bytes on the wire**. The mutation could not
  change anything observable. Fixed: the stub now records the `initialize` body it received, the
  test drives the CLI with a **relative** `--project`, and two assertions check the wire form.
  Mutant N6 (`rootUri` back to raw concatenation) now **dies**.
- **Only the new unreachable arm is uncovered.** Round 1 said "the explicit language arm is not
  covered by a test"; that was imprecise. The `"typescript"` arm **is** covered — review's mutant
  making it scan `.nope` died on the polyglot index test. What is uncovered is the `other` arm,
  which is the unreachable one (verified independently by review: `extract_symbols` is called only
  at `runner.ml:290` inside `match cfg_opt with Some cfg`, `lookup` errors outside its five
  entries, `run_multi` delegates to `run`, and `Lsp_extractor` is not re-exported). Declared rather
  than faked.
- **Diagnostic volume**: bounded to one line per `(method, path)` per run, measured at 3 lines on
  a 3-file fixture. Before round 3 it was 21 lines per function. Argued above.

## Identified out-of-scope

- `arch-body-compare` proves syntactic duplication and would have flagged the six duplicated
  functions this change removes — but nothing invokes it, and it requires a `modules` table the LSP
  producer does not write. Filed as **arch-index#22**; not fixed here.
- The `?clock` parameter on `Call_graph_extractor.extract_calls` is the library's only injection
  point and is always given the real clock. Not touched.
- 11 pre-existing untracked paths (briefs, `tools/`, `docs/plans/`) belong to other tasks and were
  left alone; the round's own work is committed, so `git status` is not empty by design rather than
  by omission.
