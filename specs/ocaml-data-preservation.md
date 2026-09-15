---
name: roster-spec
type: spec
status: live
feature: Bounded OCaml data preservation
brief: briefs/ocaml-data-preservation-intake.md
date: 2026-09-15
version: 1.0.0
---

# Spec — Bounded OCaml data preservation

## Clarifications

| Q | A |
|---|---|
| Which source relation? | Main schema modules.path through module_id; alternative ID/file_path schema uses file_path. Exact lexical-normalized paths, no fuzzy matching. |
| Missing path / flat schema? | Missing path may bind one unique exact name. Ambiguous/unmatched records remain NULL with diagnostics. Flat/effects-only schemas retain NULL IDs; malformed ID-based schemas fail. |
| Payload equality? | Name, optional path, kind, optional target, producer, directness and soundness; NULL differs from empty. IDs are recomputed associations, not payload identity. |
| Transaction/counters? | Writer preparation and batch are atomic. Count insertions/changed associations as written and unchanged exact payloads as duplicates, only after commit. Explicit CLI migration is separate; existing allow-skip parsing remains. |
| Producer paths? | Relative source metadata is relative to the explicitly selected root, not object directory. Contained absolute paths become relative; outside-root stay absolute; missing stays NULL. This is not arbitrary metadata relocation support. |
| Shadowing? | Supported top-level variable binding order follows Typedtree lists, not locations; final binding bare, earlier #N. No added nested/lambda effect coverage. |
| Duplicate eligibility? | Same run/root/source/unit and full artifact-byte equality with a successfully indexed representative. No normalized metadata equivalence. Immutable inputs; changed/unreadable inputs cannot authorize reuse. |
| Provenance / remaining scope? | Distinct selected artifact paths remain independent catalogue/binding inputs. Independently compiled variants remain rejected here and move to stage 4 by explicit user approval. #68 stays partial. |

## User Stories

### US-1: Correct source-aware effects (Priority: P0)

As an index consumer I want each effect associated with its own source function so homonyms do not contaminate other modules.
**Why this priority:** wrong-ID attribution is reproduced.
**Scope:** no complete higher-order, nested-module or historic effect recovery claim.
**Independent Test:** real loader and compiled producer with path, homonym and shadowing fixtures.
**Acceptance Scenarios:**
1. **Given** a.ml/f ID1 and b.ml/f ID2, **When** both effects load, **Then** each retains its source and own ID.
2. **Given** ambiguous pathless f, unmatched c.ml/f, or flat schema, **When** loaded, **Then** payloads remain stored with NULL IDs, with ambiguity/unmatched diagnostics where applicable.
3. **Given** metadata src/a.ml and explicit root, **When** emitted from a deeply nested object directory, **Then** its path is src/a.ml; contained absolute equivalents normalize identically and underscores stay literal.
4. **Given** two top-level f bindings, **When** emitted and loaded, **Then** earlier f#1 and final f retain distinct identities.

### US-2: Truthful, lossless persistence (Priority: P0)

As a producer operator I want exact duplicate accounting and atomic failure so successful loading does not conceal rejected rows.
**Why this priority:** existing writer mixes SQL errors and duplicate skips.
**Scope:** no reconstruction of already-lost historical records or atomicity between producer EOF and consumer output.
**Independent Test:** real loader with temporary legacy databases, constraints and injected SQL failures.
**Acceptance Scenarios:**
1. **Given** equal complete payloads, **When** loaded twice, **Then** one row remains and unchanged repeats count as duplicates.
2. **Given** payloads differing by soundness or NULL versus empty optional fields, **When** loaded into a legacy database, **Then** each distinct payload survives without deleting old rows.
3. **Given** a later SQL failure after an earlier valid row, **When** loading the batch, **Then** the CLI is nonzero, no success counts appear and no batch changes commit.
4. **Given** an old wrong association, **When** its payload reloads, **Then** the ID is corrected; a subsequent unchanged reload is a duplicate.

### US-3: Exact-copy reuse with independent artifact provenance (Priority: P0)

As a CMT operator I want proven copies to share graph facts while every selected artifact remains accounted for.
**Why this priority:** an exact copy currently causes a whole-unit rejection.
**Scope:** independently compiled variants are assigned to stage 4, not silently treated as equivalent.
**Independent Test:** real CMT CLI with a compiled functor fixture, copy, symlink and nonidentical same-source control.
**Acceptance Scenarios:**
1. **Given** two exact copies, **When** indexed, **Then** CLI succeeds with the single-artifact graph and two collected catalogue/binding inputs; markers require successful storage.
2. **Given** separately selected symlink and target paths, **When** indexed, **Then** both path identities survive and only graph extraction is shared.
3. **Given** nonidentical readable same-source CMTs, **When** indexed, **Then** existing explicit rejection/drop/unknown behavior remains, with no borrowed catalogue success.
4. **Given** reindexing or failed representative/collection, **When** processed, **Then** no stale reuse or false completion is produced.

## Challenges

Fresh independent research, clarification, challenger and formalizer session IDs and full resolutions are recorded in `roster/ocaml-data-preservation/spec-input.md`.

| ID | Story | Challenge | Resolution |
|---|---|---|---|
| C1 | US-1 | Competing source fields | modules.path authoritative in main schema; alternative file_path schema only when no module_id. |
| C2 | US-1 | Unique name becomes ambiguous | Recompute on payload reload and clear obsolete ID; unrelated DB edits are not automatically observed. |
| C3 | US-1 | Equal/generated locations | Typedtree declaration order, not location sorting. |
| C4 | US-1 | Cmt_format has additional build context | Explicit-root bounded contract; divergent CMTs are not unified. Prior art: OCaml compiler-libs 5.3 Cmt_format. |
| C5 | US-2 | Conflicting legacy duplicate rows | Transactional refusal, no arbitrary winner/deletion. |
| C6 | US-2 | Association repair vs payload retention | Retain row IDs and payload, change only reloaded association; preservation-blocking constraints fail. |
| C7 | US-2 | Non-SQL failures | Preserve parsing defaults/allow-skip; input IO fails without success. No crash-after-commit/output atomicity or stream completeness promise. |
| C8 | US-2 | Mixed repair/duplicate then failure | Return counts only for a committed batch; rollback prior batch changes on error. |
| C9 | US-3 | Different roots/runs | Reuse cache belongs to one run/root. |
| C10 | US-3 | Multiple path spellings | Preserve existing exact-string selection, not realpath catalogue identity. |
| C11 | US-3 | Partial graph or failed callback | Reuse only after extraction returns without new SQL failures; each catalogue/binding result is independent. |
| C12 | US-3 | Dune artifact vs selected spellings | Existing FunctorCatalogueInput means selected path, not unique physical program. Dune artifact variables do not change that existing contract. |

## Functional Requirements

### Source association

- **FR-001** [US-1]: When a path is supplied, the loader MUST use exact normalized source identity and exact function name; it MUST NOT fall back to basename, suffix, underscore or name-only matching. Trace: US1-S1/2, C1, CHECK-1.
- **FR-002** [US-1]: The loader MUST preserve unmatched/ambiguous effects with NULL IDs and diagnostics; pathless effects MAY bind only a unique exact name. Flat/effects-only schemas MUST retain NULL IDs, not fabricated IDs. Reload MUST recompute associations. Trace: US1-S2, C2, CHECK-1.
- **FR-003** [US-1]: The producer MUST normalize source metadata against the selected root as clarified above, retaining missing and outside-root distinctions. Trace: US1-S3, CHECK-1.
- **FR-004** [US-1]: The producer MUST preserve supported top-level shadowed binding identities by declaration order and MUST NOT claim unsupported nested/higher-order or divergent-build unification. Trace: US1-S4, C3/4, CHECK-1/2.

### Persistence

- **FR-005** [US-2]: The writer MUST preserve distinct complete payloads, including soundness and NULL/empty differences; unchanged equal payload reloads MUST be idempotent. Trace: US2-S1/2, CHECK-1.
- **FR-006** [US-2]: Migration/reload MUST preserve existing row IDs and payloads; incompatible preexisting duplicates or constraints MUST fail without guessed association/deletion. Trace: C5/6, CHECK-1.
- **FR-007** [US-2]: Reload MUST repair an obsolete association on the matching payload and count that change as written; unchanged association MUST count only as duplicate. Trace: US2-S4, C2/8, CHECK-1.
- **FR-008** [US-2]: Any writer preparation/bind/step/commit failure MUST abort with Error/nonzero CLI and rollback the batch without a successful committed-count summary. Default malformed input and input IO errors MUST refuse; explicitly allowed parse skips retain existing semantics. Trace: US2-S3, C7/8, CHECK-1.

### CMT reuse

- **FR-009** [US-3]: Graph extraction MAY be reused only for full byte-identical artifacts with the same resolved source/unit within one run/root; changed/unreadable inputs MUST NOT authorize reuse. Trace: US3-S1/3, C9, CHECK-2.
- **FR-010** [US-3]: Reuse MUST NOT cross runs/roots or merge selected-path identities; existing discovery/spelling behavior MUST remain unchanged. Trace: US3-S2/4, C9/10/12, CHECK-2.
- **FR-011** [US-3]: Each distinct selected artifact MUST retain independent catalogue and binding collection even when graph extraction is reused. Trace: US3-S1/2, CHECK-2.
- **FR-012** [US-3]: Reuse MUST require a successfully stored representative graph; an artifact's collection failure MUST prevent corresponding completion and MUST NOT be relabelled successful through another artifact. Trace: US3-S4, C11, CHECK-2.

## Acceptance Criteria

- AC-1 [US-1 happy path; FR-001/002/003]: Homonyms, exact paths and actual source-root producer output → correct identities, NULL for unmatchable input, no fabricated object-directory source.
- AC-2 [US-2 happy path; FR-005/007]: Reload equal payload → one row and duplicate; distinct soundness/NULL/empty → separate payloads.
- AC-3 [US-3 happy path; FR-009/011]: Exact copies → successful single graph with separate complete artifact provenance.
- AC-4 [US-1, C1; FR-001/002]: Competing path fields or flat schema → only prescribed source relation or NULL, no hybrid fallback.
- AC-5 [US-1, C2; FR-002/007]: Formerly unique pathless payload becomes ambiguous → reload clears ID with diagnostic.
- AC-6 [US-1, C3; FR-004]: Repeated top-level bindings → earlier #N and final bare name, including equal-location order.
- AC-7 [US-3, C4; FR-004/009]: Nonidentical same-source CMTs → unchanged rejection/unknown behavior, no unification.
- AC-8 [US-2, C5/6; FR-006]: Conflicting legacy duplicates or preservation-blocking constraints → failure without deletion/partial batch changes.
- AC-9 [US-2, C7/8; FR-008]: SQL batch failure/default malformed input/input IO failure → no successful summary or committed batch changes, preserving explicit allow-skip semantics and separate CLI migration boundary.
- AC-10 [US-3, C9; FR-010]: Separate runs/roots → fresh reuse state, not stale module IDs.
- AC-11 [US-3, C10/12; FR-010/011]: Selected copy/symlink spellings → distinct artifact records, graph sharing only.
- AC-12 [US-3, C11; FR-012]: Representative or later collection failure → no borrowed graph eligibility or false catalogue/binding marker.

## Edge Cases

- Missing path can resolve only a unique exact name; provided mismatch never falls back.
- Flat/no-functions tables retain effects without IDs; malformed advertised ID schema fails.
- Legacy already-lost records cannot be recovered; re-extraction is required. No automatic repair of payloads not reloaded.
- Lexical normalization is not physical symlink identity or arbitrary CMT relocation.
- Typedtree ordering distinguishes equal locations; unsupported binding patterns keep existing coverage limits.
- Exact copies/symlinks preserve per-artifact outcomes; nonidentical variants remain stage-4 work.
- Explicit migration is separate from record loading. Output failure after commit cannot undo a committed transaction.

## Runnable Checks

All commands use 0=pass, 1=assertion failure, 2=setup/input error, and real built binaries. They must be implemented and proven RED/GREEN, not treated as existing passes.

- CHECK-1 [AC-1/2/4/5/6/8/9]: `node roster/ocaml-data-preservation/check-effects.js` → actual producer/loader identities, migration, accounting, negative and rollback controls.
- CHECK-2 [AC-3/7/10/11/12]: `node roster/ocaml-data-preservation/check-cmt-copies.js` → real CMT copies/symlinks/conflicts, catalogue/binding and reindex controls.
- CHECK-3 [AC-1/3]: `node roster/ocaml-data-preservation/check-tezos.js` → pinned410 canonical callgraph neutrality, explicit effect-path/association observations. Local corpus requirement, not a CI corpus claim.

## Claims Metadata

```claims
{"record":"claims-header","schema_version":1,"namespace":"ocaml-data-preservation","spec_lifecycle":"draft"}
{"record":"requirement","id":"FR-001","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-002","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-003","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-004","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-005","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-006","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-007","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-008","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-009","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-010","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-011","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-012","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"acceptance-criterion","id":"AC-1","for":["FR-001","FR-002","FR-003"]}
{"record":"acceptance-criterion","id":"AC-2","for":["FR-005","FR-007"]}
{"record":"acceptance-criterion","id":"AC-3","for":["FR-009","FR-011"]}
{"record":"acceptance-criterion","id":"AC-4","for":["FR-001","FR-002"]}
{"record":"acceptance-criterion","id":"AC-5","for":["FR-002","FR-007"]}
{"record":"acceptance-criterion","id":"AC-6","for":["FR-004"]}
{"record":"acceptance-criterion","id":"AC-7","for":["FR-004","FR-009"]}
{"record":"acceptance-criterion","id":"AC-8","for":["FR-006"]}
{"record":"acceptance-criterion","id":"AC-9","for":["FR-008"]}
{"record":"acceptance-criterion","id":"AC-10","for":["FR-010"]}
{"record":"acceptance-criterion","id":"AC-11","for":["FR-010","FR-011"]}
{"record":"acceptance-criterion","id":"AC-12","for":["FR-012"]}
{"record":"check","id":"CHECK-1","for":["AC-1","AC-2","AC-4","AC-5","AC-6","AC-8","AC-9"]}
{"record":"check","id":"CHECK-2","for":["AC-3","AC-7","AC-10","AC-11","AC-12"]}
{"record":"check","id":"CHECK-3","for":["AC-1","AC-3"]}
```

## Entities

- EffectPayloadIdentity: the complete direct-effect payload, excluding its recomputable function-ID association.
- ExactCmtGraphReuse: per-run reuse of a successfully extracted graph for an exact artifact copy under the same source/unit mapping.
- Existing FunctorCatalogueInput/Occurrence/Contract and FunctorBindingInput/Contract remain per selected artifact. This change admits proven copies before module insertion; actually rejected insertions still mean dropped_module. Lifecycle examples/tests must be amended accordingly.

## Validation record

Three stories, eight clarifications, twelve resolved challenges, twelve requirements, twelve ACs and three checks. Formalizer Terra `01a0a634-08d9-7031-b46e-732bf6602bb9` supplied FR/AC draft. Root corrected its missing-path contradiction, overbroad IO atomicity statement, and wording that accidentally prohibited graph sharing across distinct artifact paths. Claims validation/projection unavailable (not installed); metadata remains draft, no fabricated validation or proof. Routine human quiz waived under explicit autonomous Roster authority; no answers fabricated.
