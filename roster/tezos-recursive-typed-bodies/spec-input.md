# Specification inputs — tezos-recursive-typed-bodies

This is working input, not a validated specification or implementation approval.
Routine gates operate under explicit user autonomy; no quiz answers are invented.

## Clarifications (Terra independent pass)

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

## Proposed user stories

### US-1: Follow an exact local open-recursive self-call (P0)

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

### US-2: Independently verify refinement and preservation (P0)

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

## External prior art

| Source | Existing approach | Contract implication |
|---|---|---|
| OCaml5.3 typedtree.mli | newtypes/constraints in exp_extra, n-ary function and optional application slots | Annotations are not wrapper constructors; syntax arity differs from supplied slot count. |
| OCaml5.3 ident.mli | Ident.same binding identity vs name-based equality | Names/locations cannot certify an exact binder. |
| OCaml5.3 shape.mli/shape_reduce.mli | Internal UID is not unique and reduction can approximate | No unconditional global UID identity inference. |
| OCaml5.3 location.mli | locations include ghosts and have no uniqueness guarantee | Physical identity and actual allocation are separate from source positions. |

Exact official URLs and documentary citations are in research.md Q7–Q8. No
intentional divergence from those compiler facts is proposed. Broader ordinary
local-table behavior is intentionally not extended: preserving predecessor facts
is the specified boundary.

## Required deterministic checks (deliverables)

Native exact admission/refusal/storage; full non-vacuous metadata and flat
preservation; native witness shape/identity/capacity positives and tampering;
immutable baseline replay and no-overwrite; fixed410 counted positive delta;
unchanged scope/schema/public API/self-policy and full build/test/review/QA/CI.
Checks use0 pass,1 semantic assertion,2+ setup/input/runtime error. No checker
may label tool failure as authentic TDD RED.

## Fresh research confirmation (Sol)

The frozen attempt5 predecessor DB contains the14 selected TOP self-heads and
seven distinct continuation TOP calls at translator2874/2916/2947/3088/3116/5913
and storage_description391. The latter are explicit preservation controls, not
additional targets. Code lines1991–2017 admit direct functions only;2044–2057
uses the separate ordinary local table for non-head occurrences. No project KB.

## Adversarial challenges and resolutions (Sol challenges; root resolutions)

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
