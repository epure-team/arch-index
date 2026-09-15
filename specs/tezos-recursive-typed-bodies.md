---
name: roster-spec
type: spec
status: live
feature: Exact singleton recursive path-open invocation targets
brief: briefs/tezos-recursive-typed-bodies-intake.md
date: 2026-09-15
version: 1.0.0
---

# Spec — exact singleton recursive path-open invocation targets

Fifth and final attempt of the existing five-iteration loop. This version extends
only the single path-open constructor exclusion in historical tezos-local-recursion
FR-002/AC-7. Historical contracts/checkers are not rewritten. No0CFA or general
functor interpretation is claimed. Fresh Sol/Terra research, clarification,
adversarial and formalization inputs are recorded in spec-input.md. Standing
explicit user autonomy governs routine gates; no quiz answer or formal proof is
invented. The initial unsealed baseline was invalidated; only sealed v2 qualifies.

## Clarifications

| Q | A |
|---|---|
| Which shape? | Exactly one Texp_open(Tmod_ident, direct Texp_function), singleton Recursive Texp_let and Tpat_var. |
| Which expression identity? | Original inner function object, never wrapper or copy; exact active Ident.same self-head. |
| Ordinary binding tables? | No additions for the new shape, neither binding_literals nor local_lam_stamps. |
| Availability? | Actual collision-qualified name, one physical observation and successful storage; otherwise TOP. |
| Arity? | Existing inner fn_arity; supplied Some slots; result-arrow partiality and prior residual rule. |
| Preserved paths? | Parent occurrence, continuation, non-head uses, public flat, ownership/CFG/effects/channels unchanged. |
| Annotations? | exp_extra is distinct from the expression descriptor and is not peeled. |
| Open material question? | None within the contractual boundary. |


## User Stories

### US-1: Follow an exact local open-recursive self-call (Priority: P0)

As a Tezos graph reader, I want an admissible recursive invocation to reach its
actual stored function body without implying definite execution.
Priority: observed protocol self-heads are unresolved. Scope excludes general
wrapper/alias/value-flow, mutual recursion and continuation resolution.
Independent test: compile/index a native one-open singleton and inspect the
stored caller/callee rows and kind.

1. Given `module M = struct end` and an outer function containing
   `let rec aux = let open M in fun x -> if x=0 then 0 else aux (x-1) in aux n`,
   when indexed, the self-head targets the one physically observed stored root
   as MAY_ENUMERATED; the continuation and prior parent occurrence are unchanged.
2. Given a nested lambda invokes that same binder and a sibling lambda shadows
   it, when indexed, only exact binder occurrences refine and each call retains
   its own caller, conditional/dead flags, scopes, channels and effects.
3. Given optional/partial applications and a returned-function overapplication,
   when indexed, existing inner syntactic arity and supplied Some arguments govern
   partiality and one returned-call residual; old hidden-arrow residuals survive.
4. Given actual SQL root rejection or duplicate source positions, when indexed,
   a target requires unique physical observation and real storage; dropped root
   is dropped_node TOP, other ambiguity is callback_param TOP.

### US-2: Independently verify refinement and preservation (Priority: P0)

As a maintainer, I want counted native witnesses and preserved predecessor facts
so that a gain cannot hide wrong targets or regressions.
Priority: measured trustworthy improvement is the loop's retention condition.
Scope excludes corpus changes, old-checker edits and threshold relaxation.
Independent test: copied-binary neutral replay and malformed/capacity witness
controls pass without requiring a product change.

1. Given direct recursion, mutual groups, alias patterns, nested opens, computed
   module opens/RHSs, continuations and non-head uses, when paired against PR108,
   all unadmitted facts including parent occurrences remain identical in count.
2. Given nonempty configured exception/channel/effect and shape fixtures, when
   comparing native pending/stored/flat outputs, all non-resolution metadata and
   full public flat multisets remain identical, including duplicate rows.
3. Given frozen PR108 producer/schema and the pinned410 manifest, when replaying,
   all45052 rows, digest082bdce92c6cab7b654f87a90db59ca9979d7004f45a42997a33718f6cd7c67a
   and4849/12157 relations reproduce; altered inputs or overwritten baseline fail.
4. Given candidate deltas, wrong binder/root/ordinal/caller/range or reused native
   capacity, when verified, mismatches refuse; only positive independently
   witnessed gain with zero relation loss/unexplained change/new MUST plus full
   roster/guard and exact-head green CI may be retained and merged.


## Challenges

| ID | Story | Challenge | Resolution |
|---|---|---|---|
| C-1 | US-1 | Candidate certifies its own root | Compiler-only independent observation reconstructs binder/root/caller/ordinal; candidate DB checks storage correspondence only. |
| C-2 | US-1 | Original inner body versus copied equivalent | Original immediate inner expression object is mandatory; physical traversal observation, no copy or outer-wrapper substitution. |
| C-3 | US-1 | Which module path forms? | Admission checks exactly Tmod_ident, as the existing structural-open rule does. All paths carried by that constructor are accepted; no path interpretation/substitution is performed. Tmod_apply/unpack/constraint and other module-expression constructors refuse. |
| C-4 | US-1 | Homonyms and shadow-binding RHS | Native Ident.same decides occurrences, including references to outer binder while walking an inner nonrecursive RHS; printed names never decide. |
| C-5 | US-1 | Parent row count hides retargeting | Full counted canonical and rich pending metadata multisets preserve every parent occurrence, not just totals. |
| C-6 | US-1 | Arity boundaries and omitted slots | Let a=inner fn_arity and n=countSome. partial iff result-arrow or n<a. At n=a no syntactic residual; at n>a one. None slots do not increase n. |
| C-7 | US-1 | Legacy and new residual double-count | Existing OR rule emits at most one residual per application, whether syntactic or legacy predicate or both. Existing residuals remain; only independently justified new residuals use addition capacity. |
| C-8 | US-1 | Partition missing/wrong/dropped storage | Known rejected named root is dropped_node; missing name, unobserved/multiply observed root or unavailable unconfirmed correspondence is callback_param. Wrong root cannot justify a bounded target. Same-position other objects are not matches. |
| C-9 | US-2 | Duplicate pairing and ordinals | Compare complete counted canonical tuples, excluding DB surrogate IDs; native full ranges and actual ordinals supply candidate permissions. Preserve rich/flat multisets separately. |
| C-10 | US-2 | Balanced ordinary-table leaks | Assert exact continuation/escape/parent outputs against predecessor with native witnesses plus inspect that existing mask/table insertion branches remain unchanged; no aggregate-only check. |
| C-11 | US-2 | Nonempty elsewhere but selected call empty | Positive fixtures must include refined calls with real exception/channel scopes and contexts with nonzero effects; explicit presence assertions precede comparison, alongside full nonempty shape families. |
| C-12 | US-2 | Rich changes versus identical flat | Public flat collector does not enable private recursive descriptors. Entire flat output remains identical, not merely selected columns. |
| C-13 | US-2 | Stale candidate output | Run actual current producer from recorded build; hash source, producer, schema and all inputs before/after; forbid substituting baseline output. |
| C-14 | US-2 | Witness independence undefined | No SQL-derived identity/shape/arity/allocation facts. Native compiler-only probe observes full410 before canonical pair approval. Candidate storage is a separate predicate. |
| C-15 | US-2 | Duplicate/mixed evidence reuse | Each native application supplies one head capacity and at most one residual capacity; complete indistinguishable groups must agree; each capacity consumed at most once. |
| C-16 | US-2 | Which positivity metric? | Distinct ordinary caller/source-line/internal-target relation gain on fixed410; exclude value_alias, require zero old relation losses.14heads are not14promised gains. |
| C-17 | US-2 | Exact head versus verification provenance | Content hashes bind source/test/checker and binaries across local checks. Final checked PR SHA and required CI head must agree; docs-only commits need explicit unchanged-code evidence, not assumed equivalence. Guarded merge uses exact head. |
| C-18 | US-1 | Prior art does not certify every module path | No module path is used as target evidence: original literal-body identity determines the target. Tmod_ident is a syntax boundary, not a claim about module contents or instantiated functors. |
| C-19 | US-2 | Location/UID treated as physical identity | Native physical root and same-artifact Ident.same are required. Locations/UIDs are supporting audit fields; never global uniqueness assertions. |

All19 challenges are resolved from the intake, actual compiler observation and
existing contracts; no material scope expansion or new human question required.
EC coverage: exact positive; nested/shadow RHS; parent duplicates; arity−1/a/a+1
with None slots; rejected body; Tmod_ident versus computed module; equal-location
distinct roots; wrong ordinal; overlapping residual predicates; mixed groups.


## Functional Requirements

- FR-001 [US-1]: On a local singleton Recursive Texp_let with Tpat_var, the indexer MUST admit the new RHS shape only when it is exactly one Texp_open(Tmod_ident, immediate Texp_function).
- FR-002 [US-1]: The new admission MUST NOT include mutual/nonrecursive bindings, alias/tuple patterns, multiple opens, indirect RHSs or other module-expression constructors.
- FR-003 [US-1]: Every path carried by Tmod_ident MUST be treated uniformly as syntax, never interpreted or used as module-content/target evidence.
- FR-004 [US-1]: The target MUST identify the original immediate inner function expression object, never the outer open, a copy or a same-position substitute.
- FR-005 [US-1]: Self-heads MUST match the active same-artifact binder by Ident.same; names, locations and UIDs alone MUST NOT establish identity.
- FR-006 [US-1]: The active RHS scope MUST preserve outer-binder references in inner nonrecursive RHSs and exclude distinct shadowing binders and the outer let continuation.
- FR-007 [US-1]: A bounded self-target MUST have exactly one physical observation, its actual allocated collision-qualified name and successful intended-body storage.
- FR-008 [US-1]: Known named storage rejection MUST yield MAY_TOP/dropped_node; missing, ambiguous or unconfirmed correspondence MUST yield MAY_TOP/callback_param.
- FR-009 [US-1]: Equal locations or UIDs on distinct objects MUST NOT establish physical-root or storage correspondence.
- FR-010 [US-1]: For inner syntactic arity a and supplied count n=count(Some), partial MUST equal result-type-arrow OR n<a; omitted None slots MUST NOT increase n.
- FR-011 [US-1]: The syntactic returned-call rule MUST add exactly one residual when a>0 and n>a, and none otherwise.
- FR-012 [US-1]: Syntactic and legacy residual predicates MUST combine by the existing OR rule, yielding at most one residual per application and preserving every predecessor residual.
- FR-013 [US-1]: The private descriptor MUST affect invocation heads only, with no new binding_literals/local_lam_stamps entries for open-wrapped binders and no public flat activation.
- FR-014 [US-1]: The change MUST preserve every prior parent occurrence, continuation, escape/non-head use, traversal/name/caller/ownership, CFG, dead/conditional, scope/channel/exception/effect and non-resolution fact.
- FR-015 [US-1]: Expression extras MUST remain metadata distinct from descriptor admission; no annotation or other constructor peeling is permitted.
- FR-016 [US-2]: The verifier MUST derive binder/group/shape, original body/root/ordinal, caller, full application range and arity from independent compiler-only native observation.
- FR-017 [US-2]: Candidate SQL MUST check successful storage correspondence separately and MUST NOT supply native identity, shape, arity or allocation facts.
- FR-018 [US-2]: Canonical comparison MUST use complete counted tuples without DB surrogate IDs and refuse wrong binder/root/ordinal/caller/range correspondence.
- FR-019 [US-2]: Verification MUST preserve complete rich non-resolution and unadmitted pending facts, all non-call shape families and complete public flat multisets, including duplicates.
- FR-020 [US-2]: Native continuation, escape, non-head and parent controls plus unchanged mask/table insertion boundaries MUST expose ordinary-lookup leakage; aggregate equality is insufficient.
- FR-021 [US-2]: Preservation checks MUST assert refined fixture calls with real exception/channel scope coverage, contexts with nonzero effects and nonempty relevant shape families before comparing them.
- FR-022 [US-2]: Each native application MUST supply one head capacity and at most one residual capacity, each single-use, with complete indistinguishable groups agreeing.
- FR-023 [US-2]: The verifier MUST refuse incomplete, excess, mixed or reused occurrence evidence before accepting a candidate delta.
- FR-024 [US-2]: The metric MUST count distinct ordinary caller/source-line/internal-target relation gains on the pinned410 corpus, exclude value_alias and require zero prior relation losses.
- FR-025 [US-2]: The observed14 self-heads MUST remain candidate capacity, never a promised distinct-relation gain.
- FR-026 [US-2]: Frozen PR108 replay MUST reproduce45052 canonical rows, digest082bdce92c6cab7b654f87a90db59ca9979d7004f45a42997a33718f6cd7c67a and Irmin4849/protocol12157.
- FR-027 [US-2]: Baseline verification MUST reject altered pins/inputs or overwrite, use a self-contained sealed DB with no WAL/SHM, preserve all SQL data across sealing and verify ordinary-SELECT byte stability on a disposable copy.
- FR-028 [US-2]: Each run MUST hash source/tests/checkers, actual producer/schema and all inputs before/after, record candidate provenance and refuse stale or changed evidence.
- FR-029 [US-2]: Required checks MUST distinguish0 pass,1 semantic assertion and2+ setup/input/runtime failure; tool failure MUST NOT be called authentic RED.
- FR-030 [US-2]: Retention MUST require positive independently witnessed gain, no old relation loss/unexplained changes/new MUST and complete scope/schema/public API/self-policy/build/test/review/QA/CI gates; neutral complexity is discarded.
- FR-031 [US-2]: Required CI and guarded merge MUST use the final exact PR head; local evidence reuse for documentation-only successors requires demonstrated content identity and MUST NOT waive exact-head CI.

## Acceptance Criteria

- AC-1 [US-1]: Happy path: exact singleton path-open native fixture reaches its stored inner root as MAY_ENUMERATED while prior parent and continuation facts remain unchanged.
- AC-2 [US-2]: Happy path: unchanged producer replay and unsupported/native tampering controls independently verify preservation and refusal without requiring a product gain.
- AC-3 [US-1]: C-1: candidate root claims require independently reconstructed compiler root/caller/ordinal and separate storage confirmation.
- AC-4 [US-1]: C-2: outer/copy/same-position alternatives do not certify the original physical inner body.
- AC-5 [US-1]: C-3: Tmod_ident paths are syntax-only; computed/non-ident module expressions, nested opens and other excluded forms refuse.
- AC-6 [US-1]: C-4: nested calls and inner nonrecursive RHSs use exact active binder identity; distinct homonyms do not refine.
- AC-7 [US-1]: C-5: parent occurrences retain complete counted facts, so balanced retargeting/deletion is detected.
- AC-8 [US-1]: C-6: a-1/a/a+1 and interleaved None slots obey supplied-count partiality and residual boundaries.
- AC-9 [US-1]: C-7: overlapping residual predicates yield at most one residual; every predecessor residual survives.
- AC-10 [US-1]: C-8: known rejected root is dropped_node; missing/multiple/wrong-root correspondence is callback_param, never a dangling bounded leaf.
- AC-11 [US-2]: C-9: duplicate tuples/full ranges/ordinals preserve multiplicity and incorrect pairings refuse.
- AC-12 [US-2]: C-10: ordinary-table or mask leakage is detected by exact parent/continuation/escape/non-head controls.
- AC-13 [US-2]: C-11: empty selected metadata coverage refuses; refined calls and their contexts exercise actual scopes/channels/effects.
- AC-14 [US-2]: C-12: entire public flat output remains identical; rich permitted head changes do not excuse unrelated metadata movement.
- AC-15 [US-2]: C-13: substituted candidate output or stale/changed producer/input state refuses.
- AC-16 [US-2]: C-14: native full410 observation supplies identity/shape/arity/ordinal; SQL-derived evidence cannot certify them.
- AC-17 [US-2]: C-15: mixed groups, duplicate or reused head/residual permissions refuse; complete single-use capacity succeeds.
- AC-18 [US-2]: C-16:14refinements alone are insufficient; only positive eligible distinct relation gain with zero loss can qualify for retention.
- AC-19 [US-2]: C-17: required CI must be green on the exact final head; local content reuse does not waive that identity check.
- AC-20 [US-1]: C-18: target evidence is original literal identity, never interpreted module contents/functor instantiation.
- AC-21 [US-2]: C-19: locations and UIDs remain audit fields; collisions do not replace native physical and Ident.same evidence.

## Edge Cases

- EC-1 [US-1]: one original inner root, exact self binder → stored bounded target.
- EC-2 [US-1]: inner nonrecursive RHS and homonyms → lexical Ident.same only.
- EC-3 [US-1]: duplicate parent occurrences → unchanged complete multiset.
- EC-4 [US-1]: arity boundaries and None slots → specified partial/residual rule.
- EC-5 [US-1]: rejected/missing/ambiguous root → prescribed conservative TOP.
- EC-6 [US-1]: arbitrary path inside Tmod_ident vs computed module → syntax boundary only.
- EC-7 [US-1]: same location, different physical roots → no identity inference.
- EC-8 [US-2]: wrong allocation ordinal → witness refuses.
- EC-9 [US-2]: both residual predicates true → at most one residual capacity.
- EC-10 [US-2]: mixed indistinguishable groups → refuse rather than choose one.
- EC-11 [US-2]: WAL main-file hash changes on ordinary read → invalid baseline; never update pin silently.

## Runnable Checks

These task-specific commands are implementation deliverables, not yet asserted
present or passing. Authentic semantic RED and a runnable independent verifier
must precede product edits. Setup/input errors are never RED evidence.

- CHECK-1 [AC-1,AC-4,AC-5,AC-6,AC-7,AC-8,AC-10,AC-12,AC-13,AC-14,AC-20,AC-21]: `node roster/tezos-recursive-typed-bodies/check-native.js` → authentic compiled admission/refusal/storage and non-vacuous complete preservation; exit0 pass,1 assertion,2+ error.
- CHECK-2 [AC-2,AC-3,AC-4,AC-5,AC-10,AC-11,AC-15,AC-16,AC-17,AC-21]: `node roster/tezos-recursive-typed-bodies/check-witness-inputs.js` → authentic witness positives plus shape/identity/ordinal/tampering/capacity refusals; exit0 pass,1 assertion,2+ error.
- CHECK-3 [AC-2,AC-15]: `node roster/tezos-recursive-typed-bodies/check-baseline.js` → sealed pinnedPR108 provenance, no-overwrite, all SQL sealing preservation, byte-stable read and neutral replay; exit0 pass,1 assertion,2+ error.
- CHECK-4 [AC-1,AC-2,AC-3,AC-7,AC-11,AC-13,AC-15,AC-16,AC-17,AC-18]: `node roster/tezos-recursive-typed-bodies/check-comparison.js` → fresh fixed410 positive independently witnessed gain; zero loss/unexplained/new MUST; exit0 pass,1 assertion,2+ error.
- CHECK-5 [AC-7,AC-12,AC-14,AC-18,AC-19]: `node roster/tezos-recursive-typed-bodies/check-compatibility.js` → exact scope/public/schema/self-policy and non-resolution preservation; exit0 pass,1 assertion,2+ error.
- CHECK-6 [AC-8,AC-9,AC-17]: `node roster/tezos-recursive-typed-bodies/check-residual-capacity.js` → authentic omitted/partial/overapplication and single-use residual cases; exit0 pass,1 assertion,2+ error.

AC-18/19 additionally require actual full build/test/bundle/diff, independent
review/QA and exact-head required CI plus guarded merge; no local script can
claim future CI success. Baseline full340 guard passed before product changes.

## Claims Metadata

Project reconciler and managed KB are absent. Draft metadata is not human
comprehension or formal verification certification. No global projection claimed.

```claims
{"record":"claims-header","schema_version":1,"namespace":"tezos-recursive-typed-bodies","spec_lifecycle":"draft"}
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
{"record":"acceptance-criterion","id":"AC-1","for":["FR-001","FR-004","FR-005","FR-007","FR-014"]}
{"record":"acceptance-criterion","id":"AC-2","for":["FR-016","FR-018","FR-019","FR-026","FR-027","FR-029"]}
{"record":"acceptance-criterion","id":"AC-3","for":["FR-016","FR-017"]}
{"record":"acceptance-criterion","id":"AC-4","for":["FR-004"]}
{"record":"acceptance-criterion","id":"AC-5","for":["FR-001","FR-002","FR-003"]}
{"record":"acceptance-criterion","id":"AC-6","for":["FR-005","FR-006"]}
{"record":"acceptance-criterion","id":"AC-7","for":["FR-014","FR-019"]}
{"record":"acceptance-criterion","id":"AC-8","for":["FR-010","FR-011"]}
{"record":"acceptance-criterion","id":"AC-9","for":["FR-012","FR-022"]}
{"record":"acceptance-criterion","id":"AC-10","for":["FR-007","FR-008","FR-009"]}
{"record":"acceptance-criterion","id":"AC-11","for":["FR-018","FR-019"]}
{"record":"acceptance-criterion","id":"AC-12","for":["FR-013","FR-020"]}
{"record":"acceptance-criterion","id":"AC-13","for":["FR-021"]}
{"record":"acceptance-criterion","id":"AC-14","for":["FR-013","FR-019"]}
{"record":"acceptance-criterion","id":"AC-15","for":["FR-027","FR-028"]}
{"record":"acceptance-criterion","id":"AC-16","for":["FR-016","FR-017"]}
{"record":"acceptance-criterion","id":"AC-17","for":["FR-022","FR-023"]}
{"record":"acceptance-criterion","id":"AC-18","for":["FR-024","FR-025","FR-030"]}
{"record":"acceptance-criterion","id":"AC-19","for":["FR-028","FR-031"]}
{"record":"acceptance-criterion","id":"AC-20","for":["FR-003","FR-004"]}
{"record":"acceptance-criterion","id":"AC-21","for":["FR-005","FR-009","FR-016"]}
{"record":"check","id":"CHECK-1","for":["AC-1","AC-4","AC-5","AC-6","AC-7","AC-8","AC-10","AC-12","AC-13","AC-14","AC-20","AC-21"]}
{"record":"check","id":"CHECK-2","for":["AC-2","AC-3","AC-4","AC-5","AC-10","AC-11","AC-15","AC-16","AC-17","AC-21"]}
{"record":"check","id":"CHECK-3","for":["AC-2","AC-15"]}
{"record":"check","id":"CHECK-4","for":["AC-1","AC-2","AC-3","AC-7","AC-11","AC-13","AC-15","AC-16","AC-17","AC-18"]}
{"record":"check","id":"CHECK-5","for":["AC-7","AC-12","AC-14","AC-18","AC-19"]}
{"record":"check","id":"CHECK-6","for":["AC-8","AC-9","AC-17"]}
```

## Entities

- `ResolutionRelation`: one canonical caller/source-line/internal-target tuple; not a unique syntactic expression.
- `ResolutionRowMultiset`: canonical stored call facts with multiplicity, excluding database surrogate IDs from identity.
- `LocalOpenRecursiveInvocation`: same-CMT direct Pident self-head of a local singleton Recursive Tpat_var binding with exactly one Tmod_ident open around its original immediate function body, within the RHS and targeting its uniquely observed stored root.

The new entity does not redefine historical LocalRecursiveInvocation or structural
OpenBodyInvocation. Shared relation/multiset definitions remain byte-equivalent.
