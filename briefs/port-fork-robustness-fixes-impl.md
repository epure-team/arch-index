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
- [x] Tests: `dune test` → **exit 0** (70 tezt + the alcotest targets; 3 new files: `test_lsp_uri` 14 cases, `lsp_error_diagnostics` 1 case with 6 assertions, `lsp_call_diagnostics` 1 case with 7 assertions — 71 tezt tests, up from 70)
- [x] Unit target alone: `dune exec test/test_lsp_uri.exe` → `Test Successful … 14 tests run.`
- [x] **Self-index golden** (`.github/workflows/ci.yml:74-87`): `arch_callgraph_ocaml --build-dir=_build/default/lib/arch_index` then `diff test/fixtures/self-index-stats.txt` → **exit 0** after regenerating the golden per `docs/adr/001-self-index-golden.md`. It was **exit 1** in round 1 (`functions: 426` golden vs `431` actual) and `dune build`/`dune test` were both 0, so this was the only gate that saw it. The golden has moved three times across rounds and each delta was accounted for by diffing the edge multiset, not inferred: round 1 `426 → 431` functions / `3391 → 3382` calls (dedup collapsing duplicated bodies), round 3 `431 → 432` / `3382 → 3391` (`report_once` — its own node plus 8 edges; the return to main's original 3391 is arithmetic coincidence, verified as such by review), round 4 `432 → 432` / `3391 → 3393`, exactly `outgoing_calls -> relative_path` and `outgoing_calls -> strip_file_uri` from the R3-2 fix and nothing else (`comm` on the normalised edge sets, empty removed-side).
- [x] `arch-rules /tmp/self.db arch-rules.txt --on-vacuous fail` → **exit 0**. Recorded at the time as `4 rule(s), 0 failing`; CORRECTED (PR #70) — that line was the tool's own summary collapsing a three-state verdict into one number, and the run was **1 proved / 0 violations / 3 UNKNOWN**. Only one of the four invariants was established; the other three abstain because their cone escapes through a ⊤ edge. The exit code was and is 0 — UNKNOWN is fail-open — so the correct claim is *the gate is unchanged*, not *the gate passes*. See specs/qualified-unit-resolution.md §10.5.
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
| **R3-1a `report_once` memo never records** | **SURVIVED round 3** → KILLED (round 4) — 3 lines become 126 |
| **R3-1b `report_once` `eprintf` removed** | **SURVIVED round 3** → KILLED (round 4) — the founding defect, restored in one line |
| **R3-2/M-c memo key drops the method** | **SURVIVED round 3** (unobservable then) → KILLED (round 4) |
| M-d memo table module-level instead of per-run | **SURVIVES** — see below; not closable, and the reason matters |

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

## Round 4 — what review found and what changed

One HIGH, and it is the round's own headline change: **`report_once` shipped with zero test
coverage.** The cause was structural, not an oversight of diligence: `lsp_error_diagnostics`'s stub
refuses *every* request after the handshake, so `documentSymbol` fails, zero functions are
extracted, and `extract_calls` is reached with `fn_rows = []`. The `prepareCallHierarchy` call site
was never executed by any test in the suite. Review demonstrated it with two one-line mutants that
both passed a green `dune test`, the second of which — deleting the `eprintf` — restores an empty
call graph with no stated reason anywhere, which is precisely the defect this branch exists to
remove.

Review offered the escape hatch ("ship it, file the stub as follow-up, that is defensible"). It was
declined. A guard whose founding defect a one-line mutant reinstates under a green suite is an inert
guard, and this branch is about not shipping those.

**The fix — `tezt/tests/lsp_call_diagnostics.ml`.** A second stub that answers the handshake,
answers `workspace/symbol` with nothing and `documentSymbol` with two functions per file, then
*splits* the call-hierarchy surface: the function at line 1 gets a prepare result whose
`outgoingCalls` is refused, the function at line 5 has its prepare refused outright. Both refusals
therefore land on the **same file**, which is the only arrangement under which a memo keyed on the
path alone is observably wrong — review had flagged M-c as unobservable, and this is what makes it
observable. Assertions are **counts, not containments**: `contains` cannot tell 3 from 126, and a
containment-only assertion is exactly what let M4 survive in round 1.

The first version of this test was red for a real reason: the stub matched
`callHierarchy/prepareCallHierarchy` while the client sends `textDocument/prepareCallHierarchy`
(`call_graph_extractor.ml:103`), so the request fell through to the default arm and no diagnostic
fired. Recorded because it is the same class as round 2's silent `str.replace`: a step that appears
to run and does not. Here the assertion caught it.

**R3-2 — the `outgoingCalls` site was keyed on `item.name`, a function name.** Two consequences,
both real: the line read "failed for alpha" where the reader expects a file, and the bound was one
line per *function* — 432 on this repo, not the 3 the brief claimed. Now keyed on
`relative_path ~project_dir (strip_file_uri item.uri)`, so "one line per (method, file)" is true at
both sites rather than at one. This is the +2 in the golden.

**M-d survives, and chasing it changed the design story rather than the coverage.** The threading of
`~seen` was justified — by me, in the code comment — on the grounds that a module-level table would
leak between the per-language `extract_calls` calls that `Runner.run_multi` makes in one process,
because *function names* collide across languages far more readily than paths. R3-2 removed that
argument: both sites now key on **paths**, and a file belongs to exactly one language pass, so the
key space is naturally disjoint.

Round 4 review then showed my conclusion from that was wrong, and wrong in the direction this
branch exists to reject. I wrote "there is no collision left to provoke, and therefore no test can
kill M-d" — the second half does not follow from the first. Review supplied a *better* proof of the
cross-pass half than I had (`Language_registry.detect_language_roots` keeps one root per language,
`add_in` guarding on `Hashtbl.mem`, plus disjoint extension sets — so two passes can never share a
file, which is stronger than "naturally disjoint"), and then pointed at the comment's own second
scenario: one process indexing the same project twice. That is trivially constructible, and
`Arch_index.run_lsp` is public, so a test needs no widening of the surface. **M-d is closable, not
unclosable.**

It is not closed, and that is a judgment rather than an oversight: no caller indexes the same
project twice — `arch_index_cli` calls `run_lsp` or `run_lsp_multi` exactly once — so the test would
pin behaviour no code path reaches. The guard stays because it is correct and free. Both the brief
and the code comment now say *defensive and untested by choice*, never *untestable*. Claiming a
guard cannot be tested is precisely the move that produces inert guards.

**R3-4** — `relative_path`'s docstring still carried the one-sided "`project_dir` is absolutised
first" that F-2 was the bug report for. It now states that both arguments are normalised, that
matching is lexical and requires a segment boundary, the filesystem-root behaviour, and — as a
`{pre}` rather than the previous `(none)` — that a relative `abs_path` is absolutised against the
CWD and may then match, which is a behaviour change this round introduced.

**R3-3** — two stale figures in the gate table, same class as rounds 1–3 at lower amplitude:
`calls` and the `test_lsp_uri` case count. Both corrected above, and the golden's three moves are
now each accounted for by an edge-set diff rather than by a plausible sentence.

### Gates, round 4

| Gate | Command | Exit |
|---|---|---|
| Build | `dune build` | 0 |
| Tests | `dune test` | 0 — **71/71** (was 70) |
| Self-index golden | index + `diff test/fixtures/self-index-stats.txt` | 0 (`19 / 432 / 3393`) |
| arch-rules | `./arch-rules /tmp/selfg.db arch-rules.txt --on-vacuous fail` | 0 — **1 proved / 0 violations / 3 UNKNOWN** (recorded here as `4 rule(s), 0 failing`; corrected in PR #70, see the checklist above) |

Mutants R3-1a / R3-1b / M-c were each run by rebuilding and executing the new test through the tezt
binary by `--title`; the suite as a whole was then re-run with `dune test` (exit 0) with every
mutation restored. `git status --porcelain lib/ test/ tezt/` shows only this round's intended edits.

**Cost of the new test: ~10 s** (was ~25 s; measured on this machine, not inferred from review's 3 s figure, which was taken at a 3 s timeout rather than the 10 s that shipped). The first version left the timeout at 60 s, which lets
the warm-up run its full 21 sweeps, and the brief justified that by claiming the volume property is
"only observable across those sweeps". Review measured that claim false: at a 3 s timeout the run
does ~2 sweeps, the unbounded mutant yields 9 against an expected 3, and it still dies — and M-b,
M-c and the two review-authored name-key mutants do not depend on sweep count at all. The memo caps
the count at 3, so the assertion is invariant under sweep count; only the mutant's number moves. The
timeout is now 10 s, which keeps a margin over the 2-3 sweeps the separation needs while dropping
~60% of the wall clock. Both M-a and review's E-1 name-key mutant were re-verified dead at the
shorter timeout AND against the rescoped assertion 6 — cutting the budget must not cost a mutant,
and rescoping an assertion must not either. Same overstated-figure class as R3-3, caught the same way — by measuring instead
of reasoning about it.

## QA — verified by execution on real servers, not by reading the tests

The first QA pass returned NO-GO on `Library "ppx_inline_test" not found`. That was the default
opam switch, not the branch: reproduced both ways — default switch reproduces the exact message,
local switch gives `dune clean && dune build` exit 0 in 2.6 s. **A build failure whose message is a
missing library is an environment diagnosis, not a verdict on a branch.** The second pass, with the
switch pinned as a precondition, returned GO on all gates.

That pass verified three of the four ported behaviours by reading the tests that cover them rather
than by running the behaviour, and took the brief's word on the timeout one — the thing it was told
not to do. So the four were re-verified here directly, with real language servers
(`gopls`, `ocamllsp` both present):

| Behaviour | How it was exercised | Result |
|---|---|---|
| Absolute `file://` URIs | real `gopls`, **relative** `--project proj`, 2-function Go project | `found 2 functions`, `found 1 calls`; `file_path` stored as `main.go` — relative, machine-independent. Both halves of the fix at once: the rootUri had to be absolute for the document to open at all, and `relative_path` had to relativise for the path not to be absolute. |
| Honest partial results on timeout | `EPURE_ARCH_INDEX_TIMEOUT_S=3` against this repo with `ocamllsp` | `timeout after 3s — using partial results (2603 functions, 0 calls)` and the DB holds **2603** rows. The fork returned `([], [])` here. |
| Diagnostic volume, at real scale | same run | **91 `prepareCallHierarchy failed` lines, 91 distinct files** — exactly one per file, on 2603 functions, against an `ocamllsp` that answers `Request not supported yet!`. The fixture measured 3 on 3 files; this is the same property on two orders of magnitude more input, and it is the number the memo exists to produce. Unbounded it would be ~21 per function attempted. |
| Unknown-language fallback | `--language cobol` | exit 0, no output — `Language_registry.lookup` rejects it before `scan_source_files` is reached, which is exactly the reachability claim made in round 1 and verified by review: the `| _ -> scan_ts_files` arm was dead for anything but TypeScript. |

Per-file failure isolation remains covered by the two stub tests rather than by a real server —
making a real server refuse exactly one document is not arrangeable without a proxy, and that is
recorded as a gap, not converted into a pass.

`scripts/check-copyright.sh` does **not** exist in this repo and CI does not reference it. It was
listed as a passing gate earlier in this task; that was `tail`'s exit code inside a pipe, not the
script's — the same defect class as the mutation table run by hand. Copyright headers are present in
the new files regardless.
