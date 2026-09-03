# Implementation Brief — coverage-matrix

**Date:** 2026-09-03
**Mode:** fast
**Status:** COMPLETED

## Where the work lives

Worktree `/tmp/claude-1000/-home-mathias-dev-arch-index/14fbc421-dfc7-4b31-91d6-c084baeb45e0/scratchpad/wt-covmatrix`,
branch `feat/coverage-matrix`, based on `origin/main@901116a`.

## Scope

Roadmap Phase 1 item 1.3: `analysis_coverage(language, analysis, status, detail)` — the honest-
absence guarantee. Two research passes (spawned agents, pre-implementation) found the roadmap's
own design note's premise inaccurate: it assumes one shared "analysis registry" checkable via a
single `Language_registry.lookup` call, but Go/Rust callgraph producers are standalone binaries
entirely outside that registry, and the six analysis kinds
(`callgraph`/`effects`/`cfg`/`decisions`/`coverage`/`types`) split into at least three genuinely
different availability-detection mechanisms — one kind (`decisions`) isn't even part of the main
dune build. Presented this to the user; chosen scope: build a real cross-producer registry rather
than a narrowly-bounded slice limited to `Language_registry`-mediated languages.

## Decisions made

- **A new binary + library module, not an extension of `arch_index_cli`.** `bin/arch_coverage_matrix`
  (thin CLI) + `lib/arch_index/coverage_matrix.ml`/`.mli` (all detection logic) — a coverage run
  targets an arbitrary project directory, independent of whether that project is ALSO being
  indexed by `arch_index_cli`/`arch_callgraph_ocaml` in the same invocation. Matches this
  session's established pattern (thin CLI wrapper over library logic, e.g. `arch_index_cli` over
  `Runner.run`).
- **Per-kind detection strategy, not one shared lookup mechanism** — the heterogeneity is real,
  confirmed by direct testing, not assumed:
  - **OCaml callgraph/effects**: bundled dune executables — "available" once `project_dir/
    _build/default` exists and contains `.cmt`/`.cmti` files (`Covered`); present-but-empty is
    `Partial`; absent is `Not_analysed` with a `dune build` instruction.
  - **Go/Rust callgraph**: availability of the DRIVER each repo-root wrapper script
    (`arch-callgraph-go`, `arch-callgraph-rust`) gates internally — checked at
    `repo_root/bin/arch-callgraph-go` and the 4 candidate paths `arch-callgraph-rust`'s own script
    probes (`callgraph-rust/target/{release,debug}`, `$CARGO_TARGET_DIR/{release,debug}`), from
    `repo_root` (this arch-index installation), never `project_dir` (the target being analysed).
    **A real bug caught by manual testing before any automated test was written**: an earlier
    draft checked the WRAPPER SCRIPT's own existence, which is checked into git and therefore
    always present — every checkout would have reported `rust callgraph: covered` regardless of
    whether the actual Rust driver was ever built. Fixed by checking the driver path each wrapper
    itself probes, not the wrapper.
  - **Every other `Language_registry`-registered language**: `Language_registry.lookup`, with
    `lsp_install_instruction` appended to `detail` on failure — this is the ONE place the
    roadmap's own literal design (one shared registry lookup) is actually correct.
  - **`cfg`/`types`**: NOT independently invoked — these are properties the `callgraph` producer
    for a language already emits as part of its own output (post-dominance/CFG; the `types`
    table), so their rows mirror that language's `callgraph` row's status rather than being
    probed a second time. There is no `bin/arch_cfg*`/separate types binary to check.
  - **`coverage`** (test-line coverage — an unrelated meaning from the pre-existing `coverage` SQL
    table): requires an externally-supplied LCOV tracefile this tool cannot discover on its own —
    `Not_analysed` unless `--lcov <path>` names an existing file.
  - **`decisions`** (`poc/decision-lint`): a proof-of-concept outside the main dune build graph
    entirely — always `Not_analysed`, honestly, rather than silently invoked or silently dropped.
- **Go's `effects` producer is `Not_analysed`, not `Covered`**, even though it exists in
  `callgraph-go/effects/main.go` — it has no repo-root wrapper script and no build.sh target; it
  exists only as test-harness infrastructure (`tezt/lib/arch_tezt.ml`'s own `build_go` helper
  builds it into a throwaway temp dir per test run). Reporting `Covered` here would be a lie:
  nothing outside the test suite can actually invoke it today.
- **`analysis_coverage` gets its own DDL embedded twice** — once in `architecture-schema.sql`
  (so a coverage run can target an existing main-schema database), once as a literal string in
  `bin/arch_coverage_matrix/arch_coverage_matrix.ml` (so a coverage run can also create a fresh,
  minimal database on its own). Kept as two copies rather than a shared fragment file: the two
  are legitimately different files with no build step connecting them, and
  `tezt/tests/coverage_matrix.ml` pins them structurally equal via the actual binary's behavior.
- **Snapshot semantics, not accumulation** — every run does `DELETE FROM analysis_coverage` then
  re-inserts: this table describes the run that just computed it, matching `arch_coverage_load`'s
  own `--write` precedent ("replaces rather than accumulates") elsewhere in this codebase.
- **`current_schema_version` bumped 1.4 → 1.5** (main schema: new table, additive).
- **`must_null_ceiling.ml`'s ratchet recalibrated 289 → 321** (+32) — the new
  `coverage_matrix.ml`'s calls into `Sys.*`/`Filename.*`/`Unix.*`/`Sqlite3.*`, plus the
  intervening `provenance-columns`/`language-universe` tasks' own additions since the prior
  recalibration. Verified by direct query that every new MUST-with-NULL-callee row is a genuine
  external stdlib/library leaf (`Unix.access`, `Sqlite3.exec`/`prepare`/`bind`/`step`/`finalize`,
  `Arch_tezt.Check.option`), not a new unsound edge kind.

## Modified files

| File | Type of change | Reason |
|---|---|---|
| `architecture-schema.sql` | addition | `analysis_coverage` table (+ 2 indices). Main schema version 1.4→1.5 |
| `lib/arch_index/arch_index_db.ml` | modification | `current_schema_version` 1.4→1.5 |
| `lib/arch_index/coverage_matrix.ml`/`.mli` | addition | All detection logic (see Decisions above) |
| `lib/arch_index/arch_index.ml`/`.mli` | modification | Re-exports `Coverage_matrix` (matches the `Language_registry` re-export pattern) |
| `bin/arch_coverage_matrix/arch_coverage_matrix.ml`/`dune` | addition | Thin CLI: `--project`/`--db-path`/`--lcov`/`--allow-partial`/`--verbose`; embeds the table DDL; exit-code policy |
| `docs/schema.md` | addition | `1.5` version-history row; "Analysis coverage" section documenting the per-kind detection strategy |
| `tezt/lib/arch_tezt.ml` | modification | New `arch_coverage_matrix ()` locate helper |
| `tezt/tests/coverage_matrix.ml` | addition | 6 tests: un-built OCaml (not_analysed, exit 1), built OCaml (covered), `--allow-partial` (exit 0), Rust with no driver built (not_analysed, exact detail), cross-language rows (language NULL), snapshot semantics (re-run doesn't accumulate) |
| `tezt/tests/main.ml` | modification | Registers `Coverage_matrix` |
| `tezt/tests/must_null_ceiling.ml` | modification | Ratchet recalibrated 289→321 (see Decisions) |
| `test/fixtures/self-index-stats.txt` | regenerated | Per ADR 001 — 542→572 functions, 3849→3957 calls |

## Quality Gates

- [x] Build: `dune build --root . @all` (under the `arch-index` opam switch) ✅ clean, zero warnings
- [x] Tests: `dune test --root . --force` ✅ 102/102 tezt tests pass (6 new `coverage_matrix.ml` tests)
- [x] Self-index golden regenerated per ADR 001
- [x] `must_null_ceiling` ratchet recalibrated and verified against real query output (not a blind bump)

## Points of attention for review

- Confirm the per-kind detection split is a principled response to real heterogeneity (verified:
  Go/Rust drivers genuinely live outside `Language_registry`; `decisions` genuinely isn't in the
  main dune build; `cfg`/`types` genuinely have no separate binary) rather than an excuse to
  under-deliver relative to "a real registry".
- The Go/Rust driver-path-vs-wrapper-script bug (caught before any automated test existed, via
  manual testing against a real Rust fixture) — confirm the fix's exact candidate paths match
  each wrapper script's own internal logic precisely (`arch-callgraph-go`, `arch-callgraph-rust`
  quoted in full in the research that preceded implementation).
- `find_sibling_tool`'s upward-search algorithm duplicates `tezt/lib/arch_tezt.ml`'s
  `find_upwards`/`locate` pair rather than sharing it — deliberate, since that module depends on
  `Tezt` (`Test.fail`) and this is production code where "not found" is an expected outcome, not a
  hard failure. Confirm this duplication is justified rather than something to unify.

## Identified out-of-scope (deferred, not silently dropped)

- Wiring `callgraph-go`/`callgraph-rust`'s own effects/decisions producers into a shipped,
  installed form (rather than test-harness-only) — mechanical follow-up, touches producer
  codebases outside this item's own scope.
- Promoting `poc/decision-lint` into the main dune build graph — a separate, larger decision
  (does this proof-of-concept get productionized at all) not this item's to make.
- Any cross-database aggregation (a single project's coverage spanning multiple database files
  from independently-invoked producers) — `arch-coverage-matrix` computes and writes one
  database's worth of coverage per invocation; consolidating several is a distinct, larger
  problem the roadmap does not ask this item to solve.
- The Octez-scale acceptance test the roadmap names ("4,550 .rs files must produce a
  not_analysed row") — not run in this task; the mechanism it exercises (Rust driver absence →
  `not_analysed`) is directly verified by `tezt/tests/coverage_matrix.ml`'s Rust fixture test.

## Review-round addendum

A fresh review round (reviewer + architect in parallel, cross-runtime codex skipped — degraded
all session) found and fixed:

- **CRITICAL (both reviewers independently)**: `repo_root` was computed in the CLI as a single
  `Filename.dirname Sys.executable_name` hop, landing inside
  `_build/default/bin/arch_coverage_matrix/` rather than the true repo root — `go_callgraph_row`/
  `rust_callgraph_row` checked against that wrong root with no upward search, so Go/Rust
  callgraph reported `not_analysed` in EVERY real invocation of the compiled binary, regardless
  of whether the drivers were built. Manual testing during implementation only ever exercised the
  driver-NOT-built case (which looks identical to this bug), so it shipped undetected. Fixed with
  a new `find_repo_root`, but the first fix attempt (search upward for
  `architecture-schema.sql` alone) hit a SECOND instance of the same class of bug: dune mirrors
  that file into `_build/default/` too, so the search found dune's own copy one directory short
  of the real root. The working fix requires BOTH `architecture-schema.sql` AND a sibling
  `_build` directory — `_build/default` itself never contains a further `_build` of its own, so
  this cannot match the mirror. A further complication: the TEST file's own `repo_root ()` helper
  (used to place stub executables) initially used `schema ()` (CWD-based search), which resolved
  differently from the CLI's own exe-path-based search under `dune test`'s sandboxed working
  directory — fixed by having the test call `Coverage_matrix.find_repo_root` directly, from the
  exact directory the binary under test itself starts from.
- **HIGH (reviewer)**: no test exercised the "driver actually built → covered" path for Go/Rust —
  the existing not-built test is indistinguishable from the CRITICAL bug's always-not_analysed
  symptom. Added two new tests that plant a real stub executable at the exact repo-relative path
  and assert `covered` — these are what actually caught the CRITICAL bug persisting after the
  first fix attempt.
- **HIGH (reviewer)**: `effects` rows were silently omitted (not emitted at all) for every
  language except OCaml/Go, contradicting the module's own `.mli` contract and reopening exactly
  the silent-absence failure this table exists to close. Fixed: every detected language now gets
  an `effects` row.
- **HIGH (reviewer)**: `rust_callgraph_row` checked only the cargo driver, missing the wrapper
  script's SECOND hard gate (the whole-program merge pass, `bin/arch_callgraph_rust_merge`) —
  a checkout with the driver built but not the merge pass would have reported `covered` while the
  real wrapper actually exits 2. Fixed: both gates checked, with a distinct `detail` for each.
- **CRITICAL (reviewer)**: `has_cmt_files`'s directory walk crashed the whole binary
  (uncaught `Sys_error`, exit 125) on a dangling symlink or symlink cycle under `_build/default`
  (which dune builds are dense with) — reproduced directly. Fixed: per-entry `Unix.lstat`
  (skips symlinks outright rather than following them into either failure mode) plus a depth cap.
- **MEDIUM (both reviewers, independently confirmed by direct diffing)**: the `analysis_coverage`
  DDL was duplicated as a hand-copied literal in the CLI, and the claim that a test "pins the two
  copies structurally equal" was false — no test ever exercised the `architecture-schema.sql`
  copy. Fixed by eliminating the duplication entirely: the CLI now re-executes
  `Arch_index.schema_sql` (already embedded via `ppx_blob`) — every statement in
  `architecture-schema.sql` is `CREATE ... IF NOT EXISTS`, so this is a safe no-op against an
  existing populated database and a complete bootstrap against an empty one.
- **MEDIUM (reviewer)**: `write_coverage`'s DELETE-then-INSERT ran outside a transaction (a
  mid-run failure destroyed the old snapshot and left the new one partial) and every `Sqlite3.bind`
  result was silently ignored (a failed bind could leave a NULL or a stale previous-row value
  written with exit 0). Fixed: wrapped in `BEGIN IMMEDIATE`/`COMMIT`/`ROLLBACK`, every bind
  checked, `clear_bindings` before each row.
- **MEDIUM (reviewer)**: `has_gap` counted the two structurally-always-`not_analysed`
  cross-language rows (`coverage` without `--lcov`, `decisions`), making every invocation without
  `--allow-partial` exit 1 unconditionally — a gate that always fires carries no signal. Fixed:
  only language-scoped rows count. `Partial` (an empty `_build/default` — about to silently index
  nothing) now also counts as a gap, which it previously did not.
- **LOW (reviewer)**: `is_executable` used `Unix.access [X_OK]` alone, which succeeds on
  directories too (a directory named `bin/arch-callgraph-go` would have matched). Fixed: requires
  `Unix.S_REG` first.

Re-verified after fixes: build clean, 105/105 tests (5 new/changed this round: two real
driver-built positive tests for Go/Rust that actually caught the CRITICAL bug surviving its first
fix attempt, an existing-main-schema-database safety test, plus the `register_ocaml_built` exit
code assertion updated from 1→0 to match the corrected `has_gap` semantics). Self-index golden
regenerated again (575 functions, 3986 calls).

## Ratchet

First round.
