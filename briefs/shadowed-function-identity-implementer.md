# Implementer Brief — shadowed-function-identity

**Date:** 2026-09-02
**Status: VALIDATED**

## Goal

Fix GitHub issue #41 / roadmap item 0.6: same-level shadowing (two top-level bindings of the same
name in one compilation unit) currently produces only one `functions` row via `INSERT OR REPLACE`
on `UNIQUE(module_id, name)`, and both bindings' outbound call edges resolve post-hoc onto that
single surviving row. Give each same-level binding a distinct identity via a `#N` ordinal suffix,
mirroring `lambda_name`'s existing precedent (`lib/arch_index/arch_index_cmt.ml:801-811`).

## Critical decision — read before touching any code

**The last (source-order-final) binding at a colliding name/position keeps the bare name. Every
earlier (shadowed) binding takes the `#N` suffix.** This is the opposite of what a prior
uncommitted draft did, and the inversion is not cosmetic — it is required for correctness:

- Cross-module callers can only ever reference the bare syntactic name (`add_path_call` records a
  callee's name purely from the OCaml path text — no ordinal awareness is possible there).
  `resolve_qualified` (`lib/arch_index/arch_index.ml:355-372`) resolves that bare name via a plain
  `(mod_path, name)` lookup in `fn_lookup`. If the bare name is assigned to the *first* (shadowed,
  dead) binding, every external caller of `M.f` silently gets rebound onto dead code — reproducing
  issue #41's own bug on the cross-module axis.
- This also matches actual OCaml shadowing semantics: `M.f` always denotes the last `let f = ...`
  in the structure.
- It also reproduces the pre-fix external observable for `arch-query` bare-name lookups (which
  today, via `INSERT OR REPLACE`, always land on the last-written row) — so this is not a new
  behavior change for the bare-name case, only a newly-visible extra row for the shadowed one.

Do not re-derive this from scratch — treat it as settled. Document it in the PR description
verbatim as the "user-visible naming-contract" note below.

## Prior draft — use as a strong starting point, not ground truth

An uncommitted draft exists at
`/tmp/claude-1000/-home-mathias-dev-arch-index/14fbc421-dfc7-4b31-91d6-c084baeb45e0/scratchpad/wt-rowid`,
branch `fix/shadowed-function-identity`, based on stale commit `161f3d7` (~17 commits behind
current `main`). It introduces:

- `type binding_identity = {bind_name; bind_base; bind_last}` and
  `build_binding_names structure` in `arch_index_cmt.ml`/`.mli` — walks all top-level value
  bindings via `iter_structure_items`, assigns ordinals per colliding base name, and computes
  `bind_last` (true for whichever binding is numerically last per a `totals` count).
- Threading of `build_binding_names` through `build_local_fn_stamps ~binding_names structure`
  and into the main indexing walk's function-row-write site (uses `bid.bind_name` for the row
  name; `exposed`/doc-comment gated on `bid.bind_last`).
- The same threading in `call_graph_extractor.ml` (`~prefix:""`, since that walk is flat).
- `tezt/tests/shadowed_definitions.ml` (new): a "shadow" fixture and a "clean" fixture.

**Use this as your reference implementation, but do not port it as a patch.** Re-derive it
against current `main` (`014becd`), specifically:

1. **Invert the name-string assignment** per the Critical Decision above. The draft's
   `bind_last`-gated `exposed`/doc-comment logic is *already correctly oriented* (last-bound gets
   `exposed`) — only the bare-name-vs-`#N` string choice needs flipping to match. Re-verify this
   gating is still correct after your rebase; do not assume.
2. **Re-read current `main`'s versions** of `build_local_fn_stamps`, the value-binding row-write
   site, and `build_local_fn_stamps`'s callers before merging in the draft's changes — two
   intervening commits touch this exact region:
   - `2a0a771` — wildcard-binding fix (stopped recording wildcard bindings as functions)
   - the `insert_function` return-value fix (commits `278f182`/`644d5a6`)
   Confirm the ordinal mechanism composes correctly with both; do not blindly apply the draft's
   diff over current `main`.
3. **`Tstr_include`-introduced collisions are already handled for free** — confirmed by direct
   read that `iter_structure_items` (`arch_index_cmt.ml:97-115`) already descends into
   `Tstr_include` via `module_expr`/`Tmod_structure` at the includer's own prefix. No special-case
   code is needed for this; `build_binding_names` sees these bindings automatically. Do not add
   extra logic for it.
4. **`let rec f = e1 and f = e2` needs no test coverage** — this is rejected by the OCaml
   type-checker (duplicate name within one `and`-group) and cannot occur in valid `.cmt` input.
   Do not add a fixture for it.

## Scope Boundary

Out of scope (do not touch):
- The pre-existing, already-accepted cross-module homonym hazard in `bin/arch_query/arch_query.ml`
  (documented at `bin/arch_effects_queries.ml:37-58`). This fix's collision axis is same-module,
  same-level only — do not fix the cross-module axis, and do not make it worse (this is exactly
  why the ordinal-direction Decision above matters).
- `functions.name` uniqueness contract for consumers keyed by `(name, module)` —
  `arch_index_support.ml`'s intent updater, `arch_body_compare`'s dedup sweep — unaffected, no
  change needed.
- A durable cross-loader stable qualified identity (roadmap item 1.6) — out of scope.
- Switching `functions` off `INSERT OR REPLACE` — not this fix's direction.

## Relevant Files

| File | Role |
|---|---|
| `lib/arch_index/arch_index_cmt.ml` | Value-binding walk and row-write site; `lambda_name` ordinal precedent (`:801-811`); `iter_structure_items` (`:97-115`, confirmed to descend into `Tstr_include`) |
| `lib/arch_index/arch_index_cmt.mli` | Signature for `build_binding_names`/`binding_identity`, consumed by `call_graph_extractor.ml` |
| `lib/arch_index/arch_index_db.ml` | `insert_function` (`:184-207`), the `INSERT OR REPLACE` call site — unchanged by this fix |
| `lib/arch_index/arch_index.ml` | `fn_lookup` build (`:287-297`), `resolve_local` (`:341-342`), `resolve_qualified` (`:355-372`) — the code that makes the ordinal-direction Decision load-bearing |
| `lib/arch_index/call_graph_extractor.ml` | Sibling LSP/flat-schema path — must call `build_binding_names` and stay consistent with the main indexer |
| `architecture-schema.sql` | `functions` table, `UNIQUE(module_id, name)` (`:51`) — unchanged |
| `tezt/tests/shadowed_definitions.ml` (new) | Test fixtures — port from the draft, invert the shadow fixture's assertions, add a cross-module fixture (see Step 3 below) |

## Sequential Steps

1. Re-derive `binding_identity`/`build_binding_names` in `arch_index_cmt.ml`/`.mli` against
   current `main`, with the ordinal direction flipped (last-bound = bare name, earlier = `#N`,
   numbered among themselves in source order). Build clean.
2. Thread the corrected mechanism through `call_graph_extractor.ml`. Confirm both extraction
   paths agree on a shadowed function's identity.
3. Rebuild `tezt/tests/shadowed_definitions.ml`:
   - "shadow" fixture: invert the row-identity assertions for the flipped direction.
   - "clean" fixture: unchanged (pins byte-identical behavior when there's no collision).
   - **New cross-module fixture**: module `A` with two same-named top-level bindings (each
     calling a distinct helper), module `B` calling `A.f` by qualified path. Assert `B`'s call
     resolves to the live (last) definition's edges, not the shadowed one. This must be
     demonstrably red against the (hypothetical) unflipped direction and green against the
     corrected one.
4. Run the full evidence gate (see Quality Gates below).
5. Write the user-visible naming-contract note into the PR description, verbatim per the Critical
   Decision section above.

## Quality Gates

```bash
eval "$(opam env --switch=/home/mathias/dev/arch-index --set-switch)"
dune build
dune test --force
dune fmt
```

Also required (roadmap soundness gate for this item class): `arch-rules --on-vacuous fail` over a
self-index, and a self-index-scale MUST/MAY_TOP measurement before/after. Full Octez
re-measurement is deferred as a documented follow-up, not a blocking requirement for this PR.

## Risks and Assumptions carried from the plan

- Rebase risk: two intervening commits (`2a0a771`, `insert_function` return-value fix) touch the
  same code region — re-read current `main`, do not blindly apply the draft's diff.
- `#N` ordinal numbering direction (counting up vs. down among the shadowed bindings) is left to
  your discretion; document the convention chosen.
- Self-index evidence may show no measurable MUST/MAY_TOP delta if no naturally-occurring
  same-level shadowing exists in this repo's own `.cmt` output — acceptable; the cross-module
  tezt fixture is the primary correctness proof, not the self-index measurement.
- Re-verify `bind_last`-gated `exposed`/doc-comment logic is still correctly oriented after your
  rebase — assumed correct in the draft, but not re-verified in this planning phase.
