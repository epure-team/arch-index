# Reviewer Brief — rust-soundcg-whole-program

**Date:** 2026-09-03
**Status: VALIDATED**

## What was implemented

A new Rust MIR call-graph producer (`arch-callgraph-rust`), built fresh (not merged) against
`specs/rust-soundcg-whole-program.md`, replacing the DO-NOT-MERGE `feat/rust-soundcg-a1`/`a2`
branches. Two slices: US-1 (sound MUST/MAY_TOP-only skeleton + trait-impl fact emission) and US-2
(a post-process merge pass narrowing `dyn`-dispatch sites to `MAY_ENUMERATED` across the whole
workspace, gated by a publish-boundary check and a missing-facts fallback).

This is a large, first-time-in-main feature — treat the review as full-scrutiny, not a
delta/incremental pass, regardless of how the implementer sequenced their commits.

## Critical things to verify first

1. **The four undocumented CRITICAL findings.** No record of them exists anywhere retrievable —
   this review IS the mechanism that substitutes for archaeology (per the intake brief's explicit
   scope boundary). Do not assume the implementer's own step-2 triage caught everything; review
   the final code fresh, as if A1/A2 never existed, specifically hunting for defects in: MIR
   terminator classification correctness, `Instance::resolve` handling, mono-item collection
   completeness, and anywhere a call site could be silently dropped rather than anchored.
2. **The missing-facts fallback (spec item 4, plan step 12).** Verify directly: construct or trace
   a scenario where one workspace crate's facts are absent/stale, and confirm every trait touched
   by that crate's facts falls back to `MAY_TOP` — not a partial `MAY_ENUMERATED`. This is the
   single highest-value soundness seam per the plan's own risk analysis (both dual-voice reviews
   flaged a version of this).
3. **The publish-boundary gate (spec item 3).** Confirm it actually reads `Cargo.toml`'s `publish`
   key correctly, including the `[workspace.package] publish = false` inheritance case a
   naive per-crate-only TOML parse could miss (flagged during planning). Confirm the accepted-
   residual documentation (README/code comments) states plainly that this is a weak proxy, not a
   strong guarantee — an implementer who quietly oversells this gate's protection is a defect.
4. **RTA-union extension (plan Decisions table).** Confirm the merge pass's candidate filter uses
   the union of RTA-reachable types across ALL workspace crates' mono-item collections, not just
   the calling crate's own local RTA set — a per-crate-only filter would silently reintroduce a
   missing-candidate risk symmetric to the one this whole task exists to fix.
5. **Cross-producer naming (CHECK-9, new this plan).** Confirm the MIR producer emits fully-
   qualified, DefId-derived names throughout — spot-check against a function also visible via the
   existing rust-analyzer LSP path and confirm no silent misattribution between the two producers'
   rows. Read `specs/sound-qualified-name-resolution.md` first — this is the same bug class that
   spec was written to close for OCaml.
6. **Scope guard (CHECK-8).** Confirm `git diff` against `lib/arch_index/call_graph_extractor.ml`
   and `tezt/tests/lsp_languages.ml` is empty. Any change there is a scope violation, full stop.
7. **Loud-fail semantics (US-1 AC-3).** Confirm the non-zero exit / no-partial-graph behavior is
   scoped exactly to "crates the wrapper actually visits as part of the requested build target" —
   not a stricter "any workspace crate anywhere" (which the plan explicitly declined to require,
   to avoid making the tool unusable on large, partly-broken monorepos).

## Files to audit first

- The new `callgraph-rust/` crate in full (fresh code, not a diff against A1/A2 — there is no
  merge base to diff against).
- Any change to `lib/arch_index/arch_load.ml` (or equivalent loader) — confirm it's scoped to
  tolerating the new fact-record kind, not a broader rewrite.
- The merge-pass fact-format design doc (plan step 4's deliverable) — confirm the implementation
  actually matches what was designed, not a drifted ad-hoc format.
- `selftest-callgraph-rust.sh` or its replacement, and the new multi-crate fixtures (step 14) —
  confirm CHECK-4 (sibling + downstream in one fixture) is a real, non-trivial fixture, not a
  toy that happens to pass.
- The CI-wiring follow-up ticket artifact (step 17) — confirm it names an owner and a concrete
  revisit trigger, not just "TODO: wire CI."

## Identified risks to verify

- One of the 4 undiscoverable CRITICALs turning out to be structural (affecting the shared
  MIR-walk core) — if you find evidence of this, it's a legitimate NO-GO, not a nitpick.
- The three accepted residuals (cache-staleness, publish-flag weakness, single-feature-set scope)
  being silently undocumented rather than stated plainly — check the README/code comments
  directly, don't take "the spec says it's accepted" as proof the shipped docs actually say so.
- Multi-crate fixture flakiness across cargo cache states (both dual-voice reviews warned this is
  the likely long pole) — run the selftest twice in a row, with and without a warm cargo cache,
  and confirm it's deterministic either way.

## Expected behaviors to confirm

- Direct calls: `MUST` with correct callee.
- `dyn Trait` dispatch with the impl set closed and bounded, workspace-wide, and the trait's
  crate sets `publish = false`: `MAY_ENUMERATED` including sibling AND downstream candidates.
- Same, but a blanket impl exists anywhere in the workspace: `MAY_TOP`.
- Same, but the trait's crate does not set `publish = false`: `MAY_TOP` regardless of closure.
- Same, but one workspace crate's facts are missing/stale: `MAY_TOP` for every trait that crate's
  facts would have touched.
- Named `extern "C"` FFI call: `MAY_TOP` with the symbol name recorded (not the anonymous sentinel).
- A crate outside the requested build target failing to compile: does not affect the run.
- A crate inside the requested build target failing to compile: non-zero exit, no NDJSON claiming
  a complete graph.
