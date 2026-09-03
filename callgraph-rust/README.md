# arch-callgraph-rust

Sound (over-approximate) Rust call-graph producer for arch-index. A `rustc_private` MIR driver
walks every `TerminatorKind::Call` of every reachable monomorphic instance in a crate's own
compilation and emits NDJSON `function`/`call` records — `MUST` for a uniquely-resolved callee,
`MAY_TOP` (anchored to `*TOP*`) for anything this single-crate walk cannot resolve. See
`specs/rust-soundcg-whole-program.md` for the full contract (FR-002: never drop a `Call`
terminator).

## Two stages

1. **Per-crate producer** (`src/main.rs`, invoked via `../arch-callgraph-rust`): one process per
   crate compilation (via `RUSTC_WORKSPACE_WRAPPER`). Emits `function`/`call` records plus a
   `trait_impl_fact` record per locally-defined trait-impl method — consumed only by stage 2,
   never by `arch-load`.
2. **Whole-program merge pass** (`../bin/arch_callgraph_rust_merge`): reads the UNION of every
   crate's NDJSON from a workspace batch and narrows `dyn`-dispatch `MAY_TOP` sites (tagged
   `x_dyn_trait`/`x_dyn_method` by stage 1) into `MAY_ENUMERATED` edges, one per matching
   non-blanket impl — subject to the publish-boundary and blanket-impl safety gates below. Strips
   `trait_impl_fact` records and the `x_dyn_*` fields before the output ever reaches `arch-load`,
   whose strict record-type/field contract (`bin/arch_load/arch_load.ml`) is intentionally
   untouched by this whole task.

```
for crate in $(cargo metadata --no-deps -q | jq -r '.packages[].name'); do
  # RUSTC_WORKSPACE_WRAPPER runs the driver once per crate; concatenate the streams
done | arch_callgraph_rust_merge --expected-crates "$(comma_joined_member_list)" | arch-load out.db
```

(No single script wires this end-to-end yet — see "Accepted residuals" below.)

## Accepted residuals

These are documented trade-offs, not silent gaps — each was weighed against the task's already
multi-day scope and accepted as-is rather than deferred without a record.

1. **Cache-staleness precision cost.** The merge pass has no notion of incremental re-runs: every
   invocation re-derives its trait index from the full NDJSON batch handed to it. A workspace
   where only one crate changed still needs every crate's facts re-supplied for correct
   narrowing — there is no persisted trait-impl index that survives across merge-pass
   invocations. This trades simplicity for wasted recomputation on large workspaces; a persisted,
   incrementally-updated index is future work if merge-pass latency becomes a problem.
2. **Publish-flag proxy weakness.** The publish-boundary gate is a hand-rolled line-scanning TOML
   reader (`source_crate_sets_publish_false` in `src/main.rs`), not a real TOML parser — it
   handles the two documented cases (`[package] publish = false` and
   `[workspace.package] publish = false` via `publish.workspace = true`) but can be fooled by
   unusual formatting (multi-line tables, a `#` comment containing the word "false"). `publish`
   itself is also just a **crates.io publish gate**, not a language-level sealed-trait mechanism —
   a `publish = false` crate can still be depended on via a git/path dependency by a downstream
   consumer this analysis never sees. The gate is a cheap, imperfect proxy for "this trait cannot
   be implemented by code outside what we've analyzed," documented as such in the spec.
3. **Missing-facts fallback is whole-batch, not per-trait.** The plan's original framing
   anticipated a fallback scoped to only the traits an absent crate's facts would have touched.
   This round implements a coarser, whole-batch version instead: if any `--expected-crates` member
   is absent from the batch, **every** dyn-dispatch site in the run stays `MAY_TOP`, not just the
   ones plausibly affected. This is strictly sound (over-conservative, never under-conservative)
   but loses precision when only one crate's facts are missing in a large workspace. A finer
   per-trait fallback would need to know, for an ABSENT crate, which traits its (never-produced)
   facts would have touched — not derivable from the batch that exists, so it would require a
   separate manifest of "traits each crate is expected to implement," which is out of scope for
   this round.
4. **RTA-type-reachability union not implemented.** The plan's Decisions table called for
   candidate enumeration scoped to "the union of RTA-reachable types across all workspace crates'
   own mono-item collections." This round enumerates ALL non-blanket impls of a trait found
   anywhere in the batch instead — still sound (extra candidates only make a downstream
   `unreachable` query more conservative, never less), but less precise than the plan specified.
   Accepted as a scope reduction given the task's size; implementing the RTA union is future work.
5. **Cross-producer naming check (CHECK-9): reasoned, not automated.** The existing rust-analyzer
   LSP-based extractor (`lib/arch_index/call_graph_extractor.ml`) names functions with the bare
   LSP `prepareCallHierarchy` symbol name (e.g. `do_it`); this MIR-based producer always emits
   crate-qualified `stable_def_path`-derived names (e.g. `crate_a::use_dyn`,
   `<A as Doer>::do_it`, `crate_a::{impl#0}::do_it`). The two naming schemes are structurally
   distinct string spaces with no shared bare-name collisions to misattribute across — verified by
   inspection, not by a mechanical check (no deterministic check is meaningful here: there is no
   shared key space to assert equality or inequality over, only two producers that must never be
   run against the same repo's output stream and merged as if they used one naming convention,
   which the harness scripts don't do).

## CI wiring

**Not yet wired into CI.** Ticket: file as a follow-up issue titled "Wire arch-callgraph-rust +
merge pass into CI for workspace X" — owner and specific workspace TBD by the human maintainer;
this driver requires a pinned nightly toolchain with `rustc-dev`/`llvm-tools` components, which is
a heavier CI dependency than the rest of this repo's OCaml/Go tooling and should be a deliberate,
reviewed CI change rather than something silently added by this task.
