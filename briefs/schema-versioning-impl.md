# Implementation Brief — schema-versioning

**Date:** 2026-09-03
**Mode:** fast
**Status:** COMPLETED

## Where the work lives

Worktree `/tmp/claude-1000/-home-mathias-dev-arch-index/14fbc421-dfc7-4b31-91d6-c084baeb45e0/scratchpad/wt-schemaver`,
branch `fix/schema-versioning`, based on `origin/main` at `69e5c3d`, commit `ad6ad83`.
`git status --porcelain` is empty.

## Modified files

| File | Type of change | Reason |
|---|---|---|
| `lib/arch_index/arch_index_db.ml`/`.mli` | addition + fix | `current_schema_version` (hand-bumped `"major.minor"`, single source of truth), `schema_sql` (compile-time embed via `ppx_blob`), fixed dead `schema_path` default (`docs/architecture-schema.sql` → `architecture-schema.sql`), 2 new inline tests |
| `lib/arch_index/runner.ml` | fix | Both `set_meta db "schema_version" "1"` call sites now read `Arch_index_db.current_schema_version` |
| `lib/arch_index/arch_index.ml`/`.mli` | addition | Re-exports `schema_version`/`schema_sql` as public API |
| `lib/arch_index/dune` | addition | `preprocessor_deps` on the root `architecture-schema.sql` for the `ppx_blob` embed |
| `docs/schema.md` | addition | New "Schema version history" section: the versioning convention, the flat-schema caveat (shares the version key but isn't versioned by it), and a table retroactively dating the two already-shipped migrations as `1.1`/`1.2` |

## Decisions made

- **`(major, minor)` versioning, not a monotonic integer** — human decision, made before this
  brief was written (Phase 1 queues 6 more additive schema changes behind this).
- **Embed via `ppx_blob`, not a dune install-file stanza.** The library already depends on
  `ppx_blob` and already uses it for exactly this purpose (`ts_enricher.ml`'s `ts_shim.js`) —
  reusing an established, working pattern rather than fighting the opam install-path question the
  roadmap's own research flagged as the harder route.
- **`schema_sql`/`schema_version` re-exported from `arch_index.ml` as bare top-level `val`s, not
  nested under the existing `Db` sub-module.** `Db` is a deliberately narrow, already-documented
  re-export ("the accounting surface only, not the whole insert API"); broadening its stated scope
  to cover schema inspection would contradict its own docstring. A new top-level surface is a
  cleaner fit and more discoverable.
- **`docs/schema.md` extended, not a new `docs/schema-versions.md` file.** A schema doc already
  existed and already documented the flat-vs-main schema distinction; a second file would have
  been redundant and easy to drift out of sync with the first.
- **Two already-shipped migrations dated retroactively as `1.1`/`1.2`**, using each migration
  file's own commit-message "Phase 1"/"Phase 2" label (`effects-schema-migration.sql` came first
  chronologically per `git log --follow`, matching its own "Phase 1" label; `capabilities-...`
  came second, matching its own "Phase 2" label) — not re-derived, taken from what the migrations
  themselves already say about their own ordering.
- **Existing `--schema-path=architecture-schema.sql` workarounds in `docs/install.md`, `README.md`,
  `.github/workflows/ci.yml` left in place**, not removed — the intake brief's scope boundary
  called this optional cleanup, not required; removing them is a legitimate but separate follow-up.

## Quality Gates

- [x] Build: `dune build @all` ✅ clean, zero warnings
- [x] Tests: `dune test --force` ✅ 89/89 tezt tests pass (repo-wide, unchanged from before this
      change) + 2 new inline tests (`arch_index_db.ml`) — well-formed version string, `schema_sql`
      defines the base tables
- [x] End-to-end verification (not just the constant in isolation): built a fresh minimal OCaml
      project, ran the actual LSP indexing CLI (`arch_index_cli -l ocaml -p ... -o ...`) against
      it, and queried the resulting database directly — `comment_db_meta.schema_version` = `"1.2"`,
      confirming the fix through the real runtime write path, not just a unit-level assertion

## Points of attention for review

- The `ppx_blob` embed path (`../../architecture-schema.sql` relative to
  `lib/arch_index/`) — confirm it resolves correctly from a clean build (not just an
  already-built tree), and that `preprocessor_deps` actually tracks the root file for rebuild
  invalidation (edit `architecture-schema.sql`, rebuild, confirm `schema_sql` picks up the change).
- The flat-schema caveat in `docs/schema.md` — confirm it's accurate: the flat schema really has
  never had its own version-worthy change, and sharing the `schema_version` key with the main
  schema really is intentional/harmless (a flat-schema consumer that reads `schema_version` and
  assumes it describes the flat schema's own (nonexistent) structure would be misled — worth
  independently confirming no such consumer exists today).
- `current_schema_version = "1.2"` is a literal string constant — nothing enforces that a future
  schema change actually bumps it; this is process discipline (documented in the code comment and
  `docs/schema.md`), not a mechanically-enforced invariant. Consistent with the intake brief's
  explicit scope boundary (no capability-check API, no automated schema-diff-triggers-a-bump
  mechanism) but worth flagging as a residual, not silently assumed solved.

## Identified out-of-scope (deferred, not silently dropped)

- A capability-check API (issue #51's third suggested option) — the roadmap explicitly scoped
  this out as a nice-to-have layered on top of versioning, not required by this item.
- Removing the now-redundant `--schema-path=architecture-schema.sql` flags from
  `docs/install.md`/`README.md`/CI — harmless to leave, optional cleanup.
- Any mechanical enforcement that a schema change bumps `current_schema_version` (e.g. a CI check
  diffing `architecture-schema.sql` against the last-bumped commit) — not requested by the
  roadmap item, would be new scope.
- Issue #51 part 2 (duplicated call sites) — filed separately as roadmap item 3.8.

## Ratchet

_(first round, no loop-back yet)_
