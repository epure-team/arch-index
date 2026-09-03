# Intake Brief — rust-soundcg-whole-program

**Date:** 2026-09-03
**Status: VALIDATED**
**Type:** feature
**Trust boundary:** no

## Goal

Land a sound, whole-program-aware Rust MIR call-graph producer (`arch-callgraph-rust`) into the
main repo. Two prior branches (`feat/rust-soundcg-a1` — walking-skeleton MIR driver with a blanket
`MAY_TOP` fallback; `feat/rust-soundcg-a2` — adds CHA/RTA trait-impl enumeration, narrowing
`MAY_TOP` to `MAY_ENUMERATED` for closed, bounded trait dispatch) exist as unmerged worktrees and
were both marked **DO-NOT-MERGE, 5 CRITICALs** by a prior review. Only one of those five findings
is documented anywhere retrievable (see Architecture Notes): A2's `trait_impls_of` call is scoped
to a single crate compilation (`TyCtxt`'s own extern-crate dependency closure), so it silently
misses trait impls that live in a sibling or downstream crate — a net soundness regression for any
trait implementable outside the crate being analyzed, versus A1's safe (if imprecise) blanket
`MAY_TOP` for all trait/generic dispatch.

The roadmap's design decision (made 2026-09-02, not re-litigated here): commit to **whole-program**
analysis mode for trait-impl resolution, rather than keeping per-crate analysis with a `MAY_TOP`
fallback for downstream-visible traits. This closes the soundness gap by construction — the
resolver must see every crate's impls, not just the current compilation's.

## Scope Boundary

What is explicitly OUT of scope:
- Discovering the exact text of the other 4 "CRITICAL" findings from the original review. No
  review artifact for either branch exists anywhere retrievable — not in `gh pr list`/`issue
  list`, not in `briefs/`, not committed to either worktree branch (confirmed by research; see
  `roster/rust-soundcg-whole-program/research.md` Question 3). Re-deriving them by archaeology is
  not attainable. Instead: this task's own `/roster-review` phase performs a full, fresh
  adversarial review of the resulting implementation (reviewer + architect specialists, same
  process used for issue #41), which will surface whatever remains wrong on its own merits,
  documented findings or not. The plan phase must not assume any specific subset of "4 more fixes"
  is required — it must treat the whole producer as needing full-scrutiny review, full stop.
- Full Charon/Aeneas-based alternative producer path — `docs/rust-sound-callgraph-design.md`
  already evaluated and rejected this (Charon doesn't support `dyn Trait` and silently drops
  untranslatable declarations); the `rustc_private` MIR driver approach (what A1/A2 already build)
  is the settled direction and is not reopened here.
- The separate, already-existing rust-analyzer LSP call-hierarchy path
  (`lib/arch_index/call_graph_extractor.ml`, `tezt/tests/lsp_languages.ml`) — this remains a
  distinct, intentionally under-approximate path for IDE-style queries; this task does not modify
  it, only adds the new sound MIR producer alongside it (mirroring how `callgraph-go` and the OCaml
  CMT path coexist with their own LSP paths).
- CI wiring for the new producer's toolchain (installing the pinned nightly + `rustc-dev` in
  GitHub Actions) — flagged as a likely follow-up requirement but not committed to as in-scope
  here; the plan phase should explicitly decide whether it's required for this PR to merge or can
  be a documented follow-up (`callgraph-go`'s CI wiring pattern is the reference if needed).

## Relevant Files

| File | Role | Key snippet |
|---|---|---|
| `/mnt/ssd-external-2to/arch-index-wt-rust-a1/callgraph-rust/src/main.rs` | Branch A1: walking-skeleton MIR driver, blanket `MAY_TOP` for all trait/generic/fn-ptr dispatch. Strong reference for the sound skeleton (never-drop invariant, FR-002) | `classify_callee` (`:230-307`): `InstanceKind::Virtual(..) => Callee::Top { name: TOP.to_string() }` |
| `/mnt/ssd-external-2to/arch-index-wt-rust-a2/callgraph-rust/src/main.rs` | Branch A2: adds CHA/RTA trait-impl enumeration. Contains the per-crate `trait_impls_of` defect this task fixes, and the `MAY_ENUMERATED` precision logic to preserve | `enumerate_impls` (`:406-441`): `let impls = tcx.trait_impls_of(trait_def_id);` — scoped to the current `TyCtxt` (one crate compilation) only |
| `/mnt/ssd-external-2to/arch-index-wt-rust-a2/callgraph-rust/Cargo.toml`, `rust-toolchain.toml` | Pinned nightly (`nightly-2026-06-20`, `rustc-dev`+`llvm-tools`+`rust-src` components) required to link `rustc_private`. Toolchain confirmed already installed locally (`rustup toolchain list`) | `channel = "nightly-2026-06-20"` |
| `/mnt/ssd-external-2to/arch-index-wt-rust-a2/selftest-callgraph-rust.sh` | End-to-end self-test: builds the driver, runs it against a controlled single-crate fixture, asserts sound MUST/MAY_TOP/MAY_ENUMERATED/UNREACHABLE verdicts via `arch-load`+`arch-query`. Reference for this task's own test harness — must be extended with a multi-crate fixture (none exists today, per research Q6) | Lines 33-195: fixture crate + assertions |
| `callgraph-go/main.go` | This repo's OWN precedent for whole-program analysis: `packages.Load(cfg, "./...")` (`:426`) loads the whole module once, feeding one `ssa.Program` (`:467`) that `cha.CallGraph` (`:500`) analyzes as a single unit. The Rust whole-program redesign should follow this repo's own established shape where the two languages' models allow it | `packages.Load(cfg, expanded...)` covering the whole module |
| `docs/rust-sound-callgraph-design.md` | Original design doc (2026-06-26, "design only") — root-cause analysis of the LSP path's under-approximation, rejection of Charon, and the `RUSTC_WORKSPACE_WRAPPER` per-crate integration model this task must extend to whole-program | §4 (~line 150): `RUSTC_WORKSPACE_WRAPPER` invocation design |
| `~/notes/2026-09-01-arch-index-roadmap.md` | Roadmap record: item 4.3, the only place the "5 CRITICALs" count and the one documented finding exist | Lines 46, 525 |

## Architecture Notes

**Why whole-program, not per-crate-plus-fallback.** `trait_impls_of` is a raw rustc query scoped
to the `TyCtxt` handed to one `rustc_driver::run_compiler` invocation. In the intended
`RUSTC_WORKSPACE_WRAPPER` integration mode, cargo re-invokes the producer once **per crate** in a
workspace — so a compilation of crate `X` only ever sees impls of `X`'s own traits that exist in
`X` itself or in `X`'s upstream dependency closure, never in a sibling or downstream crate. A2's
CHA/RTA enumeration (`enumerate_impls`) trusts this incomplete set as if it were closed, converting
what A1 safely treated as `MAY_TOP` into a false-precision `MAY_ENUMERATED` that can omit a real
callee entirely — the definition of a soundness regression.

**How rustc itself achieves whole-program impl visibility (per research Q7), and why this
producer can follow the same approach.** rustc's own coherence/orphan rules guarantee no two
crates can define conflicting impls of the same `(trait, type)` pair, which is what makes it safe
to treat every crate's impls as one merged set. rustc serializes each crate's own impls into its
compiled metadata (`.rmeta`), and a query against a crate that has that dependency **linked**
transparently decodes impls from every dependency's metadata blob — this already works correctly
for any crate that is an upstream dependency of the one being compiled. The gap is specifically
**downstream and sibling** crates, which are never linked into the compilation of the crate
defining the trait. Closing this requires driving compilation (or at least metadata loading) for
every crate in the workspace within one process/session — analogous to what `cargo metadata`
(research Q7) already exposes as the workspace's dependency graph, and analogous to what
`callgraph-go` already does for Go via `packages.Load("./...")`.

**Two independently-shippable slices, not one big-bang change.** The a1→a2 history already
establishes vertical-slice precedent: a1 is a safe, mergeable-on-its-own baseline (never wrong,
only imprecise); a2 adds precision on top. The plan phase should consider whether landing (a) a
corrected whole-program-aware skeleton first — even if it only restores A1-equivalent MAY_TOP
safety without new precision — and (b) whole-program CHA/RTA enumeration second, is a better
sequencing than one combined PR, given the size of this work (the original design doc's own
estimate: "2-4 focused days for a walking-skeleton MIR producer, more for full MAY_ENUMERATED
trait CHA").

**Multi-crate test fixture is a hard requirement, not optional.** Per research Q6, zero
multi-crate trait-resolution fixtures exist anywhere today — every existing selftest uses a single
temp crate. This task's own evidence bar must include a fixture with at least two crates where a
trait defined in crate A is implemented in crate B (a sibling of, or downstream from, the crate
whose compilation exercises the call site), proving the whole-program redesign actually resolves
across the crate boundary. Without this, the exact defect being fixed would ship with no
regression-proof test — the same class of gap issue #41's own plan explicitly guarded against for
the OCaml indexer.

## Quality Gates

```bash
# Build (from within callgraph-rust/, once landed in the main repo)
RUSTC_BOOTSTRAP=1 cargo build --release

# Tests — no unit-test harness exists yet in either branch; the existing evidence bar is the
# end-to-end selftest script driving the compiled binary through arch-load/arch-query:
./selftest-callgraph-rust.sh
```

Not documented anywhere as a single repo-wide command for this producer specifically, since it has
never been merged. The pinned toolchain (`nightly-2026-06-20`, components `rustc-dev`,
`llvm-tools`, `rust-src`) is already installed locally (confirmed via `rustup toolchain list`) —
no environment setup blocker for local implementation/review/QA. CI wiring for this toolchain is
explicitly out of scope per the Scope Boundary above, pending a plan-phase decision.

## Open Questions

_(none — the design direction, scope boundary around the undocumented findings, and the
multi-crate test requirement are all resolved above)_
