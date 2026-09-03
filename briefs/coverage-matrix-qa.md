# QA Report — coverage-matrix

**Date:** 2026-09-03
**Mode:** fast
**Status:** GO ✅

## Context

- `briefs/coverage-matrix-review.json` — GO. reviewer + architect, cross-runtime codex skipped
  (degraded all session). Round 1 found and fixed 2 CRITICAL, 3 HIGH, 3 MEDIUM, 1 LOW — most
  notably a repo_root miscalculation that silently defeated all Go/Rust callgraph detection,
  caught independently by both specialists, requiring two fix passes (dune mirrors
  `architecture-schema.sql` into `_build/default/` too) and new stub-based positive tests to
  actually verify closed.
- `briefs/coverage-matrix-impl.md` — scope: new `analysis_coverage` table (main schema, 1.4→1.5)
  + `bin/arch_coverage_matrix` binary + `lib/arch_index/coverage_matrix.ml`.
- No `specs/coverage-matrix.md` exists (Fast mode) — Step 3 substituted with independent
  fresh-fixture reverification, per this pipeline's established precedent this session.

## Gate 1 — Build

```
dune build --root . @all
```
**PASS** — clean, zero warnings.

## Gate 2 — Tests (full suite)

```
dune test --root . --force
```
**PASS** — 105/105 tezt tests, ~84s. Includes 9 `coverage_matrix.ml` tests, 2 of which (added
during the review round) plant real stub executables to independently verify the previously-
broken Go/Rust `covered` detection path.

## Gate 3 — Format / Lint

Same pre-existing `@fmt` diff already on `main` HEAD (unrelated to this task) — not a blocker,
consistent with the prior two ships this session.

## Step 3 substitute — independent fresh-fixture reverification (no spec exists)

Outside the review round's own test files, using fresh fixtures in `/tmp/qa-covmatrix*`:

1. **Rust, driver not built anywhere**: fresh Cargo fixture, no stub planted — `rust callgraph:
   not_analysed`, exact fix instruction. PASS.
2. **Rust, both gates**: planted a real stub at `callgraph-rust/target/release/arch-callgraph-rust`
   only (no merge-pass artifact present, confirmed absent by `ls`) — `rust callgraph:
   not_analysed (arch_callgraph_rust_merge not built...)`, correctly naming the SECOND gate
   specifically, not the first. This independently reconfirms the review round's HIGH fix (the
   two-gate check) actually holds. PASS.
3. **OCaml, single-language project, dune-built**: exit 0 in both a "would-be-gap" scenario and
   a clean one — confirms the review round's MEDIUM fix (`has_gap` excluding the two permanently-
   not_analysed cross-language rows) holds under fresh exercise, not just the review's own tests.
   PASS.

All three independently confirm the review round's fixes hold, including the specific two-stage
Rust gate the reviewer flagged as easy to get subtly wrong (checking the driver but not the merge
pass, or vice versa).

## Step 3.5 — Code-intel invariant gate

Not applicable — no `kb/properties.md` `code-intel` block in this repository.

## Step 4 — TUI check

N/A — no TUI surface in scope.

## Step 4.5 — Cross-runtime QA re-verification

`codex` degraded (non-conforming-output) on every invocation this entire session, including the
review round for this task. Per the breaker: `status: skipped-degraded`, not re-invoked.
`Cross-runtime QA: skipped (review breaker, unchanged runtime version)`

## Verdict

**GO ✅** — all deterministic gates pass (build clean, 105/105 tests), and independent
fresh-fixture reverification confirms every review-round fix (repo_root, the Rust two-gate check,
exit-code semantics) holds under exercise outside the review round's own test suite. Ready for
`/roster-ship`.
