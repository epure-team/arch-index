---
name: roster-spec
type: spec
status: live
feature: OCaml functor binding provenance (resolution slice 1)
brief: roster/functor-binding-resolution/task.md
date: 2026-09-13
version: 1.0.1
---

# Spec — OCaml functor binding provenance

This contract records which syntactically identified formal is supplied by each supported,
selected-CMT-local functor application. It is not graph closure, target resolution, semantic
substitution, tamper authentication, runtime identity, or source-freshness evidence. The accepted
public record and schema contract below is normative; implementation technique is not prescribed.

## Clarifications

The user's repeated standing autonomy covered routine clarification choices. Eight questions were
resolved from existing interfaces and the accepted design without asking the user and without
fabricating answers. This document claims no implementation, QA execution, or formal proof.

| Q | A |
|---|---|
| Which CLI and limit contract applies? | `arch-query DB functor-bindings [limit]`; the existing six formats, default 50, strict nonnegative ASCII decimal fitting OCaml `int`, zero allowed, and invalid/extra arguments rejected before database access. |
| Which schema surface is added? | Additive main schema 1.15 (slot rechecked at ship), flat schema unchanged, with the three tables defined below and `producer_run_id` as the SQL run-column name. |
| What is declaration identity? | The direct named binder's exact artifact-local `Ident.unique_name`, compared with `Ident.same` inside one CMT; names and coordinates are display-only. |
| What is a formal telescope? | The maximal consecutive literal `Tmod_functor` result telescope after constraint peeling, serialized with the closed nullable grammar below. |
| What does `actual_root_key` mean? | Only the exact local nonpersistent root identity of an eligible stripped path operand; no alias chasing, definition/member/value inference, or substitution. |
| How are refusals classified? | By the closed nine-reason vocabulary and precedence below; every covered occurrence remains accounted for. |
| When is the marker earned? | Only after committed data satisfies complete catalogue-v1, input, count, linkage, uniqueness, and grammar validation; zero applications/declarations is valid but empty selection is not. |
| What does the reader trust and expose? | It validates all required persisted old/new facts in one read-only snapshot, but does not re-read CMT/source, authenticate coordinated rewrites, infer targets, or claim closure. |

## User Stories

### US-1 — Persist accountable formal bindings (Priority: P0)

As an index producer consumer, I want to inspect which formal each supported application supplies
without changing calls.

**Why this priority:** binding provenance is the smallest accountable bridge from the existing
application catalogue to later analyses while preserving explicit unresolved evidence.

**Exclusions:** resolving actual contents, body evaluation, call targets, graph closure,
cross-unit identity normalization, substitutions, runtime/fresh exception identities, source
freshness, and authenticated evidence.

**Independent test:** compile an owned native fixture, index it, and inspect the new SQL rows without
using the query CLI.

1. **Given** named `F(X)(Y)`, `A`, `B`, and `F(A)(B)`, **when** indexed, **then** the two existing occurrence IDs are matched to positions 1 and 2 respectively, arguments remain unchanged, declarations are not cloned, and call/catalogue snapshots are unchanged.
2. **Given** same-spelled shadowed binders, aliases, and local-module applications, **when** indexed, **then** each match uses its own artifact-scoped declaration key, never a same-name declaration, and identities from different CMTs cannot cross-bind.
3. **Given** external, parameter, path-projected, inline, and application-valued heads, **when** indexed, **then** every occurrence receives its deterministic unresolved reason and remains in total accounting.
4. **Given** a binding input whose storage fails after a successful insert, **when** rollback completes, **then** that input has no declaration/result rows and a failed outcome where storage permits, the marker is absent, and earlier catalogue and graph facts remain usable.
5. **Given** a selected collected input with zero applications, **when** indexed, **then** it has a binding-input row and may earn the marker; an empty selection cannot.

### US-2 — Read a bounded trustworthy provenance report (Priority: P0)

As a CLI user, I want a complete, bounded binding report and its unresolved scope without confusing
missing analysis with an empty result set.

**Why this priority:** consumers need fail-closed validation and stable rendering before persisted
binding facts can be interpreted safely.

**Exclusions:** read-time CMT/source access, source revalidation, tamper authentication, implicit
external resolution, alias traces, inferred callees, and target/closure claims.

**Independent test:** hand-construct valid and invalid SQLite data and invoke the real query without
the producer.

1. **Given** a valid two-input, three-result database with two matched and one unresolved result, **when** queried with limit 2, **then** it returns complete counts 3/2/1 and two sorted rows without changing database bytes.
2. **Given** marked data with missing, orphaned, position, kind, reference, count, or JSON corruption beyond the first row, **when** queried with limit 0, **then** it exits 3 with `INCONSISTENT_BINDINGS` before stdout.
3. **Given** an old, flat, or markerless database, or an invalid limit, **when** queried, **then** it yields the applicable schema/collection refusal or usage exit 2, without silent defaults or writes.
4. **Given** complete collected data with zero results, **when** queried in any renderer, **then** it produces a summary and an empty row table; JSON's second array is `[]`, distinct from not collected.

## Closed public contract

### Schema and records

Main schema 1.15 adds these tables; the version slot must be rechecked at ship. Flat schema remains
unchanged. SQL uses `producer_run_id` wherever the logical contract below says `run`. All foreign
keys cascade on deletion, and the new tables participate in drop/reindex lists.

- `functor_binding_inputs(run, artifact, outcome, expected_declarations, expected_bindings)`: primary key `(run,artifact)` and foreign key to the catalogue input; `outcome` is `collected|collection_failed`; counts are SQLite integers, nonnegative, and in range.
- `functor_declarations(run, artifact, declaration_key, name, location, formals)`: primary key `(run,artifact,declaration_key)` and foreign key to the binding input. `declaration_key` and `name` are nonempty text. `location` uses the existing closed valid-or-null catalogue location grammar.
- `functor_bindings(run, artifact, ordinal, status, reason, declaration_key, formal_position, head_application_ordinal, actual_root_key)`: primary key `(run,artifact,ordinal)`, foreign keys to the existing occurrence and binding input, and nullable same-input declaration linkage.

The actual operand is joined from the unchanged catalogue argument and is not duplicated.
Declaration and formal keys are opaque nonempty strings, never parsed stamp numbers. Keys are scoped
per input and stable only for identical input bytes/compiler, not across builds or as runtime/global
identifiers. Ghost or same-position declarations never merge keys.

### Declaration traversal and identity

The collection universe is the pinned OCaml 5.3 `Tast_iterator.default_iterator` over
`Implementation.structure`, including module expressions under types, expressions, classes,
objects, and deferred bodies. It registers named `module_binding` and `Texp_letmodule` binders,
including recursive groups, and collects parameter identities from named module-expression and
module-type functor parameters. Untyped attribute/extension payload AST is not traversed as new typed
declarations. The narrower graph definition walker is not this traversal.

Only registered module binders whose constraint-peeled immediate RHS is `Tmod_functor` become
declarations. All such direct named declarations are persisted, including unused ones. Duplicate
`Ident.same` registration or binder/parameter cross-role collision makes the input
`collection_failed`; collection never guesses between conflicts.

### Formal grammar

`formals` is a nonempty JSON array whose entries have exactly this closed shape and contiguous
one-based positions:

```text
Formal := {
  "position": Integer >= 1,
  "kind": "named" | "unit",
  "binder_key": NonemptyString | null,
  "name": NonemptyString | null
}
```

Duplicate or extra keys are invalid. A `unit` formal requires both nullable fields to be null. A
`named` formal permits all four independent key/name nullability combinations; both-null means an
anonymous named formal, not unit. No key is fabricated for an anonymous formal. Kind alone controls
application-kind matching, and position identifies unnamed slots. Parameter types, substitutions,
runtime identities, and fresh exception identities are not serialized.

### Result grammar and resolution precedence

A matched result has `status=matched`, null reason, an existing same-input declaration key, and a
positive existing formal position. An unresolved result has `status=unresolved`, null declaration
and position, and exactly one reason:

```text
cross_unit_head | parameter_supplied_head | alias_cycle |
local_declaration_missing | unsupported_alias_rhs | unsupported_path |
unsupported_head_shape | curried_result_not_functor | formal_kind_mismatch
```

Resolution peels constraints. An application head recursively resolves its own head, propagates any
refusal unchanged, otherwise advances one formal. If the next index exceeds the literal telescope,
the reason is `curried_result_not_functor`; bodies are not evaluated. Every application-headed row
retains its stripped head occurrence ordinal even when unresolved. For a matched parent, that head
must match the same declaration at position minus one; direct or alias heads begin at position 1.

For a path head, a constructor other than `Pident` yields `unsupported_path` before root inspection.
A persistent `Pident` yields `cross_unit_head`; a local parameter yields
`parameter_supplied_head`; an absent registered binder yields `local_declaration_missing`; a local
functor RHS selects declaration position 1. A local alias follows only `Pident` chains with a visited
set; revisiting yields `alias_cycle`. Any other bound RHS, including an application, yields
`unsupported_alias_rhs`. Any other expression head, including inline functor, unpack, or structure,
yields `unsupported_head_shape`. Formal/application kind is checked last: `apply_unit` requires
`unit`, `apply` requires `named`, otherwise `formal_kind_mismatch`.

### Actual-root grammar

`actual_root_key` is SQL null or an opaque nonempty string. It is available only for a
constraint-peeled `Tmod_ident` operand whose path consists solely of `Pident`/`Pdot`, has a
nonpersistent root, and whose catalogue descriptor has `contains_apply=false`. `Pextra_ty`,
persistent roots, `Papply`, anonymous structures, nested applications, and other non-path operands
produce null. It denotes only that local root identity; there is no alias chasing or claim about its
definition, member, value, substitution, or runtime identity. The reader validates structural
consistency in persisted facts and does not re-execute the compiler extraction from display text.

### Input, marker, and failure lifecycle

Successful catalogue inputs independently attempt binding collection/storage after successful catalogue persistence and its collected-count increment,
inside their own binding savepoint. A failed attempt rolls back only its new binding declarations and
results and then attempts a `collection_failed` input row with zero counts. If that row also fails,
the input remains absent and a warning is reported; collected status is never fabricated. Any
write/rollback uncertainty latches binding eligibility false.

The marker `functor_binding_contract=v1` is durably cleared with the other central markers before
schema replacement. The outer transaction commits data; catalogue finalizes independently; the
binding marker is the final separate write and never precedes data commit. An interruption during an
input or after data commit but before marker write cannot yield binding success. No process-SIGKILL
coverage is claimed unless separately tested.

Marker eligibility requires: valid catalogue v1; a nonempty selected-input set; exactly one binding
input per collected catalogue input; every such binding input collected; exact expected declaration
counts; `expected_bindings` equal to both catalogue `expected_applications` and actual binding count;
exactly one result for every covered occurrence; and all grammar, uniqueness, provenance, linkage,
formal-kind, and curried-reference predicates. Zero applications and/or declarations is valid for a
collected input. A missing input/result, orphan, malformed row, or failed input prevents eligibility.
The final completion validator applies the same structural/count/link predicates as the reader.

### Query, projection, and failures

The command is `arch-query DB functor-bindings [limit]`, in the existing six formats. Limit defaults
to 50 and must be nonnegative ASCII decimal fitting OCaml `int`; zero is valid. Arguments are parsed
before database access. Successful reads fully validate all required facts in one read-only snapshot
before limiting or rendering, even for limit 0.

Validation covers all rows in old catalogue required tables using catalogue-v1 semantic checks and
all rows in the three binding tables, including unused declarations. Exactly one catalogue run is
supported. Foreign-run rows, orphans, unaccounted inputs, duplicate keys even in unconstrained
hand-crafted tables, invalid storage types/ranges, provenance mismatches, malformed JSON, count,
position, kind, or reference errors are inconsistent. Old tables outside the catalogue closure, such
as effects, are not newly validated.

Error precedence is:

1. invalid command, arity, or limit: usage exit 2 before database access;
2. open or begin-snapshot failure: operational exit 2;
3. required old/new table/column shape or flat discriminator failure: exit 3, `UNSUPPORTED_SCHEMA`;
4. missing or non-exact-text catalogue-v1 or binding-v1 marker: exit 3, `NOT_COLLECTED_BINDINGS`;
5. failed full row validation: exit 3, `INCONSISTENT_BINDINGS`.

SQL, connection, commit, or rollback failures at any accessed step remain operational exit 2. No
classification is promised if an earlier required operation fails. All errors leave stdout empty;
rendering occurs only after successful validation and snapshot completion.

The ten summary columns are, in order:

```text
contract, selected_inputs, collected_inputs, total, matched, unresolved,
returned, truncated, scope, limitations
```

Counts derive from the full validated set before limit. `scope` is
`selected_cmt_local_binding_provenance`. `limitations` is exactly:

```text
not_runtime_instances;not_closed_world;no_call_target_resolution;no_actual_substitution;no_source_freshness_check;artifact_scoped_compiler_identity
```

The fifteen row columns are, in order:

```text
artifact, source, compiler_unit, ordinal, status, reason, declaration_key,
declaration_name, formal_position, formal_kind, formal_key, formal_name,
head_application_ordinal, actual_root_key, argument
```

Rows join source/unit only from the same-run catalogue input and sort by artifact then ordinal.
Validated unique artifacts and positive contiguous catalogue ordinals make this order total. Existing
renderer `Nul`/`Int`/`Text` cells and escaping are canonical. Missing text/numeric values are null
cells, not empty strings or magic zero. `argument` remains one JSON-valued string. Summary precedes
rows. JSON emits two newline-separated arrays, with second array `[]` for zero returned rows. No
alias trace, implicit external resolution, or inferred callee is exposed.

## Functional Requirements

### US-1 requirements

- **FR-001** [US-1]: The producer **MUST** create exactly one binding result for every existing catalogue occurrence in a same-run selected input whose catalogue outcome is collected, including nested head and argument occurrences, and **MUST NOT** fabricate ordinals for failed catalogue inputs. _Trace: US1-S1, C1; CHECK-1, CHECK-2._
- **FR-002** [US-1]: The producer **MUST** persist every direct named declaration in the closed typed traversal whose registered module binder has a constraint-peeled immediate `Tmod_functor` RHS, including unused declarations. _Trace: US1-S2, C2; CHECK-1._
- **FR-003** [US-1]: A declaration key **MUST** be the exact artifact-local binder `Ident.unique_name`, matched in-memory with `Ident.same`; printed names and coordinates **MUST NOT** determine identity. _Trace: US1-S2, C10; CHECK-1._
- **FR-004** [US-1]: Duplicate identity registration or a binder/parameter cross-role collision **MUST** make the input collection-failed before matching and **MUST NOT** leave partial binding data. _Trace: US1-S2, C5; CHECK-1, CHECK-2._
- **FR-005** [US-1]: A declaration's `formals` **MUST** be the nonempty maximal consecutive literal `Tmod_functor` result telescope after constraint peeling with contiguous one-based positions. _Trace: US1-S1, C3; CHECK-1._
- **FR-006** [US-1]: Each formal **MUST** obey the closed nullable grammar, allowing all four independent key/name nullability combinations for named formals and requiring both null for unit formals; duplicate/extra keys and empty present strings **MUST NOT** be accepted. _Trace: US1-S1, C4; CHECK-1, CHECK-3._
- **FR-007** [US-1]: A matched result **MUST** have null reason, an existing same-input declaration and positive existing formal position whose kind agrees with the application kind. _Trace: US1-S1; CHECK-1, CHECK-3._
- **FR-008** [US-1]: An unresolved result **MUST** have null declaration and formal position and exactly one member of the closed nine-reason vocabulary. _Trace: US1-S3, C5; CHECK-1, CHECK-3._
- **FR-009** [US-1]: Every application-headed result **MUST** retain its stripped head occurrence ordinal, and a matched parent **MUST** reference the same declaration at the preceding position. _Trace: US1-S1, C3; CHECK-1, CHECK-3._
- **FR-010** [US-1]: Resolution **MUST** follow the closed precedence, propagate an inner refusal unchanged before outer kind checking, and use `curried_result_not_functor` when advancement exceeds the telescope. _Trace: US1-S3, C3, C5; CHECK-1._
- **FR-011** [US-1]: `actual_root_key` **MUST** be null or the eligible local root key defined by the closed grammar and **MUST NOT** imply alias, member, definition, substitution, or runtime identity. _Trace: US1-S1, C10; CHECK-1, CHECK-3._
- **FR-012** [US-1]: Every result **MUST** retain the existing argument JSON byte-for-byte, and binding collection **MUST NOT** clone declarations, mutate calls, or alter catalogue or graph facts. _Trace: US1-S1; CHECK-1, CHECK-4._
- **FR-013** [US-1]: Each selected catalogue-collected input **MUST** have exactly one binding-input row with a closed outcome and nonnegative expected counts; a collected zero-declaration or zero-application input **MUST** remain valid. _Trace: US1-S5, C1; CHECK-1, CHECK-2._
- **FR-014** [US-1]: Binding storage failure **MUST** isolate rollback to that input's new binding entities, preserve earlier catalogue/graph facts, attempt the defined failed row, and leave eligibility false on failure-row or transaction uncertainty. _Trace: US1-S4, C6; CHECK-2, CHECK-4._
- **FR-015** [US-1]: The exact binding marker **MUST** be cleared before replacement and **MUST NOT** be written until committed data passes complete eligibility; interruption before marker write **MUST NOT** yield success. _Trace: US1-S4, C6; CHECK-2._
- **FR-016** [US-1]: Marker eligibility **MUST** require complete catalogue v1, nonempty selection, exact collected-input/count/result coverage, and every closed grammar, uniqueness, provenance, linkage, kind, and curried-reference predicate. _Trace: US1-S5, C1, C6; CHECK-1, CHECK-2._
- **FR-017** [US-1]: A match **MUST** mean only the syntactically identified formal at this application and **MUST NOT** assert cross-unit normalization, graph closure, tamper evidence, call targets, body evaluation, substitution, runtime instances, or freshness. _Trace: US1-S2, C10; CHECK-4._

### US-2 requirements

- **FR-018** [US-2]: The query **MUST** implement the accepted command, six-format, default-limit, and strict limit grammar, rejecting invalid/extra arguments with exit 2 before database access. _Trace: US2-S1, US2-S3, C9; CHECK-3._
- **FR-019** [US-2]: The reader **MUST** fully validate every required old catalogue fact and every row of the three new tables in one read-only snapshot before limit or output, including unused declarations and limit 0. _Trace: US2-S2, C7; CHECK-3._
- **FR-020** [US-2]: Full validation **MUST** enforce the closed run, provenance, type, range, uniqueness, count, grammar, formal, and reference closure and **MUST NOT** newly validate unrelated old tables. _Trace: US2-S2, C7; CHECK-3._
- **FR-021** [US-2]: The CLI **MUST** apply the closed usage, operational, schema, marker, and consistency error precedence and associated exit categories. _Trace: US2-S2, US2-S3, C9; CHECK-3, CHECK-4._
- **FR-022** [US-2]: Every error path **MUST** leave stdout empty, and rendering **MUST NOT** begin before successful full validation and snapshot completion. _Trace: US2-S2, US2-S3, C9; CHECK-3._
- **FR-023** [US-2]: A successful query **MUST** derive counts from all validated rows before limiting and emit exactly the ten frozen summary columns with the fixed scope and limitations. _Trace: US2-S1, C8, C10; CHECK-3._
- **FR-024** [US-2]: Successful rows **MUST** use exactly the fifteen frozen columns, same-run catalogue provenance, total artifact/ordinal order, and renderer-native null cells. _Trace: US2-S1, C8; CHECK-3._
- **FR-025** [US-2]: Every renderer **MUST** emit summary before rows with canonical existing escaping/cells; JSON **MUST** emit two newline-separated arrays with second `[]` for zero rows, while argument remains one JSON-valued string. _Trace: US2-S1, US2-S4, C8; CHECK-3._
- **FR-026** [US-2]: A query **MUST NOT** change database bytes, and the feature **MUST NOT** change existing catalogue, graph, alias, exception, or flat-schema query semantics. _Trace: US2-S1, US2-S3; CHECK-4._

## Challenges

| ID | Story | Challenge | Resolution |
|---|---|---|---|
| C1 | US-1 | Quantified occurrence universe | Exactly every existing catalogue occurrence for a same-run collected input is covered, including nested occurrences; failed inputs fabricate none; eligibility also requires complete catalogue v1. |
| C2 | US-1 | Declaration traversal closure | Use the pinned 5.3 full typed iterator boundary described above, register named and parameter identities including recursive/local contexts, persist only immediate direct functor RHS declarations, exclude untyped payload declarations, and never substitute the narrower graph walker. |
| C3 | US-1 | Exhausted telescope and unresolved head reference | Every application-headed row retains its head ordinal; advancement beyond the telescope is `curried_result_not_functor`; no body evaluation occurs. |
| C4 | US-1 | Optional named fields | Named formals allow all four independent key/name nullabilities with nonempty present strings; both-null named remains distinct from unit; kind controls matching. |
| C5 | US-1 | Conflicting categories and reason order | Identity/cross-role conflicts fail the input before matching; matching follows the specified shape/root/parameter/binder/cycle/RHS precedence, propagating inner refusals before outer kind checks. |
| C6 | US-1 | Failure-row failure and interruption | Per-input savepoint rollback affects binding entities only; failed-row failure leaves absence plus warning; uncertainty prevents eligibility; marker is cleared before replacement and written only after committed valid data. |
| C7 | US-2 | Whole validation set | Validate all required catalogue-v1 and binding rows, support exactly one catalogue run, reject foreign/orphan/unaccounted/duplicate data, and do not extend validation to unrelated old tables. |
| C8 | US-2 | Sorting and bytes | Unique artifact plus contiguous positive ordinal gives total order; frozen ten summary and fifteen row columns use canonical cells/escaping; six-format byte oracles are independently constructed. |
| C9 | US-2 | Error precedence | Parse before open; then operational open/snapshot, schema, exact markers, full validation; later accessed-operation failures remain operational; stdout is empty on all failures. |
| C10 | US-1 | Why not Env/Subst/Shape | Local identity plus literal telescope suffices only for syntactic formal provenance; wider normalization APIs remain future options and are not closure, target, or substitution evidence. |

## Acceptance Criteria

- **AC-1 (US-1 happy path).** The owned native `F(X)(Y)` fixture produces one two-slot declaration and matched positions 1/2 with unchanged arguments and catalogue/call facts. _Covers FR-001, FR-005, FR-007, FR-009, FR-012; CHECK-1, CHECK-4._
- **AC-2 (US-2 happy path).** A valid marked two-input/three-result database queried at limit 2 emits complete 3/2/1 counts, two sorted rows in all six formats, and unchanged database bytes. _Covers FR-018, FR-023–FR-026; CHECK-3, CHECK-4._
- **AC-3 (US-1, C1).** Nested and failed-input fixtures prove exact result coverage, no fabricated failed-input ordinal, and rejection of missing/extra results before eligibility. _Covers FR-001, FR-013, FR-016; CHECK-1, CHECK-2._
- **AC-4 (US-1, C2).** Typed fixtures cover every specified traversal context and excluded untyped payloads, inventorying only declarations inside the closed traversal. _Covers FR-002; CHECK-1._
- **AC-5 (US-1, C3).** A premise-checked synthetic overapplication retains its head ordinal and reports `curried_result_not_functor`; a valid chain links preceding positions. _Covers FR-005, FR-009, FR-010; CHECK-1, CHECK-3._
- **AC-6 (US-1, C4).** Tests cover all four named-formal nullability combinations and unit, while rejecting empty present strings and malformed closed JSON. _Covers FR-006, FR-007; CHECK-1, CHECK-3._
- **AC-7 (US-1, C5).** Genuine negative identity mutation fails atomically, and real native or explicitly premise-checked synthetic cases exercise all nine refusal reasons and precedence. _Covers FR-004, FR-008, FR-010; CHECK-1, CHECK-2._
- **AC-8 (US-1, C6).** Deterministic failure boundaries prove isolated rollback, failed-row failure behavior, preserved existing facts, and absent marker; no SIGKILL guarantee is inferred. _Covers FR-014–FR-016; CHECK-2, CHECK-4._
- **AC-9 (US-2, C7).** Corruption beyond the limit or in unused data, including every closed validation category, yields `INCONSISTENT_BINDINGS` and empty stdout even at limit 0. _Covers FR-019, FR-020, FR-022; CHECK-3._
- **AC-10 (US-2, C8).** Independent semantic cells and explicit byte oracles verify exactly ten summary headers, fifteen row headers, ordering, nulls, escapes, argument-string treatment, and summary-first output in all six formats. _Covers FR-023–FR-025; CHECK-3._
- **AC-11 (US-2, C9).** Cases for every precedence stage produce the specified exit/category and empty stdout, including accessed-operation failures. _Covers FR-018, FR-021, FR-022; CHECK-3, CHECK-4._
- **AC-12 (US-1, C10).** Shadowing, aliases, cross-CMT lookalikes, external heads, and misleading display relationships prove local syntactic matching only and expose no target, graph, tamper, substitution, runtime, or freshness claim. _Covers FR-003, FR-011, FR-017; CHECK-1, CHECK-4._

- **AC-13 (US-1, C6; rollback correction gate).** A standalone real-producer regression builds and invokes the producer from the exact checkout under test on two owned native CMT inputs with two applications each, first proves a healthy positive run, then injects a schema-only SQLite trigger that executes `RAISE(ROLLBACK)` on the fault input's second binding insert only after another artifact already has binding rows. The fault run **MUST** exit 0 with the binding-failure warning; its catalogue and graph facts **MUST** equal the healthy run; the earlier good input's binding-input, declaration, and result rows **MUST** remain complete; the fault input **MUST** have a persisted `collection_failed` row, zero declaration/result rows, and no eligibility contribution; and `functor_binding_contract` **MUST** be absent. The fixture/trigger premise **MUST NOT** depend on artifact-name or filesystem-selection ordering. _Covers FR-014–FR-016; CHECK-5._

## Edge Cases

- An unused direct declaration with zero applications stores counts 1/0 and may earn the marker; no declarations with zero applications is also valid for a collected input.
- Empty selected input is ineligible even though a collected selected input may have zero results.
- Declaration/formal keys and names are nonempty when present; nullable SQL/JSON values are real null, never empty strings or sentinel zero.
- Conflicting compiler identities fail the whole binding input; no name-only fallback exists.
- Application-headed unresolved rows retain a head ordinal while declaration and position remain null.
- Persistent, projected, extra-typed, applied, anonymous, and non-path actual operands yield null root keys according to the closed grammar.
- Malformation after the returned prefix, in unused declarations, or under limit 0 still refuses the complete query.
- A wrong-type or wrong-version marker is treated as absent, after schema validation.
- Existing wider compiler APIs and an old exposure flag are not evidence of closure.

## Runnable Checks

The following check families are contractually required and are now registered in the
Tezt/Dune test dependency graph. Inventory combines source-valid native fixtures with explicitly
premise-checked synthetic CMTs; lifecycle combines direct storage/finalizer APIs with actual
producer CLI failures. Query uses authored semantic/renderer oracles and a genuine accessed-SQL
failure through the CLI. Reader begin/commit/rollback fault injection is direct API evidence,
not a claim that each transaction method was injected into the separate CLI process.
Compatibility includes historical main and flat semantic oracles. Current execution evidence
and review status live in `roster/functor-binding-resolution/acceptance-status.md`.
Commands inherit the compiler environment from opam/Dune/CI. Outside a selected environment,
set `ARCH_FUNCTOR_OPAM_SWITCH` to the intended switch; no machine-specific switch is hardcoded.
Each plain Node invocation must distinguish pass `0`, semantic assertion failure `1`, and
infrastructure failure `>=2`; no missing tool or fixture may masquerade as assertion failure.

- **CHECK-1 — inventory:** `node scripts/check-functor-bindings.js inventory`; covers AC-1, AC-3, AC-4, AC-5, AC-6, AC-7, AC-12 with owned native fixtures, unit/anonymous formals, genuine identity mutation, telescope/linkage, roots, and all refusal premises.
- **CHECK-2 — lifecycle:** `node scripts/check-functor-bindings.js lifecycle`; covers AC-3, AC-7, AC-8 with real persistence rollback and deterministic interruption/failure boundaries.
- **CHECK-3 — query:** `node scripts/check-functor-bindings.js query`; covers AC-2, AC-5, AC-6, AC-9, AC-10, AC-11 using crafted marked corruption, limit 0, independent semantic cells, and six explicit formatter byte oracles.
- **CHECK-4 — compatibility:** `node scripts/check-functor-bindings.js compatibility`; covers AC-1, AC-2, AC-8, AC-11, AC-12 with old catalogue/graph query and semantic-table comparisons plus byte-unchanged read-only query.

- **CHECK-5 — real-producer global rollback:** `node roster/functor-binding-resolution/check-global-rollback.js`; covers AC-13. This standalone checker builds `bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe` with `dune build --root <repository-under-test>` in the inherited selected compiler environment, invokes only that checkout's resulting producer, compiles its owned two-CMT fixture with the inherited compiler, and uses a schema-only `RAISE(ROLLBACK)` trigger. Exit 0 means all assertions pass, exit 1 means a semantic assertion fired, and exit >=2 means setup/build/infrastructure error. This command is a separate gate, not a nested build inside Dune tests. Implementation and RED/GREEN evidence are pending.

## Claims Metadata

Metadata is draft. The claims CLI is absent, so deterministic claims validation/projection is
unavailable and is not claimed.

```claims
{"record":"claims-header","schema_version":1,"namespace":"functor-binding-resolution","spec_lifecycle":"draft"}
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
{"record":"requirement","id":"FR-013","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-014","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-015","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-016","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-017","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-018","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-019","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-020","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-021","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-022","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-023","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-024","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-025","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-026","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"acceptance-criterion","id":"AC-1","for":["FR-001","FR-005","FR-007","FR-009","FR-012"]}
{"record":"acceptance-criterion","id":"AC-2","for":["FR-018","FR-023","FR-024","FR-025","FR-026"]}
{"record":"acceptance-criterion","id":"AC-3","for":["FR-001","FR-013","FR-016"]}
{"record":"acceptance-criterion","id":"AC-4","for":["FR-002"]}
{"record":"acceptance-criterion","id":"AC-5","for":["FR-005","FR-009","FR-010"]}
{"record":"acceptance-criterion","id":"AC-6","for":["FR-006","FR-007"]}
{"record":"acceptance-criterion","id":"AC-7","for":["FR-004","FR-008","FR-010"]}
{"record":"acceptance-criterion","id":"AC-8","for":["FR-014","FR-015","FR-016"]}
{"record":"acceptance-criterion","id":"AC-9","for":["FR-019","FR-020","FR-022"]}
{"record":"acceptance-criterion","id":"AC-10","for":["FR-023","FR-024","FR-025"]}
{"record":"acceptance-criterion","id":"AC-11","for":["FR-018","FR-021","FR-022"]}
{"record":"acceptance-criterion","id":"AC-12","for":["FR-003","FR-011","FR-017"]}
{"record":"acceptance-criterion","id":"AC-13","for":["FR-014","FR-015","FR-016"]}
{"record":"check","id":"CHECK-1","for":["AC-1","AC-3","AC-4","AC-5","AC-6","AC-7","AC-12"]}
{"record":"check","id":"CHECK-2","for":["AC-3","AC-7","AC-8"]}
{"record":"check","id":"CHECK-3","for":["AC-2","AC-5","AC-6","AC-9","AC-10","AC-11"]}
{"record":"check","id":"CHECK-4","for":["AC-1","AC-2","AC-8","AC-11","AC-12"]}
{"record":"check","id":"CHECK-5","for":["AC-13"]}
```

## Entities

- **FunctorBindingInput:** one binding-collection outcome and expected counts for a selected catalogue-collected input.
- **LocalFunctorDeclaration:** one direct named, artifact-local functor declaration identified by its binder key.
- **FunctorFormalSlot:** one position in a declaration's literal functor-result telescope, with independent nullable named metadata.
- **FunctorBindingResult:** the matched or unresolved binding provenance result for exactly one existing catalogue application occurrence.
- **FunctorBindingContract:** independently earned v1 eligibility for complete selected-input binding provenance.

Existing `FunctorCatalogueInput`, `FunctorApplicationOccurrence`,
`FunctorExpressionDescriptor`, and `FunctorCatalogueContract` entities remain unchanged. Existing
module-alias and exception contracts are preserved by the no-consumer-change boundary.
