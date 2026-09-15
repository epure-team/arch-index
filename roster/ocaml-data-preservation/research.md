# Research — ocaml-data-preservation

_Generated: 2026-09-15_
_Mode: full_
_Online research: enabled_

## Research execution

Neutral input: `questions.manifest.json`, seven questions, canonical questions SHA256 `a7b15983953b2c0ac9ec01dfd48652f25f7060736cb2acf869f2ca49efec9701`.
Four independent read-only CLI documentarians completed: locator Terra (`01a0a5ef-08b5-70b2-862d-f7f207467be6`), analyzer Sol (`01a0a5ee-ff54-71d3-90f0-60e29c4e9afa`), pattern finder Terra (`01a0a5ef-0419-7753-9941-641a9d257278`), external researcher Sol (`01a0a5f0-8601-7732-b5f3-81afe7476cbd`). Native agent quota was exhausted; ephemeral CLI processes supplied the separate contexts. Three local roles ran concurrently; external research followed. Model substitution follows the user's Terra/Sol authorization. Synthesis below excludes recommendations.

## Question 1: Existing identity schemas and joins

Modules have synthetic IDs and unique paths. Functions have synthetic IDs and uniqueness on `(module_id, name)`; OCaml collection also distinguishes shadowed definitions (the test expects `f` and `f#1`). The unit registry keeps distinct source paths under a unit name; it is not a CMT ingestion deduplicator. The effect record interface carries a function name and optional file path, not a binding location or executable identity. Its loader resolves `function_id` by name alone with `LIMIT 1`. Effect row uniqueness uses function name, coalesced file path, kind, target, producer and directness; neither `function_id` nor `soundness` participates in that key.

**References:**
- `architecture-schema.sql:131` — module identity.
- `architecture-schema.sql:151` — function schema; unique key at line 195.
- `lib/arch_index/arch_index_cmt.ml:98` — unit-name registry of source paths.
- `lib/arch_effects/extractor_intf.mli:52` — effect record fields.
- `lib/arch_effects/effects_db.ml:80` — name-only function lookup.
- `effects-schema-migration.sql:78` — effect deduplication key.
- `tezt/tests/shadowed_definitions.ml:69` — shadowed definitions fixture and distinct identity assertions.

## Question 2: Effects extraction, serialization and loading

The OCaml scanner sorts CMT paths and excludes basenames starting `dune__`. Implementation annotations are traversed to emit direct effects under current top-level binding names. Relative `cmt_sourcefile` values are joined to the CMT directory. The CLI serializes effect records as JSON lines. The loader accepts effect/value-kind fields, applies defaults, then writes via `effects_db`. Unmatched function names remain stored with a NULL function ID. Existing query tests cover path-sensitive homonyms independently of loader ID assignment.

**References:**
- `lib/arch_effects/ocaml_effects_extractor.ml:94` — scanner.
- `lib/arch_effects/ocaml_effects_extractor.ml:125` — implementation annotation dispatch and source path construction.
- `lib/arch_effects/ocaml_effects_extractor.ml:152` — binding-name collection.
- `bin/arch_effects_ocaml/arch_effects_ocaml.ml:21` — JSON serialization.
- `lib/arch_effects/effects_load.ml:25` — JSON decoding and defaults.
- `lib/arch_effects/effects_load.ml:83` — writer invocation.
- `lib/arch_effects/effects_db.ml:117` — row persistence.
- `tezt/tests/effects.ml:350` — path-sensitive query fixture.

## Question 3: Duplicate CMT ingestion

The main scanner collects sorted CMT/CM TI artifacts (excluding basenames ending `__`); each selected CMT is processed. Module insertion is a plain INSERT keyed by source-derived module path. A rejected module row records a dropped compilation unit and invokes catalogue reporting with a dropped-module outcome. The unit-path registry separately deduplicates identical source paths. The catalogue records artifact path, producer run, unit/source/module information; no per-executable or CMT-digest equivalence key is present in that schema.

**References:**
- `lib/arch_index/arch_index_cmt.ml:310` — sorted recursive artifact scanning.
- `lib/arch_index/arch_index.ml:618` — selected artifact processing.
- `lib/arch_index/arch_index.ml:513` — module insertion.
- `lib/arch_index/arch_index_cmt.ml:3129` — source path and module registration.
- `lib/arch_index/arch_index_cmt.ml:3189` — rejected module handling and catalogue callback.
- `architecture-schema.sql:73` — artifact catalogue identity.

## Question 4: Counters and diagnostics

Main index insertion failures are counted globally and per table; dropped units and collection failures have explicit catalogue outcomes. The effects scanner warns and returns no records when a CMT cannot be read. Effects parsing separately counts malformed records; the database writer's skipped count combines idempotent duplicates with certain statement failures and per-record exceptions. Function lookup exceptions can yield NULL IDs without a dedicated ambiguity/unmatched counter.

**References:**
- `lib/arch_index/arch_index_db.ml:230` — insertion failure counters.
- `lib/arch_index/arch_index.ml:1866` — final failure reporting.
- `lib/arch_index/arch_index_cmt.ml:3205` — collection-failed catalogue outcome.
- `lib/arch_effects/ocaml_effects_extractor.ml:225` — CMT warning path.
- `lib/arch_effects/effects_load.ml:62` — malformed input handling.
- `lib/arch_effects/effects_db.ml:132` — skipped record accounting.
- `bin/arch_effects_load/main.ml:42` — exit and summary reporting.

## Question 5: Existing tests and fixtures

Effects tests exercise two-module homonyms with different purity and a real extraction/load pipeline. Separate hand-built path fixtures test longest suffix and literal underscores at query time. Unit writer tests inspect counts without seeding functions for same-name identity assertions. Shadowed definitions and qualified library scoping have independent callgraph fixtures. `duplicates.ml` tests duplicate function bodies, not duplicate CMT artifact ingestion.

**References:**
- `tezt/tests/effects.ml:30` — two-module homonym fixture.
- `tezt/tests/effects.ml:91` — pipeline invocation.
- `tezt/tests/effects.ml:350` — manually seeded path fixture.
- `test/test_effects.ml:75` — writer tests.
- `test/test_effects.ml:101` — NDJSON loader tests.
- `tezt/tests/shadowed_definitions.ml:69` — shadowed function definitions.
- `tezt/tests/qualified_library_scoping.ml:64` — wrapped library fixture.
- `tezt/tests/duplicates.ml:1` — duplicate body detection tests.

## Question 6: [ecosystem] OCaml compiler artifact metadata

Compiler-libs 5.3 CMT metadata distinguishes module name, annotations, source file, build directory, compilation arguments, load path, source digest, imports and interface digest. It also contains environments, declaration dependencies, UIDs and shapes. There is no dedicated final executable/stanza identity field. Typedtree is the typed program representation, not a precomputed per-function effect summary. CMT reading can return associated CMI information.

**References:**
- [OCaml compiler-libs 5.3 Cmt_format](https://ocaml.org/p/ocaml-compiler/5.3.0/compiler-libs.common/Cmt_format/index.html).
- [OCaml compiler-libs 5.3 Cmi_format](https://ocaml.org/p/ocaml-compiler/5.3.0/compiler-libs.common/Cmi_format/index.html).
- [OCaml compiler-libs 5.3 Typedtree](https://ocaml.org/p/ocaml-compiler/5.3.0/compiler-libs.common/Typedtree/index.html).
- Local installed `_opam/lib/ocaml/compiler-libs/cmt_format.mli` confirms these fields, including `cmt_declaration_dependencies`.

## Question 7: [ecosystem] Dune artifact layouts

Dune separates build contexts and supports wrapped libraries and executables. Its documented artifact variables expose CMT and CMTI artifacts; source path alone does not encode the complete build context. Internal object layouts are not a universal stable identity interface.

**References:**
- [Dune artifact variables](https://dune.readthedocs.io/en/stable/advanced/variables-artifacts.html).
- [Dune wrapped executables](https://dune.readthedocs.io/en/stable/reference/dune-project/wrapped_executables.html).
- [Dune library stanza](https://dune.readthedocs.io/en/latest/reference/dune/library.html).
- [Dune build contexts](https://dune.readthedocs.io/en/latest/reference/dune-workspace/context.html).

## Patterns found

| Pattern | File | Lines | Notes |
|---|---|---|---|
| Main source recovery | `lib/arch_index/arch_index_support.ml` | 211–237 | Existing files, preprocessed source fallback, project-relative paths |
| Idempotent effect storage | `lib/arch_effects/effects_db.ml` | 117–155 | INSERT OR IGNORE and changes count |
| Shadowed names | `tezt/tests/shadowed_definitions.ml` | 69–91 | Distinct `f` / `f#1` |
| Query path disambiguation | `tezt/tests/effects.ml` | 350–410 | Longest suffix and underscore controls |

## External prior art

| Interface | Source | Key finding |
|---|---|---|
| CMT metadata | OCaml Cmt_format above | Source, compilation and typed annotation fields are distinct |
| Artifact lookup | Dune artifact variables above | Explicit CMT/CMTI lookup rather than a universal guessed object layout |

## Coverage gaps

- Q3/Q5: no dedicated duplicate-per-executable-CMT regression was found in the searched tests. Source inspection does not establish equivalence of two independently compiled artifacts.
- Q1/Q2: the current effect record lacks a binding location; same-source shadowing is not uniquely represented by name/path alone.
- Q6/Q7: current official interfaces do not establish equivalence of different CMTs merely sharing module/source names.
- Runtime counts and reproductions belong to the separate diagnostic record, not this blind research synthesis.
