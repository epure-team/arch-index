---
name: roster-spec
type: spec
status: live
feature: OCaml same-CMT 0-CFA propagation
brief: briefs/ocaml-cfa-propagation-intake.md
date: 2026-09-16
version: 1.0.0
---

# Spec — OCaml same-CMT 0-CFA propagation (Stage 3)

## Clarifications

| Q | A |
|---|---|
| Analysis boundary? | One CMT/session, context-insensitive. No cross-CMT linking or functor correspondence. |
| Supported declarations? | Top-level or local `Tpat_var = Texp_function(..., Tfunction_body ...)`; a recursive group is supported only when every member has that shape. |
| Supported formals and labels? | `Tparam_pat(Tpat_var)` with `Nolabel` or nonoptional `Labelled`; slots must match the flattened leading parameter slots and labels exactly. |
| Supported normal results? | The shared identifier/function/if/match/sequence grammar, supported simple nonrecursive lets, and supported application-result cells. |
| Supported captures? | Exact same-CMT `Ident` reads of tracked immutable roots, formals, local aliases and application results. Aggregate projection, mutation, objects/modules/imports and cross-CMT values remain unknown. |
| Supported recursion? | Direct or mutually recursive simple function groups; mixed or unsupported groups retain callback uncertainty. Cycles are inclusion constraints, not unrolling. |
| Partial application identity? | A finite internal pair `(underlying callable, consumed leading-slot count)`; aliases preserve it, repeated stages advance only to declared arity. |
| Evidence meaning? | Authentic CMT fixtures establish behavior. The pinned Tezos replay establishes exact structural gains/losses and resource observations only. |

## User Stories

### US-1: Seal the CFA session and semantic domain (Priority: P0)

As an analysis maintainer, I want one lifecycle-safe transfer boundary and an
exhaustive uncertainty vocabulary so that later interprocedural constraints
cannot silently produce stale or misclassified values.

**Why this priority:** every later flow depends on the session having one fixed
point and on unknown contributions remaining semantically distinguishable.

**Scope:** This story does not add argument, return, capture, recursion or partial
closure flow.

**Independent Test:** exercise every session entry point around finalization and
compare the shared transfer dispatcher under root and local policies.

**Acceptance Scenarios:**

1. **Given** a finalized session, **when** any mutation entry point is called,
   **then** it raises the prescribed `Invalid_argument` before changing state and
   all prior query results remain identical.
2. **Given** callback uncertainty, known producer rejection, duplicates and an
   overapplication residual, **when** values are joined and persisted, **then**
   the two semantic reason kinds remain exhaustive and distinct while the
   structural residual remains independent.
3. **Given** equal supported syntax under root and local policies returning equal
   observations, **when** transfer is evaluated, **then** it produces equal
   abstract values through one dispatcher and every foundation fixture keeps its
   canonical output.

### US-2: Propagate arguments and normal returns through a finite fixed point (Priority: P0)

As a Tezos call-graph reader, I want function-valued actuals and normal results
to cross supported same-CMT call boundaries so that indirect calls through
higher-order helpers and recursive groups resolve conservatively.

**Why this priority:** this is the central 0-CFA gain and directly targets the
unresolved higher-order patterns present in protocol and Irmin code.

**Scope:** This story excludes captures, partial residual calls, cross-CMT flow,
functors, optional/default/destructured parameters and whole-program claims.

**Independent Test:** compile fixtures for identity/apply helpers, disjoint call
sites and mutual recursion, then query physical application results.

**Acceptance Scenarios:**

1. **Given** `id f = f` and a saturated call receiving known function `target`,
   **when** the session reaches its fixed point, **then** `target` flows through
   the formal and return cells into that physical application-result cell.
2. **Given** two call sites with disjoint known targets and a mutually recursive
   higher-order cycle, **when** constraints are registered in different orders,
   **then** shared formal/return cells converge to the same context-insensitive
   finite union at every supported result occurrence.
3. **Given** a known-plus-unknown actual or an unsupported formal/slot/boundary,
   **when** flow crosses the call, **then** all known candidates and the explicit
   callback frontier propagate independently and no closed result is claimed.

### US-3: Preserve captures and staged callable values in output (Priority: P0)

As an architecture reviewer, I want supported lexical closures and partial
applications to remain finite callable values with occurrence-accurate evidence
so that eventual calls resolve without inventing execution or stronger edges.

**Why this priority:** capture and currying are common OCaml higher-order shapes;
omitting them leaves the largest intended Stage-3 holes.

**Scope:** This story excludes aggregate/mutable capture, optional arguments,
feeding overapplication into returned callables, cross-CMT closure instances and
Stage-4 functor/member substitution.

**Independent Test:** compile capture, staged saturation, mixed-arity and
same-location occurrence fixtures and compare both main/flat outputs plus the
pinned Tezos replay.

**Acceptance Scenarios:**

1. **Given** repeated evaluations of one lambda allocation site with distinct
   supported captured callables, **when** the closure is invoked, **then** its
   context-insensitive capture contains their union; unsupported captures add an
   independent callback frontier.
2. **Given** a known callable applied in multiple supported stages, **when** it is
   under-saturated, **then** a finite residual value is produced without return
   flow; **when** declared arity is reached, **then** the underlying target and
   normal return flow reach the saturating occurrence.
3. **Given** mixed arities, equal source locations, unknown labels/arity and
   overapplication, **when** occurrences expand, **then** each candidate and each
   physical stage retain their own metadata, all new targets are
   `MAY_ENUMERATED`, all unknown fronts survive and no new `MUST` appears.

## Challenges

| ID | Story | Challenge | Resolution |
|---|---|---|---|
| C-1 | US-1 | Which APIs mutate after finalization? | Close the list over all current and new owner, literal, notification, binding, call and constraint registration APIs; reject before effects. |
| C-2 | US-1 | Is finalization repeatable and exception-safe? | Repeated successful finalization is idempotent; pre-finalize queries reject; a failing finalize exposes no partial transition. |
| C-3 | US-1 | What is the reason vocabulary and multiplicity? | Stage 3 has exactly `Callback_param` and `Dropped_node`; semantic kinds deduplicate, while an overapplication residual remains structurally separate. |
| C-4 | US-1 | Can typed reasons preserve existing output? | Mapping is exhaustive with no catch-all; architecture-only changes preserve canonical foundation rows byte-for-byte. |
| C-5 | US-1 | What does “shared grammar” mean? | One `exp_desc` dispatcher owns syntax; explicit lookup/literal policies own root/local authentication differences. |
| C-6 | US-1 | Does bottom become unknown globally? | No. Bottom remains bottom until invocation; an invoked bottom occurrence becomes callback unknown. |
| C-7 | US-2 | Which callable/formal/application shapes are supported? | Only the shapes in Clarifications; unsupported or mixed shapes contribute callback unknown rather than guessed transfer. |
| C-8 | US-2 | How are result and occurrence identities separated? | Each physical application token owns a result cell; each callable owns shared formal and normal-return cells. Metadata stays on the token. |
| C-9 | US-2 | Is call-site merging acceptable? | Yes. Context-insensitive union across sites is contractual and tested explicitly. |
| C-10 | US-2 | How is termination established? | Cells, callable identities and residual identities are allocated from the finite Typedtree before solve; solve allocates none. |
| C-11 | US-2 | Can direct resolution be duplicated by CFA? | No. The direct edge remains authoritative, while actual/result constraints may still propagate values. |
| C-12 | US-3 | What counts as immutable capture and closure identity? | Exact tracked `Ident` values only; one lambda allocation-site declaration is the context-insensitive closure identity. |
| C-13 | US-3 | How are staged, mixed-arity and over-applied calls represented? | Residual key is target plus consumed leading slots; candidates advance independently; extras retain the existing unknown residual and do not call a returned value. |
| C-14 | US-2 | Prior art: Shivers CFA carries abstract closures and explicit application constraints. | Adopt its actual/formal and body/result inclusion shape only for the declared Typedtree subset; document the narrower target/reason abstraction. |
| C-15 | US-2 | Prior art: AAM bounds stores and models continuations. | Use a finite preallocated inclusion graph and normal-result cells; make no AAM, continuation or exceptional-return equivalence claim. |
| C-16 | US-3 | Prior art: Flambda operates after closure conversion with explicit environments. | Typedtree identities and conservative unknowns are the evidence boundary; no wrapper/surrogate or closure-layout claim enters persisted output. |
| C-17 | US-2 | Prior art: MLton assumes whole-program CFA plus defunctorization. | Explicitly retain same-CMT open-world uncertainty and exclude Stage-4 functor work. |
| C-18 | US-1 | Prior art: Infer keeps bottom and missing summaries distinct. | Preserve bottom until invocation and make unavailable/open flow an explicit callback reason. |

## Functional Requirements

#### Session and domain contract

- **FR-001** [US-1]: Every current or new owner, literal, storage-notification, rejection, binding, call, expression-call and constraint-registration API MUST reject use after successful finalization with `Invalid_argument` whose message starts `CFA CMT session already finalized`, before any observable mutation.
- **FR-002** [US-1]: A rejected post-finalization operation MUST leave all query results and session-observable allocation/constraint state unchanged.
- **FR-003** [US-1]: Successful repeated `finalize` calls MUST be observationally idempotent, and every occurrence-value query before successful finalization MUST reject.
- **FR-004** [US-1]: If finalization raises, the session MUST expose no partially finalized state, provisional target/reason seed, or newly queryable result.
- **FR-005** [US-1]: CFA uncertainty MUST use the exhaustive semantic type `Callback_param | Dropped_node`; unsupported/open-world flow MUST map explicitly to the former and known producer rejection explicitly to the latter.
- **FR-006** [US-1]: Persistence MUST map every semantic reason exhaustively without a catch-all; equal semantic reasons MUST deduplicate, while overapplication residual output MUST remain a separate occurrence contribution.
- **FR-007** [US-1]: Exactly one expression dispatcher MUST define transfer for identifiers, functions, conditionals, matches, sequences, supported simple lets and application results; root/local differences MUST be supplied as explicit lookup and literal-authentication policies.
- **FR-008** [US-1]: Equal supported syntax under policies returning equal observations MUST yield equal abstract values.
- **FR-009** [US-1]: An unseeded cell or cycle MUST remain bottom until invocation; an invoked bottom contribution MUST persist as callback uncertainty rather than disappear.
- **FR-010** [US-1]: Lifecycle, reason-typing and dispatcher refactors MUST preserve every existing foundation fixture's canonical rows byte-for-byte.

#### Same-CMT argument and return flow

- **FR-011** [US-2]: The analysis MUST support top-level and local `Tpat_var = Texp_function(..., Tfunction_body ...)` declarations and MUST support a recursive group only when every member has that shape.
- **FR-012** [US-2]: Supported formals MUST be nonpartial `Tparam_pat(Tpat_var)` parameters with `Nolabel` or nonoptional `Labelled`; `Tfunction_cases`, optional/default/refutable/destructured/wildcard parameters and mixed recursive groups MUST retain callback uncertainty.
- **FR-013** [US-2]: An actual MUST map only to its corresponding flattened leading formal slot with an exact label match; absent, mismatched or optional slots MUST retain callback uncertainty.
- **FR-014** [US-2]: Every supplied supported actual cell MUST flow immediately to its matched formal cell, including during underapplication.
- **FR-015** [US-2]: Normal callable results MUST be derived through the shared expression grammar, supported simple nonrecursive lets and supported application-result cells; every unsupported result path MUST contribute callback uncertainty.
- **FR-016** [US-2]: Each physical application token MUST own one result cell, while every supported callable MUST own one shared formal cell per formal and one shared normal-return cell across all call sites.
- **FR-017** [US-2]: At a supported saturated application, the candidate callable's normal-return cell MUST flow to that physical application's result cell.
- **FR-018** [US-2]: Formal and return cells MUST intentionally merge values context-insensitively across supported call sites, and the same union MUST be observable at each affected saturated result cell.
- **FR-019** [US-2]: Direct and mutually recursive inclusion cycles MUST converge without unrolling and independently of constraint registration order or duplication.
- **FR-020** [US-2]: Targets and uncertainty reasons MUST propagate independently through actual, formal, capture, return and application-result constraints; crossing the same-CMT/open-world boundary MUST add callback uncertainty without erasing known targets.
- **FR-021** [US-2]: Every cell, callable identity and residual identity MUST be allocated from the finite CMT/Typedtree before solving; the solver MUST allocate none of them.
- **FR-022** [US-2]: When existing static resolution emits a call edge, it MUST remain the single authoritative edge and MUST NOT gain a duplicate CFA edge, while supported actual/formal and return/result constraints still participate.
- **FR-023** [US-2]: Stage 3 MUST remain a same-CMT, context-insensitive inclusion analysis and MUST NOT claim whole-program, AAM, closure-converted, defunctorized or full-OCaml equivalence.

#### Captures, partial callable values and output

- **FR-024** [US-3]: A supported capture MUST be an exact `Ident` read of a tracked immutable root, formal, local alias or application result lexically visible in the same CMT.
- **FR-025** [US-3]: Aggregate projection, mutable storage or fields, objects, modules, imports and cross-CMT values MUST retain callback uncertainty rather than a guessed capture target.
- **FR-026** [US-3]: The lambda allocation-site declaration MUST be the context-insensitive closure identity, and supported captured values from its evaluations MUST merge.
- **FR-027** [US-3]: A supported residual callable MUST have the finite identity `(underlying callable identity, consumed leading-slot count)` plus an independent reason set; aliases MUST preserve both and each further supported underapplication MUST advance the count monotonically at most to declared arity.
- **FR-028** [US-3]: An under-saturated candidate MUST NOT receive normal-return flow; on declared-arity saturation it MUST retain the underlying target and receive that callable's normal-return flow.
- **FR-029** [US-3]: Candidates with different known arities MUST saturate or remain residual independently at one occurrence; unknown arity or unsupported labels MUST preserve callback uncertainty.
- **FR-030** [US-3]: Arguments beyond saturation MUST retain the existing independent overapplication residual and MUST NOT be applied to a function-valued return in Stage 3.
- **FR-031** [US-3]: Each distinct Typedtree `Texp_apply` object MUST remain a distinct physical occurrence even at an equal source location, and each application stage MUST retain its own provenance rather than composed provenance.
- **FR-032** [US-3]: Every expanded row MUST copy the source occurrence's caller, call site, partiality, conditionality, deadness, exception scope, result scope and residual metadata exactly.
- **FR-033** [US-3]: Every newly resolved CFA target MUST be `MAY_ENUMERATED`, never `MUST`, and every independent unknown frontier MUST coexist with its known targets.
- **FR-034** [US-3]: Authentic compiled-CMT checks MUST cover arguments, returns, direct and mutual recursion, captures, staged residuals, saturation, mixed arity, occurrence identity, metadata and known-plus-unknown flow in both producer paths where applicable.
- **FR-035** [US-3]: The pinned 410-input replay MUST compare exact canonical row multisets and exact relation sets, report Irmin and protocol gains/losses separately, and reject every exact relation loss or new `MUST` row.
- **FR-036** [US-3]: A proposed Stage-3 correction requiring a pinned relation loss MUST bounce rather than weaken CHECK-3 within this task.
- **FR-037** [US-3]: CHECK-3 MUST report wall time and sampled RSS when available but MUST NOT claim a performance bound, semantic soundness/completeness or physical-occurrence proof from those measurements.
- **FR-038** [US-3]: Stage 3 MUST NOT add functor actual/member correspondence, independent compiled-variant reuse, broad query qualification or a storage migration.

## Acceptance Criteria

- AC-1 [US-1, C-1/C-2]: Every listed mutator after finalize rejects before effects; queries are identical; repeated finalize is idempotent; pre-finalize query rejects; injected finalization failure exposes no partial transition.
- AC-2 [US-1, C-3/C-4]: Callback and dropped-node values join and persist distinctly with same-kind deduplication, exhaustive mapping and an independent overapplication residual.
- AC-3 [US-1, C-5/C-6]: Root/local policy-equivalent syntax yields equal transfer, bottom stays bottom before invocation, invoked bottom becomes callback uncertainty, and all foundation fixture rows remain byte-identical.
- AC-4 [US-2 happy path]: A supported saturated `id f = f` call propagates a function target actual→formal→return→that physical application result.
- AC-5 [US-2, C-8/C-9]: Disjoint call-site values intentionally merge through shared formal/return cells and appear at each saturated physical result cell without merging occurrence metadata.
- AC-6 [US-2, C-7]: Unsupported cases/functions/parameters/groups/slots/results and cross-CMT sources retain callback uncertainty and never create a closed bounded result.
- AC-7 [US-2, C-10]: Direct and mutual recursive graphs reach identical finite closure under reordered/duplicated constraints, with no solver-time identity or cell allocation.
- AC-8 [US-2, C-11]: A statically resolved call keeps exactly one authoritative edge while its supported interprocedural value constraints still affect downstream application results.
- AC-9 [US-2, C-14/C-15/C-17]: Known-plus-unknown values traverse the declared bounded Shivers-style constraints without a whole-program, continuation, defunctorization or completeness claim.
- AC-10 [US-3, C-12]: Repeated evaluation of one lambda site merges exact supported captures by `Ident`; excluded capture sources retain an independent callback frontier.
- AC-11 [US-3, C-13]: Repeated supported underapplication yields only finite target/count residuals and no return flow until saturation; mixed arities advance independently.
- AC-12 [US-3, C-13/C-16]: Unknown arity/labels remain open; overapplication keeps the old residual and never feeds extras into a returned callable; no closure-layout or wrapper identity is persisted.
- AC-13 [US-3 happy path]: Distinct application objects and stages, including equal locations, expand independently with exact source metadata, only `MAY_ENUMERATED` targets and all applicable unknown fronts.
- AC-14 [US-3]: Main and flat authentic compiled fixtures demonstrate every Stage-3 flow and refusal without changing existing direct/static output semantics.
- AC-15 [US-3]: The pinned Tezos replay reports exact row deltas, separate Irmin/protocol relation deltas, zero relation losses and zero new `MUST`, plus non-normative wall/RSS observations.
- AC-16 [US-3]: No Stage-4 functor substitution, independent-variant reuse, broad query qualification or backend migration appears in the Stage-3 diff.

## Edge Cases

- EC-1 [US-1]: Post-finalize idempotent-looking mutation → reject before lookup/allocation.
- EC-2 [US-1]: Same semantic reason from several witnesses plus omitted-slot uncertainty → one semantic kind; structural residual remains independent.
- EC-3 [US-1]: Finalization fault after provisional seeds → no observable partial finalization.
- EC-4 [US-2]: A function is passed to and returned by itself → finite cyclic inclusion closure.
- EC-5 [US-2]: Two mutual functions exchange function-valued formals → shared fixed point, no unrolling.
- EC-6 [US-2]: Supported branch plus exceptional or unsupported result branch → known target plus callback frontier.
- EC-7 [US-2]: One unsupported member in a recursive group → the group is not admitted as closed transfer.
- EC-8 [US-2]: Direct resolved call returning a callable → one call edge, but a distinct application-result cell participates.
- EC-9 [US-3]: One lambda site captures different functions on different evaluations → context-insensitive union.
- EC-10 [US-3]: One candidate saturates while another remains partial → independent target-specific results.
- EC-11 [US-3]: Repeated partial application in a recursive cycle → residual keys remain bounded by target arity.
- EC-12 [US-3]: Distinct application objects share ghost location → distinct tokens and rows.
- EC-13 [US-3]: Saturated function returns a callable and receives extra actuals → extra application remains unknown in Stage 3.
- EC-14 [US-3]: Corpus would lose a relation after a conservative correction → Stage 3 bounces; gate is not weakened.

## Runnable Checks

All checkers use exit `0` for pass, `1` for a contract assertion failure, and
`>=2` for setup, compilation, timeout, malformed fixture or internal error.

- CHECK-1 [AC-1,AC-2,AC-3,AC-7]: `rtk proxy node roster/ocaml-cfa-propagation/check-domain.js` → independent finite-closure oracle plus lifecycle/reason/atomicity checks pass.
- CHECK-2 [AC-3,AC-4,AC-5,AC-6,AC-8,AC-9,AC-10,AC-11,AC-12,AC-13,AC-14,AC-16]: `rtk proxy node roster/ocaml-cfa-propagation/check-cmt.js` → authentic compiled main/flat fixtures and exact scope-preservation assertions pass.
- CHECK-3 [AC-15]: `rtk proxy node roster/ocaml-cfa-propagation/check-tezos.js` → pinned410 exact comparison passes with zero relation loss and zero new `MUST`.

## Claims Metadata

```claims
{"record":"claims-header","schema_version":1,"namespace":"ocaml-cfa-propagation","spec_lifecycle":"draft"}
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
{"record":"requirement","id":"FR-031","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-032","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-033","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-034","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-035","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-036","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-037","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-038","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"acceptance-criterion","id":"AC-1","for":["FR-001","FR-002","FR-003","FR-004"]}
{"record":"acceptance-criterion","id":"AC-2","for":["FR-005","FR-006"]}
{"record":"acceptance-criterion","id":"AC-3","for":["FR-007","FR-008","FR-009","FR-010"]}
{"record":"acceptance-criterion","id":"AC-4","for":["FR-011","FR-014","FR-015","FR-016","FR-017"]}
{"record":"acceptance-criterion","id":"AC-5","for":["FR-016","FR-018","FR-031","FR-032"]}
{"record":"acceptance-criterion","id":"AC-6","for":["FR-012","FR-013","FR-015","FR-020"]}
{"record":"acceptance-criterion","id":"AC-7","for":["FR-019","FR-021"]}
{"record":"acceptance-criterion","id":"AC-8","for":["FR-022"]}
{"record":"acceptance-criterion","id":"AC-9","for":["FR-020","FR-023"]}
{"record":"acceptance-criterion","id":"AC-10","for":["FR-024","FR-025","FR-026"]}
{"record":"acceptance-criterion","id":"AC-11","for":["FR-027","FR-028","FR-029"]}
{"record":"acceptance-criterion","id":"AC-12","for":["FR-025","FR-029","FR-030"]}
{"record":"acceptance-criterion","id":"AC-13","for":["FR-031","FR-032","FR-033"]}
{"record":"acceptance-criterion","id":"AC-14","for":["FR-010","FR-022","FR-034"]}
{"record":"acceptance-criterion","id":"AC-15","for":["FR-035","FR-036","FR-037"]}
{"record":"acceptance-criterion","id":"AC-16","for":["FR-038"]}
{"record":"check","id":"CHECK-1","for":["AC-1","AC-2","AC-3","AC-7"]}
{"record":"check","id":"CHECK-2","for":["AC-3","AC-4","AC-5","AC-6","AC-8","AC-9","AC-10","AC-11","AC-12","AC-13","AC-14","AC-16"]}
{"record":"check","id":"CHECK-3","for":["AC-15"]}
```

## Entities

These definitions extend the Stage-2 foundation entities for Stage 3. The
foundation spec remains the historical contract for its deliberately narrower
scope; this spec is canonical when a Stage-3 entity carries additional state.

- `CFAReason`: exhaustive Stage-3 semantic uncertainty kind (`Callback_param` or `Dropped_node`).
- `CFACell`: one preallocated node in the finite inclusion graph.
- `CFACallable`: one authenticated same-CMT function declaration or lambda allocation site.
- `CFAFormalCell`: context-insensitive value cell for one supported callable parameter.
- `CFAReturnCell`: context-insensitive normal-result cell for one supported callable.
- `CFAApplicationOccurrence`: one physical Typedtree application token with its own result cell and metadata.
- `CFAResidual`: finite partial-callable identity consisting of an underlying callable and consumed leading-slot count.
- `CFATransferPolicy`: root/local lookup and literal-authentication policy supplied to the shared expression dispatcher.
