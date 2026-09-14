---
name: roster-spec
type: spec
status: live
feature: Tezos structural open-body invocation resolution
brief: briefs/tezos-open-bodies-intake.md
date: 2026-09-14
version: 1.0.0
---

# Spec — Tezos structural open-body invocation resolution

## Clarifications

| Q | A |
|---|---|
| Which definitions are admitted? | Structural single-variable bindings with exactly one path-only open immediately containing a literal function; existing module/functor-definition traversal remains, and instances are excluded. |
| Which uses are admitted? | Same-CMT `Pident` application heads only; callback, letop, alias, qualified, local-let, and escape paths remain unchanged. |
| What identifies the target? | The actual existing root lambda, not its binding parent, together with the existing shadow-aware binding name. |
| How is collision ordinal determined? | The collector begins with a fresh marker table; the open is not peeled; `Tmod_ident` has no expression children; therefore the direct root literal is the first allocation and ordinal 1. The canonical formatter is shared with the existing allocator, later collisions are preserved, and native ghost-location and shadow controls validate the premise. |
| What happens when the body is missing? | The new path requires actual body registration or explicit refusal. Parent rejection makes the expected body unavailable. A known rejected body yields `dropped_node` TOP; descriptor or actual-name mismatch preserves `callback_param` TOP. No dangling enumerated leaf is created, and legacy missing-enum behavior is not changed globally. |
| How are partial and residual calls classified? | Inner syntactic arity and supplied `Some` expressions determine partiality. The admitted head remains enumerated. Each overapplied occurrence has exactly one independently evidenced unknown returned-call residual. |
| Which effects and flat facts may change? | None beyond the explicitly admitted target transition and permitted residual: existing callers, parent-to-lambda relations, CFG, effect ownership, and flat output remain unchanged. |

## User Stories

### US-1: Identify callable bodies (Priority: P0)

As a protocol callgraph consumer, I want direct invocations of supported wrapped bindings to identify the actual indexed body, so graph queries can follow that body rather than stopping at an avoidable unknown.

**Why this priority:** The fixed corpus contains181 unresolved applications of Raw.step; this is a concrete resolution gap, not a promised gain.

Scope: structural same-CMT `Pident` application heads for a single-variable binding whose expression is exactly one path-only open immediately containing a literal function. Callbacks, local lets, qualified members, nested or computed opens, instances, and general value analysis are excluded.

Independent test: index a compiled recursive wrapped-function fixture and query exact caller, site, target, and kind rows against independently extracted compiler identities.

1. **Given** `let open M in fun x -> step x` and another caller, **when** both admitted application sites are indexed, **then** both target the actual synthetic `step` root body as `MAY_ENUMERATED`, produce no new `MUST`, and retain their pre-existing caller names and sites.
2. **Given** a two-parameter wrapped body, an omitted labeled slot, and an overapplication, **when** the calls are indexed, **then** supplied `Some` count determines partial metadata and exactly one unknown returned-call residual occurs only for each overapplied occurrence.
3. **Given** shadowed structural binders and ghost or same-location nested literals, **when** admitted calls are indexed, **then** each reaches its exact canonical root-body identity or is refused, never a later shadow, nested closure, or homonym.

### US-2: Preserve honest boundaries (Priority: P0)

As an index consumer, I want unsupported or missing-body cases and existing facts preserved, so improved resolution cannot misattribute calls or manufacture certainty.

**Why this priority:** A new target is useful only if existing graph and effect facts remain trustworthy.

Scope: preservation of existing refusal classifications, canonical call rows, rich facts, relations, effects, ownership, CFG, and flat output. Global enum fallback changes and new flat features are excluded.

Independent test: index refusal and rejection fixtures and compare unchanged rich and flat facts with the pinned predecessor independently of positive target assertions.

1. **Given** parameter, local-let, nested or computed-open, callback, letop, alias, qualified, and escaped-value occurrences, **when** they are indexed, **then** their previous rows and refusal reasons remain unchanged.
2. **Given** an admitted definition whose parent or synthetic body is rejected, **when** another caller invokes it, **then** the site remains TOP with `dropped_node`, not an external or dangling enumerated leaf or an unrelated homonym.
3. **Given** unchanged fixed410 inputs, **when** candidate and predecessor are compared, **then** every changed invocation has independent native identity, site, body, and multiplicity evidence; no old relation, point-free fact, caller, CFG, effect-ownership, rich, or flat fact is lost; and tampered, reused, wrong-body, or ambiguous witnesses refuse.

## Challenges

| ID | Story | Challenge | Resolution |
|---|---|---|---|
| C-1 | US-1 | Descriptor versus real persisted body | Success requires a uniquely corresponding promoted root body and successful same-CMT storage. Prepass membership alone never authorizes a resolved edge. Parent or lambda rejection yields `dropped_node` TOP. |
| C-2 | US-1 | Ordinal 1 depends on traversal | Collector markers start empty; a path module contributes no expression child; the root function is allocated before its defaults or body. Those events are preserved and use the canonical formatter. Ghost or same-location nested functions cannot substitute for the root; premise or name mismatch refuses. |
| C-3 | US-1 | Shadow or homonym identity | Match exact same-CMT compiler `Ident`, retain its existing `binding_name`, and require a unique actual root-body identity. Bare-name, suffix, source-line-only, and homonym fallback are forbidden. |
| C-4 | US-1 | `exp_extra` ambiguity | Preserve compiler extras as-is. Constraint, coercion, and newtype extras are eligible only when the exact descriptor shape remains unchanged; expression or module constructors are not stripped. |
| C-5 | US-1 | Arity composition | Apply existing function-arity semantics to the inner literal: leading parameters plus a terminal function-cases argument. Set `partial` when the result remains an arrow or supplied `Some` count is below arity. Unrelated heads and parameter traversal remain unchanged. |
| C-6 | US-1 | Residual multiplicity | Retain or emit exactly one unknown returned-call residual per admitted overapplied syntactic head occurrence, not per surplus argument or deduplicated relation. An existing compatible residual is retained rather than duplicated. Native evidence binds arity, supplied count, and occurrence. |
| C-7 | US-1 | Complete new-target partition | Supported, unique, stored matching body becomes `MAY_ENUMERATED`; known parent or body storage rejection becomes `MAY_TOP/dropped_node`; failed identity, name, uniqueness, or availability without recorded rejection preserves original `callback_param` TOP. No dangling enum leaf or new `MUST` is permitted. |
| C-8 | US-2 | Refusal precedence | Unsupported shapes never enter the mechanism and preserve legacy behavior and rejection precedence. For supported candidates, known storage rejection outranks descriptor mismatch; otherwise mismatch or unknown availability preserves `callback_param` TOP. |
| C-9 | US-2 | Preservation universe | The fixed410 canonical call-row multiset outside explicitly witnessed transitions and residuals remains unchanged. Paired fixture snapshots retain functions, callers, positions, lambdas, CFG conditional/dead facts, exception/value scopes, carriers, origins, and ownership, modulo storage surrogate-ID renaming only. |
| C-10 | US-2 | Flat equality | Compare complete `call_row` multisets with duplicate counts: caller and callee names, caller and callee files, call site, and edge form. Only iteration order is ignored. Unsupported and unrelated homonym rows are included, and no synthetic callee spelling is added. |
| C-11 | US-2 | Position-free canonical rows versus occurrences | A witness contains artifact hash, caller and body identities and ranges, head-expression offsets, exact binder, and a unique native traversal occurrence identity, and is consumed once. If line-granularity rows cannot distinguish candidates, admission requires all corresponding native occurrences to agree on target and classification with exact multiplicity; otherwise the ambiguous group refuses. A witness cannot justify another duplicate or be reused. |
| C-12 | US-2 | Replacing TOP versus relation loss | `ResolutionRelation` counts only non-null internal targets and excludes `value_alias`. An exactly witnessed target-null TOP may be replaced; no previously resolved relation may be deleted. Every removed or added canonical row requires matched witness capacity, without blanket exemptions. |
| C-13 | US-2 | Generalized opens can have effects | Every non-`Tmod_ident` open is refused by the new mechanism. Effectful module application, structure, and unpack controls preserve module-expression calls, CFG, scopes, origins, effects, ownership, and flat rows. |
| C-14 | US-2 | Parameter effects | Parameter peeling, default traversal, and parameter/case effect ordering remain unchanged. Optional/default and refutable-parameter fixtures compare exact owner, scope, CFG, and effect facts for partial and full uses. New edges remain `MAY_ENUMERATED` and make no claim that parameter effects executed. |
| C-15 | US-1 | Omitted slots | New-head partiality and overapplication use supplied `Some` count, never argument-list length. Paired omitted-label and fully supplied controls distinguish them, while legacy counting for other heads remains unchanged. |

## Functional Requirements

#### US-1 — Identify callable bodies

- **FR-001** [US-1]: When a same-CMT `Pident` application head refers to an admitted structural binding whose promoted root body is uniquely matched and successfully stored, the index MUST classify the call as `MAY_ENUMERATED` and target the actual root body.
- **FR-002** [US-1]: The index MUST NOT emit a new `MUST` edge for an admitted wrapped binding.
- **FR-003** [US-1]: The index MUST preserve the pre-existing caller identity and call site when resolving an admitted wrapped binding.
- **FR-004** [US-1]: The index MUST match an admitted binding by its exact same-CMT compiler `Ident`, existing shadow-aware `binding_name`, and unique actual root-body identity; it MUST NOT fall back to a bare name, suffix, source line, homonym, later shadow, or nested closure.
- **FR-005** [US-1]: For an admitted path-only open directly containing a literal function, the index MUST associate the binding with the root literal's canonical first allocation; it MUST refuse resolution when the ordinal premise or canonical actual name does not match.
- **FR-006** [US-1]: Ghost locations or shared locations MUST NOT permit a nested function, shadow, or homonym to substitute for the admitted root literal.
- **FR-007** [US-1]: The index MUST preserve compiler `exp_extra` values as-is and MUST admit constraint, coercion, or newtype extras only when the exact admitted descriptor shape remains unchanged; it MUST NOT strip expression or module constructors to create eligibility.
- **FR-008** [US-1]: The index MUST derive syntactic arity from the inner literal using the existing function-arity contract, including leading parameters and a terminal function-cases argument.
- **FR-009** [US-1]: The index MUST count only supplied `Some` arguments when determining partiality and overapplication; omitted labeled slots MUST NOT count as supplied arguments.
- **FR-010** [US-1]: The index MUST set the admitted call's partial flag when the result remains an arrow or the supplied-argument count is below syntactic arity.
- **FR-011** [US-1]: For each admitted overapplied syntactic head occurrence, the index MUST retain or emit exactly one independently evidenced unknown returned-call residual, regardless of the number of surplus arguments.
- **FR-012** [US-1]: The index MUST NOT duplicate an already compatible returned-call residual or deduplicate residuals belonging to distinct admitted head occurrences.
- **FR-013** [US-1]: Parameter peeling, default-expression traversal, parameter traversal, and parameter/case effect ordering MUST remain observably unchanged for admitted bindings.
- **FR-014** [US-1]: Resolution of an admitted edge MUST NOT assert that parameter or default effects executed.

#### US-2 — Preserve honest boundaries

- **FR-015** [US-2]: Callback, letop, alias, qualified, local-let, escaped-value, nested-open, computed-open, module-instance, and other unsupported occurrences MUST remain outside the new resolution mechanism and preserve their previous rows and refusal behavior.
- **FR-016** [US-2]: A non-`Tmod_ident` open MUST NOT be admitted, and its module-expression calls, CFG, scopes, origins, ownership, effects, and flat rows MUST remain unchanged.
- **FR-017** [US-2]: An admitted occurrence MUST become `MAY_ENUMERATED` only when its promoted root body is uniquely matched and successfully stored in the same CMT.
- **FR-018** [US-2]: When the binding parent or promoted root body has a known storage rejection, the admitted occurrence MUST remain `MAY_TOP` with refusal reason `dropped_node`, and MUST NOT become an external or dangling enumerated leaf.
- **FR-019** [US-2]: For a supported candidate without a recorded storage rejection, an identity, canonical-name, uniqueness, or body-availability mismatch MUST preserve the original `callback_param` TOP classification.
- **FR-020** [US-2]: For a supported candidate, known parent or body rejection MUST take precedence over descriptor mismatch; unsupported shapes MUST preserve legacy rejection precedence.
- **FR-021** [US-2]: The new path MUST NOT change legacy missing-enum behavior outside admitted candidates.
- **FR-022** [US-2]: Outside independently witnessed target transitions and returned-call residuals, the fixed410 canonical call-row multiset MUST remain unchanged.
- **FR-023** [US-2]: Paired rich-fixture results MUST preserve functions, callers, positions, lambdas, parent-to-lambda relations, CFG conditional/dead facts, exception/value scopes, carriers, origins, effect ownership, and other existing facts, except for storage surrogate-ID renaming.
- **FR-024** [US-2]: Paired flat output MUST preserve the complete `call_row` multiset, including duplicate counts, caller and callee names and files, call site, and edge form; only iteration order MAY differ.
- **FR-025** [US-2]: Flat comparisons MUST include unsupported occurrences and unrelated homonyms, and the candidate MUST NOT add synthetic callee spelling.
- **FR-026** [US-2]: Every accepted transition MUST have an independent witness binding the artifact hash, exact binder, caller and body identities and ranges, head-expression offsets, native traversal occurrence identity, arity, supplied count, target and classification, and multiplicity.
- **FR-027** [US-2]: Each native witness MUST be consumed at most once and MUST NOT justify a different duplicate occurrence.
- **FR-028** [US-2]: When line-granularity stored rows cannot distinguish native candidates, the comparator MUST accept the group only if every corresponding native occurrence agrees on target and classification and exact multiplicity is discharged; otherwise it MUST refuse the entire ambiguous group.
- **FR-029** [US-2]: Replacing an exactly witnessed target-null TOP row MAY occur, but the candidate MUST NOT delete any previously resolved non-null internal relation.
- **FR-030** [US-2]: Every removed or added canonical row MUST be matched to witness capacity; no blanket transition exemption is permitted.
- **FR-031** [US-2]: Tampered, reused, wrong-body, mismatched, ambiguous, or insufficient-capacity witnesses MUST be refused.
- **FR-032** [US-2]: Existing callers, parent-to-lambda relations, CFG, effect ownership, and flat-output contracts MUST remain unchanged except for explicitly witnessed admitted call-target transitions and their permitted residuals.
- **FR-033** [US-2]: Baseline verification MUST use a distinct pinned baseline and neutral replay, MUST refuse an input or replay mismatch, and MUST NOT overwrite the pinned baseline while checking it.
- **FR-034** [US-2]: The exact self-smoke and full guard policy MUST remain unchanged, and an exact-reference refresh MUST NOT be accepted until source-only attribution succeeds.

## Acceptance Criteria

- **AC-1** [US-1 happy path]: Two admitted same-CMT calls to `let open M in fun x -> step x` retain their callers and sites, target the actual synthetic root body as `MAY_ENUMERATED`, and add no `MUST`.
- **AC-2** [US-2 happy path]: Unsupported and missing-body fixtures retain honest TOP or refusal outcomes and all unaffected rich, relation, effect, CFG, ownership, and flat facts.
- **AC-3** [US-1, C-2, C-3, C-4]: Shadowed, constrained, ghost-location, and same-location fixtures resolve only the exact canonical root body; ordinal, name, identity, uniqueness, or shape ambiguity refuses rather than selecting a shadow, nested closure, or homonym.
- **AC-4** [US-1, C-5, C-6, C-15]: Partial, fully supplied, omitted-label, and overapplied fixtures use supplied-`Some` count and inner syntactic arity, set partial metadata correctly, and yield exactly one residual per overapplied occurrence only.
- **AC-5** [US-1, C-14]: Optional/default and refutable-parameter fixtures preserve parameter traversal, ordering, CFG, scope, and effect ownership for partial and full uses; admitted edges remain `MAY_ENUMERATED` without asserting runtime effect execution.
- **AC-6** [US-2, C-1, C-7, C-8]: Supported candidates partition as unique and stored to `MAY_ENUMERATED`, known parent or body rejection to `MAY_TOP/dropped_node`, and unmatched or unavailable without recorded rejection to original `callback_param` TOP, with no dangling enum leaf.
- **AC-7** [US-2, C-8, C-13]: Unsupported and non-path or effectful opens never enter admission and preserve their prior calls, refusal precedence, CFG, scopes, origins, effects, ownership, and flat rows.
- **AC-8** [US-2, C-9, C-10]: CHECK-1 paired fixtures preserve complete rich facts, relations, effects, ownership, and duplicate-sensitive flat `call_row` multisets outside the admitted transitions and permitted residuals.
- **AC-9** [US-2, C-11]: A witness is accepted only for its exact native occurrence and capacity; reuse is rejected, and indistinguishable stored-row groups refuse unless every native occurrence agrees and exact multiplicity is discharged.
- **AC-10** [US-2, C-12]: Only exactly witnessed target-null TOP rows may be replaced; no pre-existing resolved non-null internal relation is deleted, and every canonical addition or removal is capacity-matched.
- **AC-11** [US-2, C-11, C-12]: Tampered, wrong-body, mismatched, reused, insufficient-capacity, or native-occurrence-ambiguous witnesses refuse without authorizing unrelated transitions.
- **AC-12** [US-2]: A distinct pinned baseline accepts its neutral replay, rejects mismatch, and remains byte-for-byte unmodified by the check.
- **AC-13** [US-2]: Exact self-smoke and the full guard retain their existing policy, and exact-reference refresh is refused unless source-only attribution succeeds first.

## Edge Cases

- **EC-1** [US-1, C-2, C-3]: A shadowed binder with a ghost or same-location nested literal resolves to the exact admitted root body; ambiguous correspondence refuses and never selects the nested function or homonym.
- **EC-2** [US-1, C-5, C-6, C-15]: An omitted labeled slot and a full overapplication use actual supplied count, set the partial flag accordingly, and yield one residual only for each overapplied occurrence.
- **EC-3** [US-2, C-1, C-7, C-8]: A rejected parent with a homonymous stored body leaves the supported invocation at `dropped_node` TOP without homonym fallback.
- **EC-4** [US-2, C-9, C-13, C-14]: A computed or effectful open retains its original rows, CFG, scopes, origins, effects, ownership, and flat output, with no new admission.
- **EC-5** [US-2, C-11, C-12]: Identical canonical rows backed by different native candidates refuse unless the complete native group agrees and exact multiplicity is discharged once.

## Runnable Checks

All commands use exit 0 for pass, exit 1 for an assertion failure, and exit 2 or greater for setup or execution error. The statuses below preserve the specification-time obligations. Execution update (2026-09-14): main personally ran CHECK-1, CHECK-2, CHECK-3 with replay, and CHECK-4 successfully after implementation and the attributed reference refresh. Full candidate guard passed 336/336; CHECK-5 then passed on source commit a5ae981. See roster/tezos-open-bodies/implementation-validation.md. No review, QA or delivery verdict is implied.

- **CHECK-1** [AC-1, AC-2, AC-3, AC-4, AC-5, AC-6, AC-7, AC-8]: `node roster/tezos-open-bodies/check-native.js` → exact native target, refusal, arity, shadow, ghost, drop, rich, relation, effects, ownership, CFG, and flat paired-fixture assertions pass. **Status: required implementation; not passed.**
- **CHECK-2** [AC-9, AC-10, AC-11]: `node roster/tezos-open-bodies/check-witness-inputs.js` → comparator and witness-admission positive controls pass and tampered, reused, wrong-body, mismatch, insufficient-capacity, and ambiguous-occurrence negative controls refuse. **Status: required implementation; not passed.**
- **CHECK-3** [AC-12]: `node roster/tezos-open-bodies/check-baseline.js --replay` → distinct pinned baseline, neutral replay, mismatch refusal, and no-overwrite assertions pass. **Status: implemented preparation gate; exact run results in baseline-preparation.md, no candidate gain.**
- **CHECK-4** [AC-8, AC-10, AC-11]: `node roster/tezos-open-bodies/verify.js --witness improvement/2026-09-14-tezos-resolution/attempt3-reviewed-witness.json` → fixed410 candidate changes are exactly witnessed and all unwitnessed canonical rows and relations are preserved. **Status: required candidate comparison; not passed.**
- **CHECK-5** [AC-13]: `node roster/tezos-open-bodies/check-self.js` → exact self-smoke, full guard policy, pristine attribution, and source-only-before-reference-refresh assertions pass. **Status: required implementation; not passed.**

## Traceability

| Requirement | Acceptance criteria |
|---|---|
| FR-001–FR-003 | AC-1 |
| FR-004–FR-007 | AC-3 |
| FR-008–FR-012 | AC-4 |
| FR-013–FR-014 | AC-5 |
| FR-015–FR-016 | AC-2, AC-7 |
| FR-017–FR-021 | AC-2, AC-6 |
| FR-022–FR-025 | AC-2, AC-8 |
| FR-026–FR-028 | AC-9, AC-11 |
| FR-029–FR-030 | AC-10 |
| FR-031 | AC-11 |
| FR-032 | AC-2, AC-5, AC-7, AC-8 |
| FR-033 | AC-12 |
| FR-034 | AC-13 |

| Acceptance criterion | Runnable checks |
|---|---|
| AC-1–AC-7 | CHECK-1 |
| AC-8 | CHECK-1, CHECK-4 |
| AC-9 | CHECK-2 |
| AC-10–AC-11 | CHECK-2, CHECK-4 |
| AC-12 | CHECK-3 |
| AC-13 | CHECK-5 |

## Claims Metadata

Metadata remains draft: the canonical claims validator/projector is not installed;
no formal validation or generated projection is claimed. This spec's routine
validation uses the user's explicit autonomous roster-gate delegation. No quiz
answers or individual human review of the following clauses are fabricated.

```claims
{"record":"claims-header","schema_version":1,"namespace":"tezos-open-bodies","spec_lifecycle":"draft"}
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
{"record":"acceptance-criterion","id":"AC-1","for":["FR-001","FR-002","FR-003"]}
{"record":"acceptance-criterion","id":"AC-2","for":["FR-015","FR-017","FR-018","FR-019","FR-020","FR-021","FR-022","FR-023","FR-024","FR-032"]}
{"record":"acceptance-criterion","id":"AC-3","for":["FR-004","FR-005","FR-006","FR-007"]}
{"record":"acceptance-criterion","id":"AC-4","for":["FR-008","FR-009","FR-010","FR-011","FR-012"]}
{"record":"acceptance-criterion","id":"AC-5","for":["FR-013","FR-014","FR-032"]}
{"record":"acceptance-criterion","id":"AC-6","for":["FR-017","FR-018","FR-019","FR-020","FR-021"]}
{"record":"acceptance-criterion","id":"AC-7","for":["FR-015","FR-016","FR-032"]}
{"record":"acceptance-criterion","id":"AC-8","for":["FR-022","FR-023","FR-024","FR-025","FR-032"]}
{"record":"acceptance-criterion","id":"AC-9","for":["FR-026","FR-027","FR-028"]}
{"record":"acceptance-criterion","id":"AC-10","for":["FR-029","FR-030"]}
{"record":"acceptance-criterion","id":"AC-11","for":["FR-026","FR-027","FR-028","FR-031"]}
{"record":"acceptance-criterion","id":"AC-12","for":["FR-033"]}
{"record":"acceptance-criterion","id":"AC-13","for":["FR-034"]}
{"record":"check","id":"CHECK-1","for":["AC-1","AC-2","AC-3","AC-4","AC-5","AC-6","AC-7","AC-8"]}
{"record":"check","id":"CHECK-2","for":["AC-9","AC-10","AC-11"]}
{"record":"check","id":"CHECK-3","for":["AC-12"]}
{"record":"check","id":"CHECK-4","for":["AC-8","AC-10","AC-11"]}
{"record":"check","id":"CHECK-5","for":["AC-13"]}
```

## Entities

- `ResolutionRelation`: one canonical caller/source-line/internal-target tuple; not a unique syntactic expression.
- `ResolutionRowMultiset`: canonical stored call facts with multiplicity, excluding database surrogate IDs from identity.
- `OpenBodyInvocation`: a same-CMT `Pident` application occurrence whose structural single-variable binding is exactly one path-only open immediately containing a literal function and whose target candidate is that literal's actual root body.
