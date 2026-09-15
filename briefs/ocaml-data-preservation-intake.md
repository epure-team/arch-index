# Intake Brief — ocaml-data-preservation

**Date:** 2026-09-15
**Status: VALIDATED**
**Type:** api-change
**Trust boundary:** no

## Goal

First of the five approved delivery stages: repair confirmed effects identity/path losses and duplicate CMT handling before implementing bounded 0CFA. Maintain explicit unknown/ambiguous outcomes and measured provenance; do not merge distinct artifacts merely because names or source paths coincide. The historical #26 loss percentage is not a reproduced acceptance target; current wrong function-ID attribution and #68 duplicate rejection are reproduced.

User accepted the proposed split with "ok ok continue": this stage handles proven exact-copy CMT duplicates; independently compiled variants move explicitly to stage 4 with functor contexts. Issue #68 remains partial, not closed. Routine Type/api-change and Trust boundary/no approval follows standing autonomous Roster authorization; no quiz answers are attributed to the user.

## Scope Boundary

- No 0CFA, functor actual substitution or new analysis binary in this stage.
- No Tezos source/build changes, vulnerability research, unrelated files, PR93 or foreign worktree cleanup.
- No claim of complete OCaml effect coverage or equivalence from source digest alone.
- No issue closure based only on a synthetic copy test while independently compiled copies remain unsupported.
- Each delivered stage requires independent Roster review/QA, exact-head green required CI and guarded merge before its successor.

## Relevant Files

| File | Role | Key snippet |
|---|---|---|
| `lib/arch_effects/effects_db.ml` | Effect association and persistence | `SELECT id FROM functions WHERE name=? LIMIT 1` |
| `lib/arch_effects/effects_db.mli` | Writer contract | `(int * int, string) result` |
| `lib/arch_effects/effects_load.ml` | Input validation / count boundary | `Effects_db.write_effects ~db_path recs` |
| `lib/arch_effects/ocaml_effects_extractor.ml` | Source paths and effect identity | `Filename.concat (Filename.dirname cmt_path) f` |
| `bin/arch_effects_load/main.ml` | Observable summary / failure status | `effects written, ... skipped` |
| `bin/arch_effects_ocaml/arch_effects_ocaml.ml` | Producer source-root options | `source_root_arg` |
| `effects-schema-migration.sql` | Effect deduplication key | `fn_effects_identity` |
| `lib/arch_index/arch_index_cmt.ml` | CMT graph admission | `insert_module` and `on_implementation` |
| `lib/arch_index/arch_index.ml` | Per-artifact catalogue accounting | `selected_catalogue_inputs` / `catalogue_collected` |
| `lib/arch_index/arch_index_support.ml` | Existing source resolution | `source_path_of_cmt` |
| `architecture-schema.sql` | Source-indexed module identity | `path TEXT UNIQUE NOT NULL` |
| `test/test_effects.ml` | Unit writer/loader tests | `create_test_db` |
| `tezt/tests/effects.ml` | Real producer/loader/query fixture | `register_ocaml` |

## Architecture Notes

Effect binding currently ignores file paths; two functions `f` in `a.ml` and `b.ml` receive one function ID even though both effect rows are stored. Association must consider source identity and preserve ambiguous/unmatched effects rather than choose an arbitrary row. Flat-schema compatibility must remain explicit. SQL failures cannot be represented as successful duplicate skips.

The graph schema permits one module per source path. Artifact catalogue/binding identity is separately per artifact and producer run. Skipping an artifact before its catalogue callback would silently break that completeness contract. Exact-byte copies can safely share extracted graph facts while retaining separate artifact records; independently compiled copies are not necessarily byte-identical. A broader equivalence rule or multi-variant module model requires an explicit contract covering all graph, type, exception and error-channel facts, not just call counts.

Fresh Tezos baseline: 410 pinned CMTs, 45052 rows, Irmin 4849 / protocol 12171 resolved relations, unchanged canonical output. See `roster/ocaml-data-preservation/preflight.md` for commands and receipts.

No managed claims reconciler, KB or installed research-orientation pack. Autonomous approval covers routine gates; no quiz answers or approval of a scope reduction are fabricated.

### Frozen bounded behavior for decomposition

- Main-schema association uses modules.path through module_id; the alternative ID/file_path schema uses that path. Exact lexical-normalized source matching, no suffix/basename guessing. Missing path binds only a unique exact function name; otherwise preserve NULL with diagnostic. Flat/no-functions effects storage keeps NULL IDs; malformed advertised ID schema errors.
- Preserve distinct payloads differing by soundness or NULL/empty optional fields. Exact unchanged payload reload is a duplicate; obsolete function IDs are recomputed for the reloaded payload (including clearing newly ambiguous IDs), updates count as written. Preserve row IDs/payloads during canonical legacy index migration; incompatible preexisting duplicates/extra constraints cause transactional refusal rather than deletion.
- Writer schema preparation and record batch commit atomically on success; SQL/IO failures are not duplicate skips. Counts are published only after commit. Existing explicit CLI migration remains a separate operation; malformed-input/allow-skip grammar is unchanged. No end-to-end stream completeness or output-after-commit atomicity claim.
- Effects producer interprets relative cmt_sourcefile under the selected explicit source root, never the object directory. Absolute paths under the root become relative; outside-root stay absolute; missing path stays None. No arbitrary CMT relocation claim. For supported top-level variable bindings use Typedtree order: final f stays bare, preceding bindings f#1, f#2. No nested-module/lambda coverage expansion.
- Exact-copy reuse is per run/root, same source/unit, full artifact equality against a successful representative; no reuse after graph extraction raised or increased statement failures. Duplicates collect their own catalogue/binding data; callback failures still block corresponding markers. Distinct selected path strings stay distinct, including symlinks. Nonidentical same-source artifacts retain explicit rejection/unknowns; #68 remains partial.
- Update the existing copied/symlinked artifact lifecycle expectations intentionally, retaining nonidentical conflict, failed collection, reindex and zero-selection coverage. Test source-path, homonym, shadowed binding, flat schema, NULL/empty/soundness, rollback and legacy reload behavior. Add standalone checks `roster/ocaml-data-preservation/check-effects.js`, `check-cmt-copies.js`, `check-tezos.js`, plus native test integration under `test/` or `tezt/tests/` and associated dune wiring. Keep pinned410 canonical callgraph unchanged and report effect observations without claiming a completeness percentage.
- Allowed supporting changes: `lib/arch_effects/` modules/interfaces/dune, CMT ingestion modules/interfaces, effects CLI docs, `docs/effects-data-preservation.md`, relevant `specs/functor-instance-resolution.md` amendments, `tezt/fixtures/functor_catalogue/lifecycle_checks.js` and relevant test wiring. No generic schema redesign. Existing self-index golden fixtures may be updated only after actual measured source-driven changes and review, never blind refresh.

## Quality Gates

```bash
rtk proxy opam exec -- dune build
rtk proxy opam exec -- dune runtest --force
rtk proxy node scripts/review-bundle-verify.js
rtk proxy git diff --check
```

Lint/format: no separate configured command documented. New targeted identity, failure atomicity, duplicate/conflict and catalogue-preservation checks must be specified and demonstrated RED/GREEN. Re-run pinned Tezos inputs and compare identities, not merely aggregate gains. Builds/tests and source/report writes are serialized.

## Open Questions

None. Exact-copy reuse must retain per-artifact catalogue/binding records. Nonidentical same-source artifacts retain explicit rejection and conservative unknown behavior; no guessed equivalence. Independently compiled variant representation is assigned to stage 4 by the user's scope approval.
