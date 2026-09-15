# Spec preparation — ocaml-data-preservation

## Independent inputs

Spec researcher Sol session `01a0a62f-39ef-7211-b8f8-66eac2c7219d`: source joins are name-only; distinct selected artifact paths must retain separate catalogue identities. New finding: `tezt/fixtures/functor_catalogue/lifecycle_checks.js` currently requires copied and symlinked CMT rejection. This is an intentional behavior change requiring amended lifecycle assertions and a nonidentical-artifact negative control, not deletion of coverage.

Clarifier Terra session `01a0a631-0e8a-7e62-b6ad-197a9d0fe8bc`: eight material questions below. All are resolved as bounded engineering details under the approved scope; no further user questions or invented answers.

## Clarifications

| Q | Resolution |
|---|---|
| Source-aware matching? | Main schema joins functions to modules by module_id. Compare exact source-relative paths after lexical slash/dot normalization, never basename/suffix/underscore matching. Provided mismatching paths never fall back to name. Missing path may bind only a unique exact name; otherwise persist NULL ID with a diagnostic. |
| Flat schema? | Detect schema shape once. Flat functions without integer IDs, and standalone effects-only databases, retain NULL IDs and all effect payloads; do not invent IDs. A malformed advertised ID-based schema is a database error, not a flat-schema fallback. |
| Row equality? | Function name, optional source path, kind, optional target, producer, directness and soundness define effect payload equality. NULL and empty text remain distinct. Repeated equal payloads are idempotent; different soundness survives separately. Existing persisted payloads are not deleted during index migration. |
| Error transaction? | Schema preparation and writes are transactional. Any SQL preparation/bind/step/commit error aborts with Error/nonzero CLI and no success summary; batch inserts roll back. Only an exact persisted payload duplicate can increment the duplicate count. Reloading a matching payload repairs an obsolete function ID rather than retaining wrong association; changed associations count as written. No recovery claim for already-lost historic payloads. |
| Source normalization? | A present relative cmt_sourcefile is interpreted relative to the explicit source root, never the object-file directory. An absolute source under that root becomes root-relative, outside-root paths stay absolute. Normalize lexical dot segments; retain literal underscores. Missing source remains None, not a fake .cmt source. The caller must select the root matching the producer metadata; no heuristic artifact-directory reconstruction or general relocation claim. |
| Shadowed definitions? | For producer-supported top-level Tpat_var bindings, final source-order binding retains bare name and preceding occurrences use #1, #2, matching existing graph identity. Nested-module/lambda effect attribution is not expanded by this fix. Legacy short-name effect inputs without disambiguating binding information do not establish complete shadowing coverage. |
| Exact-copy evidence? | Same resolved source and compiler unit plus equal full artifact bytes associated with a successfully indexed representative. No source-digest-only, name-only, normalized-CMT or arbitrary winner policy. Scope is immutable build inputs; changed/unreadable representatives cannot authorize reuse. Reuse table is per run. All selected paths retain independent catalogue and binding collection. |
| Lifecycle controls? | Copies and symlinks succeed with one graph, two collected artifact records and earned catalogue/binding markers when all collections succeed. A readable CMT changed in content for the same source must still reject, preserve dropped/MAY_TOP behavior and withhold catalogue eligibility. Reindex resets reuse state. |

## Stories

### US-1: Correct source-aware effect association (P0)

As an index consumer I want loaded effects to reference their own source function so homonyms do not contaminate another module.
Priority: confirmed wrong-ID attribution. Excludes complete higher-order/nested effect analysis.
Independent test: real loader and real compiled OCaml producer with homonym/path fixtures.

1. Given main functions a.ml/f ID1 and b.ml/f ID2, when both effect payloads load, then each retains its path and own ID.
2. Given ambiguous pathless f, unmatched provided c.ml/f, or a flat-schema function, when loaded, then effects remain stored with NULL IDs and ambiguity/unmatched diagnostics where applicable, never arbitrary association.
3. Given CMT source src/a.ml and explicit source root, when emitted from a deeply nested object directory, then the path remains src/a.ml, not object-dir/src/a.ml; absolute paths under the root normalize equivalently and underscores are literal.
4. Given two top-level f bindings, when emitted and loaded, then earlier f#1 and final f retain distinct effect identity.

### US-2: Lossless and truthful effect persistence (P0)

As a producer operator I want exact duplicate accounting and atomic errors so a successful load cannot conceal rejected data.
Priority: current writer mixes errors with duplicates. Excludes reconstruction of old missing payloads.
Independent test: actual loader on temporary databases with constraints/triggers and legacy index.

1. Given two equal payloads, when loaded twice, then one row persists and exact duplicates are counted separately from writes.
2. Given different soundness or NULL versus empty optional fields, when loaded into an old migrated database, then distinct payloads remain distinct without deleting old rows.
3. Given a later row that fails an SQL constraint after an earlier valid row, when loading the batch, then CLI is nonzero, no success summary appears, and neither new row commits.
4. Given an old wrong function ID for a payload, when the same payload is reloaded against source-aware functions, then its association is corrected; another unchanged reload is a duplicate.

### US-3: Exact-copy graph reuse without losing artifact provenance (P0)

As a CMT index operator I want proven copies to share graph facts while each selected artifact remains accounted for.
Priority: reproduced duplicate rejection. Excludes independently compiled variants, assigned to stage 4 with explicit user approval.
Independent test: compiled small functor fixture, actual copy and symlink, real CLI and catalogue/binding queries.

1. Given two exact copies of a supported source CMT, when indexed, then graph rows equal the single-artifact graph, both artifact catalogues/bindings are collected, CLI succeeds and markers are earned only after successful storage.
2. Given a symlink path and its target selected separately, when indexed, then both selected path identities survive and only graph extraction is reused.
3. Given two nonidentical readable CMTs sharing a source, when indexed, then explicit conflict/drop behavior remains and no success is borrowed from the first artifact; #68 is not declared fully resolved.
4. Given reindexing and a failed representative or catalogue callback, when processed, then no stale reuse or false catalogue/binding completion occurs.

## External prior art

- OCaml Cmt_format 5.3 separates source path, build directory, compilation arguments and typed annotations: https://ocaml.org/p/ocaml-compiler/5.3.0/compiler-libs.common/Cmt_format/index.html . This bounded producer path contract takes an explicit source root; it does not claim arbitrary metadata relocation.
- Dune artifact variables provide explicit CMT lookup: https://dune.readthedocs.io/en/stable/advanced/variables-artifacts.html . No reconstruction of source identity from internal object directory spellings.

## Candidate checks

Self-contained Node checks under roster/ocaml-data-preservation/ with 0=pass, 1=assertion, 2=setup error: check-effects.js (US1/2), check-cmt-copies.js (US3), check-tezos.js (fixed410 neutral callgraph replay, plus scoped effects source/association observations). Native tests also join dune runtest. No model-only acceptance.

## Adversarial challenge resolutions

Fresh challenger Sol `01a0a632-cc7f-7ee0-9bc1-d969e64b88ec`; all twelve resolved from existing contracts and approved bounded scope, no additional user direction required.

| ID | Story | Challenge | Resolution |
|---|---|---|---|
| C1 | US1 | Module vs function source disagreement | Main-schema modules.path is authoritative through module_id; alternate ID/file_path fixture schema uses file_path. No hybrid field precedence or fuzzy fallback. Missing match yields NULL with diagnostic. |
| C2 | US1 | Unique pathless association later becomes ambiguous | Recompute association for each reloaded payload; replace obsolete ID by NULL if now ambiguous. No automatic response to unrelated external database edits between loads. |
| C3 | US1 | Source order and generated locations | Use Typedtree structure-list/value-binding order, not line sorting; final occurrence keeps bare name. Location equality does not merge bindings. |
| C4 | US1 | Compiler metadata has build contexts beyond source paths | Approved stage1 does not unify divergent contexts; main index still rejects nonidentical same-source CMTs. Explicit source-root contract is bounded, documented and tested. No producer path claims for arbitrary relocated/build-dir metadata. |
| C5 | US2 | Multiple equal old payloads with different IDs | Refuse incompatible duplicate existing rows transactionally, do not delete or guess. Valid legacy schema's payload index already prevents this case. |
| C6 | US2 | Obsolete association keys vs retention | Only canonical documented legacy index is upgraded; retain row IDs and payload columns, change function_id only on reloading that payload. Unknown extra constraints that prevent preservation cause Error with rollback. |
| C7 | US2 | Non-SQL failures | Preserve malformed-input default refusal and explicit allow-skip behavior. Propagate input/IO errors without successful load reporting. Filesystem/producer interruption cannot imply a complete stream; no end-to-end stream completeness or crash-after-commit/output atomicity promise. |
| C8 | US2 | Mixed repairs/duplicates followed by abort | Counts are returned only after commit. Written counts insertions plus changed associations, skipped counts exact unchanged payloads; on failure no counts are reported as committed success. |
| C9 | US3 | Copy selected under different source roots | Cache is scoped to one run/root and keyed by resolved source/unit; never reused across runs or roots. |
| C10 | US3 | Path spellings/symlink chains | Existing discovery and exact-string selection remain unchanged; no realpath-based catalogue dedup. Filesystem loop behavior outside this change remains unchanged. |
| C11 | US3 | Representative success / callback failure | Admit reuse only after representative graph extraction returns without new statement failures. Each duplicate runs its own catalogue/binding collection, whose failures independently prevent relevant markers. An earlier failed catalogue is never relabelled collected by another copy. |
| C12 | US3 | Dune single artifact vs selected spellings | Retain existing FunctorCatalogueInput definition: one exact selected path, not unique physical program. Exact repeats collapse only in existing selected_inputs; distinct spellings/copies remain distinct with shared graph only. |

Edge cases EC1/2/4/6/7/8/10 retain the specified behaviors. EC3 is C2; EC9 follows immutable-input scope and changed/unreadable input refusal. EC5 uses existing NDJSON enum/default parsing; this stage changes persistence, not the parser grammar, and SQL/IO failures are never duplicate success. No new size-limit promise.
