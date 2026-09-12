# Implementation Brief — lsp-runner-diagnostics

**Date:** 2026-09-12T14:08:43Z
**Mode:** fast
**Status:** COMPLETED

## Modified files

| File | Type of change | Reason |
|---|---|---|
| `lib/arch_index/runner.ml` | modification | Emit the four existing failure/partial-result diagnostics on stderr independently of verbose mode. |
| `tezt/tests/lsp_runner_diagnostics.ml` | addition | Exercise lookup, startup, timeout, and unexpected-exception diagnostics through the actual CLI with separated stdout/stderr. |
| `tezt/tests/main.ml` | modification | Register the four new Tezt regressions. |
| `docs/install.md` | modification | Document unconditional stderr diagnostics and the unchanged best-effort exit/database contract. |
| `skills-meta/friction.jsonl` | modification | Record TDD and implementation phase friction. |
| `briefs/lsp-runner-diagnostics-impl.md` | addition | Record implementation decisions and gate evidence. |
| `briefs/lsp-runner-diagnostics-state.json` | addition | Record the completed implementation phase. |

## Decisions made

- Removed only the `verbose` guards around `LSP lookup failed`, `LSP start failed`, `timeout ... using partial results`, and `unexpected error`. Progress narration, readiness, row counts, output-path narration, and the unrelated enrichment warning remain verbose-only.
- Kept the existing return values, exit codes, atomic database writing, and partial-row refs unchanged. No structured outcome API was introduced.
- Used actual CLI processes and PATH-controlled server fixtures. Startup failure returns a JSON-RPC error containing `STARTUP_SENTINEL`; unexpected exception uses a present non-executable `gopls`; timeout uses a hanging executable.
- Corrected an initial test-fixture assumption that immediate server exit would always say `initialize`: the observed reason was transport-specific, so the fixture was strengthened to a deterministic JSON-RPC sentinel before final RED/GREEN evidence.

## Quality Gates

- [x] Baseline build: `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune build --root . @install` — exit 0.
- [x] Baseline tests: `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune test --root . --force` — exit 0; 227/227 Tezt plus all Alcotest groups.
- [x] Initial RED: `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune exec --root . tezt/tests/main.exe -- --file lsp_runner_diagnostics.ml` — exit 1; 1/4 played, lookup test failed with two assertions for the absent label and reason.
- [x] Complete RED after deterministic fixture refinement: temporarily restored only the original four verbose guards, then ran `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune exec --root . tezt/tests/main.exe -- --file lsp_runner_diagnostics.ml --keep-going` — exit 1; 4/4 tests failed, two missing-diagnostic assertions per branch. The production fix was then restored with the exact inverse patch.
- [x] Focused GREEN: `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune exec --root . tezt/tests/main.exe -- --file lsp_runner_diagnostics.ml` — exit 0; 4/4.
- [x] Final build: `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune build --root . @install` — exit 0.
- [x] Final tests: `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune test --root . --force` — exit 0; 231/231 Tezt plus all Alcotest groups.
- [x] Format/style: `rtk git diff --check` — exit 0; no formatter is configured.
- [ ] Supplemental package lint: `rtk proxy opam lint arch-index.opam` — non-zero with pre-existing error 23 (`maintainer`) and warnings 25/35/36/68. Not a green gate and not changed in this slice.

## Points of attention for review

- Confirm the production diff changes only the four requested gates and leaves progress messages guarded.
- Confirm the tests inspect stderr separately, retain each underlying reason, preserve exit 0/quiet stdout, and prove verbose mode emits the diagnostic exactly once while retaining progress output.
- The timeout fixture waits for its ten-second process lifetime during switch cleanup; it is deterministic but adds about ten seconds to the suite.

## Coverage limits

- The timeout branch deterministically reaches the partial-result diagnostic with zero collected rows. Existing mutable refs and database writing are left untouched; this slice does not add a production hook to force timeout after non-empty symbol extraction.
- Generic exception coverage is deterministic for POSIX permission denial through a present non-executable server fixture.

## Identified out-of-scope

- Exit-code redesign and a structured run outcome remain explicitly outside roadmap slice #23.
- The pre-existing opam metadata lint debt remains unchanged.

## Scope/debt

The implementation is limited to runner diagnostic visibility, actual-CLI regression coverage, usage documentation, and required pipeline artifacts. No schema, enrichment, merge-path, or bundled review-tooling changes were made.
