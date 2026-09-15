# Implementer — ocaml-data-preservation

**Status: VALIDATED**
**Mode:** full

## Goal

Implement stage1 of the approved five-stage plan: correct effects source-aware association/path emission, truthful lossless persistence, and exact-copy CMT graph reuse without losing per-artifact catalogue/binding provenance. Independently compiled variants are explicitly stage4; #68 remains partial. No0CFA yet.

## Required behavior

1. Main functions join modules.path via module_id. Alternative id/name/file_path schema supported; flat/no-functions effects-only databases retain NULL IDs. Detect schema once; malformed advertised ID-based schema errors. Supplied path requires exact lexical-normalized path+name, never suffix/basename/name fallback. Missing path may bind unique exact name; unmatched/ambiguous stores NULL with diagnostics.
2. Complete effect payload = function_name, optional file_path, value_kind, optional target, producer, is_direct, soundness. NULL differs from empty. Equal unchanged reload counts duplicate; different payload survives. Recompute ID on reload, including clearing newly ambiguous associations; changed association counts written. Preserve old row IDs/payloads. Canonical legacy index upgrade is transactional; incompatible existing duplicate rows or constraints refuse, never delete to make migration succeed.
3. Writer schema preparation and batch writes are atomic; check SQL prepare/bind/step/commit errors. On failure rollback and Error/nonzero, no success counts. Explicit CLI migration stays separate; parser defaults/allow-skip unchanged. No stream/output-after-commit atomicity claim.
4. Producer relative cmt_sourcefile is relative to selected explicit source root, not object directory. Contained absolute paths become relative, outside-root stay absolute, missing stays None. Lexical dot normalization, literal underscores. Supported top-level Tpat_var bindings use Typedtree source order: earlier f#1/f#2, final f. No expansion of nested/lambda effects coverage.
5. CMT graph reuse only within one run/root for same resolved source/compiler unit/full artifact bytes and a representative that completed graph extraction without increased statement failures. Unreadable/changed inputs cannot authorize reuse. Each selected copy/symlink still gets separate catalogue/binding collection with existing path-string identity; callback failures withhold relevant markers. Nonidentical same-source artifacts still reject/drop/unknown; reindex cache resets. Actually rejected insertion is never borrowed success.

## Files / scope

- `lib/arch_effects/effects_db.ml`, `.mli`: existing name-only LIMIT1 and INSERT OR IGNORE must become source-aware, explicit-error persistence.
- `lib/arch_effects/effects_load.ml`, `.mli`, `ocaml_effects_extractor.ml`, dune; optional small path helper module/interface within `lib/arch_effects/`.
- `effects-schema-migration.sql`; `bin/arch_effects_load/main.ml`; `bin/arch_effects_ocaml/arch_effects_ocaml.ml`.
- `lib/arch_index/arch_index_cmt.ml`, `.mli`, `lib/arch_index/arch_index.ml`: run-local reuse and retained `on_implementation` callback; existing `insert_module` failure remains negative case.
- `test/test_effects.ml`, `test/dune`, `tezt/tests/effects.ml`, new `tezt/tests/data_preservation.ml` if needed, `tezt/tests/main.ml`, `tezt/tests/dune`.
- `tezt/fixtures/functor_catalogue/lifecycle_checks.js`: intentionally change exact copies/symlinks from dropped to collected, retaining nonidentical failure control and old failure/reindex/zero-selection controls.
- `roster/ocaml-data-preservation/check-effects.js`, `check-cmt-copies.js`, `check-tezos.js`, supporting fixture/probe files under same task directory.
- `docs/effects-data-preservation.md`; `specs/functor-instance-resolution.md` narrow lifecycle amendment; task spec and briefs/friction/roadmap artifacts.
- Self-index fixture changes only after measured source-driven drift and review: `test/fixtures/self-index-stats.txt`, `test/fixtures/origin-consumer/reference.json`, `test/fixtures/origin-consumer/self.allow`, `checks/origin-recurring-consumer.js` if genuinely necessary, no blind refresh.
- User-approved scope extension (2026-09-15): `tezt/tests/must_null_ceiling.ml`, recalibrate `clean_measured` from 524 to 554 after pristine A=B545/C=D554 source-only evidence. Keep headroom25, queries and floors unchanged; see `roster/ocaml-data-preservation/calibration-attribution.md`.

Do NOT edit Tezos sources/CMTs, old baselines/checkers, unrelated dirty files, PR93, foreign worktrees or toolchain config. No commits/PR/merge from implementation subagents; root owns gated handoff.

## Sequence and TDD

Follow plan steps1–5. Write runnable failing assertions before production edits for each behavior; prove failure is semantic, not a missing executable or syntax failure. Node check convention0PASS/1assertion/2setup. Do not weaken tests to satisfy implementation; existing copy lifecycle expectations change only because the approved behavior changes, with negative conflict coverage retained. Scope includes all robustness/docs/tests, not follow-up debt.

Only one writer/build owner at a time, no worktree. Use apply_patch for manual edits; all shell commands `rtk proxy ...`. Capture real results and failures. Baseline full dune suite already passed in preflight.md; resume build/bundle/test collection also passed. Max3 correction attempts per bounded unit then report concrete remaining issue, no fabricated success.

## Quality gates

```
rtk proxy opam exec -- dune build
rtk proxy opam exec -- dune runtest --force
rtk proxy node scripts/review-bundle-verify.js
rtk proxy git diff --check
rtk proxy node roster/ocaml-data-preservation/check-effects.js
rtk proxy node roster/ocaml-data-preservation/check-cmt-copies.js
rtk proxy node roster/ocaml-data-preservation/check-tezos.js
```

CHECK1 covers main/alternative/flat paths, homonyms, shadowing, NULL/empty/soundness, migration, obsolete ID and rollback. CHECK2 covers bytes, source/unit, independent catalogues/bindings, markers, nonidentical rejection, reindex/failed representative/collection. CHECK3 uses existing pinned410 manifest and generated new-stage baseline package (`improvement/2026-09-15-ocaml-cfa/stage1-baseline/`), requiring unchanged canonical callgraph (45052rows, digest1799c07fd3eb87d4bca433b15b7daeb47f466f90cb098541372e1dd9dd7bac7a; relations4849/12171), unchanged input digests and honest effect observations. Corpus checks local-only, not CI availability claims. No separate lint/coverage setup installed.

## Review priorities / risks

Exact identity not count-only improvements; stale-ID reload; transactional migration; callback/marker independence; immutable-input reuse evidence; OCaml5.3 local switch (system compiler5.5 is wrong). Use `opam exec --` for compiler/builds. No general source-relocation or complete-effect claim.
