# Implementer Brief — rust-soundcg-whole-program

**Date:** 2026-09-03
**Status: VALIDATED**

## Goal

Land a sound, whole-program-aware Rust MIR call-graph producer (`arch-callgraph-rust`) into
`/home/mathias/dev/arch-index`, built fresh against `specs/rust-soundcg-whole-program.md` (not a
wholesale merge of the DO-NOT-MERGE `feat/rust-soundcg-a1`/`feat/rust-soundcg-a2` branches).
Two independently-shippable slices: US-1 (P0, sound MUST/MAY_TOP-only skeleton, plus emitting the
trait-impl fact records US-2 will consume) and US-2 (P1, whole-program `dyn`-dispatch enumeration
via a post-process merge pass over those facts).

## Scope Boundary

Out of scope (do not touch):
- `lib/arch_index/call_graph_extractor.ml`, `tezt/tests/lsp_languages.ml` — the existing
  rust-analyzer LSP call-hierarchy path. **CHECK-8 is an automated `git diff` guard on this** —
  any diff touching either file is a scope violation, not a legitimate part of this fix.
- Discovering/reconstructing the other 4 undocumented CRITICAL findings by archaeology — instead,
  step 2 below runs a fresh adversarial review of the current A1/A2 code and step 3 triages it.
- The Charon/Aeneas alternative producer path (already rejected, `docs/rust-sound-callgraph-design.md`).
- Non-`dyn` generic trait-bound narrowing, sealed-trait/supertrait-privacy detection, dependency-
  graph-aware (vs. flat-union) merge precision, feature-powerset analysis — all explicitly deferred
  per the spec and this plan's Decisions table. Do not attempt any of these; document as follow-ups.
- CI wiring for the pinned nightly toolchain is not required to land this PR, but step 17 (below)
  — an explicit ticket with a named owner and revisit trigger — **is** required before this task
  is done.

`arch_load.ml` **may** be modified if the new trait-impl-fact NDJSON record type requires it (e.g.,
tolerating an unrecognized record kind gracefully) — this is confirmed in-scope, not a violation
of the scope guard above (which only covers the two LSP-path files named).

## Relevant Files

| File | Role |
|---|---|
| `/mnt/ssd-external-2to/arch-index-wt-rust-a1/callgraph-rust/src/main.rs` | Reference for the safe skeleton: `classify_callee` (`:230-307`) — blanket `MAY_TOP` for `dyn`/generic/fn-ptr. Port only after step 2/3 clears it. |
| `/mnt/ssd-external-2to/arch-index-wt-rust-a2/callgraph-rust/src/main.rs` | Reference for CHA/RTA precision: `enumerate_impls` (`:406-441`, contains the known per-crate `trait_impls_of` defect — do not port this function as-is), `build_rta_types` (`:485-507`), `Callee`/`Candidate` types. |
| `/mnt/ssd-external-2to/arch-index-wt-rust-a2/{Cargo.toml,rust-toolchain.toml}` | Pinned nightly reference (`nightly-2026-06-20`, `rustc-dev`+`llvm-tools`+`rust-src`) — confirmed already installed locally. |
| `/mnt/ssd-external-2to/arch-index-wt-rust-a2/selftest-callgraph-rust.sh` | Single-crate selftest reference style — extend with multi-crate fixtures (step 14), don't just append to this file if a cleaner multi-crate harness is warranted. |
| `callgraph-go/main.go` | This repo's own whole-module precedent (`packages.Load(cfg, "./...")` → one `ssa.Program` → `cha.CallGraph`) — cited in the spec's architecture rationale. |
| `lib/arch_index/arch_load.ml` (or equivalent loader) | May need a tolerant-unknown-record-kind change for the new fact-record NDJSON type — confirmed in-scope. |
| `specs/sound-qualified-name-resolution.md` | Prior art for the cross-producer naming risk (step 6/15) — read this before implementing name qualification. |
| `docs/rust-sound-callgraph-design.md` | Original design doc; do not reopen its Charon-rejection or `RUSTC_WORKSPACE_WRAPPER` decisions. |

## Sequential Steps

Follow `briefs/rust-soundcg-whole-program-plan.md`'s 19 numbered steps exactly; summarized:

1. Nightly-pin sanity build check (A1 and A2 as committed) — stop and report if either fails to build.
2. Fresh adversarial review of current A1/A2 code (spawn reviewer+architect specialists) to surface the 4 undocumented CRITICALs.
3. Triage those findings against the spec's settled architecture; escalate (do not silently override) if any contradicts a settled spec decision.
4. Write the merge-pass fact-format design doc (on-disk format, batch-completeness manifest) **before** any US-2 coding.
5. Scaffold `callgraph-rust/` fresh in the main repo; port only triage-cleared plumbing from A1/A2.
6. Per-crate MUST/MAY_TOP walk (US-1 core) — fully-qualified DefId-derived names throughout (closes the cross-producer naming risk).
7. `RUSTC_WORKSPACE_WRAPPER` integration + loud-fail scoped to crates the wrapper actually visits.
8. Emit per-crate trait-impl fact records per step 4's format (unused until step 10, per spec's explicit US-1/US-2 coupling).
9. 2-crate fixture, CHECK-1/2/3 green — US-1 is independently shippable at this point.
10. Merge-pass implementation (US-2 core), standalone stage per step 4's design.
11. Publish-boundary gate (`publish = false` check) — document explicitly as a weak, accepted-residual proxy, not a full guarantee.
12. Missing-facts fallback using step 4's completeness marker — document the cache-staleness operational consequence in the producer's README.
13. Cross-crate blanket-impl detection + RTA union extension (union of RTA-reachable types across all workspace crates, not just the caller's own).
14. Multi-crate fixture infrastructure (sibling, downstream, cross-crate blanket, missing-facts) — its own real budget, not a checklist afterthought.
15. Cross-producer naming check (CHECK-9, new).
16. Scope guard (CHECK-8) wired into the same check run as everything else, from early on.
17. CI-wiring decision ticket: named owner, explicit revisit trigger.
18. Docs: README states the accepted residuals plainly (cache-staleness, publish-flag weakness, single-feature-set scope); file the deferred items as tracked follow-ups.
19. Full check run (CHECK-1..9), then hand off to `/roster-review`.

## Accepted residuals (state these explicitly in code comments/README, do not silently omit)

Per an explicit human decision during planning (not to be re-litigated by the implementer):
- **Cache-staleness precision cost**: `MAY_ENUMERATED` only reliably narrows immediately following
  a full workspace rebuild; an incremental re-index conservatively degrades most cross-crate
  candidates to `MAY_TOP` via the missing-facts fallback. This is a documented operational
  requirement for precise results, not a bug to fix in this task.
- **Publish-boundary gate weakness**: the `publish = false` Cargo.toml check is a cheap, gameable
  proxy — it does not detect path/git-dependency consumption outside the analyzed cargo session.
  State this plainly; do not claim a stronger guarantee.
- **Single-feature-set scope**: the producer analyzes exactly one resolved feature/cfg graph per
  invocation; a trait impl gated behind a disabled feature is invisible. Feature-powerset analysis
  is out of scope.

## Quality Gates

```bash
# From within callgraph-rust/
RUSTC_BOOTSTRAP=1 cargo build --release

# End-to-end (extend, don't just append to, selftest-callgraph-rust.sh per step 14)
./selftest-callgraph-rust.sh
```

Pinned toolchain `nightly-2026-06-20` (`rustc-dev`, `llvm-tools`, `rust-src`) confirmed already
installed locally (`rustup toolchain list`).

## Risks and Assumptions (carried from the plan)

- Nightly pin may have bit-rotted since 2026-06-20 — step 1 surfaces this immediately.
- One of the 4 undocumented CRITICALs may be structural, affecting the shared MIR-walk core both
  US-1 and US-2 depend on — step 2/3's triage exists specifically to catch this before scaffolding
  locks in a shape.
- Multi-crate fixture engineering (hermetic `RUSTC_WORKSPACE_WRAPPER` firing across cargo cache
  states, reproducibly, in a bash selftest) is likely the long pole — both dual-voice reviewers
  independently warned against underestimating this.
- "Whole workspace" = one `cargo` `[workspace]`-rooted `Cargo.toml` in one wrapper batch (Voice 1
  A-1). The merge pass is a distinct stage, not a mode flag (Voice 1 A-2). A2's non-controversial
  plumbing may be reused once step 2/3 clears it (Voice 1 A-4).
