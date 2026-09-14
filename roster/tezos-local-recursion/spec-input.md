# Specification working input — not a validated spec

## Step1 research

Independent documentary worker recursive_research_flow reread the full intake.
Existing Texp_let traversal ignores rec_flag and visits RHS before stamp insertion
(arch_index_cmt.ml:1946–1971); ordinary table affects non-head occurrences and MUST
(1998–2011,2335–2341). Literal naming mutates collision counters (1499–1507).
Actual visit owns name, context and physical root (1920–1945). Existing rich-only
open-body finalization observes identity/cardinality/storage (3851–3883), while
the exported wrapper leaves its private table empty (3008–3013; mli427–455).
All documentary details are corroborated in research.md; no implementation
recommendation is attributed to this worker. Fresh-thread quota required reuse.

## External prior art

OCaml5.3.0 Typedtree uses rec_flag, Ident, direct function descriptors, separate
exp_extra metadata and optional application slots; Ident/Location API distinguishes
binder identity from source location. Versioned primary links are in research.md.
Existing ordinary arch-index literal invocation may create MUST; the selected
bounded refinement intentionally only creates MAY_ENUMERATED. Existing flat public
collector omits rich-only descriptors. Each divergence needs an explicit challenge.

## Proposed stories for adversarial review

### US-1: Resolve exact local recursive self-invocations (P0)

As an Irmin/protocol callgraph consumer, I want direct self-call targets for a
singleton local recursive literal to point to its real stored body, so that I can
follow that relation without treating it as definitely executed.
Why P0: concrete current TOP examples in Irmin io.ml32/44 and tree.ml41/45/48.
Scope excludes mutual recursion, wrapper/alias discovery, non-head value flow,
qualified invocations and general0CFA. Independent test: a compiled fixture
contains a stored singleton recursive body whose exact self-call is MAY_ENUMERATED.
Scenarios:
1. Given `let outer n = let rec aux n = if n=0 then 0 else aux (n-1) in aux n`,
   when its native CMT is indexed, the recursive RHS head targets its actual stored
   synthetic literal, as MAY_ENUMERATED; the continuation call keeps its old facts.
2. Given a direct self-reference inside a nested closure/default/refutable body,
   when indexing, identity remains the enclosing recursive binder and the caller,
   CFG/exception/channel facts retain their existing attribution.
3. Given omitted optional slots, partial application or higher-order return
   overapplication, when indexing, actual supplied arguments and literal arity
   preserve partial flags and one unknown returned-call residual where required.
4. Given failed body storage, same-position roots or mismatched physical evidence,
   when indexing, a missing/ambiguous target never becomes a known dangling leaf;
   collision-qualified actual names are used only when uniquely witnessed.

### US-2: Reject unsupported refinements and retain graph facts (P0)

As a maintainer comparing Tezos snapshots, I want every admitted change witnessed
and every unrelated fact preserved, so that a higher resolution count cannot hide
wrong targets, missing edges or certainty inflation.
Why P0: correctness and attributable gain are the loop's retention contract.
Scope excludes expanding the fixed corpus or relaxing thresholds/old checkers.
Independent test: paired predecessor/current native fixture plus unchanged binary
replay and tampered witnesses verify exact preservation/refusal without needing a
positive gain in an unsupported fixture.
Scenarios:
1. Given mutual/nonrecursive/wrapped/aliased bindings, homonymous binders, recursive
   value escapes and structural recursion, when indexing, all prior facts remain
   unchanged outside exact in-scope invocation sites; no new MUST is created.
2. Given enabled value channels, raised exceptions, conditional/dead sites and flat
   collection, when comparing predecessor/current, nonempty preservation sets and
   duplicate-sensitive flat rows agree, apart from precisely admitted head metadata
   and any justified residual record with native single-use occurrence capacity.
3. Given the frozen410 manifest and PR107 baseline, when replaying unchanged input,
   all45052 canonical rows/digest9ab4e0b1… and4781/12046 relations reproduce exactly.
   Wrong producer/schema/CMT/binder/target/caller/range or reused capacity is refused.
4. Given a candidate fixed410 run, when retaining it, independently witnessed
   relation gain is positive, losses/unexplained changes/new MUST are zero, and
   full guards/review/QA/exact-head CI pass before guarded merge.

## Proposed checker decomposition (not executable yet)

CHECK-1 native fixture identity, arity, caller and non-vacuous preservation.
CHECK-2 negative witness/capacity controls using actual compiler artifacts.
CHECK-3 frozen PR107 baseline and no-overwrite/neutral replay controls.
CHECK-4 full fixed410 candidate comparison plus independent native witnesses.
CHECK-5 exact self-reference policy/pristine attribution and diff boundaries.
CHECK-6 isolated returned-call residual positive/negative capacity controls.
Commands will be task-local node check scripts honoring0pass/1assertion/2error;
actual executable deliverables and red observations must precede product edits.

## Clarifications (independent Terra step2, source-checked)

| Q | A |
|---|---|
| Do constraints/coercions wrap literals? | No. Eligibility is the direct Texp_function descriptor, permitting exp_extra metadata without peeling constructors (arch_index_cmt.ml878–891). |
| Where is the recursive evidence active? | Only the exact singleton Recursive binding RHS, including its nested callable contexts; preserve existing callers. Never its continuation or a different Ident. |
| What identifies the body? | The physical literal actually visited and its assigned collision-qualified node, with unique correspondence and successful storage; not predicted location text. |
| Which arity/count applies? | Existing fn_arity leading chain plus terminal cases argument; supplied Some slots only; result-arrow partiality and one residual per overapplied application. |
| Which other facts may change? | No mutual/nonrecursive/structural/non-head refinements; unchanged public flat and all rich facts except exact admitted heads and justified residuals. |

No OPEN contractual question; zero user questions asked. Detailed intake line
numbers in the worker response were stale; main checked current sections and
source snippets instead of adopting those line numbers as evidence.

## Adversarial challenges and resolutions

Independent Sol step4 returned18 challenges and12 edge cases. Resolutions below
are grounded in the intake and documentary source, not new scope decisions.

| ID | Story | Challenge | Resolution |
|---|---|---|---|
| C-1 | US-1 | Binder identity vs location/UID/stamp | Same-artifact compiler Ident equality (same/unique_name equivalence), exact physical RHS and scoped occurrence; no location/name-only or cross-build stamp proof. |
| C-2 | US-1 | Singleton means group or callable member? | Exactly Texp_let(Recursive,[vb],body); no filtering larger groups. |
| C-3 | US-1 | Recursive RHS visibility | Active exact binder only in its RHS; nested same-binder references eligible, shadowing/new stamps excluded; continuation uses unchanged legacy path. |
| C-4 | US-1 | Actual stored body vs guessed name | Actual observed physical root, assigned name/ordinal, unique correspondence and successful stored row required. Known dropped node remains TOP/dropped_node; absent/ambiguous correspondence remains callback_param TOP. |
| C-5 | US-1 | exp_extra vs wrappers | Direct Texp_function with any compiler metadata remains literal; no constructor peeling. Native constrained-literal and real wrapper controls distinguish this. |
| C-6 | US-1 | Root arity and returned closures | Existing fn_arity counts leading function chain and terminal cases parameter only; a non-function body boundary stops peeling. |
| C-7 | US-1 | Omitted slots | Only Some expressions count on the newly admitted path; preserve existing legacy arity behavior elsewhere. |
| C-8 | US-1 | Residual multiplicity | One unknown returned-call record per overapplied native application, not per surplus argument or collapsed row. Counted comparison preserves existing residuals. |
| C-9 | US-1 | Nested ownership | Existing callable/CFG lowering owns each invocation, including defaults/refutable/nested functions. Witness independently reconstructs the same ownership from native structure; it never derives caller from candidate target. |
| C-10 | US-2 | Ordinary table can create MUST/non-head changes | New admissions only enumerated; ordinary table timing/semantics unchanged. Paired non-head and certainty controls reject leakage. This conservative divergence is intentional. |
| C-11 | US-2 | Structural vs local vs mutual distinction | Native fixtures contain all three with compiler binder/group shape asserted, and unchanged predecessor facts for excluded groups. |
| C-12 | US-2 | Flat compatibility | Exact duplicate-sensitive full public/flat call rows unchanged; private evidence not exposed through public API. |
| C-13 | US-2 | Rich preservation completeness | Compare full pending records except admitted head/partial metadata and justified residuals, plus shape/CFG/conditional/dead/scopes/origins/carriers/channels/effects/reexports. Configured channels and boundary cases must be nonempty. |
| C-14 | US-2 | Circular witness | Native CMT supplies artifact, Ident, recursion flag/group, literal identity/name ordinal, caller, full application range, arity and supplied count independently of candidate resolved output; DB only checks resulting correspondence/storage. |
| C-15 | US-2 | Duplicate capacity | Every indistinguishable group member must agree on admission/target; each head occurrence capacity is single-use and each residual occurrence capacity independently single-use, never reusable by another addition. |
| C-16 | US-2 | Aggregate counts hide losses/movement | Count full canonical multisets, pair each removed TOP with one admitted target and preserve every other row, allowing only separately witnessed residual additions; zero lost old relations or new MUST. |
| C-17 | US-2 | Provenance simultaneous binding | Pin producer/schema/410 manifest and each CMT hash; before/after source-state and neutral copied-binary replay. Refuse overwrite/mismatch; assertion failures exit1, runtime/load/tool failures>=2. |
| C-18 | US-2 | Neutral outcome | Neutral/no-gain added complexity is DISCARD under original loop; report refusals honestly, retain evidence only, no product merge or false KEEP. |

## Edge cases from adversarial review

- EC-1 [US-1]: ghost-location collision -> use actual ordinal/physical root or refuse.
- EC-2 [US-1]: homonymous shadow binders -> match exact Ident only.
- EC-3 [US-1]: exp_extra vs constructor wrapper -> direct descriptor admitted, wrapper unchanged.
- EC-4 [US-1]: optional/refutable/default/result-arrow -> existing context and stated partiality preserved.
- EC-5 [US-1]: same-line overapplications -> distinct single-use residual capacity.
- EC-6 [US-1]: rejected body with homonym -> no dangling known leaf.
- EC-7 [US-2]: callback escape beside direct head -> only direct head changes.
- EC-8 [US-2]: mixed mutual group -> whole group excluded, not filtered singleton.
- EC-9 [US-2]: count-neutral relation replacement -> counted comparison refuses loss.
- EC-10 [US-2]: mixed-identity indistinguishable group -> refuse ambiguous admission.
- EC-11 [US-2]: rich name leaks into flat -> paired complete multiset rejects.
- EC-12 [US-2]: matching location across differing artifact -> provenance rejects.

Cross-spec entity comparison: ResolutionRelation and ResolutionRowMultiset use
byte-identical definitions in tezos-call-resolution/residual-targets/open-bodies.
New LocalRecursiveInvocation does not redefine their entities or historical scope.

Tool discovery correction: human-validation.md and claims-reconcile.js are absent
from this project's installed harness, but now located in the roster source tree.
Main read the full upstream governance protocol. The user's repeated explicit
autonomy overrides routine interactive quizzes, not correctness or material-scope
gates; no quiz answers are fabricated. Upstream validation availability will be
reported separately from project installation/projection.

Upstream actual commands: manifest-neutral questions.manifest.json exit0;
claims-reconcile check --root . exit2 at pre-existing
specs/functor-binding-resolution.md375: unmatched-record AC-1. Its normative AC
exists at293 in older bold/parenthesis syntax; no project claims-authority or
managed context manifest exists. This is legacy parser incompatibility, not a
successful freshness check or detected stale managed projection. Do not edit
historical out-of-scope specs/tooling or run project-wide projection. Validate
the new spec separately and record global validation unavailable on this tree.
