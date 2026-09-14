---
name: roster-spec
type: spec
status: live
feature: Exact singleton local recursive invocation targets
brief: briefs/tezos-local-recursion-intake.md
date: 2026-09-15
version: 1.0.0
---

# Spec — exact singleton local recursive invocation targets

Attempt4 of the existing five-iteration Tezos loop. This contract adds no general
0CFA, functor interpretation or new certainty guarantee. Independent documentary,
clarification, adversarial and formalizer passes are recorded in
roster/tezos-local-recursion/spec-input.md. Standing explicit user autonomy applies
to routine phase gates; no interactive quiz answers or formal proof are claimed.

## Clarifications

| Q | A |
|---|---|
| What is singleton? | Exactly one binding in Texp_let(Recursive,[vb],body), never a filtered mutual group. |
| Are annotations wrappers? | exp_extra metadata preserves a direct Texp_function; actual expression constructors are not peeled. |
| Where does evidence apply? | Direct same-binder self-heads in that exact RHS, including nested callable contexts, never its continuation or non-head uses. |
| Which literal identity? | Actual physical root and its observed assigned collision-qualified stored node; no guessed name or cross-CMT stamp. |
| Which arity? | Existing leading function chain plus terminal cases argument; only supplied Some slots, with existing result-arrow partiality. |
| What stays unchanged? | Public/flat output, ordinary local lookup and all rich facts outside admitted heads and separately justified residuals. |

## User Stories

### US-1: Follow exact local recursive self-calls (Priority: P0)

As an Irmin/protocol callgraph consumer, I want direct recursive self-call targets
to identify their stored literal body without asserting definite execution.
**Why this priority:** retained Irmin io.ml32/44 and tree.ml41/45/48 show this gap.
**Scope:** no mutual groups, constructor wrappers, alias/value-flow discovery,
qualified calls, public API changes or general abstract interpretation.
**Independent Test:** compile and index a singleton recursive fixture; its self-head
reaches the actual stored literal as MAY_ENUMERATED.
**Acceptance Scenarios:**
1. **Given** `let outer n = let rec aux n = if n=0 then 0 else aux (n-1) in aux n`,
   **When** its CMT is indexed, **Then** the RHS self-head reaches its actual stored
   body as MAY_ENUMERATED and the continuation call retains its previous facts.
2. **Given** a self-head within a nested callable or default/refutable context,
   **When** indexing, **Then** its original caller, CFG, scopes and effects remain
   attached to that context rather than moving to the enclosing function.
3. **Given** omitted optional arguments, partial applications and returned-function
   overapplications, **When** indexing, **Then** supplied expressions and literal
   arity determine partiality and one unknown residual per overapplied application.
4. **Given** rejected storage or colliding ghost positions, **When** indexing,
   **Then** only a uniquely witnessed stored physical root can be a bounded target;
   missing or ambiguous evidence cannot produce a dangling known leaf.

### US-2: Preserve facts and verify gains independently (Priority: P0)

As a maintainer comparing Tezos results, I want each refinement independently
witnessed and all other facts preserved, so that counts cannot conceal wrong edges.
**Why this priority:** trustworthy incremental improvement is the retention rule.
**Scope:** no corpus expansion, old checker edits or threshold relaxation.
**Independent Test:** paired unsupported fixtures and unchanged-binary replay
demonstrate exact preservation and reject tampered witnesses without requiring a gain.
**Acceptance Scenarios:**
1. **Given** mutual/nonrecursive/structural recursion, wrappers, aliases and a value
   escape beside a self-head, **When** comparing versions, **Then** only admitted
   direct heads change and no new MUST/non-head relation appears.
2. **Given** configured value channels, exceptions, conditional/dead sites and flat
   duplicates, **When** comparing versions, **Then** nonempty complete preservation
   sets agree apart from precisely admitted head metadata and justified residuals.
3. **Given** the frozen PR107 producer/schema and410 inputs, **When** replaying,
   **Then** all45052 rows and4781/12046 relations reproduce exactly; tampered input,
   binder, caller, target or reused occurrence capacity is rejected.
4. **Given** a candidate, **When** deciding retention, **Then** positive witnessed
   gain, zero loss/unexplained change/new MUST and complete roster/guard/CI evidence
   are required before guarded merge; a neutral candidate is discarded.

## Challenges

| ID | Story | Challenge | Resolution |
|---|---|---|---|
| C-1 | US-1 | Names/locations are not binder identities | Same-artifact compiler Ident plus physical RHS; never cross-build stamps. |
| C-2 | US-1 | Singleton group vs one callable member | Exactly one group binding. |
| C-3 | US-1 | RHS scoping and shadowing | Exact active binder within RHS only, preserving continuation/non-head behavior. |
| C-4 | US-1 | Guessed name vs stored root | Actual observed name/ordinal, unique physical correspondence and successful storage; otherwise explicit TOP. |
| C-5 | US-1 | OCaml metadata vs constructors | Direct descriptor accepts exp_extra; no constructor peeling. |
| C-6 | US-1 | Root arity vs returned closure | Existing fn_arity chain/cases rule, stopping at non-function body. |
| C-7 | US-1 | Omitted slots are not supplied args | Count Some expressions only on newly admitted path. |
| C-8 | US-1 | Residual multiplicity | One per overapplied application, not surplus argument or collapsed row. |
| C-9 | US-1 | Nested/default ownership | Preserve existing context, independently reconstructed from native structure. |
| C-10 | US-2 | Ordinary lookup may produce MUST/escapes | Intentional divergence: new heads enumerated only; ordinary timing unchanged. |
| C-11 | US-2 | Structural/local/mutual conflation | Native group/binder controls and predecessor comparison distinguish them. |
| C-12 | US-2 | Rich provenance leaks into flat | Entire duplicate-sensitive public flat multiset stays unchanged. |
| C-13 | US-2 | Rich preservation can be vacuous | Complete pending and shape/channel facts, nonempty configured controls. |
| C-14 | US-2 | Circular DB-derived witness | Artifact/Ident/root/caller/range/arity/ordinal from CMT; DB checks correspondence/storage only. |
| C-15 | US-2 | Duplicate/mixed witness reuse | Group members must agree; independent single-use head and residual capacities. |
| C-16 | US-2 | Counts hide losses/retargeting | Full counted multiset accounting and zero lost old relations. |
| C-17 | US-2 | Provenance and exit classes | Pin all inputs and baseline producer/schema; candidate hash recorded; source state stable per run;0pass/1assertion/2+error. |
| C-18 | US-2 | Neutral/no-gain behavior | Discard neutral added complexity; incomplete gates remain pending, never KEEP/merge. |

Prior art: official OCaml5.3 [Typedtree](https://raw.githubusercontent.com/ocaml/ocaml/5.3.0/typing/typedtree.mli)
and [Ident](https://raw.githubusercontent.com/ocaml/ocaml/5.3.0/typing/ident.mli)
ground C-1,C-2,C-5,C-6,C-7; existing arch-index ordinary and public collection
ground the intentional conservative differences C-10,C-12. No prior-art
divergence is silently ignored. No unresolved challenge requires a scope change.

## Functional Requirements

### Exact recursive targets

- FR-001 [US-1]: The indexer MUST restrict admissions to direct same-artifact Pident self-heads of the sole plain-variable binding in a local Recursive group, within that exact RHS including nested callable contexts.
- FR-002 [US-1]: The indexer MUST require a direct Texp_function descriptor, allowing exp_extra without constructor peeling and preserving all unsupported pattern/RHS behavior.
- FR-003 [US-1]: A bounded target MUST be the uniquely observed physical root's actual collision-qualified stored node; known dropped nodes remain MAY_TOP/dropped_node and missing/ambiguous correspondence remains MAY_TOP/callback_param.
- FR-004 [US-1]: Admitted applications MUST use existing literal syntactic arity and result-arrow partiality, counting only supplied Some expressions on this path.
- FR-005 [US-1]: Every overapplied admitted application MUST retain exactly one unknown returned-call residual, without multiplying by surplus arguments or collapsing duplicate applications.
- FR-006 [US-1]: Admitted invocations MUST retain original caller/context, conditional/dead, CFG, exception, scope, channel and effect attribution.
- FR-007 [US-1]: Every new resolved self-head MUST be MAY_ENUMERATED with a real stored callee and null TOP metadata; no new MUST is permitted.

### Preservation and independent verification

- FR-008 [US-2]: Outside admitted self-heads and justified residuals, prior rich and flat call facts MUST remain unchanged with multiplicity, including ordinary lookup, continuation, structural/mutual/nonrecursive and non-head behavior.
- FR-009 [US-2]: Comparison MUST preserve complete non-admitted pending fields and all shape, ownership, CFG, scopes, origins, carriers, channels, effects, reexports and flat facts using nonempty configured boundary controls.
- FR-010 [US-2]: Every changed head and residual MUST consume independent native CMT evidence for artifact, compiler binder/group, physical root/ordinal, caller, full application range, arity and supplied count with single-use capacities and refusal of mixed indistinguishable groups.
- FR-011 [US-2]: Candidate comparison MUST account for full canonical multisets, pairing every removed TOP with an admitted bounded target and only independently witnessed residual additions, with zero lost old relations, unexplained movement or new MUST.
- FR-012 [US-2]: Evidence MUST bind the frozen baseline producer/schema/410 manifest and every CMT hash, record the candidate producer, verify source stability per run and neutral predecessor replay, and refuse baseline overwrite.
- FR-013 [US-2]: Check processes MUST distinguish0pass,1semantic assertion failure and2+malformed input/provenance/runtime/tool failure; no infrastructure error may be presented as RED proof.
- FR-014 [US-2]: Retention MUST require positive independently witnessed gain, zero losses/unexplained changes and complete guards/review/QA/exact-head green CI before guarded rebase merge; neutral changes are discarded and incomplete gates stay pending without merge.

## Acceptance Criteria

- AC-1 [US-1 happy path]: Authentic compiled singleton recursion reaches the exact stored literal as MAY_ENUMERATED, including nested same-binder invocations.
- AC-2 [US-2 happy path]: Paired unsupported controls and unchanged replay preserve complete counted facts; tampered evidence is refused.
- AC-3 [US-1,C-1]: Homonymous or same-position but different compiler identities cannot authorize an admission.
- AC-4 [US-1,C-2]: A multi-binding recursive group remains excluded even if only one member is a direct literal.
- AC-5 [US-1,C-3]: Recursive evidence is confined to the RHS; shadowing, continuation and non-head occurrences retain prior behavior.
- AC-6 [US-1,C-4]: Actual collision ordinals resolve only with unique physical/stored correspondence; actual SQL storage rejection and missing/ambiguous correspondence yield prescribed TOP.
- AC-7 [US-1,C-5]: Native direct annotated literals are eligible; actual constructor wrappers and unsupported patterns/RHSs are unchanged.
- AC-8 [US-1,C-6]: Leading function-chain and terminal-cases arity stops at non-function boundaries, preserving returned-closure behavior.
- AC-9 [US-1,C-7]: Omitted optional slots do not count as supplied; partial/result-arrow flags match the specified rule.
- AC-10 [US-1,C-8]: Same-line overapplications retain one residual per native application with no capacity reuse.
- AC-11 [US-1,C-9]: Root/nested/default/refutable/conditional contexts retain independently witnessed caller and original attributed facts.
- AC-12 [US-2,C-10]: New targets have stored callees, MAY_ENUMERATED and null TOP metadata; no new MUST or non-head leakage occurs.
- AC-13 [US-2,C-11]: Native structural/local/mutual/nonrecursive groups are distinguished by binder/group evidence; excluded facts agree with predecessor.
- AC-14 [US-2,C-12]: Complete public flat call-row multisets, including duplicates and binder spellings, are unchanged.
- AC-15 [US-2,C-13]: Full pending metadata and shape/scope/channel/CFG/effect/reexport comparisons use nonempty configured preservation sets and show no unadmitted drift.
- AC-16 [US-2,C-14]: Wrong artifact/binder/group/root/ordinal/caller/range/arity/count evidence is rejected; native witness does not learn targets from candidate output.
- AC-17 [US-2,C-15]: Mixed indistinguishable groups and repeated use of either head or residual capacity are refused.
- AC-18 [US-2,C-16]: Count-neutral retargeting, lost relations, duplicate deletion, unsupported additions and new MUST fail the comparison.
- AC-19 [US-2,C-17]: Frozen PR107 replay reproduces45052rows,digest9ab4e0b13457247fb93dc83bf80323fcc5cec67866a18f56995ac0ec4a20867e,Irmin4781/protocol12046; overwrite/input/source/provenance mismatches are refused with distinct exit classes.
- AC-20 [US-2,C-18]: Only positive verified gain plus complete gates authorizes retention/merge; neutral changes are DISCARD and incomplete work remains pending.

## Edge Cases

- EC-1 [US-1]: ghost-position collisions -> actual ordinal and physical identity or refusal.
- EC-2 [US-1]: shadowed homonyms -> exact binder only.
- EC-3 [US-1]: exp_extra versus real wrapper -> descriptor boundary governs.
- EC-4 [US-1]: omitted/default/refutable/result-arrow -> correct context and partiality.
- EC-5 [US-1]: same-line overapplications -> separate residual capacities.
- EC-6 [US-1]: rejected root with a homonym -> no dangling bounded target.
- EC-7 [US-2]: escape beside direct head -> only the head can change.
- EC-8 [US-2]: mixed mutual group -> excluded as a whole.
- EC-9 [US-2]: count-neutral replacement -> lost-relation check refuses.
- EC-10 [US-2]: mixed identity in indistinguishable rows -> refuse admission.
- EC-11 [US-2]: private name/provenance in flat -> full multiset check fails.
- EC-12 [US-2]: matching location across altered CMT -> provenance failure.

## Runnable Checks

These concrete task-local commands are implementation deliverables, not claimed
present or passing at spec time. They must become executable before product edits,
with actual native assertion RED evidence. Every script honors0/1/2+ above.

- CHECK-1 [AC-1,AC-3,AC-4,AC-5,AC-6,AC-7,AC-8,AC-9,AC-11,AC-12,AC-13,AC-14,AC-15]: `node roster/tezos-local-recursion/check-native.js` -> native admission/storage/refusal and non-vacuous full preservation pass.
- CHECK-2 [AC-2,AC-3,AC-4,AC-6,AC-16,AC-17,AC-18]: `node roster/tezos-local-recursion/check-witness-inputs.js` -> authentic witness positives and tampered/capacity negative controls pass.
- CHECK-3 [AC-2,AC-19]: `node roster/tezos-local-recursion/check-baseline.js` -> immutable PR107 baseline, provenance, no-overwrite and neutral replay pass.
- CHECK-4 [AC-1,AC-2,AC-11,AC-12,AC-15,AC-16,AC-17,AC-18,AC-19,AC-20]: `node roster/tezos-local-recursion/check-comparison.js` -> fixed410 positive gain, all changes witnessed, zero loss/unexplained/new MUST.
- CHECK-5 [AC-12,AC-14,AC-15,AC-20]: `node roster/tezos-local-recursion/check-compatibility.js` -> scope/self-reference policy and exact attribution pass; no thresholds relaxed.
- CHECK-6 [AC-8,AC-9,AC-10,AC-16,AC-17,AC-18]: `node roster/tezos-local-recursion/check-residual-capacity.js` -> real overapplication and single-use residual positives/refusals pass.

AC-20 additionally requires actual full build/test/bundle/diff, independent roster
review/QA and exact-head CI/merge evidence; local scripts cannot claim future CI.
Baseline full336 guard already passed before product edits, recorded separately.

## Claims Metadata

Draft metadata is not formal or human-authority certification. Project reconciler
is absent; the upstream parser currently rejects older out-of-scope spec syntax,
so global validation/projection is not claimed. New-spec validation is separate.

```claims
{"record":"claims-header","schema_version":1,"namespace":"tezos-local-recursion","spec_lifecycle":"draft"}
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
{"record":"acceptance-criterion","id":"AC-1","for":["FR-001","FR-003","FR-007"]}
{"record":"acceptance-criterion","id":"AC-2","for":["FR-008","FR-009","FR-010","FR-012","FR-013"]}
{"record":"acceptance-criterion","id":"AC-3","for":["FR-001","FR-010"]}
{"record":"acceptance-criterion","id":"AC-4","for":["FR-001","FR-008"]}
{"record":"acceptance-criterion","id":"AC-5","for":["FR-001","FR-008"]}
{"record":"acceptance-criterion","id":"AC-6","for":["FR-003"]}
{"record":"acceptance-criterion","id":"AC-7","for":["FR-002"]}
{"record":"acceptance-criterion","id":"AC-8","for":["FR-004","FR-005"]}
{"record":"acceptance-criterion","id":"AC-9","for":["FR-004"]}
{"record":"acceptance-criterion","id":"AC-10","for":["FR-005","FR-010"]}
{"record":"acceptance-criterion","id":"AC-11","for":["FR-006"]}
{"record":"acceptance-criterion","id":"AC-12","for":["FR-007","FR-008"]}
{"record":"acceptance-criterion","id":"AC-13","for":["FR-001","FR-008"]}
{"record":"acceptance-criterion","id":"AC-14","for":["FR-008","FR-009"]}
{"record":"acceptance-criterion","id":"AC-15","for":["FR-006","FR-009"]}
{"record":"acceptance-criterion","id":"AC-16","for":["FR-010","FR-013"]}
{"record":"acceptance-criterion","id":"AC-17","for":["FR-010","FR-013"]}
{"record":"acceptance-criterion","id":"AC-18","for":["FR-011"]}
{"record":"acceptance-criterion","id":"AC-19","for":["FR-012","FR-013"]}
{"record":"acceptance-criterion","id":"AC-20","for":["FR-014"]}
{"record":"check","id":"CHECK-1","for":["AC-1","AC-3","AC-4","AC-5","AC-6","AC-7","AC-8","AC-9","AC-11","AC-12","AC-13","AC-14","AC-15"]}
{"record":"check","id":"CHECK-2","for":["AC-2","AC-3","AC-4","AC-6","AC-16","AC-17","AC-18"]}
{"record":"check","id":"CHECK-3","for":["AC-2","AC-19"]}
{"record":"check","id":"CHECK-4","for":["AC-1","AC-2","AC-11","AC-12","AC-15","AC-16","AC-17","AC-18","AC-19","AC-20"]}
{"record":"check","id":"CHECK-5","for":["AC-12","AC-14","AC-15","AC-20"]}
{"record":"check","id":"CHECK-6","for":["AC-8","AC-9","AC-10","AC-16","AC-17","AC-18"]}
```

## Entities

- `ResolutionRelation`: one canonical caller/source-line/internal-target tuple; not a unique syntactic expression.
- `ResolutionRowMultiset`: canonical stored call facts with multiplicity, excluding database surrogate IDs from identity.
- `LocalRecursiveInvocation`: a same-CMT direct Pident application of the sole plain-variable/direct-literal binder of a local Recursive group within its RHS, targeting its uniquely observed stored physical root.

Shared entity definitions match previous Tezos specs; no historical contract is rewritten.
