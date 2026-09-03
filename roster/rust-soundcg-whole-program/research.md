# Research — rust-soundcg-whole-program

_Generated: 2026-09-03_
_Mode: full_
_Online research: enabled_

## Question 1: Where is `trait_impls_of` currently defined and implemented, and what scope of data (per-crate vs. cross-crate) does it currently traverse?

**Finding:** `trait_impls_of` is not defined anywhere in this codebase — it is the standard rustc query `tcx.trait_impls_of(trait_def_id)`. It is called exactly once, at `callgraph-rust/src/main.rs:412` on branch `feat/rust-soundcg-a2`, inside `enumerate_impls` (`main.rs:406-441`). It is not called at all on `feat/rust-soundcg-a1` (only referenced in a comment marking the future extension point, `main.rs:288`), and there is no `callgraph-rust` directory in the main repo at all — this producer has never been merged.

`enumerate_impls` takes `tcx: TyCtxt<'tcx>` and a single `trait_def_id: DefId`. `tcx` is the `TyCtxt` handed to `CallgraphCallbacks::after_analysis` (`main.rs:652-661`), which fires once per `rustc_driver::run_compiler` invocation. The binary is designed to run either directly on one file or, in its intended integration mode, as a `RUSTC_WORKSPACE_WRAPPER` (design doc comment, `main.rs:667-696`): cargo re-invokes it once **per crate** in the workspace. Each `tcx`/`trait_impls_of` call is therefore scoped to a single compilation session (one crate plus its transitively-linked extern-crate dependency metadata) — not a merged, workspace-wide multi-crate view. A downstream or sibling crate that adds another impl of an upstream-defined trait is invisible to a compilation of that upstream crate, since the downstream crate isn't compiled/linked into that session.

The `rta` argument to `enumerate_impls` is `RtaTypes` (`main.rs:462-478`), built once per crate compilation in `build_rta_types` (`main.rs:485-507`) by walking the mono items from `tcx.collect_and_partition_mono_items(())` (`main.rs:590`, called at `main.rs:628`) — again entirely within that one crate compilation's reachable-instance set.

**References:**
- `callgraph-rust/src/main.rs:412` (branch `feat/rust-soundcg-a2`, worktree `/mnt/ssd-external-2to/arch-index-wt-rust-a2`) — the sole `tcx.trait_impls_of(trait_def_id)` call site, inside `enumerate_impls`
- `callgraph-rust/src/main.rs:288` (branch `feat/rust-soundcg-a1`) — comment-only reference, not called
- `callgraph-rust/src/main.rs:652-661,667-696` (a2) — `CallgraphCallbacks::after_analysis`, `RUSTC_WORKSPACE_WRAPPER` design comment
- `callgraph-rust/src/main.rs:462-507,590,628` (a2) — `RtaTypes`, `build_rta_types`, mono-item collection, all scoped to one crate compilation
- Main repo `/home/mathias/dev/arch-index`: no `callgraph-rust` directory exists (confirmed via `find`); only `docs/rust-sound-callgraph-design.md` documents the intended design

---

## Question 2: What data structures or abstractions already exist for representing multiple crates or a whole-program view, and are any already used elsewhere for cross-crate lookups?

**Finding:** No workspace/dependency-graph/session abstraction spanning multiple crates exists anywhere in the Rust code (main repo or either worktree) — `callgraph-rust` has no notion of "other crates" beyond what rustc's own crate-metadata loading gives a single `TyCtxt` for free (its extern-crate dependency closure).

By contrast, this repo's **Go** producer already implements a genuine cross-package, whole-module view: `packages.Load(cfg, expanded...)` (`callgraph-go/main.go:426`) is called once, covering the whole module via `"./..."` (comment at `main.go:400`); the resulting packages feed one `ssa.Program` (`prog.AllPackages()` at `main.go:467`); and `cha.CallGraph(prog)` (`main.go:500`) does class-hierarchy analysis over that single whole-program SSA representation. Cross-package/cross-file CHA is already a first-class, exercised pattern in this repo — just in the Go analyzer, not Rust.

The **OCaml** producer (`bin/arch_callgraph_ocaml/arch_callgraph_ocaml.ml`, 52 lines) is a thin driver; it does not itself implement a multi-module merge in-process. Cross-module joining for OCaml happens by walking each `.cmt` file's typedtree independently and relying on the SQL database (`lib/arch_db`, `architecture-schema.sql`) as the place where per-compilation-unit outputs are merged into one graph — not an in-process whole-workspace type/session object.

The design doc `docs/rust-sound-callgraph-design.md` (dated 2026-06-26, "design only") already frames the intended future integration as the `RUSTC_WORKSPACE_WRAPPER` mode "so deps are compiled too" (§4) — i.e., it anticipates per-crate invocation with dependency-closure visibility, not a merged multi-crate `tcx`.

**References:**
- `callgraph-go/main.go:400,426,467,500` — whole-module `packages.Load`, single `ssa.Program`, whole-program CHA
- `bin/arch_callgraph_ocaml/arch_callgraph_ocaml.ml` — thin per-file driver; `lib/arch_db`, `architecture-schema.sql` — DB-level cross-unit merge
- `docs/rust-sound-callgraph-design.md` §4 (~line 150) — `RUSTC_WORKSPACE_WRAPPER` integration design, per-crate invocation model

---

## Question 3: What are the 5 CRITICAL findings recorded in the prior review of `feat/rust-soundcg-a1`/`a2`, and where are they documented?

**Finding:** Only the count ("5 CRITICALs") and one substantive finding (the `trait_impls_of` per-crate soundness gap) are recorded anywhere discoverable — in `~/notes/2026-09-01-arch-index-roadmap.md` (lines 46, 525). No PR, issue, or `briefs/*review.json`/`.md` artifact exists for either branch: `gh pr list`/`gh issue list` against `epure-team/arch-index` searching for "rust soundcg"/"rust soundcg trait" return nothing, and no review file exists in either worktree or the main repo. The other 4 CRITICAL findings are **not documented anywhere retrievable** — they are referenced only by count in the roadmap, with no itemization.

**References:**
- `~/notes/2026-09-01-arch-index-roadmap.md:46,525` — "DO-NOT-MERGE, 5 CRITICALs" and the `trait_impls_of` per-crate finding; no other detail
- `gh pr list -R epure-team/arch-index --search "rust soundcg"` — no results
- `gh issue list -R epure-team/arch-index --search "rust soundcg trait"` — no results
- No `briefs/*rust*review*` file exists in `/home/mathias/dev/arch-index`, and no review artifact is committed to either worktree branch

**Gap flagged for the intake/plan phase:** since 4 of the 5 CRITICALs are not discoverable in any written record, a fresh review pass over both branches (independent of this research) will likely be needed before a complete implementation plan can be written — this cannot be resolved by more research, only by re-reviewing the branches' current code directly.

---

## Question 4: How does the existing MAY_TOP fallback mechanism work, and where is it invoked?

**Finding:** Both branches define `enum Callee` with a `Top { name: String }` variant; `TOP` is the sentinel string `"*TOP*"`. `emit.call(...)` records a `Top` callee with `kind = "MAY_TOP"`, counted in `Emitter`'s `n_may_top`.

**Pre-A2 baseline (branch `feat/rust-soundcg-a1`):** every trait-method call that isn't uniquely resolved goes straight to `Callee::Top` — two sites: `InstanceKind::Virtual(..) => Callee::Top { name: TOP.to_string() }` (`main.rs:289`, `dyn Trait` vtable dispatch) and `Ok(None) => Callee::Top { name: TOP.to_string() }` (`main.rs:301`, unresolved generic/associated-item call). No trait CHA/enumeration exists in a1; `trait_impls_of` is referenced only as a comment marking a future extension point.

**Branch `feat/rust-soundcg-a2`:** the same two sites now call into CHA/RTA enumeration instead of going straight to `Top`: `InstanceKind::Virtual(method_def_id, _) => enumerate_trait_method(tcx, method_def_id, rta)` (`main.rs:322`) and `Ok(None) => enumerate_unresolved(tcx, *def_id, args, rta)` (`main.rs:336`). `enumerate_trait_method` (`main.rs:359-383`) still falls back to `Callee::Top` in three cases: the method isn't a trait item (`tcx.trait_of_assoc` returns `None`), the RTA-filtered candidate set comes back empty (to avoid silently dropping the site), or `enumerate_impls` returns `None` because a blanket impl is reachable (`main.rs:416`) or a candidate can't be resolved to a concrete method. Outside trait dispatch, `Callee::Top` is still used identically to a1 for foreign items, intrinsics, resolution errors, fn-pointers, and any other non-`FnDef` operand — neither branch ever removes an edge (an FR-002 "never-drop" invariant stated in both files' module doc comments).

Net effect: A2 narrows the trait-dispatch/unresolved-generic slice of MAY_TOP into MAY_ENUMERATED whenever the candidate impl set is provably closed and bounded (no blanket impl, every candidate resolvable, RTA-reachable Self type); everything else remains MAY_TOP in both branches.

**References:**
- `callgraph-rust/src/main.rs:227-234,246-258` (a1/a2) — `Callee` enum definitions
- `callgraph-rust/src/main.rs:166,568-577` (a2) — `TOP` sentinel, `Emitter`, `n_may_top`
- `callgraph-rust/src/main.rs:289,301` (a1) — pre-A2 baseline fallback sites
- `callgraph-rust/src/main.rs:322,336,359-383,406-441` (a2) — A2's CHA/RTA enumeration and remaining fallback cases

---

## Question 5: What does A2 do with `trait_impls_of`'s output, and what consumes it?

**Finding:** `enumerate_impls` (`main.rs:406-441`, a2) turns the raw `tcx.trait_impls_of` result into `Option<Vec<Candidate>>`: for each RTA-reachable, non-blanket impl it maps the trait method to the impl's concrete method via `tcx.impl_item_implementor_ids(impl_def_id)`, falling back to the trait's own default-method `DefId` when the impl doesn't override it, dedups by `DefId`, and builds one `Candidate { name, file }` per surviving impl.

That `Vec<Candidate>` flows up through `enumerate_trait_method` → `classify_callee` as `Callee::Enumerated { candidates }`, which `walk_instance` (`main.rs:543-583`) matches on: for each candidate it calls `emit.call(..., "MAY_ENUMERATED")` once — one edge per enumerated impl method, all sharing the same caller/call-site but distinct callee names/files.

There is exactly one consumer chain in the whole codebase: `trait_impls_of` → `enumerate_impls` → `enumerate_trait_method`/`enumerate_unresolved` → `classify_callee` → `walk_instance` → `Emitter::call` (NDJSON records) → stdout, meant to be piped to `arch-load` and queried by `arch-query`. No other analysis pass and no other producer (Go/OCaml) currently reads or depends on `trait_impls_of`'s output — the main repo has no `callgraph-rust` code at all yet, so this entire chain exists only on the unmerged `feat/rust-soundcg-a2` branch.

**References:**
- `callgraph-rust/src/main.rs:406-447` (a2) — `enumerate_impls`'s candidate construction
- `callgraph-rust/src/main.rs:371,543-583` (a2) — `Callee::Enumerated` propagation, `walk_instance`'s per-candidate `emit.call`
- `callgraph-rust/src/main.rs:8-12` (a2) — module doc describing the NDJSON output format and intended `arch-load`/`arch-query` consumption

---

## Question 6: What test coverage/fixtures exist for trait implementation resolution (single- and multi-crate)?

**Finding:** No multi-crate test fixtures currently exist anywhere in this repo or either worktree. All Rust trait-resolution tests use single-crate fixtures:

- **`feat/rust-soundcg-a1`**: `selftest-callgraph-rust.sh` builds one temp testcrate with a `Doer` trait (impls `A`, `B`), asserting static dispatch is MUST, `dyn Doer` dispatch and fn-pointer calls are MAY_TOP, and a disconnected function (`island`) is soundly UNREACHABLE — plus an FR-002 never-drop check (every dynamic site appears as an edge) and a loud-fail-on-broken-build check.
- **`feat/rust-soundcg-a2`**: `selftest-callgraph-rust.sh` extends the same fixture so `dyn Doer` dispatch enumerates MAY_ENUMERATED over `{A, B}`, asserts a previously-UNKNOWN unreachability verdict becomes decidable (UNREACHABLE) once the dyn frontier is bounded, and confirms fn-pointer/FFI calls remain MAY_TOP.
- **Main repo**: `tezt/tests/lsp_languages.ml:161-223` tests the separate, under-approximate rust-analyzer LSP callHierarchy path (module nesting, `edges ≥ 1` regression guard) — this is not the MIR-based producer and has no ⊤ contract or unreachability verdicts.

No fixture in either worktree or the main repo exercises a trait implemented in one crate being called from, or resolved against, a second crate.

**References:**
- `selftest-callgraph-rust.sh:33-110` (branch `feat/rust-soundcg-a1`)
- `selftest-callgraph-rust.sh:33-195` (branch `feat/rust-soundcg-a2`)
- `tezt/tests/lsp_languages.ml:161-223` (main repo)

---

## Question 7 [ecosystem]: How do existing Rust compiler-analysis tools gather and represent trait implementations across a multi-crate workspace?

**Finding — rustc's own coherence/orphan rules make whole-program impl visibility safe by construction.** Every trait impl must satisfy the orphan rule (trait or a covered type local to the defining crate), which guarantees no two independently-compiled crates can define conflicting impls of the same (trait, type) pair — `rustc_trait_selection::traits::coherence` implements this via `InCrate::Local`/`InCrate::Remote` checks.

**Finding — rustc serializes impls into crate metadata for cross-crate visibility.** Once an impl passes coherence in its defining crate, rustc serializes it into that crate's compiled metadata (`.rmeta`/`.rlib`) via `rustc_metadata::rmeta::encoder::EncodeContext::encode_incoherent_impls()` and the `CrateRoot`/`IncoherentImpls` structures. A downstream crate's `trait_impls_of` query transparently decodes impls out of every dependency's metadata blob (via `CrateMetadataRef::get_incoherent_impls()`) rather than re-analyzing dependency source — `TyCtxt::all_impls` iterates all implementations of a trait across the whole compiled dependency set this way. This is the mechanism that makes rustc's own view "whole-program" without needing to re-parse anything.

**Finding — rust-analyzer builds its own separate cross-crate index via Salsa, not rustc metadata.** It defines `TraitImpls`/`InherentImpls` structures and two queries: `trait_impls_in_crate_query` (walks one crate's def map) and `trait_impls_in_deps_query` (iterates `crate_graph.transitive_deps(krate)` and unions each dependency's per-crate index bottom-up through the dependency DAG). *(Note: this citation is pinned to a 2021-era commit; current rust-analyzer source may have since renamed these exact identifiers amid an ongoing migration toward sharing trait-solver internals with rustc via `rustc_type_ir`/`rustc_next_trait_solver` — treat the architecture as representative, not the exact names as current.)*

**Finding — `cargo metadata` exposes the dependency graph, but not impl bodies.** Its `resolve` object gives every resolved crate id and its dependency edges (`--format-version 1` is the only stable version); a third-party tool can use it to enumerate every crate in a workspace and locate each one's source, but must still run its own per-crate extraction — `cargo metadata` supplies only the graph and manifest data.

**Finding — rustdoc JSON is explicitly documented as NOT reliably whole-program for trait impls.** `rustdoc --output-format json` (RFC 2963) emits `Impl` items per crate, but multiple sources (a live rust-lang/rust issue, and cargo-semver-checks' own 2025/2026 documentation) confirm a crate's JSON only reliably contains impls "local" to that crate; wholly-foreign impls (both trait and type defined elsewhere) may be dropped. cargo-semver-checks states it "is currently incapable of following the cross-crate connection to another_crate, generating its rustdoc JSON, and continuing its analysis there" — no existing rustdoc-JSON-based tool automatically stitches together a whole-dependency-graph merged trait-impl index today.

**Contradiction/uncertainty flagged by the researcher:** no source directly reconciles rustc's own complete, coherence-checked cross-crate impl visibility (via metadata decoding) with rustdoc JSON's documented cross-crate incompleteness — these are different pipelines serving different purposes, and a tool wanting rustc's complete view would need to hook the compiler's own query system (as `callgraph-rust` already does via `TyCtxt`), not rustdoc JSON. This bridging inference is the researcher's own, not a claim any single source made explicitly.

**References:**
- https://doc.rust-lang.org/stable/nightly-rustc/rustc_trait_selection/traits/coherence/index.html — coherence/orphan-rule implementation
- https://rust-lang.github.io/rfcs/2451-re-rebalancing-coherence.html — RFC 2451
- https://doc.rust-lang.org/nightly/nightly-rustc/rustc_metadata/rmeta/encoder/struct.EncodeContext.html — metadata encoding of impls
- https://doc.rust-lang.org/beta/nightly-rustc/rustc_metadata/rmeta/struct.CrateRoot.html — `CrateRoot`
- https://doc.rust-lang.org/stable/nightly-rustc/rustc_middle/ty/trait_def/struct.TraitDef.html — `TraitDef`/`TraitImpls`
- https://rustc-dev-guide.rust-lang.org/backend/libs-and-metadata.html — libraries and metadata guide
- https://github.com/rust-lang/rust-analyzer/blob/e131bfc747df1b21ae6ea04eb9c55001e06b7bf0/crates/hir_ty/src/method_resolution.rs — rust-analyzer's cross-crate index (2021-era commit, architecture illustrative only)
- https://rustc-dev-guide.rust-lang.org/solve/sharing-crates-with-rust-analyzer.html — shared trait-solver migration
- https://doc.rust-lang.org/cargo/commands/cargo-metadata.html — `cargo metadata`
- https://docs.rs/cargo_metadata/latest/cargo_metadata/struct.Resolve.html — `Resolve`/`Node`
- https://rust-lang.github.io/rfcs/2963-rustdoc-json.html — RFC 2963 rustdoc JSON
- https://github.com/rust-lang/rust/issues/100252 — documented cross-crate rustdoc JSON incompleteness
- https://predr.ag/blog/cargo-semver-checks-2025-year-in-review/ — cargo-semver-checks' explicit single-crate-JSON limitation statement
