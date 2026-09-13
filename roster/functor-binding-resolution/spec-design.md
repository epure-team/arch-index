# Spec design input — binding provenance v1

Draft input for adversarial review, not a validated spec or implementation.
Eight elicitor OPEN items resolved below by operator under standing autonomy;
questions asked to user:0. Existing5.3 interfaces and catalogue boundary reused.

## Clarifications / contract choices

1. CLI: `arch-query DB functor-bindings [limit]`, same six formats as catalogue,
   default50, strict nonnegative ASCII decimal fitting OCaml int, zero permitted,
   invalid/extra args exit2 before opening DB. Sort artifact then ordinal. Fully
   validate data in one readonly snapshot before limit/output. Operational error2;
   unsupported schema3/UNSUPPORTED_SCHEMA; missing either eligibility marker3/
   NOT_COLLECTED_BINDINGS; malformed marked data3/INCONSISTENT_BINDINGS, stdout empty.
2. Add main schema1.15 (recheck slot at ship), flat unchanged. Three tables:
   functor_binding_inputs(run,artifact,outcome,expected_declarations,expected_bindings),
   FK to catalogue input; outcome collected|collection_failed, nonnegative counts.
   functor_declarations(run,artifact,declaration_key,name,location,formals), PK
   run/artifact/key, FK binding_input; name/key nonempty text, location closed
   existing catalogue grammar, formals closed JSON array below.
   functor_bindings(run,artifact,ordinal,status,reason,declaration_key,
   formal_position,head_application_ordinal,actual_root_key), PK run/artifact/ordinal,
   FK existing occurrence, FK binding_input, nullable same-input declaration FK.
   Actual operand is joined from unchanged catalogue argument, not duplicated.
   SQL uses producer_run_id for run column; all FKs cascade on deletion. New tables
   participate in drop/reindex lists. Matched/unresolved fields constrained as below.
3. Identity: direct named module declaration key is exact Ident.unique_name of
   its binder, compared with Ident.same in-memory within one CMT. Printed names
   and coordinates are display only; keys are artifact-local, stable only for
   identical input bytes/compiler, not cross-build/runtime/global IDs. Scan named
   module/recmodule/local-expression binders before matching, including nested
   scopes; conflicting duplicate identities fail collection, never select one.
   Alias lookup uses local Pident chains with cycle detection; no persisted alias
   hops. All direct named functor declarations found by that scan are persisted,
   including unused ones; only constraint wrappers are peeled.
4. A declaration's formals are its maximal consecutive literal Tmod_functor result
   telescope after constraint peeling. Nonempty JSON array of exactly
   {position:int>=1,kind:"named"|"unit",binder_key:string|null,name:string|null},
   contiguous positions. Unit has null key/name; named preserves optional compiler
   key/name independently (no fabricated key for anonymous formal). No parameter
   types, substitutions, runtime or fresh exception identities are serialized.
   Each matched binding references the terminal declaration and one position.
   `head_application_ordinal` equals the stripped catalogue head's referenced
   application ordinal or null. For a matched parent, referenced head must be
   matched to same declaration at position-1; a direct/alias head has position1.
   Application kind must agree with formal kind (apply_unit/unit, apply/named).
5. Actual root key: nullable exact local root Ident.unique_name, extracted only
   from constraint-peeled Tmod_ident paths consisting of Pident/Pdot with a
   nonpersistent root. It denotes only that root, not its definition/member/value;
   no alias chasing. Persistent roots, Papply/Pextra_ty paths, anonymous structures,
   nested applications and other non-path operands get null. Original actual
   descriptor remains byte-identical catalogue JSON for every binding/refusal.
6. Status matched has reason null, existing declaration key and positive formal
   position. Status unresolved has null declaration/position and one reason:
   cross_unit_head, parameter_supplied_head, alias_cycle,
   local_declaration_missing, unsupported_alias_rhs, unsupported_path,
   unsupported_head_shape, curried_result_not_functor, formal_kind_mismatch.
   Resolve head structurally: peel constraints; application head recursively
   resolves its head, propagates its refusal unchanged, else advances one formal;
   nonliteral next result -> curried_result_not_functor. Path constructor other
   than Pident -> unsupported_path before inspecting roots. Persistent Pident ->
   cross_unit_head. Local parameter -> parameter_supplied_head. Missing binder ->
   local_declaration_missing. Local functor RHS -> declaration slot1. Local alias
   Pident chain -> same checks, revisiting binder -> alias_cycle. Other bound RHS
   (including application) -> unsupported_alias_rhs. Other head expression
   (including inline functor/unpack/structure) -> unsupported_head_shape.
   Formal/application kind check runs last; mismatch -> formal_kind_mismatch.
   Synthetic invalid-CMT identity conflicts are collection_failed, not guessed.
7. Marker `functor_binding_contract=v1` cleared centrally before replacement.
   Successful catalogue inputs independently attempt binding collection/storage
   in their own savepoint, after catalogue facts; failed binding input loses
   only its own declaration/results and records collection_failed/counts0 where
   storage allows. Catalogue/graph facts and v1 marker eligibility survive it.
   Final marker after data commit requires valid catalogue v1, nonempty selected
   inputs, exactly one binding-input per collected catalogue input, all collected,
   expected_bindings equals that catalogue input's expected_applications and
   actual result count; expected_declarations equals actual declaration count;
   every occurrence has exactly one result; all grammar/linkage checks pass.
   Zero applications/declarations is valid for a collected input. Any failure,
   missing input/result, orphan or malformed data prevents marker eligibility.
8. Reader validates all old catalogue facts plus binding counts/types/closed
   grammars, FK linkage, uniqueness, matched formal positions/kinds and curried
   references; no partial stdout on failure, even limit0. Stored marker is
   collection bookkeeping, not authenticated evidence; coordinated DB rewrites
   and source freshness are not verified. No read-time CMT/source access.

## Public query projection

Summary columns: contract,selected_inputs,collected_inputs,total,matched,unresolved,
returned,truncated,scope,limitations. Counts derive from all validated persisted
rows before limit. Scope selected_cmt_local_binding_provenance; limitations fixed:
not_runtime_instances;not_closed_world;no_call_target_resolution;no_actual_substitution;
no_source_freshness_check;artifact_scoped_compiler_identity.

Rows: artifact,source,compiler_unit,ordinal,status,reason,declaration_key,
declaration_name,formal_position,formal_kind,formal_key,formal_name,
head_application_ordinal,actual_root_key,argument. Nullable missing text/numeric
cells use existing renderer null cells, not empty strings; argument is JSON-valued
string. JSON outputs two arrays separated by newline, second[] for zero returned.
No alias trace, implicit external resolution or inferred callee is exposed.

## User stories

### US-1: Persist accountable formal bindings (P0)

As an index producer consumer, inspect which formal each supported application
supplies without changing calls. Independent test: compile owned native fixture,
index and inspect new SQL rows, without query CLI.
Scope excludes resolving actual contents or closing the graph.

1. Given named F(X)(Y), A/B and F(A)(B), when indexed, two existing occurrence
   IDs have matched positions1/2 respectively and unchanged arguments; functions
   are not cloned and calls/catalogue snapshots are unchanged.
2. Given same-spelled shadowed F binders, aliases and local-module applications,
   when indexed, each match uses its own artifact-scoped declaration key, never
   a same-name declaration; identical stamps in different CMTs cannot cross-bind.
3. Given external/parameter/path-projected/inline/application-valued heads, when
   indexed, every occurrence receives its deterministic unresolved reason and
   still contributes to total accounting.
4. Given one binding input fails storage after a successful insert, when the
   operation rolls back, that input has zero new rows and failed outcome, marker
   absent, while earlier catalogue and graph facts remain usable.
5. Given selected collected input with zero applications, when indexed, it has
   a binding-input row and may earn the marker; empty selection cannot.

### US-2: Read a bounded trustworthy provenance report (P0)

As a CLI user, inspect a complete binding report and its unresolved scope without
confusing missing analysis with an empty set. Independent test: hand-construct
valid/invalid SQLite data and invoke real query without producer.
Scope excludes source revalidation, tamper authentication and target claims.

1. Given a valid two-input three-result DB with2 matched/1 unresolved, query
   limit2 returns exact summary3/2/1 and two sorted rows, unchanged DB bytes.
2. Given marked data with missing/orphan/formal-position/kind/reference/count/JSON
   corruption beyond first row, query limit0 refuses3 before stdout.
3. Given an old/flat/markerless DB or invalid limit, query yields respective
   schema/collection refusal or usage2; no silent default or writes.
4. Given complete data with zero results, every renderer produces a summary and
   empty row table; JSON's second array is[], distinct from not collected.

## Prior art requiring explicit disposition

OCaml5.3 Env/Subst/Shape.Uid can normalize/translate compiler identities across
contexts (official URLs in research Q6). This slice deliberately uses only local
Ident.same and literal telescope shape, not semantic substitution or Shape
reduction. Wider APIs are not evidence of complete available environments;
unsupported rows preserve the gap for later work. Challenge this boundary.

## Planned executable check families (not yet implemented)

`node scripts/check-functor-bindings.js inventory|lifecycle|query|compatibility`.
Each plain script command must distinguish pass0/assertion1/infrastructure>=2.
Native fixtures, unit/anonymous formal and genuine negative identity mutation,
real persistence rollback, crafted marked corruptions, six formatter byte
oracles, and old catalogue/graph query/semantic-table comparisons are required.
