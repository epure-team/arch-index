# Ship Gate — schema-versioning

**Date:** 2026-09-03
**Status: VALIDATED** — human quiz passed (all 3 recommended options confirmed), PR opened:
https://github.com/epure-team/arch-index/pull/53
**Review:** GO (round 1) — `briefs/schema-versioning-review.json`
**QA:** GO (round 1) — `briefs/schema-versioning-qa.md`

## What this ships

Fixes issue #51 part 1 only (part 2, duplicated call sites, is filed separately as roadmap item
3.8 — do not close #51 with this PR).

`comment_db_meta.schema_version` was hardcoded `"1"` and never bumped, while the schema it named
grew through two additive migrations with no version tracking — nothing anywhere read it, so it
was purely decorative. This PR:

1. Makes `schema_version` a hand-bumped `"<major>.<minor>"` string
   (`Arch_index_db.current_schema_version`), the single source both write sites now read from.
   Design decision (human, before implementation): `(major, minor)`, not a monotonic integer.
2. Ships `architecture-schema.sql`'s contents at compile time via `ppx_blob`, re-exported as
   `Arch_index.schema_sql : string` — a consumer can diff against the exact schema a build
   promises without opening a database.
3. Fixes a dead `schema_path` default (`docs/architecture-schema.sql` → the real
   `architecture-schema.sql` at the repo root).
4. `docs/schema.md` documents the version history, retroactively dating the two already-shipped
   migrations as `1.1`/`1.2`.

**A fresh review round found and fixed a real, structural defect in the first draft:** the fix
initially stamped BOTH schemas this codebase has — the main schema (`architecture-schema.sql`,
grown by the two migrations) and a structurally different flat 3-table schema (the LSP-based
path's own inline schema, the actual `arch-index` CLI's production entry point) — with the SAME
version constant. Every database the real CLI produces would have been stamped `"1.2"`, implying
capability-layer tables (`function_effects`, `attack_edges`) it can never have. Fixed by giving the
flat schema its own distinct, correctly-scoped version identity
(`current_flat_schema_version`, `"1.0"`) and by making the main-schema path (which never wrote
`schema_version` at all before this fix) actually write it. Verified independently, twice, with
both real production binaries against fresh fixtures each time.

## Commits on this branch (2, both conventional)

```
d47dc49 fix(schema): HIGH — don't stamp the flat schema with the main schema's version
ad6ad83 fix(schema): version comment_db_meta.schema_version, ship the schema (#51 part 1)
```

Branch `fix/schema-versioning`, based on `69e5c3d` — matches `origin/main`'s current tip
(fetched and confirmed), clean fast-forward-able rebase target, no rebase needed.

## Push mode

`push_mode` not set in `.harness/harness.json` (absent from this repo) — defaults to `pr` mode.
