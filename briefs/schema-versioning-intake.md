# Intake Brief — schema-versioning

**Date:** 2026-09-03
**Status: VALIDATED**
**Type:** fix
**Trust boundary:** no

## Goal

Fix issue #51 part 1: `comment_db_meta.schema_version` is written as the hardcoded literal `"1"`
at two call sites (`lib/arch_index/runner.ml:335`, `:468`) and has never been bumped, while the
schema it names has grown through two additive migrations
(`capabilities-schema-migration.sql`, `effects-schema-migration.sql`) plus whatever Phase 1 of the
roadmap adds next. Nothing reads `schema_version` anywhere in the codebase — it is purely
decorative. A downstream consumer has no way to learn, without opening a database and guessing,
which tables/columns a given schema version promises; a query against a stale assumption silently
returns zero rows / null rather than failing loudly.

A second, independent instance of the same root cause (verified against `main`, not just the
issue text): `lib/arch_index/arch_index_db.ml`'s `schema_path` default is
`"docs/architecture-schema.sql"`, but the real file lives at the repo root
(`architecture-schema.sql`). This one fails LOUDLY (`arch_index.ml` exits 1 with a message that is
itself misleading — "run from repository root" does not fix it, since every CI/doc/README caller
already works around it with an explicit `--schema-path=architecture-schema.sql`) — not the silent
failure #51 is about, but the same underlying discipline gap.

**Design decision (human, 2026-09-03):** `schema_version` becomes a `(major, minor)` pair, not a
monotonic integer — minor for additive changes (all of 1.1–1.6 in Phase 1 are new nullable
columns), major for a future breaking change (a column/table removal). This was flagged in the
roadmap as a decision to make once, before Phase 1 lands six more schema changes behind it.

## Scope Boundary

Out of scope:
- A capability-check API (the issue's third suggested option) — versioning + shipping the schema
  is the minimum that unblocks Phase 1; a capability-check API is a nice-to-have layered on top,
  not a substitute, and is not requested by the roadmap item.
- Phase 1's actual schema changes (1.1–1.6) — this item only builds the versioning/shipping
  mechanism they will use; it does not add any of their columns.
- Issue #51 part 2 (duplicated call sites) — filed separately as roadmap item 3.8, a distinct
  feature request with its own effort estimate (M/L) unrelated to this fix.
- Rewriting `arch_index_db.ml`'s schema-loading mechanism (still reads from a file path at
  runtime) — only its dead default path is fixed; the embedded-string constant is an ADDITIONAL,
  out-of-band API for consumers who want to diff without opening a database, not a replacement for
  the existing runtime behavior.

## Relevant Files

| File | Role | Key snippet |
|---|---|---|
| `lib/arch_index/runner.ml` | Both `schema_version` write sites | `set_meta db "schema_version" "1"` at lines 335, 468 |
| `lib/arch_index/arch_index_db.ml` | `schema_path` dead default | `\| None -> "docs/architecture-schema.sql"` (line ~24) — real file is at repo root |
| `architecture-schema.sql` (repo root) | The base schema, 16 tables — not shipped as an installed data file or embedded string anywhere |  |
| `capabilities-schema-migration.sql`, `effects-schema-migration.sql` | Two additive migrations already applied without any `schema_version` bump | |
| `lib/arch_index/dune`, `lib/arch_io/dune`, `lib/jsonrpc_client/dune` | Install stanzas (PR `01e9cef` made the OCaml libraries installable) — no `.sql` file is a package data file anywhere | |
| `docs/install.md:44`, `README.md:49`, `.github/workflows/ci.yml:89` | All three already pass `--schema-path=architecture-schema.sql` explicitly, working around the dead default | |

## Architecture Notes

Fix direction (from the roadmap's own research, not re-derived here):
1. **Ship the schema for out-of-band inspection.** Generate an OCaml module embedding
   `architecture-schema.sql`'s contents as a string constant (`Arch_index_db.schema_sql : string`)
   via a dune rule, rather than fighting the opam install-path question — a consumer that already
   depends on the `arch-index` library gets the exact schema text a given build promises, without
   opening a database or guessing a filesystem path.
2. **Fix the dead default** in `arch_index_db.ml`'s `schema_path` (`docs/architecture-schema.sql`
   → `architecture-schema.sql`) as an independent one-line drive-by — this makes every existing
   `--schema-path=...` workaround in docs/CI/README redundant (safe to leave them; removing them
   is optional cleanup, not required).
3. **Bump `schema_version` to `(major, minor)`.** Retroactively document the two already-shipped
   migrations as version bumps in a new `docs/schema-versions.md` (or equivalent) stating the
   table/column set each version added, and change both `set_meta db "schema_version" "1"` call
   sites to write the current version. `comment_db_meta.value` is `TEXT`, so the tuple can be
   stored as `"1.2"` (a single string) rather than requiring a schema change to
   `comment_db_meta` itself — decided at implementation time, keep it simple.

## Quality Gates

```bash
# Build (from repo root, under the local _opam switch)
eval "$(opam env --switch=/home/mathias/dev/arch-index --set-switch)"
dune build

# Tests
dune test --force

# No documented lint/format gate for this repo's OCaml beyond dune build's own warnings-as-errors
```

## Open Questions

_(empty — the one open design question, monotonic vs (major, minor), was resolved by the human
before this brief was written)_
