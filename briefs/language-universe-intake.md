# Intake Brief — language-universe

**Date:** 2026-09-03
**Status: VALIDATED**
**Type:** feature
**Trust boundary:** no

## Goal

Roadmap Phase 1, item 1.1 — "the keystone": add `functions.language` and `functions.universe` to
both schemas this tool has (`Main`/`architecture-schema.sql` and `Flat`/`bin/arch_load`'s NDJSON
loader). `Language_registry.detect_language_roots ~project_dir` already detects every language in
a project (ocaml/typescript/rust/go/python/c/java, paired with each language's root directory) but
the result is discarded — nothing ever reaches a `functions` row. This blocks the coverage matrix
(1.3), per-language reporting, splice tiers, and boundary edges (3.6), all of which need to know
which language produced which row. `SPEC-sound-callgraph.md` FR-001 already requires "node identity
carries a language tag + internal/external universe flag" — this item is the first thing that
actually implements it.

`universe ∈ {internal, external}`: `internal` for every row a producer actually emitted;
`external` for the synthesized `ext:` leaves `Arch_graph.load` creates today from
`callee_id IS NULL` (`lib/arch_tools/arch_graph.ml:86-106`) — these are currently not `functions`
rows at all (`load_nodes` reads only `functions`), which matters for witness paths (1.5, not this
item) and the `ext:` selector (2.4, not this item) later.

## Scope Boundary

Out of scope (explicitly deferred to later Phase 1/2/3 items per the roadmap):
- Provenance columns (1.2), coverage matrix table (1.3), ⊤-anchor taxonomy (1.4), witness paths
  (1.5), stable qualified-name identity (1.6) — each is its own roadmap item with its own effort
  estimate; this item is `language`/`universe` only.
- Materializing `ext:` leaves as real `functions` rows — the roadmap's own notes flag this as
  relevant to 1.5/2.4, not 1.1. This item only ensures `universe` is a valid column with correct
  values on the rows that DO get inserted; it does not change what gets inserted.
- Any change to `Arch_graph.load`'s node-loading logic itself — out of scope for this item,
  future items may build on the new column.
- Boundary-edge detection (3.6) — a later, separate roadmap item this one unblocks.

## Design decisions (from the roadmap's own already-settled research — not re-litigated here)

1. **Main schema**: `functions.language` inherited from its `modules.language` (add `language` to
   `modules` too, since a module's language is what determines its functions' language — not
   stated explicitly in the roadmap note but the only coherent design, since `functions` has no
   direct file-path column of its own to re-derive language from independently). Wire
   `detect_language_roots` into `Arch_index.run` so every `modules` row gets `language` from the
   longest matching root.
2. **Flat schema**: NDJSON contract gains an optional `language` field on the `function` record;
   `comment_db_meta.callgraph_contract` moves to `v2` when a producer emits it. A v2-aware loader
   (`bin/arch_load`) MUST still accept a v1 file (no `language` field) and record `language = NULL`
   rather than guessing — never silently fabricate a value the producer didn't actually assert.
3. **Migration style**: `IF NOT EXISTS` everywhere (matches `effects-schema-migration.sql`'s
   convention), applied by probing `pragma_table_info` for the new column — the same pattern
   `bin/arch_sidecar_load` already uses for `reachability_class`.
4. **Ratchet check** (per the roadmap's own acceptance criterion): index the existing
   `tezt/tests/multilang.ml` fixture and assert `SELECT DISTINCT language FROM functions` has one
   row per producer that actually ran and **no NULL** row for a producer-emitted function.

## Relevant Files

| File | Role | Key snippet |
|---|---|---|
| `lib/arch_index/language_registry.mli`/`.ml` | `detect_language_roots ~project_dir : (string * string) list` — already exists, currently discarded after detection | |
| `lib/arch_index/arch_index.ml` | `run` (main-schema/CMT path) — where `modules` rows are inserted; needs to call `detect_language_roots` and thread `language` through to both `modules` and `functions` inserts | |
| `lib/arch_index/runner.ml` | LSP-based flat-schema path — `write_functions`/`fn_row` type needs an optional `language` field threaded from the caller's own known language (this path already indexes one language per invocation, per `-l`/`--language` CLI flag) |
| `architecture-schema.sql` | Main schema — `modules`/`functions` table definitions (repo root) |
| `bin/arch_load/arch_load.ml` | Flat schema — `record_types`/field allow-list (`:42`), `schema` DDL (`:62-86`), `functions` insert (`:331`) — strict, rejects unknown fields; `language` must be added to the `"function"` allowed-fields list, not smuggled in as `x_language` |
| `lib/arch_tools/arch_db.ml` | `Arch_db.schema` detection (`:289`, probes `calls.caller_name` for `Flat` vs `Main`) — `lib/arch_tools` is "the only place allowed to know the difference" per the roadmap's own architecture note; do not leak schema-shape branching into `arch-rules`/`arch-query`/`arch-mcp`/`arch-serve` themselves |
| `tezt/tests/multilang.ml` | Existing multi-language fixture — the ratchet check target |
| `SPEC-sound-callgraph.md` | FR-001 — "node identity carries a language tag + internal/external universe flag" — the requirement this item implements |

## Quality Gates

```bash
eval "$(opam env --switch=/home/mathias/dev/arch-index --set-switch)"
dune build @all
dune test --force
```

Self-index golden file (`test/fixtures/self-index-stats.txt`) must be regenerated per
`docs/adr/001-self-index-golden.md` if this change adds functions to `lib/arch_index` — expected,
given the scope of this item.

## Open Questions

_(none — the roadmap's own research already resolved the design; the human decision authorizing
autonomous roadmap work covers proceeding without a fresh per-item confirmation)_
