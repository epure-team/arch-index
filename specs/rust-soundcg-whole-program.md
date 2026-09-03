# Spec — whole-program trait-impl resolution for the Rust sound call-graph producer

Adversarial spec for landing `arch-callgraph-rust` (issue-tracked as roadmap item 4.3). Two prior
branches (`feat/rust-soundcg-a1`, `feat/rust-soundcg-a2`) were marked DO-NOT-MERGE; only one of
their 5 CRITICAL findings is documented anywhere retrievable (A2's `trait_impls_of` is scoped to a
single crate compilation, silently missing sibling/downstream-crate impls). This spec does not
attempt to reconstruct the other 4 — it states the properties the corrected design must satisfy,
so `/roster-review`'s fresh adversarial pass has something falsifiable to check against, the same
role `specs/sound-qualified-name-resolution.md` played for issue #41's homonym defect.

## Architecture decision (resolved during spec, not reopened by implementers)

**Post-process merge, not a single in-process whole-workspace compilation.** A `rustc_driver`
session (`TyCtxt`) is inherently scoped to one crate compilation; rustc itself achieves cross-crate
impl visibility only for a crate's own linked upstream dependencies, by decoding impls out of each
dependency's compiled metadata (`.rmeta`) at query time — this never covers sibling or downstream
crates, which are not linked into that session. A true single-process "whole-workspace `TyCtxt`"
is not a capability rustc's architecture offers (unlike rust-analyzer, which sidesteps rustc's
compilation pipeline entirely via its own from-scratch Salsa-based type inference). The producer
therefore uses the same two-phase shape this repo's own OCaml CMT indexer already uses for
cross-compilation-unit resolution (issue #41's write-then-resolve pattern): each crate's own
per-invocation walk emits its own defined trait impls as facts (trait path, `Self`-type path,
implementing method) alongside the existing MUST/MAY_TOP/MAY_ENUMERATED-within-crate edges; a
merge pass, run after all workspace crates have been visited, resolves cross-crate candidates
against the union of all crates' emitted facts.

**Merge scope: whole workspace, flat union, dependency-direction-agnostic.** For `unreachable`/
`reaches` verdicts, a workspace-wide flat union of trait impls (rather than a rust-analyzer-style
dependency-graph-aware walk restricted to a caller's transitive deps) is **sound but not maximally
precise**: including an impl from a crate the calling crate doesn't actually depend on can only add
a candidate that could never really be reached at that exact call site, which makes an
`unreachable` verdict *more* conservative (harder to wrongly claim UNREACHABLE), never less sound.
Precision losses from ignoring dependency direction are an accepted, documented tradeoff — not a
correctness defect — and may be tightened in a later slice.

**Publish-boundary safety gate (closes a soundness gap the challenge pass found, C-9).**
Workspace-scope enumeration is unsound for any trait whose defining crate can be depended on by
code outside the workspace itself (a published, or potentially-published, library crate) — an
external, unseen consumer crate could add another impl the workspace-wide union can never see,
and `MAY_ENUMERATED` would silently omit it. **MUST**: before narrowing any trait-dispatch site to
`MAY_ENUMERATED`, the merge pass checks the trait-defining crate's `Cargo.toml` for `publish =
false`; if that key is absent or not `false` (i.e. the crate is potentially publishable), every
call site dispatching on that trait stays `MAY_TOP`, unconditionally. This is a conservative,
mechanically-checkable proxy — it does not attempt sealed-trait/supertrait-privacy detection, which
is out of scope and documented below as a residual, matching this repo's existing precedent for
documented-but-unsolved residuals (`bin/arch_query/arch_query.ml`'s cross-module bare-name hazard).

**Missing-facts fallback (closes the single highest-value gap the challenge pass found, C-13).**
If the merge pass runs with an incomplete fact set for any workspace crate (that crate failed to
build, was excluded from the batch, or its facts are missing/stale for any reason), every trait
whose full impl set cannot be proven closed **MUST** fall back to `MAY_TOP` for every call site
that dispatches on it — the merge never proceeds with a possibly-incomplete `MAY_ENUMERATED`
verdict. This mirrors A2's own existing blanket-impl handling (`enumerate_impls` returns `None`,
never a partial `Some(candidates)`, when the set can't be proven closed) and prevents the merge
step from reproducing the exact soundness-regression class this whole task exists to fix.

## User Stories

### US-1: Sound whole-program-safe skeleton (Priority: P0)

As a user of `arch-query`'s `unreachable`/`reaches` verdicts over a Rust workspace, I want the new
`arch-callgraph-rust` producer to emit a never-drop, MUST/MAY_TOP-only call graph for any
multi-crate cargo workspace, so that every dynamic dispatch site (`dyn Trait`, generic trait
method, fn-pointer, FFI) is soundly anchored as `MAY_TOP` rather than silently dropped or falsely
enumerated — built fresh against this spec (not merged wholesale from the DO-NOT-MERGE branch),
validated against a real multi-crate workspace fixture.

**Why this priority:** this is the safety floor. It must be correct and shippable even if US-2
never lands — matching A1's own role as the safe, mergeable-on-its-own baseline.

**Scope:** Does NOT include cross-crate trait-impl enumeration (`MAY_ENUMERATED`) at the edge-kind
level — that's US-2. **Does** include emitting the intermediate per-crate trait-impl fact records
(trait path, `Self`-type path, implementing method, defining crate's `publish` flag) that US-2's
merge pass consumes — US-1 and US-2 are not fully independent (challenge C-12): US-1 must produce
these facts even though it does not yet act on them, or US-2 cannot be built as a pure
post-process addition later. Does NOT include CI wiring for the pinned nightly toolchain.

**Independent Test:** Run the producer against a 2-crate workspace fixture with a `dyn Trait` call
site; assert the edge is emitted as `MAY_TOP` (never dropped, never falsely resolved to `MUST`),
and that per-crate trait-impl fact records are emitted in the NDJSON stream even though no merge
step consumes them yet.

**Acceptance Scenarios:**
1. Given a 2-crate cargo workspace where crate B calls a `dyn Trait` method whose concrete
   implementing type is defined in crate A, when the producer runs via `RUSTC_WORKSPACE_WRAPPER`
   over the whole workspace, then the call site is emitted as a `MAY_TOP` edge.
2. Given a workspace with a direct (non-trait, non-generic) function call, when the producer
   runs, then the edge is emitted as `MUST` with the correct callee.
3. Given a workspace crate that fails to compile, when the producer's wrapper is invoked as part
   of `cargo build --workspace`, then the whole run's exit code is non-zero and no NDJSON output
   claims a complete graph for the workspace (partial success is reported, not silently accepted
   as complete) — this covers only crates the wrapper actually visits as part of the requested
   build target; an unrelated crate excluded by feature flags or build target selection is out of
   scope for this scenario (resolves challenge C-4).
4. Given an `extern "C"` call to a named (non-generic) external symbol, when the producer runs,
   then the edge is emitted as `MAY_TOP` with the symbol's name recorded (not the anonymous `*TOP*`
   sentinel), distinguishing "target named but body unanalyzable" from "target truly unknown"
   (resolves challenge C-7).

### US-2: Whole-program trait-impl enumeration (Priority: P1)

As a user of `arch-query`'s `unreachable` verdicts, I want dyn-dispatch trait-method call sites to
be narrowed from `MAY_TOP` to `MAY_ENUMERATED` whenever the full set of implementing types is
provably closed across the **whole workspace** (not just the current crate compilation) and the
trait is not externally-publishable (per the publish-boundary safety gate above), so that a trait
implemented in one crate and consumed via `dyn` dispatch in another crate — sibling or downstream —
produces a sound, precise candidate list that does not omit an impl living outside the compiling
crate.

**Scope:** Non-`dyn` generic trait-bound call sites (`fn f<T: Doer>(x: T)`) are explicitly **out of
scope** for this story — only `dyn Trait` dispatch sites are narrowed (resolves challenge C-14;
generic-bound narrowing is a documented future slice). Third-party (crates.io) dependency impls
are out of scope — workspace-member crates only. CI wiring is out of scope.

**Independent Test:** Run the producer against a 3-crate workspace (trait crate A, sibling-impl
crate B, downstream-impl crate D that depends on A but not on B) with a `dyn` dispatch call site in
a fourth crate C that depends on A only; assert `MAY_ENUMERATED` includes candidates from B and D
both, and that the workspace-flat-union semantics (not a C-must-depend-on-B requirement) is what
makes this correct per Rust's own value-flow rules — C only needs to depend on the trait's crate
(A) to receive and call a `dyn Doer`, never on the concrete implementor.

**Acceptance Scenarios:**
1. Given crate A defines trait `Doer`, crate B (a sibling of the crate compiling the call site,
   depending on A but not depended on by the caller) implements `Doer` for type `X`, and crate C
   calls `dyn Doer` where the concrete type could be `X`, when the whole-workspace merge completes,
   then the edge is `MAY_ENUMERATED` and includes `X::do_it` as a candidate.
2. Given the same setup but crate B is a transitive dependency of some crate other than the
   caller (the "downstream" case), when the whole-workspace merge completes, then the edge still
   includes `X::do_it` — the merge is dependency-direction-agnostic by design (resolves challenges
   C-10, C-17).
3. Given a trait with a blanket impl anywhere in the workspace, when the producer runs, then the
   edge for any dispatch on that trait stays `MAY_TOP` (never falsely narrowed) — this already
   holds within one crate per A2's existing logic (`enumerate_impls` returns `None` on any blanket
   impl) and MUST also hold when the blanket impl lives in a *different* workspace crate than the
   dispatch site (an extension the merge pass, not the single-crate walker, is responsible for).
4. Given a trait defined in a crate whose `Cargo.toml` does not set `publish = false`, when a
   `dyn` dispatch call site on that trait is analyzed anywhere in the workspace, then the edge
   stays `MAY_TOP` regardless of how closed the workspace-visible impl set is (the publish-boundary
   safety gate, resolves challenge C-9).
5. Given the merge pass runs while one workspace crate's facts are missing or known-stale, when a
   trait touched by that crate's facts is dispatched on anywhere in the workspace, then the edge
   stays `MAY_TOP` for that trait rather than proceeding with an incomplete candidate set (the
   missing-facts fallback, resolves challenge C-13).

## Falsifiers (what would prove the fix wrong)

- **F1** — any `dyn`/generic/fn-ptr/FFI call site that produces zero edges (dropped, not anchored)
  under any workspace shape. Never-drop is the one invariant that must hold unconditionally.
- **F2** — a `MAY_ENUMERATED` verdict that omits a real implementing type that exists anywhere in
  the workspace and satisfies the publish-boundary gate. This is the exact defect class A2 shipped.
- **F3** — a `MAY_ENUMERATED` verdict for a trait whose defining crate does not set `publish =
  false`. This is unsound regardless of how complete the workspace-visible impl set is.
- **F4** — a `MAY_ENUMERATED` verdict produced while any workspace crate's facts were missing or
  stale for the trait in question. The merge must fail closed to `MAY_TOP`, never proceed.
- **F5** — a fix that makes every dispatch site `MAY_TOP` unconditionally (satisfies F1-F4
  vacuously by deleting all precision). US-2's whole point is precision gain over US-1's baseline;
  a PR that regresses to US-1-only behavior while claiming US-2 is complete is rejected.
- **F6** — any change to the existing rust-analyzer LSP call-hierarchy path
  (`lib/arch_index/call_graph_extractor.ml`) or its tests. Explicitly out of scope; a diff touching
  it is a scope violation, not a legitimate part of this fix.

## Runnable Checks

- **CHECK-1** → US-1 AC-1/AC-2: multi-crate Tezt-or-shell fixture (2 crates) with a `dyn Trait`
  call site and a direct call site; assert `MAY_TOP` and `MUST` respectively via `arch-load`+
  `arch-query`, mirroring `selftest-callgraph-rust.sh`'s existing assertion style.
- **CHECK-2** → US-1 AC-3: a workspace fixture with one crate that intentionally fails to compile;
  assert the producer's/wrapper's overall exit code is non-zero.
- **CHECK-3** → US-1 AC-4: a fixture with a named `extern "C"` call; assert the emitted edge
  carries the symbol name, not the anonymous `*TOP*` sentinel.
- **CHECK-4** → US-2 AC-1/AC-2 (the hard requirement from intake): a 3-crate fixture (trait crate,
  sibling-impl crate, downstream-impl crate not depended on by the caller) with a `dyn` dispatch
  site in a fourth caller crate; assert `MAY_ENUMERATED` includes both the sibling's and the
  downstream's candidate.
- **CHECK-5** → US-2 AC-3: a fixture with a blanket impl living in a crate *other than* the
  dispatch-site crate; assert the edge stays `MAY_TOP`.
- **CHECK-6** → US-2 AC-4: a fixture where the trait-defining crate's `Cargo.toml` omits
  `publish = false`; assert `MAY_TOP` regardless of how closed the impl set otherwise looks.
- **CHECK-7** → US-2 AC-5: simulate a missing/excluded crate's facts in the merge input; assert
  every trait touched by that crate falls back to `MAY_TOP`, not a partial `MAY_ENUMERATED`.
- **CHECK-8** → F6 (scope guard): `git diff` over the shipped PR must not touch
  `lib/arch_index/call_graph_extractor.ml` or `tezt/tests/lsp_languages.ml`.

## Explicitly not specified here

- The other 4 undocumented CRITICAL findings from the original branch review — no artifact exists
  to spec against; `/roster-review`'s fresh full-scrutiny pass is the mechanism that substitutes
  for them (see the intake brief's Scope Boundary).
- Non-`dyn` generic trait-bound call sites (`fn f<T: Bound>`) — explicitly deferred past US-2.
- Sealed-trait/supertrait-privacy detection as a refinement on top of the publish-flag gate — the
  publish-flag check is a conservative, cheap proxy; a crate could still theoretically seal a
  public-looking trait such that no external impl is actually possible, in which case this design
  is more conservative (more `MAY_TOP`) than strictly necessary. Documented residual, not a defect.
- CI wiring for the pinned nightly toolchain (`nightly-2026-06-20`) — the plan phase decides
  whether this blocks merge or ships as a tracked follow-up; either way it must be an explicit
  ticket, not a silent gap (per the intake brief's clarification).
- Precision improvements from dependency-graph-aware (rather than flat-union) merge scoping — a
  documented future slice, not required for soundness (see Architecture decision above).
