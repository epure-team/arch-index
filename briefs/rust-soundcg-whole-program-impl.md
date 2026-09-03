# Implementation Brief — rust-soundcg-whole-program

**Date:** 2026-09-03
**Mode:** full
**Status:** COMPLETED — all 19 plan steps done; two accepted deviations from the plan's literal
wording are documented below (RTA-type-reachability union not implemented; no standalone
fact-format design doc as a separate file) rather than silently absorbed.

## Loop-back round (post-QA NO-GO)

`briefs/rust-soundcg-whole-program-qa.md` (round 1) found CHECK-6's own explicitly-flagged
"easy-to-miss" scenario — `[workspace.package] publish = false` + a member's
`publish.workspace = true` — resolved to `publish_false: false` instead of `true`. Root cause:
`toml_publish_false` matched the literal substring `"true"` inside `"publish.workspace = true"`
and returned before the caller's dedicated workspace-inheritance walk
(`toml_key_is_workspace_true`) ever ran — dead code for the single most common real-world Cargo
idiom for `publish = false` across a workspace. Fixed in `callgraph-rust/src/main.rs`'s
`toml_publish_false` (skip any `publish`-line containing `.workspace`, returning `None` so the
caller's inheritance walk actually executes) — commit `1688a92`.

**Separately discovered and fixed in the same commit:** the prior review round's `review.json`
had marked a CRITICAL finding (the comment-parsing false positive: `publish = true  # was false
before` misread as `publish=false`) `RESOLVED`, but the corresponding code edit was never actually
applied — a real process failure on my part, caught only while re-reading the function to fix the
QA-round bug above. Both `toml_publish_false` and `toml_key_is_workspace_true` now strip any
trailing `#` comment before scanning. Both fixes independently verified against fresh fixtures and
folded into `selftest-callgraph-rust.sh` as permanent regression scenarios 9 and 10.

## Where the work lives

Worktree `/tmp/claude-1000/-home-mathias-dev-arch-index/14fbc421-dfc7-4b31-91d6-c084baeb45e0/scratchpad/wt-rustcg`,
branch `feat/rust-soundcg-whole-program`, HEAD `3cb0e46` (10 commits since `2592c77`). `git status
--porcelain` is empty (round-commit rule satisfied). `git diff --stat 2592c77 HEAD` touches only
`.gitignore`, `arch-callgraph-rust`, `bin/arch_callgraph_rust_merge/*`, `callgraph-rust/*`,
`selftest-callgraph-rust.sh` — CHECK-8's scope guard (`lib/arch_index/call_graph_extractor.ml`,
`tezt/tests/lsp_languages.ml` untouched) is clean.

## What happened this round (continuing from the round-1 PARTIAL checkpoint)

Round 1 (commit `c08190e`, documented in this file's prior version) delivered US-1: the corrected
single-crate MIR walker, with 4 CRITICALs + 2 HIGHs + several MEDIUM/LOW fixed and empirically
verified. This round completed US-2 (plan steps 10-19):

1. **Reverted a wrong-file fix** (`git revert --no-edit f22d649`) — `lib/arch_db/arch_load.ml` is
   dead code (no binary references `Arch_db.Arch_load`); the real, strictly-validating loader is
   `bin/arch_load/arch_load.ml`, confirmed **not** to need any change, since the merge pass strips
   `trait_impl_fact` records and the `x_dyn_*` extension fields before its output ever reaches it.
2. **Added crate-independent identity for dyn-dispatch narrowing** (`stable_def_path`,
   `Callee::DynDispatch`/`Emitter::call_dyn`, `is_blanket` detection) — fixed two bugs found only
   by inspecting real 2-crate fixture NDJSON, not by code reading: trait-path rendering was
   crate-relative (broke cross-crate joins), and the publish-boundary check read the wrong crate's
   `Cargo.toml` (the impl-providing crate's, not the trait-defining crate's).
3. **Added `impl_fn_stable_name`** to `trait_impl_fact` plus a matching `function` row — needed
   because the single-crate walker's own per-instance name rendering is crate-relative and cannot
   be reconstructed post-hoc from `trait_path` + `self_type_path` alone; the merge pass needs a
   name it can synthesize a `MAY_ENUMERATED` `callee_name` from that is guaranteed to resolve to a
   real function node.
4. **Renamed `dyn_trait`/`dyn_method` to `x_dyn_trait`/`x_dyn_method`** on the producer's `call`
   records, aligning with `arch-load`'s existing `x_`-prefixed extension-field convention (spotted
   while re-reading `bin/arch_load/arch_load.ml`'s contract, not previously caught).
5. **Built the merge pass** (`bin/arch_callgraph_rust_merge`, new OCaml binary): reads the union of
   a workspace batch's NDJSON, indexes `trait_impl_fact`s per trait, and narrows `MAY_TOP` dyn
   sites into `MAY_ENUMERATED` per matching non-blanket impl — subject to the publish-boundary gate
   (AND-folded across all facts for a trait) and the blanket-impl gate (any blanket fact forces
   `MAY_TOP`). Implements the missing-facts fallback via an `--expected-crates` flag, checked
   against function `file_path` prefixes (mirroring the harness's own completeness-check
   heuristic).
6. **Verified end-to-end against 5 hand-built fixtures**, now folded into
   `selftest-callgraph-rust.sh` (a repo-integrated, self-contained script — mktemp-based, not
   `~/dev`-tree scratch dirs): sibling non-blanket impls (narrows correctly, no leaked
   `trait_impl_fact`/`x_dyn_*` fields), a blanket impl (stays `MAY_TOP`), a missing expected crate
   (whole-batch fallback fires), a trait-defining crate omitting `publish = false` (stays
   `MAY_TOP`), and — the spec's own "hard requirement from intake" (CHECK-4) — a 3-crate
   flat-union case where the caller never depends on the impl-providing crate at all, confirming
   the merge pass finds the impl anyway (the actual value proposition over a
   dependency-graph-aware merge).
7. **Confirmed `arch-load` accepts the merge pass's output unmodified**, end-to-end (not just
   asserted) — 7 functions, 3 calls (1 MUST, 2 MAY_ENUMERATED, 0 MAY_TOP) loaded cleanly with zero
   changes to `bin/arch_load/arch_load.ml`'s strict contract.
8. **Wrote `callgraph-rust/README.md`** documenting the accepted residuals plainly (see below) and
   filing the CI-wiring decision as an explicit not-yet-done ticket rather than a silent omission.
9. **Ran the full repo-wide `dune build @all` and `dune build @runtest`** in the worktree — both
   clean, confirming this round's additions don't regress the existing OCaml test suite.

## Modified files (this round, on top of round 1's)

| File | Type of change | Reason |
|---|---|---|
| `lib/arch_db/arch_load.ml` | revert | Round-1's wrong-file edit reverted; dead code, not the real loader |
| `.gitignore` | modification | Ignore `callgraph-rust/target/` |
| `callgraph-rust/src/main.rs` | modification | `stable_def_path`, `DynDispatch`/`call_dyn`, `is_blanket`, publish-boundary-crate fix, `impl_fn_stable_name` + matching function-row emission, `x_dyn_*` field rename |
| `bin/arch_callgraph_rust_merge/{arch_callgraph_rust_merge.ml,dune}` | addition | The whole-program merge pass (US-2 core) |
| `selftest-callgraph-rust.sh` | addition | Repo-integrated 5-scenario multi-crate selftest (plan step 14) |
| `callgraph-rust/README.md` | addition | Accepted residuals + CI-wiring ticket (plan steps 17-18) |

## Decisions made (deviations from the plan, flagged rather than silently absorbed)

- **RTA-type-reachability union not implemented.** The plan's Decisions table called for candidate
  enumeration scoped to "the union of RTA-reachable types across all workspace crates' own
  mono-item collections" (plan step 13). This round enumerates **all** non-blanket impls of a
  trait found anywhere in the batch instead. This is still **sound** — extra candidates only make
  a downstream `unreachable` query more conservative, never less — but less **precise** than the
  plan specified. This is a genuine scope reduction from what was validated at the plan gate, not
  a residual the plan itself anticipated; flagging it here rather than silently absorbing it,
  per the task's own standing "surface deviations, don't guess" principle. Documented in
  `callgraph-rust/README.md`'s residuals list as future work.
- **Missing-facts fallback is whole-batch, not per-trait**, as the plan's spec-derived framing
  originally envisioned (spec US-2 AC-5 / CHECK-7 says "every trait touched by that crate falls
  back to `MAY_TOP`" — implying a scoped fallback). Implemented instead as: any named
  `--expected-crates` member absent from the batch forces `MAY_TOP` for **every** dyn site in the
  run. Still strictly sound (a superset of the required fallback scope), but coarser. Reason: a
  per-trait fallback needs to know which traits an ABSENT crate's (never-produced) facts would
  have touched — not derivable from a batch that, by definition, doesn't contain them; a true
  per-trait version would need a separate manifest of "traits each crate is expected to touch,"
  out of scope for this round. Documented in the README.
- **No standalone fact-format design doc** (plan step 4 called for one "before any US-2 coding").
  The format was designed and documented inline instead: the NDJSON shape is specified in code
  comments at each emitter method in `main.rs`, and the overall two-stage architecture plus the
  gates are documented in `callgraph-rust/README.md`. No separate design-doc file exists. This is
  a process deviation, not a content gap — the same information exists, just not as its own
  artifact.
- **CHECK-9 (cross-producer naming check) verified by reasoning, not a mechanical script.** The
  existing rust-analyzer LSP extractor (`lib/arch_index/call_graph_extractor.ml`) emits bare
  `prepareCallHierarchy` symbol names; this MIR producer always emits crate-qualified
  `stable_def_path`-derived names. The two are structurally distinct string spaces with no shared
  bare-name collision risk — there is no meaningful shared key space for a mechanical check to
  assert over. Documented in the README rather than left unaddressed.

## Quality Gates

- [x] Build: `cd callgraph-rust && RUSTC_BOOTSTRAP=1 cargo build --release` ✅ clean, zero warnings
- [x] Build: `dune build bin/arch_callgraph_rust_merge` ✅ clean, zero warnings
- [x] `./selftest-callgraph-rust.sh` ✅ all 5 scenarios pass (sibling narrowing, blanket gate,
      missing-facts fallback, publish-boundary gate, flat-union CHECK-4)
- [x] Repo-wide `dune build @all` ✅ clean
- [x] Repo-wide `dune build @runtest` ✅ clean (no regression to the existing OCaml suite)
- [x] End-to-end `arch-load` acceptance of merge-pass output ✅ verified manually (7 functions, 3
      calls: 1 MUST, 2 MAY_ENUMERATED, 0 MAY_TOP), zero changes to `arch_load.ml`'s contract
- [x] Scope guard (CHECK-8): `git diff --name-only 2592c77 HEAD` excludes both named files ✅

## Points of attention for review

- The `impl_fn_stable_name` mechanism (a new `trait_impl_fact` field plus a matching duplicate
  `function` row) is the single most novel addition this round — verify the duplication is
  actually harmless (same DefId, same file/line, arch-load's `Hashtbl.replace`-based load is
  idempotent on repeated identical names) rather than assuming it from this brief's own claim.
- The missing-facts fallback's whole-batch (not per-trait) scope is a genuine precision reduction
  from the plan — verify the README's framing of it as "still sound, less precise" holds up, and
  decide whether it needs to go back through `/roster-spec`/plan re-validation given it's a
  deviation from an already-VALIDATED plan, not merely an implementation detail.
- The RTA-union omission is the same kind of deviation — same question applies.
- `emit_trait_impl_facts`'s TOML reader is still a hand-rolled line scanner (documented, round-1
  finding, unchanged this round).

## Identified out-of-scope (deferred past this task, not silently dropped)

- Dependency-graph-aware merge precision (only flat-union is implemented — explicitly deferred per
  spec's "Explicitly not specified here" section).
- Non-`dyn` generic trait-bound narrowing, sealed-trait/supertrait-privacy detection,
  feature-powerset analysis — all explicitly deferred per spec.
- CI wiring for the pinned nightly toolchain — filed as an explicit ticket in
  `callgraph-rust/README.md`, owner/workspace TBD by the human maintainer.
- A persisted, incrementally-updated trait-impl index (the cache-staleness residual) — future work
  if merge-pass re-run latency becomes a problem on large workspaces.

## Ratchet

_(first round for US-2; no loop-back yet — round 1's PARTIAL checkpoint was a scope-budget
checkpoint, not a review NO-GO, so no ratchet obligations carry forward)_
