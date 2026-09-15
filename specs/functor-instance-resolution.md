---
name: roster-spec
type: spec
status: live
feature: OCaml functor application catalogue (resolution slice 0)
brief: briefs/functor-instance-resolution-intake.md
date: 2026-09-13
version: 1.0.0
---

# Spec — OCaml functor application catalogue

This is syntactic composition inventory, not target resolution, defunctorization,
0CFA, a closed-world guarantee or measured Tezos precision gain. Complete collection
is scoped only to selected CMT inputs. No third-party scan is part of verification.

## Clarifications

| Q | A |
|---|---|
| Runtime instances or project closure? | Selected-artifact syntax only; neither runtime multiplicity nor a closed world. |
| Which occurrences and order? | Every reachable immediate ordinary/unit module application in the local5.3 typed tree; parent-first preorder, functor before argument. |
| Which operand information? | Closed shallow descriptors below; complete application occurrence inventory does not serialize entire typed bodies. |
| Which output and limits? | Two existing-format tables with fixed fields below; optional strict decimal limit, default50. |
| Identity and locations? | Exact selected path plus ordinal, never binder spelling or location alone; invalid coordinates retained as explicit null diagnostics. |
| When is collection complete? | All nonempty selected inputs collected, counts/provenance persisted, data committed before marker; otherwise query refuses. |
| May graph behavior change? | No; existing definitions, pending tuple/head taxonomy, graph/effect data and verdicts remain semantically unchanged. |
| Which schema/toolchain? | Additive main schema only, currently1.13; flat1.3 unchanged; installed/CI compiler5.3, not an assumed5.5 API. |

## User Stories


### US-1: Inspect source-backed application composition (Priority: P0)

As an OCaml index maintainer, I want to query persisted syntactic applications and
their argument structure so I can distinguish composition shapes without guessing
from unresolved call names.

**Why this priority:** these facts do not exist in the current DB and are a prerequisite to
separately justified parameter substitution. **Scope:** no target inference, body
cloning, runtime instance count or call-graph change.

**Independent Test:** compile a native fixture, index it, and inspect the catalogue
tables directly with SQLite, without the new query command.

1. **Given** `F(X)` and `F(struct let n=1 end)` in an owned CMT, **When** indexed, **Then**
   two occurrence records preserve path versus structure arguments and locations,
   while the functions/calls snapshot retains the previous graph semantics.
2. **Given** `F(A)(B)`, `H(F(A))`, unit application, constrained expressions and an
   application inside a functor body/local module, **When** indexed, **Then** each immediate
   application appears once and head/argument references preserve tree order.
3. **Given** two same-spelled local module bindings, `module _ = F(A)`, and synthetic
   ghost/same-position locations, **When** indexed, **Then** distinct preorder identities
   retain every occurrence, with explicit unusable-location diagnostics where needed.
4. **Given** one successful CMT and one malformed or source-less selected CMT, **When**
   indexed, **Then** per-input outcomes expose the gap and no successful catalogue
   marker is stored; no graph edge is promoted by catalogue observations.
5. **Given** the same database is indexed twice, **When** reading ordered catalogue facts,
   **Then** no duplicate/stale rows survive and public identities/output are stable.

### US-2: Read an honest, bounded catalogue report (Priority: P0)

As an architecture reviewer, I want a read-only command with explicit collection
scope and limits so I can inspect available composition facts without confusing a
missing analysis, truncated listing or empty result with complete project knowledge.

**Why this priority:** SQL storage alone does not provide a usable or consistently guarded report.
**Scope:** no MCP, UI, graph verdict, new executable or publication workflow.

**Independent Test:** build a small hand-authored catalogue DB and invoke the query,
without the CMT collector. A separate native test covers end-to-end integration.

1. **Given** a valid two-input catalogue with three applications, **When** queried with
   limit2, **Then** ordered rows are capped at2 and summary reports total3/returned2/
   truncated=true, with source/artifact provenance and selected-input-only scope.
2. **Given** one collected input and zero applications, **When** queried with limit0,
   **Then** exit0 and the nonempty summary identifies a completed empty catalogue;
   JSON/table views agree and database bytes are unchanged by the read.
3. **Given** legacy/flat DB, absent marker, partial input coverage or missing required
   schema/data, **When** queried, **Then** exit3, no stdout and a named refusal distinguish
   not-collected/incomplete from zero occurrences.
4. **Given** `-1`, `0x10`, an overflowing integer or an extra argument, **When** queried,
   **Then** exit2 and no catalogue output rather than a silent default/unlimited scan.

## Challenges

Fourteen fresh adversarial challenges are preserved verbatim in
`roster/functor-instance-resolution/spec-challenges.md`; the binding resolutions
below resolve all of them. C-12/13/14 explicitly address Typedtree/Path/Shape prior art.

| Challenge | Resolution |

|---|---|
| C-1 | Traverse every Typedtree child reachable from the accepted `Implementation structure` through the OCaml5.3 default Tast_iterator, including expression, class/object, unpack, module-type-of and local-module children. No exclusion by execution/deferred/opaque context. Only immediate Tmod_apply/Tmod_apply_unit nodes are occurrences. Traversal never expands external artifacts, Env, Types signatures or Shape. |
| C-2 | Assign parent application ordinal before traversing either operand; visit functor before argument. Referenced applications in descriptors have strictly greater ordinals in the same input and must exist. Application-only ordinals are contiguous1..n per input. Applications inside shallow descriptor bodies are separately inventoried, not embedded in the descriptor. |
| C-3 | Selection is the existing producer's discovered `.cmt` path list, sorted and deduplicated by exact path string for catalogue accounting. Artifact key is that discovered path string, not realpath/inode/digest. Distinct symlink/copy paths remain distinct input selections, never advertised as unique physical programs. A duplicate source/module insertion rejected by the existing producer makes that input dropped_module, not collected via a previously inserted module. No changes to existing producer discovery or symlink policy. |
| C-4 | Persist producer-run linkage in SQL but exclude surrogate ids, run ids, timestamps and compiler stamps from the public report. Stable output applies only to identical selected path strings and artifacts under the same source mapping. No cross-build, moved-worktree or freshness guarantee. |
| C-5 | Selected is fixed before per-CMT processing. Outcome precedence: read exception/no CMT info -> unreadable; non-Implementation -> unsupported_annotation; unresolved source -> missing_source; own module insertion rejected -> dropped_module; collector/insertion/provenance error -> collection_failed; otherwise collected. Accumulate one input's occurrences completely before publishing; failure leaves zero application rows for that input. Per-input expected counts and selected count are persisted for consistency checks. |
| C-6 | Diagnostics attach to an occurrence as a sorted unique list; several codes can coexist. Closed derivation is defined below. Neither diagnostics nor an empty list express target resolution. |
| C-7 | On the same accepted fixture inputs, preserve functions identity/name/exposure/spans and calls' caller/callee identity, display/site, kind, TOP reason/anchor, conditional/dead semantics, scope/edge-form data, dependencies, exception/error facts, existing markers and query verdicts. Preserve three-list process_cmt return and existing head taxonomy. Additive schema/version/new catalogue provenance/rows and extra catalogue diagnostics are intentional differences. Catalogue failures cannot discard graph facts previously produced or promote edges; their new rejection accounting may report an additional problem. New source files can legitimately change self-index totals; calibrate with attribution, never weaken semantic tests. |
| C-8 | Clear catalogue eligibility marker via the central lifecycle before rebuilding. Persist header/input outcomes/application rows transactionally, with no partial application set for a failed input. Commit data before a separate final marker write. Earn v1 only with nonempty selection, all collected, required provenance present and exact counts stored. Interruption before marker leaves no eligible catalogue even if SQL rows survive; interruption before schema drop may leave old rows, but never an old authoritative marker. Reindex drops all new producer tables. |
| C-9 | Validate the whole catalogue before output or limit: required tables/columns, exactv1 marker, one run header linked to an existing producer, positive selected count, exact input count, every input collected with valid nonnull module/source/unit provenance, per-input expected row counts, contiguous positive ordinals and unique artifact keys, valid closed JSON descriptor/location/diagnostic schemas, forward same-input references, and no orphan rows. Marker is collection evidence, not tamper resistance; no assertion about malicious coordinated rewriting or source freshness. |
| C-10 | Usage/limit validation first => exit2. Open/operational DB failure => existing exit2. Then fixed exit3 precedence: `UNSUPPORTED_SCHEMA` (flat/missing schema), `NOT_COLLECTED` (absent/unrecognized marker), `INCONSISTENT_CATALOGUE` (header/count/outcome/provenance/descriptor/ref failure). Markerless partial runs use NOT_COLLECTED, with available failed-input outcome counts in diagnostic. No stdout before validation finishes. |
| C-11 | Freeze exact summary/application headers and JSON-valued text grammars below. Validate all data before computing total/returned; total is all validated application rows, not a filtered count. Existing renderer owns format escaping/null encoding. JSON emits exactly summary-array then application-array separated by newline; zero rows still emits `[]`. |
| C-12 | Adopt local5.3 Typedtree occurrence structure, not entire typed bodies. Shallow structure/unpack/functor descriptors deliberately omit declarations/expressions/types; only application topology and immediate operand category are promised. This is sufficient for syntax coverage, not parameter substitution. Future resolution must recover additional binder/body facts from artifacts; catalogue is not asserted sufficient alone. Installed interfaces were read, so no5.5 field is assumed. |
| C-13 | Papply is a static access path, not an observed module-expression evaluation. A Tmod_ident containing Papply remains a path descriptor with contains_apply=true and rendered compiler/source strings; it creates no extra occurrence. Distinct syntactic occurrences retain ordinal identities even for equal paths. Explicitly disclose omitted structural Path reduction and no alias/target identity guarantee. |
| C-14 | Shape definition reduction serves a different question than syntactic occurrence inventory. No Shape/UID-derived target, exactness flag, approximation or closure claim appears. Scope/limitations in every report state no target resolution and no runtime/closed-world interpretation. This deliberately bounded slice does not claim to complete defunctorization or enable substitution without further work. |


## Closed observable contract


Summary columns, in order:
`contract, selected_inputs, collected_inputs, total, returned, truncated, scope, limitations`.
contract=`v1`; counts are nonnegative integers; selected_inputs>0;
truncated is integer0or1 and equals returned<total. scope=`selected_cmt_syntax_only`.
limitations is the fixed text:
`not_runtime_instances;not_closed_world;no_target_resolution;no_source_freshness_check;paths_are_artifact_selections`.

Application columns, in order:
`artifact, source, compiler_unit, ordinal, application_kind, location, head, argument, diagnostics`.
application_kind is `apply` or `apply_unit`. The last five fields except
application_kind are: location/head/argument/diagnostics JSON-valued text,
while ordinal is an integer. No extra public fields in this version.

Location JSON has exactly
`{file,start_line,start_col,end_line,end_col,ghost}`.
Valid locations require nonempty matching start/end filenames, lines>=1,
columns>=0 and lexicographically ordered (line,column) range. Columns are compiler
byte columns, not Unicode display columns. Ghost alone does not make a location
invalid. Invalid locations set file and all coordinates to null, retain ghost,
and add unusable_location. Source path remains independently recorded.

Descriptor JSON has exactly one of these closed tagged forms:

- `{kind:"path",compiler:string,source:string,contains_apply:boolean}`;
- `{kind:"structure"}`;
- `{kind:"functor",parameter:"unit"|"named",name:string|null}` (unit => name null);
- `{kind:"unpack"}`;
- `{kind:"constraint",expression:descriptor}`;
- `{kind:"application",ordinal:positive_integer}`;
- `{kind:"unit"}` only as the argument of apply_unit.

No application-level nested body is serialized. Application descriptor references
may be under constraints. Strip constraints for the following code derivation:

- `opaque_functor_head` iff head kind is neither path nor application;
- `anonymous_argument` iff argument kind is structure;
- `unpacked_expression` iff head or argument kind is unpack;
- `unusable_location` iff location fails the rules above.

Diagnostics JSON is an ascending lexicographic unique array of applicable codes.
Named paths remain display provenance even when diagnostics is empty.

Limit is an optional strict ASCII decimal fitting nonnegative OCaml int, default50.
Overflow (including digits beyond the platform range) and any extra argument are
exit2. Limit0 produces summary and empty application table. Existing table renderers
own text escaping and headers; in JSON each descriptor is a JSON string cell (not
an unannounced nested JSON object). Two tables are rendered only after all reads and
validations succeed, preserving empty stdout for refusals.


## Functional Requirements

### Collection and composition (US-1)

- **FR-001** [US-1; scenarios 1–3; check: inventory]: For each selected OCaml 5.3 `Implementation structure` whose catalogue outcome is `collected`, the catalogue MUST contain exactly one occurrence for every reachable immediate `Tmod_apply` and `Tmod_apply_unit`, including occurrences below expressions, classes/objects, unpack, module-type-of, functor bodies, nested structures, anonymous arguments, unnamed bindings, and local modules; failed inputs follow FR-014/FR-015 instead.
- **FR-002** [US-1; scenario 2; C-1; check: inventory]: The catalogue MUST NOT report applications obtained by expanding external artifacts, environments, type signatures, or Shapes, and MUST NOT exclude a reachable application because its context is deferred, opaque, or not known to execute.
- **FR-003** [US-1; scenarios 2–3; C-2; check: inventory]: Within each selected artifact, occurrence ordinals MUST be contiguous positive integers assigned in application-only preorder, with a parent assigned before either operand and the functor operand visited before the argument operand.
- **FR-004** [US-1; scenario 2; C-2; check: inventory]: An application descriptor MUST reference an existing, strictly greater ordinal in the same artifact, while applications found inside a shallow operand MUST remain separate occurrences rather than embedded serialized bodies.
- **FR-005** [US-1; scenarios 1–3; C-3; check: inventory]: Catalogue selection MUST equal the producer-discovered `.cmt` path list sorted and deduplicated by exact path string; exact discovered path plus ordinal MUST identify a public occurrence, without realpath, inode, digest, visible name, location, or physical-program uniqueness semantics.
- **FR-006** [US-1; scenarios 3 and 5; C-3/C-4; check: inventory]: Distinct selected path strings and distinct syntactic ordinals MUST remain distinct even when artifacts are copies or symlinks, display names are equal, or locations coincide; stable ordered identity MUST be claimed only for identical selected path strings and artifacts under the same source mapping.
- **FR-007** [US-1; scenarios 1–3; C-12; check: inventory]: Each occurrence MUST expose only the immediate OCaml 5.3 syntactic operand categories and application topology, using the closed descriptor forms `path`, `structure`, `functor`, `unpack`, `constraint`, `application`, and `unit`; shallow descriptors MUST NOT serialize bodies, declarations, expressions, types, or coercion interpretations.
- **FR-008** [US-1; scenarios 1–2; C-12; check: inventory]: Descriptor values MUST conform exactly to these forms: path `{kind,compiler,source,contains_apply}`; structure `{kind}`; functor `{kind,parameter,name}` with parameter `unit` or `named`, a null name for unit parameters and an optional string name for named parameters; unpack `{kind}`; constraint `{kind,expression}`; application `{kind,ordinal}` with a positive ordinal; and unit `{kind}`, permitted only as an `apply_unit` argument.
- **FR-009** [US-1; scenario 1; C-13; check: inventory]: A `Tmod_ident` path containing `Papply` MUST remain one path descriptor with `contains_apply=true` and compiler/source display strings, MUST NOT create an additional occurrence, and MUST NOT imply structural path reduction, alias identity, or target identity.
- **FR-010** [US-1; scenarios 1 and 3; location contract; check: inventory]: Each occurrence location MUST expose exactly `file,start_line,start_col,end_line,end_col,ghost`; a valid location MUST have equal nonempty endpoint filenames, lines at least 1, byte columns at least 0, and an ordered start/end pair, while a ghost flag alone MUST NOT invalidate it.
- **FR-011** [US-1; scenario 3; location contract; check: inventory]: An invalid location MUST retain its ghost flag, set the file and every coordinate to null, and include `unusable_location`, without removing the independently recorded source path.
- **FR-012** [US-1; scenarios 1–3; C-6; check: inventory]: Each occurrence MUST expose an ascending lexicographically sorted unique diagnostics list containing exactly the applicable codes after constraints are stripped: `opaque_functor_head` when the head is neither path nor application, `anonymous_argument` when the argument is structure, `unpacked_expression` when either operand is unpack, and `unusable_location` when the location is invalid.
- **FR-013** [US-1; scenarios 1–3; C-6/C-14; check: inventory]: Diagnostics, including an empty list, MUST NOT be presented as target resolution, and catalogue output MUST NOT expose Shape/UID-derived targets, exactness or approximation flags, runtime-instance claims, closed-world claims, defunctorization completion, or sufficiency for parameter substitution.
- **FR-014** [US-1; scenario 4; C-5; check: lifecycle]: Before processing begins, every selected input MUST be fixed and MUST receive exactly one outcome using this precedence: `unreadable`, `unsupported_annotation`, `missing_source`, `dropped_module`, `collection_failed`, then `collected`; a rejected module insertion for that input MUST be `dropped_module`, not borrowed from an earlier module, while a catalogue insertion failure MUST be `collection_failed`.
- **FR-015** [US-1; scenario 4; C-5/C-8; check: lifecycle]: An input MUST publish its complete occurrence set atomically or publish zero application rows when collection, insertion, or provenance fails; inputs not marked `collected` MUST NOT contribute application rows, and a collected input MAY contain zero applications.
- **FR-016** [US-1; scenarios 4–5; C-8; check: lifecycle]: Rebuilding MUST clear catalogue eligibility through the central marker lifecycle, discard all prior catalogue tables on reindex, and MUST NOT leave an old marker authoritative after interruption or failure.
- **FR-017** [US-1; scenario 4; C-8; check: lifecycle]: The producer MUST earn `functor_catalogue_contract=v1` only after catalogue data is committed for a nonempty selection in which every input is collected and all required provenance, selected/input counts, expected row counts, and occurrence rows are present; zero successfully collected applications MAY earn the marker, but zero selected inputs MUST NOT.
- **FR-018** [US-1; scenario 4; C-4/C-5; check: lifecycle]: Persisted catalogue facts MUST retain producer-run linkage, artifact/source/compiler-unit provenance, per-input outcomes, selected count, and per-input expected counts, while public occurrence/report identity MUST exclude database surrogate IDs, run IDs, timestamps, compiler stamps, and freshness guarantees.
- **FR-019** [US-1; scenarios 1 and 4; C-7; check: compatibility]: Catalogue collection and its failures MUST NOT change existing function, call, dependency, exception, error, marker, query-verdict, three-list `process_cmt` result, or head-taxonomy semantics; catalogue observations MUST NOT promote graph edges or discard graph facts already produced.
- **FR-020** [US-1; scenario 5; C-7/C-8; check: compatibility]: Reindexing the same selected artifacts and source mapping MUST leave no duplicate or stale catalogue rows and MUST reproduce the same public identities and ordered catalogue facts, while additive catalogue schema, provenance, diagnostics, and attributable totals from genuinely new source files remain permitted.

### Catalogue query (US-2)

- **FR-021** [US-2; scenarios 1–4; check: query]: `arch-query DB functor-applications [limit]` MUST accept no other positional arguments, MUST default the limit to 50, and MUST accept an explicit limit only when it is strict ASCII decimal text fitting a nonnegative OCaml integer; negative, prefixed, overflowing, or extra arguments MUST produce exit 2 and no catalogue output.
- **FR-022** [US-2; scenarios 3–4; C-10; check: query]: The query MUST validate usage and limit before opening or interpreting catalogue state; usage failures and database open/operational failures MUST exit 2, while catalogue refusals MUST exit 3 with empty stdout.
- **FR-023** [US-2; scenario 3; C-10; check: query]: After argument and operational checks, catalogue refusal MUST use this precedence and named stderr diagnosis: `UNSUPPORTED_SCHEMA` for flat or missing schema, `NOT_COLLECTED` for an absent or unrecognized marker, then `INCONSISTENT_CATALOGUE` for invalid header, counts, outcomes, provenance, descriptors, locations, diagnostics, or references; markerless partial runs MUST be `NOT_COLLECTED` and include available failed-input outcome counts.
- **FR-024** [US-2; scenarios 1–3; C-9; check: query]: Before applying the limit or writing stdout, the query MUST validate the complete catalogue: required tables/columns, exact v1 marker, exactly one run header linked to an existing producer, positive selected count, exact input count, all inputs collected with nonnull valid module/source/unit provenance, exact expected row counts, unique artifact keys, contiguous positive ordinals, closed location/descriptor/diagnostic JSON, valid forward same-input references, and absence of orphan rows.
- **FR-025** [US-2; scenarios 1–2; C-11; check: query]: Only after full validation, the query MUST compute `total` from all validated application rows, sort applications by artifact then ordinal, apply the limit, and compute `returned` and `truncated`; limit 0 MUST mean zero application rows, not unlimited output.
- **FR-026** [US-2; scenarios 1–2; C-11/C-14; check: query]: A successful query MUST emit one summary row with columns in this exact order: `contract,selected_inputs,collected_inputs,total,returned,truncated,scope,limitations`, where contract is `v1`, counts are nonnegative with selected inputs positive, truncated is 0 or 1 exactly matching `returned < total`, scope is `selected_cmt_syntax_only`, and limitations is `not_runtime_instances;not_closed_world;no_target_resolution;no_source_freshness_check;paths_are_artifact_selections`.
- **FR-027** [US-2; scenario 1; C-11; check: query]: Application output MUST use columns in this exact order and no additional v1 public fields: `artifact,source,compiler_unit,ordinal,application_kind,location,head,argument,diagnostics`; application kind MUST be `apply` or `apply_unit`, ordinal MUST be an integer, and location/head/argument/diagnostics MUST be JSON-valued text cells.
- **FR-028** [US-2; scenarios 1–2; C-11; check: query]: The query MUST use existing `ARCH_QUERY_FORMAT` rendering semantics; JSON mode MUST emit exactly a summary array followed by one newline and an application array, and MUST emit `[]` for zero application rows rather than omitting the second table or converting descriptor cells into nested objects.
- **FR-029** [US-2; scenarios 2–3; C-9/C-11; check: query]: The query MUST emit no stdout until every required read and validation has succeeded; a valid catalogue MUST exit 0 even when it contains zero applications, whereas absent, incomplete, inconsistent, or unsupported catalogue state MUST NOT be reported as a completed empty catalogue.
- **FR-030** [US-2; scenario 2; happy path; check: compatibility]: Every successful catalogue query, including table/JSON output and limit 0, MUST leave the database bytes unchanged.


## Acceptance Criteria


- **AC-1** [US-1 happy path; FR-001–FR-013, FR-019; check: inventory]: Indexing owned OCaml 5.3 fixtures containing path, structure, nested, unit, constrained, functor-body, local-module, anonymous, unpack, ghost-location, and `Papply` cases → every and only immediate selected-artifact application is catalogued once with the closed shallow descriptor, location, diagnostic, and preorder identity contract, while the graph snapshot remains unchanged.
- **AC-2** [US-2 happy path; FR-021–FR-030; check: query]: Querying a valid two-input, three-application catalogue with limit 2 → exit 0, exact summary and application headers/values, two artifact/ordinal-sorted rows, `total=3`, `returned=2`, `truncated=1`, selected-syntax scope and fixed limitations, with no database mutation.
- **AC-3** [US-1, C-1; FR-001–FR-002; check: inventory]: A premise-verified native fixture places applications under every required OCaml 5.3 reachable child category → traversal reports all immediate nodes and reports none from external artifacts, Env, Types signatures, or Shape.
- **AC-4** [US-1, C-2; FR-003–FR-004; check: inventory]: Nested and chained fixture applications are indexed → ordinals are contiguous parent-first application preorder, functor precedes argument, and every nested descriptor reference points forward to an existing ordinal in the same artifact.
- **AC-5** [US-1, C-3; FR-005–FR-006, FR-014; check: lifecycle]: Producer discovery includes duplicate exact paths, distinct copy/symlink path strings, and a duplicate module/source insertion → selection is exact-string sorted/deduplicated, distinct paths remain distinct, and the rejected input is `dropped_module` with no borrowed collection success.
- **AC-6** [US-1, C-4; FR-006, FR-018, FR-020; check: lifecycle]: Identical artifacts and selected paths are reindexed under the same source mapping → ordered public output is stable and excludes surrogate/run/time/stamp identity, without claiming stability after rebuilds, moves, or changed source mapping.
- **AC-7** [US-1, C-5; FR-014–FR-015, FR-018; check: lifecycle]: Selected inputs independently trigger each outcome and a mid-input collection failure → the precedence is exact, each input has one outcome, failed inputs have zero application rows, and persisted selected/expected counts expose the gap.
- **AC-8** [US-1, C-6; FR-012–FR-013; check: inventory]: Fixtures trigger overlapping opaque-head, anonymous-argument, unpacked-expression, and unusable-location conditions → each occurrence carries exactly the sorted unique applicable codes, and no diagnostic state claims target resolution.
- **AC-9** [US-1, C-7; FR-019–FR-020; check: compatibility]: The same accepted fixtures are indexed with catalogue collection enabled → established graph/function/call/dependency/error/marker/query snapshots and `process_cmt`/head contracts are unchanged, and catalogue failure neither promotes an edge nor removes existing graph facts.
- **AC-10** [US-1, C-8; FR-015–FR-017, FR-020; check: lifecycle]: Reindex success, per-input failure, and interruptions before marker and before schema replacement are exercised → stale eligibility is cleared, rows are atomic per input, old catalogue tables are dropped, and v1 is written only after a complete committed nonempty-selection catalogue.
- **AC-11** [US-2, C-9; FR-024–FR-025, FR-029; check: query]: Missing required rows, count mismatch, invalid ordinal, orphan/bad/cross-input reference, malformed descriptor/location/diagnostics, invalid provenance, and incomplete outcomes are injected into a marked database with all required tables/columns → full validation rejects each before limit/output as `INCONSISTENT_CATALOGUE`; missing tables/columns instead follow `UNSUPPORTED_SCHEMA` precedence, and an exact valid v1 catalogue passes.
- **AC-12** [US-2, C-10; FR-021–FR-023, FR-029; check: query]: Usage errors, database open/operational failures, successfully opened old/flat indexes, markerless partial data, and inconsistent marked data are queried → open/operational failures remain exit 2, catalogue exits and named diagnoses follow exit-3 precedence exactly, and stdout is empty with failed-input counts where available for markerless partial data.
- **AC-13** [US-2, C-11; FR-024–FR-029; check: query]: Valid nonempty and zero-application catalogues are rendered in every supported format at limits 2 and 0 → all data is validated before totals/limits, headers and cell grammars are exact, JSON is precisely two arrays separated by a newline, and zero rows yields `[]`.
- **AC-14** [US-1, C-12; FR-007–FR-008, FR-013; check: inventory]: Native OCaml 5.3 fixtures containing structure, unpack, functor, and constrained operands are indexed → descriptors remain the closed shallow syntax contract, nested applications are separate occurrences, and no body/type/coercion or substitution-sufficiency claim appears.
- **AC-15** [US-1, C-13; FR-005, FR-009; check: inventory]: A premise-verified real Typedtree fixture contains `Tmod_ident` with `Papply` → it yields a path descriptor with `contains_apply=true`, rendered provenance, and no extra application occurrence or alias/target-resolution claim.
- **AC-16** [US-2, C-14; FR-013, FR-026–FR-027; check: query]: Every successful report is inspected → its scope and fixed limitations identify selected-artifact syntax only, exclude runtime/closed-world/target/freshness/unique-physical-program interpretations, and no report or documentation claims completion of defunctorization/substitution.

## Edge Cases

- EC-1 [US-1]: Applications in both operands => parent-first ordinal, head subtree before argument subtree, valid forward references.
- EC-2 [US-1]: Alias/copy paths => distinct input selections; exact repeated strings deduplicate; rejected duplicate module is not borrowed success.
- EC-3 [US-1]: Mid-input collection failure => failed input contributes zero applications and no whole-catalogue marker.
- EC-4 [US-1]: Ghost/same-position/invalid locations => occurrence ordinal prevents collision, ghost alone remains valid, invalid positions use explicit nulls.
- EC-5 [US-1]: Papply in an identifier path => path descriptor contains_apply=true, no invented occurrence.
- EC-6 [US-2]: Broken ordinal reference => INCONSISTENT_CATALOGUE exit3, empty stdout, including when limit0 would hide it.
- EC-7 [US-1]: Interrupted reindex after eligibility clear => old marker absent; SQL remnants never eligible.
- EC-8 [US-2]: Multiple refusal conditions => defined schema/marker/consistency precedence after usage/open checks.
- EC-9 [US-2]: Decimal overflow => usage exit2, never unlimited/default output.
- EC-10 [US-2]: Collected input with zero applications and limit0 => summary total0/returned0/truncated0 and empty second JSON array.

## Runnable Checks

Run after a full build in the OCaml5.3 opam environment. Local invocation uses
`rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- node ...`.
Each standalone group must distinguish 0=pass, 1=independent assertion failure,
>=2=setup/compile/read/operational error; never remap a generic test-runner exit1.
The scripts are implementation deliverables, not already-passed checks at spec time.

- **CHECK-1** [AC-1, AC-3, AC-4, AC-8, AC-14, AC-15]: `rtk proxy node scripts/check-functor-catalogue.js inventory` → exit0 after native occurrence census, topology, operand/location diagnostics and probe-premised Papply shapes.
- **CHECK-2** [AC-5, AC-6, AC-7, AC-10]: `rtk proxy node scripts/check-functor-catalogue.js lifecycle` → exit0 after selection identity, all input outcomes, count/provenance persistence, atomic failed inputs and interrupted/repeated indexing.
- **CHECK-3** [AC-2, AC-11, AC-12, AC-13, AC-16]: `rtk proxy node scripts/check-functor-catalogue.js query` → exit0 after hand-authored and native databases, every schema/refusal/consistency case, every formatter and strict limits.
- **CHECK-4** [AC-1, AC-2, AC-6, AC-9]: `rtk proxy node scripts/check-functor-catalogue.js compatibility` → exit0 after unchanged existing graph facts/verdicts, stable reindex output and byte-unchanged read-only query.

Each fixture must assert its premise before evaluating product behavior. Native
artifact probes may generate otherwise unavailable Papply/ghost locations, but
must not be described as ordinary compiler source output. Missing prerequisites
are error2, not a passing skip or a regression assertion. Full suite, self-index,
calibration and existing rule/consumer gates additionally remain mandatory.

## Claims Metadata

Metadata is draft: no claims reconciler is installed, so deterministic authority
validation/projection is unavailable and is not claimed.

```claims
{"record":"claims-header","schema_version":1,"namespace":"functor-instance-resolution","spec_lifecycle":"draft"}
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
{"record":"requirement","id":"FR-027","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-028","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-029","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-030","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"acceptance-criterion","id":"AC-1","for":["FR-001","FR-002","FR-003","FR-004","FR-005","FR-006","FR-007","FR-008","FR-009","FR-010","FR-011","FR-012","FR-013","FR-019"]}
{"record":"acceptance-criterion","id":"AC-2","for":["FR-021","FR-022","FR-023","FR-024","FR-025","FR-026","FR-027","FR-028","FR-029","FR-030"]}
{"record":"acceptance-criterion","id":"AC-3","for":["FR-001","FR-002"]}
{"record":"acceptance-criterion","id":"AC-4","for":["FR-003","FR-004"]}
{"record":"acceptance-criterion","id":"AC-5","for":["FR-005","FR-006","FR-014"]}
{"record":"acceptance-criterion","id":"AC-6","for":["FR-006","FR-018","FR-020"]}
{"record":"acceptance-criterion","id":"AC-7","for":["FR-014","FR-015","FR-018"]}
{"record":"acceptance-criterion","id":"AC-8","for":["FR-012","FR-013"]}
{"record":"acceptance-criterion","id":"AC-9","for":["FR-019","FR-020"]}
{"record":"acceptance-criterion","id":"AC-10","for":["FR-015","FR-016","FR-017","FR-020"]}
{"record":"acceptance-criterion","id":"AC-11","for":["FR-024","FR-025","FR-029"]}
{"record":"acceptance-criterion","id":"AC-12","for":["FR-021","FR-022","FR-023","FR-029"]}
{"record":"acceptance-criterion","id":"AC-13","for":["FR-024","FR-025","FR-026","FR-027","FR-028","FR-029"]}
{"record":"acceptance-criterion","id":"AC-14","for":["FR-007","FR-008","FR-013"]}
{"record":"acceptance-criterion","id":"AC-15","for":["FR-005","FR-009"]}
{"record":"acceptance-criterion","id":"AC-16","for":["FR-013","FR-026","FR-027"]}
{"record":"check","id":"CHECK-1","for":["AC-1","AC-3","AC-4","AC-8","AC-14","AC-15"]}
{"record":"check","id":"CHECK-2","for":["AC-5","AC-6","AC-7","AC-10"]}
{"record":"check","id":"CHECK-3","for":["AC-2","AC-11","AC-12","AC-13","AC-16"]}
{"record":"check","id":"CHECK-4","for":["AC-1","AC-2","AC-6","AC-9"]}
```

## Exact-copy lifecycle amendment (2026-09-15)

`specs/ocaml-data-preservation.md` admits graph reuse **before** attempting a
duplicate module insertion: same run/root, resolved source/compiler unit, full
artifact bytes, and a successfully extracted representative graph. Each selected
copy or symlink path still receives its own catalogue/binding collection and
outcome. This is not borrowed success after a rejected insertion: C-3, FR-014,
AC-5 and EC-2 continue to require `dropped_module` for an actually rejected
insertion, including nonidentical same-source artifacts. The lifecycle check
covers both successful exact-copy reuse and the nonidentical rejection control.

## Entities

- FunctorCatalogueInput: one exact discovered CMT path selection and its collection outcome in this run, not a unique physical program.
- FunctorApplicationOccurrence: one immediate ordinary/unit module application in one selected implementation Typedtree, identified by path and preorder ordinal.
- FunctorExpressionDescriptor: shallow syntax provenance for an operand, not a resolved module or runtime identity.
- FunctorCatalogueContract: earned selected-input collection eligibility, independent of every graph, error and exception contract.

Existing entities remain unchanged; cross-spec entity scan is recorded in
`roster/functor-instance-resolution/cross-spec.md`. Operator review corrected
optional named-functor parameters, insertion-outcome distinction and missing-schema
refusal precedence in the fresh formalizer output before validation.
