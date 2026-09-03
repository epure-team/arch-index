# Implementation Brief — top-anchor-taxonomy

**Date:** 2026-09-03
**Mode:** fast
**Status:** COMPLETED

## Where the work lives

Worktree `/tmp/claude-1000/-home-mathias-dev-arch-index/14fbc421-dfc7-4b31-91d6-c084baeb45e0/scratchpad/wt-topanchor`,
branch `feat/top-anchor-taxonomy`, based on `origin/main@2a82b9f`.

## Scope

Roadmap Phase 1 item 1.4: `calls.top_reason`/`calls.top_anchor` — making WHY a call is `MAY_TOP`
into data instead of a comment at the emission site. Pre-implementation research found the
roadmap's own cited line numbers stale (this session's three prior tasks added well over 1000
lines to the same files) and clarified its `cmt_imports`/`calls.resolution` premise: it refers to
a REAL compiler-libs field (`Cmt_format.cmt_infos.cmt_imports`), already available on every
`.cmt` file this codebase reads, but not yet consumed anywhere — not a stale/wrong premise, just
not yet wired in (confirmed directly by reading `cmt_format.mli` in the project's own opam
switch).

## Decisions made

- **Only 2 of the roadmap's 5 named OCaml reasons are structurally distinguishable today** —
  `callback_param` and `module_param` are decided cleanly from existing state
  (`qualified_is_dynamic`, already used elsewhere in the walker for the same distinction).
  `pattern_bound` (a tuple/alias-bound local lambda) and a genuine function parameter currently
  collapse to the SAME code path (`lam_stamp id = None` at a `Head_unknown` production site) —
  `local_lam_stamps` only records the `Tpat_var`-single-literal-RHS success case, so at a later
  use site "not stamped" cannot tell a real parameter from a pattern-bound lambda without NEW
  binding-site tracking (walking `Tpat_tuple`/`Tpat_alias` patterns to collect their bound idents).
  Folded both into `callback_param` — a documented, honest simplification (see
  `arch_index_cmt.ml`'s own comment on the `top_reason` type), not a silent conflation.
  `deferred` (a lazy/object body) is not actually a `Head_unknown`-production concern at all: it
  is about whether a call's EXECUTION is conditional (`walk_isolated_default`'s own job, already
  captured by `cond`/`demoted`), not about the head being unknowable — a call inside a deferred
  body gets its OWN correct `top_reason` from whatever ITS head classification finds, with no
  separate "deferred" tag needed.
- **`Dropped_node` always wins over the head's own carried reason** at classification time in
  `arch_index.ml` — it is the MORE SPECIFIC explanation ("this callee's row/unit was rejected this
  run") wherever `dropped_local`/`dropped_qualified` applies, overriding whatever reason the head
  was ORIGINALLY constructed with in `arch_index_cmt.ml`.
- **`top_anchor` is the call site, for every reason, in this round** — the roadmap's own note says
  "not always the call site (for a callback it is the parameter binding)"; correctly distinguishing
  a callback's own binding location requires plumbing an ADDITIONAL location (the parameter
  pattern's own `Location.t`, not currently tracked anywhere) through `Head_unknown`'s payload.
  Establishing the column now (correctly `NULL` outside `MAY_TOP`, populated for every `MAY_TOP`
  edge) lets downstream consumers (1.5 witness paths, 3.2 discharge ledger) start relying on its
  existence; refining WHICH location it points to is a real, separate follow-up.
- **`CHECK` constraint on `calls.top_reason`, not OCaml-side-only validation** — matches the more
  idiomatic recent precedent (`producer_runs.soundness_class` from the provenance-columns task)
  over the older `arch_load.ml` `List.mem`+`die` pattern (which the loader ALSO gets, for the same
  reason `kind` needs both: the loader is the enforcement point for anything reaching the DB from
  outside this codebase's own control).
- **`bin/arch_load` accepts the FULL ten-value vocabulary** (all 3 OCaml + 4 Go + 3 Rust reasons),
  even though only OCaml (via `Arch_index.run`, a separate binary) ever emits it today — Go/Rust
  producers (`callgraph-go`, `callgraph-rust`) do not emit `top_reason` yet, matching the same
  "documented, not silently dropped" residual pattern as roadmap 1.1's `language` field and 1.2's
  `--producer=` flags. Both already compute the underlying distinctions internally (Go's
  well-known-TOP function table; Rust's `Callee.DynDispatch`, which already surfaces `dyn Trait`
  via its own `x_dyn_trait`/`x_dyn_method` producer-extension fields) — wiring either to actually
  emit `top_reason` is mechanical, touching those producers' own codebases, out of this item's
  OCaml-side scope.
- **`calls.resolution` deferred entirely, not implemented this round.** Its exact semantics
  (distinguishing a MUST-with-NULL-callee edge that is a genuine external leaf from one whose
  owning unit was a real dependency this run never actually indexed) need a design decision this
  task did not have enough confidence to make alone — see "Identified out-of-scope" below.
- **`runner.ml`'s flat schema (the LSP path) is untouched** — it never marks ⊤ at all (never earns
  `callgraph_contract`, per its own `lsp_edge_kind` comment), so `top_reason`/`top_anchor` would be
  structurally meaningless there; only `Arch_index.run` (the CMT path, the one `sound_with_top`
  producer) and `bin/arch_load` (which OTHER `sound_with_top` producers, e.g. `callgraph-rust`,
  feed) needed this.
- **Main schema version bumped 1.5 → 1.7 (renumbered from an initial 1.6 mid-review after a cross-session coordination message from a peer session — see the Review-round addendum)** (additive columns). **`bin/arch_load`'s own schema
  version bumped 1.1 → 1.2** (a real structural change — new `calls` columns, not just new
  `comment_db_meta` keys, unlike the provenance-columns task's flat-schema treatment).

## Modified files

| File | Type of change | Reason |
|---|---|---|
| `architecture-schema.sql` | addition | `calls.top_reason` (+ CHECK constraint, full ten-value vocabulary), `calls.top_anchor`, an index. Main schema version 1.5→1.7 (renumbered mid-review, see addendum) |
| `lib/arch_index/arch_index_db.ml` | modification | `current_schema_version` 1.5→1.7 (renumbered mid-review, see addendum); `insert_call`/`insert_call_rowid` gain `?top_reason`/`?top_anchor` |
| `lib/arch_index/arch_index_db.mli` | modification | Matching signature updates |
| `lib/arch_index/arch_index_cmt.ml`/`.mli` | modification | New `top_reason` type (`Callback_param`/`Module_param`/`Dropped_node`) + `top_reason_to_string`; `Head_unknown` gains a `top_reason` payload; all ~10 production sites updated |
| `lib/arch_index/arch_index.ml` | modification | Call-classification match extended to a 4-tuple (adds `top_reason`); threads `top_reason`/`top_anchor` into `insert_call_rowid` |
| `bin/arch_load/arch_load.ml` | modification | New `top_reasons` vocabulary constant, optional `top_reason`/`top_anchor` NDJSON fields (validated, mirroring `kind`'s enforcement), schema DDL + INSERT + usage string updated. Own `schema_version` 1.1→1.2 |
| `docs/edge-kind-contract.md` | addition | New "⊤-anchor taxonomy" section: the vocabulary table, what's distinguishable today vs. the documented residuals |
| `docs/schema.md` | addition | `1.7` version-history rows (main schema + `bin/arch_load`'s own) |
| `tezt/tests/top_anchor_taxonomy.ml` | addition | New file: `callback_param`/`module_param` real-fixture verification, NULL-outside-MAY_TOP invariant, CHECK-constraint positive/negative control |
| `tezt/tests/dropped_node_dependents.ml` | modification | Extended both existing drop tests (`dropped_local` and `dropped_qualified` paths) with `top_reason='dropped_node'` assertions |
| `tezt/tests/load.ml` | modification | New assertions: invalid `top_reason` aborts the load; a valid `top_reason`/`top_anchor` pair is accepted and stored verbatim |
| `tezt/tests/main.ml` | modification | Registers `Top_anchor_taxonomy` |
| `test/fixtures/self-index-stats.txt` | regenerated | Per ADR 001 — 575→576 functions, 3986→3994 calls (final, post-review) |

## Quality Gates

- [x] Build: `dune build --root . @all` (under the `arch-index` opam switch) ✅ clean, zero warnings
- [x] Tests: `dune test --root . --force` ✅ 111/111 tezt tests pass (final, post-review-fixes count
      — 6 new `top_anchor_taxonomy.ml` tests, 2 new assertions in `dropped_node_dependents.ml`, 2 new
      assertions in `load.ml`)
- [x] Self-index golden regenerated per ADR 001 (final: 21 modules / 576 functions / 3994 calls)
- [x] `must_null_ceiling` ratchet re-checked against the final 3994-call index, still within
      existing headroom — no recalibration needed this round

## Review-round addendum

Both `reviewer` and `architect` specialists were spawned in parallel (blast radius > 3 files);
cross-runtime `codex` remained `status: skipped-degraded` (non-conforming output, breaker held
all session). Findings below are the union after dedup, most severe first.

- **HIGH (both specialists independently, converged)** — `Head_local`'s unresolved branch in
  `arch_index.ml` defaulted straight to `Some "callback_param"` without checking `dropped_local n`
  first, unlike every sibling branch in the same match (`Head_enumerated`, `Head_qualified`).
  Zero soundness risk (`kind` was already `"MAY_TOP"` either way), but a `dropped_node` edge would
  have been silently mislabeled `callback_param` — the exact kind of information loss this
  taxonomy exists to prevent. Fixed: added the same `if dropped_local n then ... else ...` guard
  used by the other branches.
- **MEDIUM-HIGH** — `dropped_node_dependents.ml`'s second drop-test asserted
  `top_reason != 'dropped_node'`, which evaluates to SQL `NULL` (not `TRUE`) whenever
  `top_reason IS NULL` — so a row silently missing its reason (the regression class the taxonomy
  exists to catch) would not be counted, and the test would pass regardless. Fixed: `!=` → `IS NOT`.
- **MEDIUM** — four production sites in `arch_index_cmt.ml` (genuinely-computed function-value
  heads with no binding site at all — an anonymous application head, an over-application residual)
  were folded into `Callback_param` with no documentation disclosing this fold, unlike the
  `pattern_bound` fold which was disclosed. Both reviewers accepted documentation-only as
  sufficient (no new vocabulary member). Fixed: extended the `.ml` type comment, the `.mli` doc
  comment, and `docs/edge-kind-contract.md`'s `callback_param` table row to honestly describe all
  three cases the reason now covers.
- **MEDIUM** — `top_anchor`'s documented format (`file:line:col`) did not match its actual format
  (`file:line` — `call.call_site` never carries a column). Fixed by correcting the documentation
  in `architecture-schema.sql` and `docs/edge-kind-contract.md`, not by changing `call_site`'s
  format globally (a much bigger, riskier change touching code used extensively elsewhere).
- **MEDIUM** — the "`top_reason`/`top_anchor` NULL unless `kind = 'MAY_TOP'`" invariant was
  documented but nowhere enforced beyond vocabulary checking, and untested globally. Fixed: added
  `CHECK(top_reason IS NULL OR kind = 'MAY_TOP')` to the SQL schema; added a matching pairing
  check to `bin/arch_load/arch_load.ml`'s parsing (dies if `top_reason` is given with a non-MAY_TOP
  `kind`); added two new tests, `register_global_invariant` and
  `register_kind_top_reason_pairing_constraint`.
- **LOW** — `top_anchor`'s computation in `arch_index.ml` was keyed off `top_reason = None` rather
  than `kind = "MAY_TOP"` directly. Fixed to key off `kind` (states the actual invariant directly,
  more robust to a future branch getting `top_reason` wrong independently).
- **LOW** — `Module_param`'s display name was inconsistent: bare name at `add_arg_escapes`'s
  `Pdot` case vs. qualified `module.name` at the other two `Module_param` sites. Fixed by making
  the first site build the qualified name too.
- **LOW** — new test assertions checked `top_reason`'s value without also pinning `kind='MAY_TOP'`
  on the same row. Fixed by adding `AND kind = 'MAY_TOP'` to the relevant queries; the
  `module_param` test also gained an explicit `callee_name = 'M.op'` filter for precision.
- **LOW** — the brief's stated golden-fixture delta was a stale copy-paste from an earlier round.
  Corrected above.

**Cross-session schema-version renumbering (not a review finding — external coordination):**
mid-review, peer session `arch-index-96` (working in parallel on `feat/error-channels`) messaged
that it had independently claimed `current_schema_version = "1.6"` for its own in-flight branch,
and asked this task to take `"1.7"` if it was also about to claim `"1.6"` — which it was. Renumbered
`lib/arch_index/arch_index_db.ml`'s `current_schema_version`, `docs/schema.md`'s version-history
row, and this brief's own prose/table references from `1.6` to `1.7`; verified via grep that no
stray `"1.6"` schema-version references remained in any file this task modified. This is a real
external collision avoided proactively, not a defect found by review.

**Final re-verification after all fixes:** `dune build --root . @all` clean; `dune test --root .
--force` 111/111 passing; self-index golden regenerated (21 modules / 576 functions / 3994 calls,
reflecting the `Module_param` display-name fix's small resolution delta); `must_null_ceiling`
re-checked against the final count, within headroom.

## Points of attention for review

- Confirm folding `pattern_bound` into `callback_param` (rather than adding new binding-site
  tracking to split them) is an honest, well-justified scoping decision given the roadmap's own
  vocabulary — not a shortcut that quietly loses information a consumer would need.
- Confirm `Dropped_node` correctly overriding the head's own carried reason (rather than the head's
  reason winning) is the right precedence — verified end-to-end via both existing drop-test
  fixtures (`dropped_node_dependents.ml`), but worth an explicit second look given how many call
  sites feed into this one classification point in `arch_index.ml`.
- `top_anchor` = call site (not the more precise "parameter's own binding location" the roadmap's
  note describes for a callback) — confirm this is an acceptable v1, not something that should
  block on the fuller tracking.
- `calls.resolution` was NOT implemented — confirm deferring it (rather than guessing at
  `cmt_imports`-based semantics with real risk of being subtly wrong) was the right call given the
  roadmap's own text left genuine ambiguity about what should happen at Octez scale.
- A THIRD, unrelated `arch_load.ml` at `lib/arch_db/arch_load.ml` (199 lines, structurally similar
  but smaller/older) was found during implementation with ZERO consumers anywhere in the codebase
  — appears to be dead/vestigial code predating `bin/arch_load` becoming canonical. Not modified
  (out of this task's scope), but flagged here rather than silently left unmentioned.

## Identified out-of-scope (deferred, not silently dropped)

- `calls.resolution ∈ {in_index, external_unit, dropped}` — needs a design decision on exact
  semantics (see "Decisions made" above) before implementation; a follow-up item, not this one.
- Splitting `pattern_bound` out of `callback_param` — needs new binding-site tracking in
  `arch_index_cmt.ml` (walking compound patterns to collect bound idents at `let`-binding time).
- Wiring `callgraph-go`/`callgraph-rust` to actually emit `top_reason`/`top_anchor` in their own
  NDJSON output — mechanical, touches producer codebases outside this item's OCaml-side scope
  (same pattern as roadmap 1.1's Go/Rust `language` gap and 1.2's `--producer=` gap).
- Refining `top_anchor` to point at a callback's own parameter-binding location rather than the
  call site — needs new location tracking through `Head_unknown`'s payload.
- The dead `lib/arch_db/arch_load.ml` file discovered during implementation — flagged, not acted
  on; a separate cleanup decision (is it truly dead, should it be removed) not this item's to make.

## Ratchet

First round.
