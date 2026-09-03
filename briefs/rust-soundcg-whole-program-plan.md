# Plan — rust-soundcg-whole-program

**Date:** 2026-09-03
**Status: VALIDATED**

## Consensus Table

| Point | Voice 1 | Voice 2 | Status |
|---|---|---|---|
| Nightly-pin build sanity check must happen before any coding starts | ✅ (R-1) | ✅ (#7) | AGREE — auto-decided: literal step 0 |
| Fresh adversarial review of A1/A2 substitutes for the undiscoverable 4 CRITICALs | ✅ (P0.2/P0.3) | ✅ (implicit in #6) | AGREE — auto-decided, matches intake's scope boundary |
| Merge-pass on-disk fact format/invocation point is unspecified and must be its own artifact before parallel work starts | ✅ (R-2) | ✅ (#4, same underlying gap) | AGREE — auto-decided: explicit design-doc step before any US-2 coding |
| CI-wiring-as-follow-up risks becoming a permanent gap given the pinned nightly's inherent drift | ✅ (R-6) | ✅ (#7) | AGREE — auto-decided: strengthen to ticket + owner + explicit revisit trigger |
| Multi-crate fixture infrastructure is genuinely new work, not an afternoon extension | ✅ (R-7) | ✅ (#9) | AGREE — auto-decided: its own budgeted step |
| `arch_load.ml` is off-limits per an "earlier plan doc" | — | Cited as a constraint (R-3) | **Fact-checked and corrected**: no such prohibition exists anywhere in this task's intake or spec — resolved as in-scope if needed |
| Loud-fail-on-any-compile-error may make the tool unusable on large, always-partly-broken workspaces | (not raised) | ✅ (#8) | Resolved without reopening spec — see Decisions |
| RTA-type-reachability narrowing's fate under whole-workspace merge is unspecified | ✅ (R-8) | (not raised) | Resolved — see Decisions |
| Two independent Rust... wait, two independent producers (LSP path + new MIR producer) risk a cross-producer naming/homonym class of bug this repo already has a hard-won spec for | (not raised) | ✅ (#5) | Resolved — see Decisions, new scope item added |
| Feature/cfg-gated trait impls are invisible to a single-feature-set compilation — a missing-edge (unsound) direction distinct from the sibling/downstream gap the flat-union already fixes | (not raised) | ✅ (#3) | Resolved as an accepted, documented residual — see Decisions |
| **Incremental cargo caching means the wrapper doesn't fire for unchanged crates, so the missing-facts fallback would apply almost every ordinary incremental run, rarely letting MAY_ENUMERATED materialize** | (not raised) | ✅ (#1) | **Escalated to the human** — resolved: accept as a documented operational residual (see Decisions) |
| **The publish-boundary gate (`publish = false`) is close to a no-op in a typical monorepo** | (not raised) | ✅ (#2) | **Escalated to the human** — resolved: accept as a documented, admittedly-weak residual (see Decisions) |

No DISAGREE items (no case where both voices proposed genuinely different approaches to the same
point). Two items were escalated as USER-CHALLENGE-adjacent (only one voice raised each, but both
strike at the spec's core value proposition) — the human chose to accept both as documented
residuals and ship as scoped, rather than invest further engineering or descope US-2.

## Decisions made

| Point | Decision | Reason |
|---|---|---|
| Cache-staleness / missing-facts-almost-always | **Accepted as a documented operational residual** (human decision, 2026-09-03). Document explicitly: `MAY_ENUMERATED` only reliably narrows immediately following a full workspace rebuild; an ordinary incremental re-index will conservatively degrade most cross-crate candidates to `MAY_TOP` rather than risk staleness. This is stated as an **operational requirement for precise results**, not hidden as a silent degradation — the plan's docs step (P3.3) must say this in the producer's own README/usage docs, not just in this plan. | Matches the human's explicit choice; the fallback firing often is exactly the sound, conservative behavior the spec already mandates (item 4) — it firing *more often than expected* is a precision cost, not a correctness bug. |
| Publish-boundary gate weakness | **Accepted as a documented, admittedly-weak residual** (human decision). State plainly in the spec/README that the `publish = false` check is a cheap, gameable proxy — it catches the case where hygiene metadata is accurate, and does not detect path/git-dependency consumption outside the analyzed cargo session. Do not claim a stronger guarantee than this proxy delivers. | Matches the human's explicit choice; strengthening this (e.g., detecting path/git deps) was explicitly declined as extra scope for this task. |
| Feature/cfg-gated impls (missing-edge risk) | **Accepted as a documented residual**, consistent with the same human decision above: the producer analyzes exactly one resolved feature/cfg graph per invocation (whatever `cargo build`'s default resolution produces) — a trait impl gated behind a disabled feature is not walked and not part of the fact set. Document this as an explicit scope boundary (single-feature-set analysis; feature-powerset analysis is future work), not a silently-accepted gap. | Same category of "known proxy/approximation limitation" the human just approved accepting rather than closing in this task; combinatorial feature-powerset analysis is a materially larger undertaking not scoped or estimated anywhere. |
| Loud-fail-on-compile-error usability risk | **No change to the spec's AC-3** (already validated — `US-1 AC-3` already scopes the loud-fail requirement to "crates the wrapper actually visits as part of the requested build target," explicitly excluding crates outside the requested build). Add an operational note: if a workspace is not fully buildable, the operator scopes the indexing run to a buildable subset (e.g. `cargo build -p <crate>...`) rather than the tool silently tolerating partial failures within the requested scope. | This is already what the validated spec says; Voice 2's concern is addressed by using the invocation correctly, not by weakening the invariant. Reopening AC-3 would contradict a validated spec artifact without new information the spec author didn't already have. |
| `arch_load.ml` scope | Confirmed in-scope to modify if the new trait-impl-fact NDJSON record type requires it (e.g., to make the loader tolerate/route an unknown-to-older-loaders record kind). Not a scope violation of CHECK-8, which only forbids touching the **LSP call-hierarchy path** (`call_graph_extractor.ml`, `lsp_languages.ml`), a different file entirely. | Fact-checked directly against the intake and spec — no prohibition on `arch_load.ml` exists in either. |
| RTA-type-reachability narrowing under whole-workspace merge | A2's existing per-crate `RtaTypes`/`build_rta_types` mechanism is **kept**, but its scope is extended to match the flat-union principle already established for impls: the merge pass's candidate filter uses the **union of RTA-reachable types across all workspace crates' own mono-item collections**, not just the calling crate's own local RTA set (which cannot know about types only ever instantiated in a different crate). | Falling back to per-crate-only RTA scoping would silently re-introduce a missing-candidate risk symmetric to the trait-impl one this whole task exists to fix; extending the already-accepted flat-union principle to RTA is the consistent, minimal-new-surface-area choice. |
| Cross-producer naming/homonym risk (new MIR producer vs. existing LSP path) | New explicit scope item, **added to this plan** (not deferred): the MIR producer's emitted function identity must be a fully-qualified path (crate name + module path + item path, DefId-derived), matching how the Go/OCaml producers already avoid bare-name collisions. Add one runnable check (CHECK-9) asserting the new producer's naming for a function also indexed by the existing rust-analyzer LSP path does not silently attribute edges to the wrong producer's row, mirroring the discipline `specs/sound-qualified-name-resolution.md` established for the OCaml case. | Voice 2 correctly identified this as a structurally identical risk class to an already-proven bug in this exact repo; the mitigation (qualified-path identity) is well-established prior art in this same codebase, not new invention. |

## Sequential steps

1. **Nightly-pin sanity check** — confirm `nightly-2026-06-20` (+ `rustc-dev`/`llvm-tools`/`rust-src`) still builds both A1 and A2 worktrees as committed today (`RUSTC_BOOTSTRAP=1 cargo build --release` in each). Completion: both build clean, or a documented decision on re-pinning if not. Files: none (verification only).
2. **Fresh adversarial review of A1+A2 as they stand** (spawn `reviewer`+`architect` specialists against both worktrees' current code, same process as issue #41) — output: a superset of the "5 CRITICALs," now attributable to file:line for the 4 previously-undocumented ones. Completion: a written findings list (not a formal `/roster-review` verdict yet — this is plan-informing research, the real `/roster-review` runs later against the new implementation).
3. **Triage step 2's findings against the settled spec architecture** — bucket each as (a) fixed by the whole-program redesign as a side effect, (b) orthogonal, must still be fixed, (c) contradicts a settled spec decision (if (c), stop and escalate — do not silently override a validated spec). Completion: a triage table, no unresolved (c) items.
4. **Merge-pass fact-format design doc** — before any US-2 coding, write the concrete on-disk/wire format for per-crate trait-impl facts (trait path, Self-type path, implementing method DefId-derived qualified path, defining crate's `publish` flag, RTA-reachable-type set for that crate, a crate-identity + build-batch-id completeness marker per Voice 1's A-3/R-2 and Voice 2's #4) and how the merge pass discovers "all fact files for this batch" (an explicit manifest of crates the wrapper was asked to visit this run, not inferred from which files happen to exist — closes Voice 2's #4 completion-barrier gap). Completion: a short design note (can live in `callgraph-rust/README.md` or a `docs/` addendum), reviewed against spec items 3/4 before step 5 starts.
5. **Scaffold `callgraph-rust/`** in the main repo (fresh `Cargo.toml`, pinned `rust-toolchain.toml`, README) — port non-controversial plumbing (NDJSON emit, CLI parsing, `after_analysis` wiring, mono-item collection) from A1/A2 only after each ported unit clears step 3's triage; do not merge either branch wholesale. Completion: crate scaffold builds and runs a no-op pass.
6. **Per-crate MUST/MAY_TOP walk (US-1 core)** — MIR terminator walk, classification for direct calls (MUST), static trait dispatch, fn-pointer, named-symbol FFI (MAY_TOP with symbol name, not the anonymous sentinel — AC-4), foreign items, everything dynamic MAY_TOP. Uses fully-qualified DefId-derived paths for every emitted name (closes the cross-producer naming risk). Completion: CHECK-1/CHECK-3 green on a 2-crate fixture.
7. **`RUSTC_WORKSPACE_WRAPPER` cargo integration + loud-fail** — scoped to crates the wrapper actually visits for the requested build target (per spec AC-3 as validated, unchanged). Completion: CHECK-2 green.
8. **Emit per-crate trait-impl fact records (US-1's US-2-enabling deliverable)** — per step 4's format, even though nothing consumes them yet. Completion: fact records present in NDJSON output, schema-valid against step 4's design doc; `arch_load.ml` updated if needed to tolerate the new record kind without hard-failing on it (confirmed in-scope).
9. **2-crate fixture + CHECK-1/2/3 full green; commit US-1 as an independently-shippable slice.**
10. **Merge-pass implementation (US-2 core)** — new, separate stage per step 4's design: reads the union of a batch's per-crate fact files, resolves cross-crate `MAY_ENUMERATED` candidates. Completion: merge pass runs standalone against step 8's fact output.
11. **Publish-boundary safety gate** — Cargo.toml `publish` check per-trait-defining-crate, documented explicitly as the accepted weak-proxy residual (Decisions table). Completion: CHECK-6 green.
12. **Missing-facts fallback** — using step 4's completeness marker (crate-identity + build-batch-id), any trait touched by a missing/stale/incomplete crate's facts falls back to `MAY_TOP`. Document the cache-staleness operational consequence explicitly (Decisions table) in the producer's README. Completion: CHECK-7 green.
13. **Cross-crate blanket-impl detection + RTA union extension** — extend A2's existing single-crate blanket-impl check across the flat union (Decisions table's RTA resolution). Completion: CHECK-5 green.
14. **3-4 crate fixture infrastructure** (its own budgeted step, not folded into a checklist line) — hermetic, deterministic multi-crate cargo workspace fixtures covering sibling, downstream, blanket-impl-in-another-crate, and missing-facts shapes. Completion: CHECK-4 green (sibling + downstream in one fixture, per spec US-2 AC-1/AC-2).
15. **Cross-producer naming check (CHECK-9, new)** — confirm the MIR producer's qualified-path identity for a function also visible via the LSP path doesn't collide/misattribute. Completion: CHECK-9 green.
16. **Scope guard (CHECK-8)** — automated `git diff` check that `lib/arch_index/call_graph_extractor.ml` and `tezt/tests/lsp_languages.ml` are untouched, wired into the same check run as CHECK-1..7/9, not a manual reviewer step.
17. **CI-wiring decision, strengthened** — produce an explicit ticket (a new roadmap line, or a filed GitHub issue) with a named owner and an explicit revisit trigger ("next time the pinned nightly needs to move, or within N weeks, whichever first") — not just "a follow-up ticket exists."
18. **Docs** — producer README states the two accepted residuals (cache-staleness precision cost, publish-flag proxy weakness, single-feature-set scope) plainly, not buried in a spec file; file the deferred items (non-`dyn` generic narrowing, sealed-trait detection, dependency-graph-aware merge precision, feature-powerset analysis) as tracked follow-ups.
19. **Full 9-check run, then `/roster-review` (full fresh scrutiny, no assumed subset of "4 more fixes"), then `/roster-qa`, then `/roster-ship`.**

## Dependencies

- Step 1 gates everything — if the pin doesn't build, re-scope before any further step.
- Step 2 must precede step 5 (can't safely port code from branches whose defects aren't yet
  attributed).
- Step 4 (fact-format design) must precede steps 8, 10, 11, 12, 13 — they all consume that format;
  building any of them before the format is fixed risks incompatible shapes (Voice 1's R-2).
- Step 9 (US-1 shippable) does not block step 10 starting, but US-1 must be feature-complete
  (including step 8's fact emission) before step 10's merge pass has anything real to consume.
- Steps 11, 12, 13 can proceed in parallel once step 10's merge-pass skeleton exists; step 14
  (fixtures) validates all three together and should follow, not precede, them.
- Step 16 (scope guard) has no code dependency — it can be written any time after step 1, and
  should run continuously (part of the check suite) from the start, not bolted on at the end.

## Identified risks

| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| Nightly pin has bit-rotted since 2026-06-20 | Medium | High (invalidates the whole estimate) | Step 1 surfaces this immediately, before any other work |
| One of the 4 undocumented CRITICALs is structural (affects the MIR-walk core both US-1 and US-2 depend on) | Medium | High (partial rewrite, not point-fixes) | Step 2/3 explicitly triage for this before scaffolding locks in a shape |
| Multi-crate fixture engineering (hermetic `RUSTC_WORKSPACE_WRAPPER` firing across cargo cache states) takes materially longer than a checklist line suggests | High | Medium (schedule slip, not correctness) | Step 14 is its own budgeted step with real time allocated, per both voices' explicit warning |
| CI-wiring follow-up ticket becomes a rubber stamp and the un-gated producer bit-rots silently | Medium | Medium | Step 17 requires a named owner and explicit revisit trigger, not just ticket existence |
| Cross-producer (LSP vs. MIR) naming collision reproduces the OCaml homonym bug class | Low-Medium | High (silent misattribution, the exact failure mode this whole project exists to prevent) | Step 6's qualified-path-identity requirement + step 15's dedicated check |

## Assumptions

- "Whole workspace" means one `cargo` workspace (one `[workspace]`-rooted `Cargo.toml`) discoverable
  in one wrapper invocation batch — not multiple independently-versioned repos glued together
  (Voice 1 A-1).
- The merge pass is a distinct executable/stage, invoked between all per-crate producer runs and
  the final `arch-load` ingestion — not a mode flag on `arch-callgraph-rust` itself (Voice 1 A-2,
  now made concrete by step 4's design-doc requirement rather than left implicit).
- A2's non-controversial plumbing (mono-item collection, NDJSON scaffolding, CLI parsing) may be
  reused/ported once cleared by step 2/3's fresh review — the DO-NOT-MERGE verdict bans merging the
  branches' defects wholesale, not all code reuse (Voice 1 A-4).
- Third-party crates.io dependency impls of a workspace-defined trait are out of scope for US-2 and
  fall under the same MAY_TOP-by-default reasoning as the publish-boundary gate (Voice 1 A-6).
