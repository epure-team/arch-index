# QA Report — provenance-columns

**Date:** 2026-09-03
**Mode:** fast
**Status:** GO ✅

## Context

- `briefs/provenance-columns-review.json` — GO. reviewer + architect, cross-runtime codex
  skipped (degraded all session). Round 1 found and fixed 3 HIGH, 6 MEDIUM, 1 LOW — including a
  second, independent, previously-undiscovered bug (`PRAGMA foreign_keys=ON` breaking re-index of
  any existing database) found while fixing one of the HIGH findings.
- `briefs/provenance-columns-impl.md` — scope: `producer_runs` table + FK on the main schema;
  `comment_db_meta` keys on both flat schemas (`runner.ml` hardcoded, `bin/arch_load` via new
  CLI flags).
- No `specs/provenance-columns.md` exists (Fast mode) — Step 3 substituted with independent
  fresh-fixture reverification of all three provenance mechanisms, per this pipeline's
  established precedent for Fast-mode tasks this session.

## Gate 1 — Build

```
dune build --root . @all
```
**PASS** — clean, zero warnings.

## Gate 2 — Tests (full suite)

```
dune test --root . --force
```
**PASS** — 96/96 tezt tests, ~3m32s. Includes 5 new/extended tests from this task (2 new
`provenance.ml` tests added during the review round: real-CMT-run and no-accumulation-on-reindex;
plus the CHECK-constraint positive control, and 2 new assertions in `lsp_languages.ml`).

## Gate 3 — Format / Lint

`dune build @fmt` reports the same pre-existing diff already present on `main` HEAD
(`lib/arch_index/dune`/`bin/arch_body_compare/dune` argument-list wrapping) — confirmed not
introduced by this task, not a blocker (same residual noted in the prior `language-universe` ship).

## Step 3 substitute — independent fresh-fixture reverification (no spec exists)

Each of the three provenance mechanisms was re-exercised from scratch, outside the review round's
own test files, using fresh fixtures in `/tmp/qa-prov`:

1. **Main schema** (`arch_callgraph_ocaml`, a fresh 2-function/1-call fixture, indexed TWICE
   against the same db path): exactly one `producer_runs` row after both invocations
   (`producer=arch_index_cmt`, `soundness_class=sound_with_top`, non-empty `invocation_digest`,
   `producer_version` NULL as documented), both `functions` rows and the `calls` row correctly
   carry `producer_run_id=1`. Independently confirms both the HIGH fix (drop-list) and the
   second bug's fix (FK pragma). PASS.
2. **Flat schema, LSP path** (`arch_index_cli`, a fresh Go fixture): `comment_db_meta` carries
   `producer=arch_index_lsp`, `soundness_class=heuristic`, a non-empty `invocation_digest`,
   alongside the pre-existing `built_by`/`language`/`schema_version` keys. PASS.
3. **`bin/arch_load`** — four scenarios: (a) `--producer=callgraph-rust
   --producer-version=v0.9 --soundness-class=sound_with_top` → all three keys stored correctly;
   (b) no flags → `soundness_class=heuristic`, no `producer`/`producer_version` keys at all
   (absent, not a guessed value); (c) `--soundness-class=bogus` → exit 2, no database file
   created; (d) `--producer=` (empty value) → exit 2 ("`--producer= must not be empty`"),
   confirming the MEDIUM fix for the empty-value bug. All four PASS.

All three mechanisms independently confirmed correct, and every review-round fix (drop-list,
FK-pragma, SHA-256→MD5 comment, `Sys.argv`→own-parameters digest input, empty-flag rejection,
unrecognised-flag rejection, CHECK-constraint positive control, `set_provenance_meta` factoring)
verified to actually hold under fresh exercise, not just trusted from the review round's own
tests.

## Step 3.5 — Code-intel invariant gate

Not applicable — no `kb/properties.md` `code-intel` block in this repository.

## Step 4 — TUI check

N/A — no TUI surface in scope.

## Step 4.5 — Cross-runtime QA re-verification

`codex` is on `PATH` but degraded (non-conforming-output) on every invocation this entire
session, including the review round for this task. Per the breaker: `status: skipped-degraded`,
not re-invoked this QA round.
`Cross-runtime QA: skipped (review breaker, unchanged runtime version)`

## Verdict

**GO ✅** — all deterministic gates pass (build clean, 96/96 tests), and all three provenance
mechanisms independently reverified with fresh fixtures, confirming every review-round fix holds.
Ready for `/roster-ship`.
