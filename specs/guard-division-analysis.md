---
name: roster-spec
type: spec
status: live
feature: Experimental bounded OCaml divisor analysis
brief: briefs/guard-division-analysis-intake.md
date: 2026-09-13
version: 1.0.0
---

# Spec — guard-division-analysis

Standalone experimental arch-guard, not an extension of existing rule verdicts. Trusted selected CMT artifacts only; no external target scanning. The following contract is authorized under the user's standing full-pipeline autonomy; no fresh human quiz or machine-checked proof is claimed.

## Clarifications

All eight OPEN rows resolved by root within the authorized bounded experiment, before story drafting.
No fresh human approval or mathematical proof claimed. These choices deliberately keep unsupported regions visible.

| ID | Resolution |
|---|---|
| Q-1 | Support Tfunction_body functions whose parameters are ordinary Nolabel/Labelled and Tparam_pat variable, wildcard or unit pattern. Bound scalar identifiers start top; unit/wildcard adds no numeric fact. Optional labels/defaults, refutable/compound params and Tfunction_cases make the entire function subtree UNSUPPORTED, including defaults and nested functions. No pattern-derived numeric refinements. |
| Q-2 | Each function outside an unsupported subtree starts a fresh environment: all parameters/captures top, no outer facts. Locals created inside that fresh entry may be tracked. Unsupported lexical-region flag is sticky across nested functions within that subtree; fresh-entry separation does not override it. Ordinary nested functions outside unsupported regions remain analyzable even in an outer branch known dead; no inherited reachability guarantee. |
| Q-3 | Local nonrecursive let supports variable/wildcard patterns only (variable aliases are RHS identifier reads, not alias-pattern projection). Simultaneous and-group RHSs evaluate in the pre-group environment; all bindings become visible only in the body. Compound, alias-pattern, refutable, or-pattern and recursive value groups mark the entire local-let subtree UNSUPPORTED. At structure level recursive groups also mark their RHS subtrees unsupported; independent later declarations start fresh. No cross-top-level numeric environment. |
| Q-4 | Closed numeric primitive transfer set: %negint, %addint, %subint, %mulint, %divint, %modint, fully supplied correct-arity native int operands. Neg/add/sub/mul must retain exact singleton/no-overflow cases; detected possible overflow may widen to top. Div/mod result value may always be top, but divisor classification still runs. Zero restrictions accept direct native-int identifier vs Const_int0 in either order, under %equal/%notequal/%eq/%noteq at int operand type. Pure boolean literals true/false also restrict branch reachability. Other predicates do not refine (both branches retained); not/ordering normalization is not promised. if-without-else joins then with unknown unit value, still inventories then-sites. UNREACHABLE only from false literal branch or contradictory zero restrictions. |
| Q-5 | Supported expression backbone: constants, identifiers, supported functions-as-values, supported local lets, sequence, if and application. Unknown ordinary applications (including indirect primitive aliases) return top, do not expand callees and preserve only existing immutable scalar bindings. Argument expressions are interpreted independently in the same incoming env; no claimed evaluation order/termination/exception reachability. Every other structural expression constructor (match,try,loops,letop,lazy,object,record/array/field mutation,local modules,extensions) is an unsupported subtree; its result to surrounding supported expressions is top. Unsupported marker is lexical, not a global poison of later independent scalar statements. Short-circuit boolean primitive applications %sequand/%sequor are unsupported subtrees. Generic pure-looking but unlisted primitives return top; their arguments retain independent evaluation. No heap, exception, ordinary-call termination or interprocedural effects used to prove unreachable. |
| Q-6 | Inventory only a Texp_apply whose immediate head is Texp_ident Val_prim from the eight closed div/mod identities. Do not reconstruct nested later saturation or aliases. One such application is one syntactic occurrence, not necessarily execution. Exactly two Nolabel, Some operands is numerically eligible for native int; all other arity/labels/options unsupported. Original second argument absent or None maps to category missing, not to a shifted slot. Other integer families unsupported at the operation; their argument expressions still visited. Location is whole Texp_apply; only syntactically immediate primitive heads count. |
| Q-7 | Artifact identity canonical physical path +SHA256; module/source metadata retained, duplicate module+source pair across distinct inputs refused. Public site ID is per-artifact one-based preorder occurrence ordinal (not cross-build stable), scoped by artifact path/digest. Sort artifacts by physical path and sites by artifact then start byte offset,end byte offset,primitive,ordinal. No compiler Ident/Uid/stamp in public IDs. Location carries source filename,start/end line,one-based byte column,absolute byte offset and ghost flag, with null for invalid/missing coordinates; retain site despite ghost/line0, never fabricate a valid source location. Missing location affects navigation, not numeric interpretation. |
| Q-8 | CLI arch_guard / root arch-guard, repeatable --cmt FILE (at least1), --format text/json default text, --help and --version. Unknown/bad args exit2; help/version0. Schema version1; exact field shape frozen in final spec. Diagnostic stderr, successful complete report stdout only; no --out/DB edits/build execution. Input limits128unique artifacts,32MiB each,256MiB aggregate; traversal100000expression nodes per invocation,10000sites and recursion-depth512. Count before semantic work and fail2 rather than truncate. JSON serialization max16MiB before any stdout. These are deterministic limits, not a hard OS memory/time sandbox; CMT files are trusted same-compiler/same-target build artifacts. External checker subprocess120s/16MiB cap. Input hash before/after read, no atomic source freshness or hostile-concurrency certificate. |

## Status and report definitions

NONZERO: modeled divisor excludes zero whenever reached.
ZERO: modeled divisor is exactly zero whenever reached; no guaranteed execution claim.
MAY_ZERO: model includes zero and at least one nonzero value (top included).
UNREACHABLE: supported entry context has bottom under the closed branch causes above.
UNSUPPORTED: syntax occurrence has no numeric interpretation under the closed fragment (takes precedence over reachability).
Successful CLI exit0 is report production, never a safety gate; failure2 emits no complete report.
An empty site list must explicitly say no matching immediate primitive occurrences in supplied artifacts, not no division in a program.

## Accepted measurable minimum

Alias means copying the current abstract value at the let binding. Refining d later need not
retroactively refine a previously copied alias a; this is a nonrelational fragment. An alias
created inside d's refined branch must copy that refinement. A guard directly on a can refine a.

Native fixtures must show nonzero literal/local alias/guard, zero literal, possible parameter,
branch0/2 join, shadowing, contradictory-guard unreachable, closed-entry captures, unsupported loops/try/defaults/cases and other integer families, partial primitive and shadowed source operator.
Small-width exhaustive containment tests plus31/63 extrema check transfers and join; they do not prove soundness for all programs.
No numeric domain representation dictated here; plan must select one meeting zero exclusion/joins/overflow conservatism.

## User Stories

## US-1: attributable primitive inventory (P0)

As an OCaml library maintainer, I want explicit CMT inputs turned into a stable syntax inventory
so that I know which native integer division/remainder occurrences were inspected and which were not.
Why P0: an empty or silently partial inventory would make every later semantic result misleading.
Scope: no numeric proof, call expansion, source scanning or existing DB mutation.
Independent test: compile a native fixture and validate inventory/metadata without depending on numeric precision.

1. Given maintainer-compiled fixture with native div/mod,int32/int64/nativeint variants and partial (/)1, when --cmt fixture.cmt --format json runs, then every immediate primitive application appears with original slot2 syntax/category and artifact attribution.
2. Given a locally shadowed (/) returning addition, when the same inventory runs, then its nonprimitive application is not classified as native division; a genuine Stdlib.( / ) occurrence still is.
3. Given the same artifacts in reversed/repeated argument order, when both runs execute, then canonical JSON bytes match and each physical artifact is counted once.
4. Given one valid artifact and one missing/incompatible/interface input, when run together, then exit2, stderr diagnostic and no complete stdout report; valid prefixes do not become a success.
5. Given an implementation with no matching primitive occurrences, when inspected, then empty inventory/census explicitly scoped to supplied artifacts, no safety claim.

## US-2: bounded numeric classification (P0)

As an OCaml library maintainer, I want a separate semantic status for each inventoried operation
so that local values and guards can distinguish routine nonzero divisors from unresolved or zero cases.
Why P0: closes the current syntax-only precision gap while preserving existing rule semantics.
Scope: native int acyclic fragment only; loops/handlers/defaults/other integer families and interprocedural execution are excluded.
Independent test: domain laws and a compiled behavioral fixture validate classifications independently of origin-rule or SQLite results.

1. Given functions dividing by literal2 and by let d=2, when analyzed, then each divisor is NONZERO; literal0 is ZERO and an unrestricted parameter is MAY_ZERO.
2. Given if d=0 then 0 else 10/d and if d<>0 then10/d else0, when analyzed, then division sites are NONZERO; an alias created inside the refined branch copies its current facts but a new shadowing binder does not. No retroactive relational propagation to an alias created before the guard is required.
3. Given let d=if b then0 else2 in10/d, when analyzed, then MAY_ZERO; given nested contradictory d=0 and d<>0 branch, then contained supported division is UNREACHABLE.
4. Given possible modular overflow yielding zero, when transferred, then zero remains in the abstract result (possibly top), never false NONZERO; bounded concrete containment and31/63 edge tests pass.
5. Given nested fun()->10/d created under d<>0, when analyzed, then captured d is fresh top/MAY_ZERO, not inherited NONZERO; nested local let x=2 still permits NONZERO outside unsupported regions.
6. Given division under loop/try/default/function-case or partial application/int64 divisor, when analyzed, then UNSUPPORTED with reason, retained in census even under a contradictory outer branch.
7. Given ordinary opaque call returning d, when d is used as divisor, then MAY_ZERO; successful command remains exit0, not a safety acceptance.
8. Given existing arch-index self golden/rules/reference, when full regression gates run after adding component, then original semantics and counts remain unchanged.

## US-3: interpretable experiment result (P1)

As a reviewer of this experiment, I want a report separating inventory size, numeric coverage and observed precision
so that I can judge whether extending the analysis is useful without treating fixture success as production impact.
Why P1: required delivery evidence and usability, independent of a chosen domain's internals.
Scope: no CI policy enforcing semantic statuses, no new artifact publication service, no source-to-CMT proof.
Independent test: validate report census equality/status distinctions, text/JSON agreement and real owned-library execution.

1. Given native fixture outputs, when rendered text and JSON, then all five statuses and reasons/census agree, supported/unsupported denominator visible.
2. Given compiler inputs, when report generated, then compiler version,int width,scope,input digests,analysis limitations and report-only exit contract present; no timestamp-induced nondeterminism.
3. Given owned lib/arch_index artifacts, when run during QA, then actual site/status counts recorded even if0; no automatic corpus expansion to manufacture benefit.
4. Given a configured deterministic input/traversal/output limit is exceeded, when run, then error2 and no complete stdout, not truncated successful evidence.

## Challenges and Edge Cases

These challenges test whether the candidate stories and resolved clarifications are sufficiently exact before implementation. They do not prescribe implementations. `Expected` records behavior already required by the approved material; `Unspecified` identifies the remaining ambiguity that a final specification must close.

1. **C-1 — Immediate primitive occurrence versus executed operation (US-1.1, US-2.6).** A `Texp_apply` headed by a recognized primitive may have a missing original slot, invalid labels, over-application, or an operand expression inside an unsupported region. The stories require every immediate occurrence in inventory while describing partial application as “not an executed division,” leaving eligibility at unusual `Texp_apply` shapes open even though all such sites enter the frozen census. **EC-1 — Expected:** each immediate recognized head is one syntax site, contributes once to `total_sites`, and remains visible with `UNSUPPORTED` where ineligible. **Unspecified:** whether a saturated recognized primitive that is itself the callee of a later application is only the inner site, and the exact unsupported reason selected for simultaneous arity, label, and missing-slot defects.

2. **C-2 — Primitive identity and operand-family proof (US-1.1–2).** `Val_prim` distinguishes a primitive from a shadowed operator, but `%equal`, `%notequal`, `%eq`, and `%noteq` are not by name alone evidence that both operands are native `int`; similarly, immediate div/mod identities span four integer families. **EC-2 — Expected:** source spelling and binder names never establish primitive or numeric-family identity; a shadowed `( / )` is excluded and a genuine primitive is retained. **Unspecified:** the exact typed evidence accepted for native-int eligibility and zero-restriction eligibility when type information is generalized, aliased, or unavailable.

3. **C-3 — Deterministic artifact deduplication has two identities (US-1.3).** Repeated paths deduplicate by canonical physical path, while distinct paths with equal module/source identity are rejected; digest is also part of public attribution. A hard link, path alias, or byte-identical copy can agree on some identities and disagree on others. **EC-3 — Expected:** reversed/repeated inputs yield byte-identical output without inflated counts, and conflicting distinct artifacts fail rather than merge. **Unspecified:** the precise equivalence and ordering of canonical-path deduplication, physical-file detection, hashing, and module/source collision rejection for hard links and copied artifacts.

4. **C-4 — Failure atomicity crosses input, traversal, and serialization boundaries (US-1.4, US-3.4).** A later input can fail after earlier artifacts were read, or a limit can fail after a complete in-memory prefix exists. The output contract now requires empty stdout, but boundary arithmetic can still differ across file bytes, aggregate bytes, node count, site count, recursion depth, and serialized JSON size. **EC-4 — Expected:** any malformed input or breached limit exits `2`, diagnoses on stderr, emits exactly empty stdout, and never truncates. **Unspecified:** whether each numeric limit is inclusive, how aggregate bytes treat deduplicated inputs, and which node/depth events increment their counters.

5. **C-5 — Empty inventory is easy to overclaim (US-1.5, US-3.3).** Zero recognized immediate sites can mean the supplied implementations contain none, relevant operations were expressed indirectly, or the provided artifacts omit source units. **EC-5 — Expected:** the result is scoped only to accepted supplied artifacts and makes no safety or whole-program claim. **Unspecified:** the mandatory machine-readable and text wording/fields that distinguish “zero matching sites” from “no division,” “safe,” or “complete program coverage.”

6. **C-6 — False `NONZERO` through OCaml modular wrap (US-2.1, US-2.4; divergent prior art: OCaml versus C alarm tools).** A transfer derived from mathematical integers or from a C analyzer’s overflow-alarm semantics can exclude zero even though OCaml 31/63-bit modular arithmetic wraps to zero. The public OCaml documentation also leaves the `min_int / -1` pair without a dedicated clause. **EC-6 — Expected:** every arithmetic result overapproximates the selected OCaml word width; possible wrap retains zero or widens, and concrete division by zero is never performed. **Unspecified:** the complete executable oracle for 31/63-bit neg/add/sub/mul boundary cases and the conservative treatment asserted for the documented `min_int / -1` gap.

7. **C-7 — `ZERO` can be misread as reachability or confirmed failure (US-2.1, US-2.7).** Classifying literal zero as `ZERO` says only what the divisor is if the syntax site is reached; unknown calls, exceptions, or evaluation order may prevent execution. **EC-7 — Expected:** `ZERO` is a conditional divisor-value fact, successful analysis exits `0`, and no vulnerability or guaranteed-execution claim follows. **Unspecified:** which report fields and normative text must carry that qualification per site rather than only globally.

8. **C-8 — Binder scope can leak facts across shadowing, aliases, and simultaneous groups (US-2.2).** A spelling-keyed environment can transfer `d <> 0` to a new `d`; sequential handling of `let x = ... and d = ...` can expose facts that OCaml’s pre-group RHS scope does not provide; relational alias propagation can also retroactively refine an alias created before a guard. **EC-8 — Expected:** restrictions attach to compiler binder identity, group RHSs use the pre-group environment, newly shadowing binders receive only their own facts, and aliasing is a nonrelational value copy at binding (an alias created inside a refined branch copies that current fact, while a pre-guard alias need not refine retroactively). **Unspecified:** the exact identity key and lookup behavior for captured, alpha-renamed, invalid, or absent compiler identities, including whether inability to establish identity yields top or an unsupported region.

9. **C-9 — False `UNREACHABLE` through state leakage into nested functions (US-2.3, US-2.5).** A nested function created inside a contradictory or nonzero outer branch is a separately callable entry; inheriting outer bottom or refinements would classify its sites `UNREACHABLE` or `NONZERO` falsely. Conversely, a nested function under an unsupported lexical subtree must not escape the sticky unsupported marker. **EC-9 — Expected:** ordinary nested functions start with parameter/capture top and fresh reachability, while unsupported lexical ancestry takes precedence; inner locals may establish new facts. **Unspecified:** the exact state-reset boundary for local function bindings, immediately applied lambdas, curried function bodies, and nested structure-level function declarations.

10. **C-10 — Unsupported-region precedence must dominate contradictory reachability (US-2.6).** A division inside a loop, handler, optional/default function subtree, compound-pattern local let, or other excluded constructor may also sit below `if false` or contradictory zero tests. Emitting `UNREACHABLE` would conceal that the semantics were never modeled. **EC-10 — Expected:** `UNSUPPORTED` wins over `UNREACHABLE`, remains inventoried, and carries a reason even beneath modeled bottom. **Unspecified:** a total precedence rule when multiple nested unsupported causes apply, including whether reasons are singular, ordered, or accumulated.

11. **C-11 — Opaque calls and unsupported applications have an unstable boundary (US-2.7).** Resolutions say unknown ordinary applications return top while short-circuit primitives and excluded structural constructs create unsupported subtrees; unlisted primitives return top and their arguments are still visited. Without a closed categorization, equivalent-looking calls can switch between `MAY_ZERO` and `UNSUPPORTED`. **EC-11 — Expected:** an opaque ordinary call result used as divisor is `MAY_ZERO`; sites lexically inside a declared unsupported subtree are `UNSUPPORTED`. **Unspecified:** the exhaustive application-shape decision table, especially malformed known primitives, indirect aliases, methods, effects, and unknown calls whose arguments contain target sites.

12. **C-12 — Goblint’s zero/top behavior is not automatically this status lattice (US-2.1, US-2.7; divergent prior art: Goblint).** Goblint distinguishes definite zero, possible zero, and safe before abstract division, propagates bottom, and maps unsupported integer operators to type top. Here, top may mean `MAY_ZERO`, while excluded syntax must be `UNSUPPORTED`; conflating the two creates either false supported coverage or hidden uncertainty. **EC-12 — Expected:** top for an eligible modeled native-int divisor maps to `MAY_ZERO`, bottom maps to `UNREACHABLE` only in a supported region, and lexical exclusion maps to `UNSUPPORTED`. **Unspecified:** the normative state-to-status table for every combination of numeric top/bottom, operation eligibility, and unsupported ancestry.

13. **C-13 — Infer widening conflicts with the deliberately acyclic fragment (US-2.3–4; divergent prior art: Infer).** Infer’s tutorial introduces widening to make loop analysis terminate, but this experiment excludes loops and recursive evaluation. Mentioning widening as precedent can imply loop-derived reachability or numeric precision that the stories prohibit. **EC-13 — Expected:** no semantic status is justified by loop iteration, guessed bounds, recursive unrolling, or widening. **Unspecified:** whether the final spec bans widening only at execution regions or also from the numeric domain API/tests, and how sites in loop condition/body/update-like typed subexpressions are uniformly classified.

14. **C-14 — Eva’s domain/alarm separation does not define this report (US-2.4, US-3.1; divergent prior art: Eva).** Eva provides product domains, top/bottom, branch reduction, widening, and separate C alarms. None prescribes this experiment’s five statuses or OCaml wrap semantics, while the output contract already fixes local coverage and precision-gain equations. **EC-14 — Expected:** the plan-selected domain overapproximates OCaml values; `numeric_covered` and `precision_gain_sites` obey the frozen equations and are not Eva alarm counts. **Unspecified:** which conformance property prevents a plan-selected domain from satisfying those equations while still producing a false `NONZERO` or false bottom on non-singleton transfers beyond the bounded examples.

15. **C-15 — Compiler-libs version sensitivity challenges accepted-input claims (US-1.4, US-3.2; divergent prior art: compiler version sensitivity).** Typedtree function representation and primitive representation have changed across OCaml releases, and compiler-libs promises no stable front-end API. Recording the compiler version is not itself proof that an artifact can be interpreted by the running tool. **EC-15 — Expected:** only trusted compatible implementation CMTs are accepted; incompatible, interface, packed, and partial annotations fail atomically, and the report records tool/compiler assumptions. **Unspecified:** the exact compatibility predicate and diagnostic distinction between wrong compiler version, unsupported annotation kind, malformed artifact, and a supported later compiler whose Typedtree shape differs.

16. **C-16 — Closed fields still leave representation and coordinate placeholders underdefined (US-3.1–4).** The output contract fixes the JSON shape and census equations, but `representation` may be null after a 256-byte identifier bound, invalid coordinates become null, cross-file ranges lose end coordinates, and free-form reasons/assumptions/limitations are strings. Two conforming renderers could therefore disagree byte-for-byte or conceal why metadata is absent. **EC-16 — Expected:** every accepted artifact and inventoried site is represented once; count equations hold; invalid/missing locations never fabricate coordinates; text is a semantic projection of JSON; empty owned-library output remains explicit and report-only. **Unspecified:** UTF-8 byte-boundary handling, the definition of invalid line/column/offset combinations, whether an overlong identifier is distinguishable from inherently unavailable spelling, the canonical reason vocabulary, and the exact semantic-equivalence oracle for text versus JSON.

## Challenge resolutions

Resolved by root under standing autonomous authorization, 2026-09-13. No new human answers or formal proof claimed. These close the existing bounded scope, not extend it. All C/EC references refer to spec-challenges.md.

| Challenge | Accepted resolution |
|---|---|
| C-1 | Only the immediate primitive-headed application is a site: later outer application does not duplicate it. All applicable eligibility reasons accumulate: unsupported_arity, unsupported_labels, missing_operand, unsupported_integer_kind. Exactly two Nolabel Some operands required. Unsupported ancestry adds its own reasons. |
| C-2 | Primitive identity comes only from resolved Val_prim. Numeric transfer and zero guards additionally require both operand types to resolve through compiler type expansion to Predef native int; no spelling-based type evidence. Unresolved types prevent numeric eligibility (unsupported_operand_type) or guard refinement respectively. Inventory remains identity-based. |
| C-3 | Reject symlink leaves before realpath. Deduplicate only canonical path strings; hard links/copies at different canonical paths remain distinct candidates and therefore fail the duplicate (module, source including null) check when that pair matches. Hash each unique accepted path before/after CMT read. No inode-based or content-based silent merging. Sort unique canonical paths before processing. |
| C-4 | Every bound is inclusive, breach means strictly greater. Bytes sum unique canonical files. Count every expression once in the full syntax traversal (including function defaults and unsupported subtrees); depth is nested expression count with top expression at 1. Site count is immediate recognized occurrences. Preflight traversal precedes interpretation. Serialize the entire result before stdout, enforce JSON UTF-8 byte size even in text mode, then enforce the same 16MiB bound on selected rendered output. No prefix output on any error. These are trusted-input limits, not deserialization sandboxing. |
| C-5 | outcome=empty_inventory iff total_sites=0; inputs and complete zero census remain present. Both formats include artifact-only scope and the limitation that indirect operations and omitted artifacts are not covered. Text explicitly says 'No matching immediate primitive occurrences in supplied artifacts.' Never say no division/safe/complete program. |
| C-6 | Neg/add/sub/mul overapproximate modular signed integers. Exact singleton results required only when mathematical result is representable; otherwise top allowed. Test oracle uses independent arbitrary-precision JS BigInt signed modular reduction for widths 3 through 8 exhaustively and selected 31/63 extrema; never native-number multiplication as oracle. Div/mod result top regardless inputs is accepted, including min_int/-1; divisor classification is separate and never executes concrete division. |
| C-7 | Each ZERO site includes reason divisor_zero_if_reached; NONZERO divisor_nonzero_if_reached; MAY_ZERO divisor_may_be_zero; UNREACHABLE contradictory_supported_branch. Global limitations explicitly disclaim guaranteed execution and confirmed failure; all successful reports exit 0. |
| C-8 | Use compiler Ident identity (Ident.same or equivalent exact stamp-aware key), never printed name. Unknown/captured/not-found bindings read top. Invalid artifact shape is input error, not guessed identity. Alpha-renaming preserves classifications. Simultaneous RHS environments are pre-group; bindings enter only body. Aliases copy values without retroactive relational refinement. |
| C-9 | Every encountered supported Texp_function starts fresh reachable state, parameters/captures top, including local function bindings, immediately-applied lambdas, curried/nested function nodes and structure declarations. No call-site specialization. Sticky lexical unsupported ancestry survives resets. Function creation does not propagate its body result into caller state. |
| C-10 | Accumulate all applicable unsupported causes from lexical ancestors and site eligibility, sorted unique. If any exist status UNSUPPORTED irrespective numeric bottom. Whole excluded subtree includes defaults, conditions, arms and nested functions; later sibling expressions outside it are not poisoned. |
| C-11 | Application dispatch: sequand/sequor means unsupported subtree; %perform/%resume/%runstack/%reperform means unsupported_effect_primitive subtree; recognized div/mod uses C-1/C-2 eligibility and independently visits operands; eligible closed arithmetic returns abstract transfer; ordinary/unlisted/indirect applications return top and independently visit head/arguments in incoming environment. Malformed numeric transfer returns top (and recognized div/mod site remains unsupported). Methods/effect-specific structural nodes are excluded constructors, not ordinary applications. No evaluation-order or termination inference. |
| C-12 | Status precedence is eligibility/lexical failure -> UNSUPPORTED; otherwise unreachable supported state -> UNREACHABLE; otherwise value exactly {0} -> ZERO; excludes 0 -> NONZERO; includes 0 and nonzero -> MAY_ZERO. A bottom value must not be invented from unsupported/unknown operations; only the frozen supported branch contradictions may establish unreachable. |
| C-13 | No loop/recursion interpretation or fixpoint/widening engine in V1; loop condition/body and every nested expression remain unsupported. Domain join/top are allowed and are not iterative widening. No unused widening API/test requirement. This is a deliberate bounded experiment, not an adoption of Infer's loop coverage. |
| C-14 | Every transfer must satisfy concrete containment for its whole represented input sets, not just singleton examples. Plan must document concretization, restriction and join. Tests exhaust all values represented by small-width abstract samples (including non-singletons/top), restriction soundness, bottom/join laws and classification exclusions; high-width boundary samples supplement, not prove, universal soundness. Census consistency alone is insufficient. Eva/Goblint concepts are reused without importing C alarm semantics or coverage claims. |
| C-15 | Compatibility is acceptance by the linked compiler's Cmt_format reader and its magic/version checks, plus Implementation annotation. Record Sys.ocaml_version and trusted same-compiler/target assumption; do not claim exact producer patch version can be independently recovered. Diagnose incompatible magic/version, unsupported annotation, malformed/read failure separately where reader exposes that distinction; unknown reader failures use malformed/read failure, no guessed mismatch. Compiler upgrades require rebuild and fixture gates; no forward-compatible serialized ABI claim. |
| C-16 | No UTF-8 truncation: identifier spelling exceeding 256 bytes becomes null with operand_spelling_omitted reason. Other/missing spelling inherently null. Position valid only if line>=1, bol>=0, cnum>=bol; then column=cnum-bol+1 and offset=cnum, else all three null. Empty filename -> null. Cross-file or backwards end range -> end coordinates null. Invalid position/range adds location_unavailable; ghost adds ghost_location without invalidating coordinates. Text check compares every site's artifact/id/status/primitive/reasons and every census count to JSON from same fixture, plus scope warnings, not typography. |

## Closed reasons

Semantic: divisor_nonzero_if_reached, divisor_zero_if_reached, divisor_may_be_zero, contradictory_supported_branch.
Eligibility: unsupported_arity, unsupported_labels, missing_operand, unsupported_integer_kind, unsupported_operand_type.
Lexical: unsupported_function_parameters, unsupported_function_cases, unsupported_recursive_binding, unsupported_binding_pattern, unsupported_short_circuit, unsupported_effect_primitive, unsupported_expression:<Typedtree constructor name>.
Metadata: operand_spelling_omitted, location_unavailable, ghost_location.
Every site has at least a semantic or unsupported reason; metadata may supplement either. Reason strings are sorted and unique. Constructor suffix is the compiler constructor name, no stamps or arbitrary source snippets.

## Remaining engineering choice

Domain representation and decomposition remain plan decisions within these requirements. No unresolved product question. questions_asked_step2=0; questions_asked_step5=0. Human quiz skipped under the user's explicit full-pipeline autonomy, not represented as a quiz performed or fresh explicit spec approval.

## Output contract

Normative output shape. Not implemented at specification approval.

## CLI

`arch-guard --cmt FILE [--cmt FILE ...] [--format text|json]`.
At least one explicit input. Binary public name arch_guard; root arch-guard only dispatches existing built binary, no build/install side effect.
Default text; help/version0; all usage/input/internal errors2, stderr diagnostic, empty stdout.
All successful classified/empty results0, irrespective semantic statuses; report-only, not policy.

## Closed JSON schema version1

Top-level fields exactly: schema_version, tool, analysis, outcome, inputs, sites, census.

- schema_version: integer1.
- tool: {name:"arch-guard", version:"0.1.0", compiler_version:string, int_bits:31|63}.
- analysis: {mode:"experimental-report-only", fragment:"ocaml-int-acyclic-v1", domain:string, assumptions:string[], limitations:string[]}. Domain name frozen in plan; assumptions expressly trusted same-compiler/target CMT, artifact-only scope, no source freshness certificate. Limitations expressly no whole-program/guaranteed execution/machine-checked proof; unsupported fragment and no interprocedural/heap reasoning.
- outcome: "empty_inventory" iff sites.length0; otherwise "classified".
- inputs: sorted by canonical physical path. Each {path:string,sha256:64lowerhex,module:string,source:string|null,bytes:nonnegative integer}. No timestamps, compiler binder stamps or Git state needed for explicit-content inputs.
- sites: sorted by input path, location.start.offset(null sorts before valid), location.end.offset(null first), primitive, id. Each exact fields:
  {artifact:string,id:positive integer,primitive:string,integer_kind:"int"|"int32"|"int64"|"nativeint",
   operand:{slot:2,category:"integer_literal"|"identifier"|"other"|"missing",representation:string|null},
   location:{file:string|null,start:{line:positive integer|null,column:positive integer|null,offset:nonnegative integer|null},end:{line:positive integer|null,column:positive integer|null,offset:nonnegative integer|null},ghost:boolean},
   status:"NONZERO"|"ZERO"|"MAY_ZERO"|"UNREACHABLE"|"UNSUPPORTED",reasons:string[]}.
- id is one-based inventory preorder ordinal within that artifact; unique per artifact, repeat-run deterministic only, NOT a cross-build finding fingerprint.
- primitive exactly one of %divint,%modint,%int32_div,%int32_mod,%int64_div,%int64_mod,%nativeint_div,%nativeint_mod; integer_kind determined from this mapping.
- representation literal: compiler literal decimal string; identifier: bounded printed long identifier up to256UTF8bytes, otherwise null; other/missing:null. Literal kind metadata remains even if unsupported numerically; no operand evaluation for syntax.
- Source file/location come from full application location. Invalid coordinates null, ghost retained; id still disambiguates duplicates. If start/end filenames differ keep start file and null out end coordinates to avoid falsely projecting a range into one file.
- reasons: sorted unique nonempty strings explaining status. NONZERO/ZERO/MAY_ZERO/UNREACHABLE explain conditional modeled meaning; UNSUPPORTED must name the responsible syntax/arity/integer-family rule. Reasons do not contain absolute timestamps or nondeterministic stamps.
- census exactly {artifacts,total_sites,numeric_covered,nonzero,zero,may_zero,unreachable,unsupported,precision_gain_sites}, allnonnegativeintegers; artifacts=inputs.length,total_sites=sites.length,numeric_covered=nonzero+zero+may_zero+unreachable,total_sites=numeric_covered+unsupported,precision_gain_sites=nonzero+unreachable. Precision gain is classification beyond syntax, not a measured production defect rate.

Text is a human-readable projection of the same result: input count/scope,int width,one line per site with status/primitive/location/reason,then all census counts and report-only/conditional-result warning; empty report states explicit zero inventory. Text/JSON agree semantically, no separate evaluator.

## Whole-invocation fail-closed boundaries

Validate/dedupe/sort inputs before output. Reject absent/unreadable/nonregular/symlink leaf, unsupported CMT annotation, compiler mismatch or changed read, duplicate module/source tuple across distinct artifacts. Explicit no hard process memory/time isolation guarantee; files are trusted local compiler artifacts.
128unique inputs,32MiBperfile,256MiBtotal,100000expression nodes,10000sites,AST recursion512; no truncation. JSON16MiB bound before stdout.
Numeric unsupported does not abort the whole report; malformed input or breached resource limit does.

## Functional Requirements

### US-1 — Attributable primitive inventory

- **FR-001** [US-1; US-1.1; C-1; AC-4]: When a maintainer supplies accepted implementation CMT artifacts, the inventory pass MUST record exactly one site for every `Texp_apply` whose immediate head resolves as `Texp_ident Val_prim` to one of `%divint`, `%modint`, `%int32_div`, `%int32_mod`, `%int64_div`, `%int64_mod`, `%nativeint_div`, or `%nativeint_mod`, including ineligible and unsupported occurrences.
- **FR-002** [US-1; US-1.1; C-1; AC-4]: When a recognized immediate primitive application is later used as the callee of another application, the inventory MUST count only that immediate primitive-headed application and MUST NOT invent a second site for later saturation.
- **FR-003** [US-1; US-1.1; C-1; AC-4]: For each inventoried site, the classifier MUST require exactly two `Nolabel`, present operands for numeric eligibility and MUST accumulate, sort, and deduplicate every applicable eligibility reason from `unsupported_arity`, `unsupported_labels`, `missing_operand`, and `unsupported_integer_kind`; unsupported lexical reasons MUST additionally remain visible.
- **FR-004** [US-1; US-1.1; Q-6; AC-1]: For every site, the inventory MUST preserve the original second operand slot and categorize it as `integer_literal`, `identifier`, `other`, or `missing`; it MUST NOT shift another argument into a missing second slot.
- **FR-005** [US-1; US-1.2; C-2; AC-5]: The inventory actor MUST identify target operations only from resolved compiler primitive identity and MUST NOT infer primitive identity or integer family from source spelling or binder names, so a shadowed operator is excluded while a genuine primitive remains inventoried.
- **FR-006** [US-1; US-1.1; C-2; AC-5]: For native-int numeric eligibility and zero-guard refinement, the analyzer MUST require both operand types to expand through compiler type information to the predefined native `int`; unresolved or non-native types MUST prevent the respective numeric interpretation without removing the inventory site.
- **FR-007** [US-1; US-1.3; C-3; AC-6]: Before processing, the CLI MUST reject symlink leaves, canonicalize candidate paths, deduplicate only identical canonical path strings, sort the remaining paths, and process each accepted canonical path once, so argument reversal and repetition do not change report bytes or counts.
- **FR-008** [US-1; US-1.3; C-3; AC-6]: Distinct canonical paths, including hard links and copies, MUST remain distinct candidates; if two accepted candidates have the same `(module, source)` tuple, the CLI MUST reject the invocation rather than merge or count them.
- **FR-009** [US-1; US-1.3; Q-7; C-3; AC-6]: Each accepted input MUST be attributed by canonical path and lowercase SHA-256 digest, hashed before and after CMT reading; a changed digest MUST fail the whole invocation, without implying adversarial filesystem atomicity.
- **FR-010** [US-1; US-1.4; C-4; C-15; AC-7; AC-18]: When any input, compatibility, annotation, read, traversal, serialization, or output condition fails, the CLI MUST exit `2`, emit a diagnostic on stderr, emit exactly empty stdout, and MUST NOT publish a successful prefix or truncated report.
- **FR-011** [US-1; US-1.4; C-15; AC-18]: The CLI MUST accept only regular, readable implementation annotations accepted by its linked compiler CMT reader and MUST reject interfaces, packed or partial annotations, incompatible magic/version, malformed reads, and changed inputs; diagnostics MUST distinguish cases when the reader exposes the distinction and MUST NOT guess a version mismatch from an unknown read failure.
- **FR-012** [US-1; US-1.5; C-5; AC-8]: When no immediate target primitive occurs, the report MUST set `outcome` to `empty_inventory`, retain accepted input attribution and an all-zero site census, and state `No matching immediate primitive occurrences in supplied artifacts.`; it MUST NOT state or imply “no division,” safety, or whole-program completeness.
- **FR-013** [US-1; Q-7; C-16; AC-19]: Within each artifact, the inventory MUST assign each site its one-based preorder occurrence ordinal and MUST scope that ID to the artifact path and digest; it MUST NOT present the ordinal as a cross-build fingerprint.
- **FR-014** [US-1; Q-7; C-16; AC-19]: The report MUST sort sites by artifact path, start offset with null before valid, end offset with null before valid, primitive, then ID, and MUST retain ghost or invalid-location sites rather than fabricate coordinates.

### US-2 — Bounded numeric classification

- **FR-015** [US-2; US-2.1; C-12; AC-2; AC-15]: For a numerically eligible native-int site in a supported lexical region, the classifier MUST apply this precedence: unreachable supported state yields `UNREACHABLE`; otherwise an abstract divisor exactly `{0}` yields `ZERO`; a divisor excluding zero yields `NONZERO`; and a divisor including zero and at least one nonzero value, including top, yields `MAY_ZERO`.
- **FR-016** [US-2; US-2.6; C-10; C-12; AC-13; AC-15]: If site eligibility fails or any unsupported lexical ancestry applies, the classifier MUST emit `UNSUPPORTED` regardless of numeric bottom or other facts, retain the site, and include all applicable sorted unique unsupported reasons.
- **FR-017** [US-2; US-2.1; Q-4; AC-2]: Given supported reachable expressions, literal `2` and a local variable or alias currently bound to `2` MUST classify as `NONZERO`, literal `0` MUST classify as `ZERO`, and an unrestricted native-int parameter MUST classify as `MAY_ZERO`.
- **FR-018** [US-2; US-2.2; Q-4; AC-2]: For direct native-int identifier comparisons against literal zero, in either operand order, under resolved `%equal`, `%notequal`, `%eq`, or `%noteq`, the analyzer MUST restrict the corresponding branches; pure boolean literals MUST restrict reachability, while other predicates MUST retain both branches without promised normalization.
- **FR-019** [US-2; US-2.2; C-8; AC-11]: Numeric facts and restrictions MUST attach to exact compiler binder identity, never printed spelling; an unknown, captured, or unbound identity MUST read as top, while an invalid artifact identity shape MUST fail input processing rather than be guessed.
- **FR-020** [US-2; US-2.2; C-8; AC-11]: A supported nonrecursive local `let` with variable or wildcard patterns MUST evaluate simultaneous RHS expressions in the pre-group environment and expose bindings only in the body; aliases MUST copy the current abstract value without retroactive relational refinement, and shadowing MUST NOT inherit facts from a prior binder of the same spelling.
- **FR-021** [US-2; US-2.3; Q-4; AC-2]: Supported branch joins MUST overapproximate both reachable branches, including classifying a join of `0` and `2` as `MAY_ZERO`; only a false literal branch or contradictory supported zero restrictions MAY establish bottom and `UNREACHABLE`.
- **FR-022** [US-2; US-2.4; C-6; C-14; AC-9; AC-17]: Abstract negation, addition, subtraction, and multiplication MUST overapproximate their complete represented input sets under signed modular OCaml integers at the selected width, MUST retain exact singleton results when the mathematical result is representable, and MUST include zero or widen when wrap may yield zero; they MUST NOT use unbounded arithmetic to justify false `NONZERO` or false bottom.
- **FR-023** [US-2; US-2.4; C-6; AC-9]: Divisor classification MUST NOT execute concrete division by zero; abstract division and remainder results MAY be top for all inputs, including `min_int / -1`, without weakening the independently computed divisor status.
- **FR-024** [US-2; US-2.4; C-14; AC-17]: The selected domain MUST define concretization, branch restriction, and join such that transfers contain all concrete results for represented inputs, restrictions are sound, bottom remains distinct from top, and join laws hold; satisfying census equations alone MUST NOT count as numeric conformance.
- **FR-025** [US-2; US-2.5; C-9; AC-12]: Every supported function body encountered—local, immediately applied, curried, nested, or structure-level—MUST start a fresh reachable entry with parameters and captures at top and MUST NOT inherit caller branch reachability or numeric refinements; locals established inside that entry MAY provide new facts.
- **FR-026** [US-2; US-2.5; C-9; AC-12]: Unsupported lexical ancestry MUST remain sticky across nested-function entry resets, and function-body results MUST NOT propagate numeric state back into the enclosing expression.
- **FR-027** [US-2; US-2.6; Q-1; Q-3; Q-5; AC-13]: Optional/default or refutable/compound function parameters, function cases, recursive binding subtrees, compound/alias/refutable/or-pattern local lets, matches, handlers, loops, let-operators, lazy/object/record/array/field-mutation/local-module/extension constructs, effects (including `%perform`, `%resume`, `%runstack`, `%reperform` primitive application subtrees), and `%sequand`/`%sequor` subtrees MUST be treated as unsupported lexical regions, including their nested expressions; later independent siblings MUST NOT be poisoned.
- **FR-028** [US-2; US-2.6; C-13; AC-16]: V1 MUST NOT derive any semantic status from loop iteration, recursive evaluation, fixpoints, guessed bounds, unrolling, or widening; join and top remain permitted non-iterative domain operations.
- **FR-029** [US-2; US-2.7; C-11; AC-14]: Ordinary, unlisted, and indirect applications MUST return top without callee expansion and MUST visit head and arguments independently in the incoming immutable environment; therefore an eligible divisor produced by an opaque ordinary call MUST classify `MAY_ZERO` unless unsupported ancestry applies.
- **FR-030** [US-2; US-2.7; C-11; AC-14]: Recognized div/mod applications MUST inventory and independently visit operands even when malformed; supported closed arithmetic applications MUST use their abstract transfers; methods and effect-specific structural nodes MUST remain excluded constructs rather than ordinary applications.
- **FR-031** [US-2; US-2.1; US-2.7; C-7; AC-10]: Every numerically supported site MUST carry its closed conditional semantic reason—`divisor_nonzero_if_reached`, `divisor_zero_if_reached`, `divisor_may_be_zero`, or `contradictory_supported_branch`—and a successful report containing any status MUST exit `0`; `ZERO` MUST NOT be presented as proof of execution or a confirmed failure.
- **FR-032** [US-2; US-2.8; AC-2]: Adding arch-guard MUST NOT change arch-index extraction behavior, existing rule verdicts, origin corpus/reference data, or existing self-index counts.

### US-3 — Interpretable experiment result

**V1 public-boundary clarification (R1):** Only the installed `arch_guard` executable and root `arch-guard` dispatcher are supported public interfaces. `lib/arch_guard` is a private Dune implementation library linking the executable and local test probes, not an installed `arch-index.guard` embedding API. Its render functions are internal; compiler-libs global state may be reset within the command process. Host-process restoration and a new subprocess/serialization embedding API are not promised.

- **FR-033** [US-3; US-3.1; C-16; AC-3; AC-19]: A successful invocation MUST render one complete result in the selected `text` or `json` format, and both renderers over the same inputs MUST agree on every site's artifact, ID, status, primitive, reasons, every census count, and artifact-only/report-only scope warnings.
- **FR-034** [US-3; US-3.2; AC-3]: The public CLI MUST accept `arch-guard --cmt FILE [--cmt FILE ...] [--format text|json]`, default to text, require at least one explicit input, provide help/version with exit `0`, reject unknown or bad arguments with exit `2`, and MUST NOT scan, build, execute, write a database, or offer an output-file mutation path.
- **FR-035** [US-3; US-3.2; AC-3]: The root `arch-guard` entry MUST only dispatch an existing built public binary named `arch_guard` and MUST NOT build or install it as a side effect.
- **FR-036** [US-3; US-3.2; C-5; C-7; C-15; AC-8; AC-10; AC-18]: Every successful report MUST explicitly scope conclusions to supplied accepted artifacts, record the linked compiler version and host `Sys.int_size` as `31` or `63`, state the trusted same-compiler/same-target and no-source-freshness assumptions, and state limitations excluding whole-program completeness, guaranteed execution, confirmed failure, machine-checked proof, interprocedural reasoning, and heap reasoning.
- **FR-037** [US-3; US-3.1; spec-output-contract; AC-3]: JSON schema version `1` MUST contain exactly the top-level fields `schema_version`, `tool`, `analysis`, `outcome`, `inputs`, `sites`, and `census`; `tool` MUST be exactly `{name:"arch-guard", version:"0.1.0", compiler_version:string, int_bits:31|63}` and `analysis` MUST be exactly `{mode:"experimental-report-only", fragment:"ocaml-int-acyclic-v1", domain:string, assumptions:string[], limitations:string[]}`.
- **FR-038** [US-3; US-3.1; spec-output-contract; AC-3]: Each JSON input MUST contain exactly `{path, sha256, module, source, bytes}` with the accepted types and each JSON site MUST contain exactly `{artifact,id,primitive,integer_kind,operand,location,status,reasons}` with the closed primitive, integer-kind, operand-category, status, and coordinate types defined by the accepted output contract; no timestamps, Git state, compiler binder stamps, or additional fields MAY appear.
- **FR-039** [US-3; US-3.1; C-16; AC-19]: Identifier representation MUST be a complete printed long identifier of at most 256 UTF-8 bytes or null with `operand_spelling_omitted`; it MUST NOT truncate UTF-8. Other or missing operands MUST use null representation, while integer literals MUST preserve the compiler decimal literal string.
- **FR-040** [US-3; US-3.1; C-16; AC-19]: A source position is valid only when line is at least `1`, beginning-of-line offset is nonnegative, and absolute offset is at least that offset; valid columns MUST be one-based and equal `cnum - bol + 1`, otherwise line/column/offset MUST all be null and `location_unavailable` MUST be present. Empty filenames MUST be null; cross-file or backwards ranges MUST null end coordinates; ghost locations MUST add `ghost_location` without invalidating otherwise valid coordinates.
- **FR-041** [US-3; US-3.1; C-10; C-16; AC-13; AC-19]: Every site MUST have a sorted unique nonempty `reasons` array drawn only from the closed semantic, eligibility, lexical, and metadata vocabularies; `unsupported_expression:<Typedtree constructor name>` MUST use only the compiler constructor name and MUST NOT embed stamps or arbitrary source text.
- **FR-042** [US-3; US-3.1; C-14; AC-17]: The census MUST contain exactly `artifacts`, `total_sites`, `numeric_covered`, `nonzero`, `zero`, `may_zero`, `unreachable`, `unsupported`, and `precision_gain_sites`, all nonnegative integers satisfying `artifacts = inputs.length`, `total_sites = sites.length`, `numeric_covered = nonzero + zero + may_zero + unreachable`, `total_sites = numeric_covered + unsupported`, and `precision_gain_sites = nonzero + unreachable`; the last value MUST be described as classification beyond syntax, not a production defect rate.
- **FR-043** [US-3; US-3.2; AC-3]: Text output MUST show input count and artifact scope, integer width, one line per site with status/primitive/location/reason, all census counts, and the conditional/report-only warning; it MUST be a projection of the same result as JSON and MUST NOT run a separate evaluator.
- **FR-044** [US-3; US-3.4; C-4; AC-7]: The CLI MUST allow at most 128 unique canonical inputs, 32 MiB per file, 256 MiB across unique files, 100,000 expression nodes per invocation, 10,000 immediate sites, recursion depth 512, 16 MiB for the complete JSON serialization even in text mode, and 16 MiB for the selected rendered output; each bound is inclusive and a value strictly greater MUST fail atomically.
- **FR-045** [US-3; US-3.4; C-4; AC-7]: The preflight traversal MUST precede interpretation, count every expression exactly once including defaults and unsupported subtrees, define the top expression depth as `1`, and count sites as immediate recognized occurrences; the CLI MUST fully serialize and bound the result before writing stdout.
- **FR-046** [US-3; US-3.4; Q-8; AC-7]: Resource limits MUST be presented as deterministic trusted-input bounds and MUST NOT be described as a hard operating-system time/memory or hostile-deserialization sandbox; an external checker invocation MUST impose its separate 120-second and 16 MiB subprocess-output caps.
- **FR-047** [US-3; US-3.3; C-5; AC-3; AC-8]: When the experiment is run on owned `lib/arch_index` artifacts, the reviewer MUST receive the actual artifact/site/status census even when total sites are zero, and the corpus MUST NOT be broadened automatically to manufacture precision or impact.

## Acceptance Criteria

- **AC-1** [US-1 happy path; US-1.1–3]: Supplying a compiled fixture containing all eight immediate primitive identities, native operand categories, a partial primitive, a shadowed operator, and repeated/reversed input paths → every genuine immediate occurrence appears once with stable attribution and slot-2 syntax metadata, the shadowed call is absent, and both input orders produce byte-identical JSON.
- **AC-2** [US-2 happy path; US-2.1–8]: Analyzing the owned native fixture and domain vectors → literals, aliases, guards, joins, contradictory branches, opaque calls, nested functions, shadowing, unsupported regions, and wrapped arithmetic produce exactly the required five-way conditional statuses while all existing arch-index regression gates remain unchanged except the user-authorized source-growth calibration of the whole-repository MUST-null pin383→430 (2026-09-13 resume; query/headroom25 unchanged; attribution in roster/guard-division-analysis/ratchet-source-growth.md). FR-032's existing-library self-index counts and extraction/rule/reference semantics remain unchanged.
- **AC-3** [US-3 happy path; US-3.1–4]: Rendering the same accepted fixture as JSON and text and running the owned-library experiment → the closed metadata/site/census contract agrees semantically, reports actual owned counts including zero, includes limitations, and succeeds with exit `0` without nondeterministic data.
- **AC-4** [US-1, C-1, EC-1]: A recognized primitive with later saturation, missing slots, labels, over-application, or unsupported ancestry → exactly the immediate application contributes once and is retained as `UNSUPPORTED` with every applicable sorted unique reason.
- **AC-5** [US-1, C-2, EC-2]: Shadowed spelling, genuine `Val_prim`, and resolved/unresolved/non-native operand types → only compiler-resolved primitive heads enter inventory, and numeric or guard eligibility occurs only for type-expanded native-int operands.
- **AC-6** [US-1, C-3, EC-3]: Repeated aliases of one canonical path and distinct hard-link/copy paths with duplicate module/source identity → canonical repeats deduplicate deterministically, while distinct conflicting artifacts fail atomically rather than merge.
- **AC-7** [US-1, US-3, C-4, EC-4]: Exercising each exact and one-over resource boundary plus a late malformed/changed input → inclusive boundary values may complete, every breach exits `2` with stderr and exactly empty stdout, and neither JSON nor text is truncated.
- **AC-8** [US-1, US-3, C-5, EC-5]: Supplying accepted artifacts with zero immediate target sites → both formats retain input scope and zero census, JSON says `empty_inventory`, text uses the exact empty-inventory sentence, and neither format implies program safety or completeness.
- **AC-9** [US-2, C-6, EC-6]: Comparing abstract neg/add/sub/mul with an independent arbitrary-precision signed modular oracle exhaustively at widths 3–8 and at selected 31/63-bit extrema → every concrete result is contained, wrap-to-zero is never classified nonzero, and divisor handling never performs concrete division by zero.
- **AC-10** [US-2, C-7, EC-7]: Reporting literal-zero and other statuses → each site has the required conditional reason, global limitations deny guaranteed execution/confirmed failure, and report production exits `0` irrespective of status.
- **AC-11** [US-2, C-8, EC-8]: Exercising alpha-renaming, same-spelling shadowing, simultaneous groups, and aliases before/inside a refined branch → facts follow compiler identity, group RHSs see only the pre-group environment, shadowing does not leak, and aliases copy only their binding-time value.
- **AC-12** [US-2, C-9, EC-9]: Placing nested, curried, immediately applied, local, and structure-level functions beneath nonzero, contradictory, and unsupported ancestry → supported function entries reset reachability and captures to top, while unsupported ancestry remains sticky and inner locals can still establish facts only in supported entries.
- **AC-13** [US-2, C-10, EC-10]: Placing sites under one or multiple unsupported causes and modeled bottom → every site remains inventoried as `UNSUPPORTED`, all causes are sorted/deduplicated, and later supported siblings are unaffected.
- **AC-14** [US-2, C-11, EC-11]: Exercising ordinary, unlisted, indirect, malformed known, short-circuit, method, and effect-related application shapes with nested target operands → dispatch follows the closed categories, opaque eligible results become `MAY_ZERO`, and excluded ancestry becomes `UNSUPPORTED` while nested inventory remains complete.
- **AC-15** [US-2, C-12, EC-12]: Enumerating supported reachable top, exact-zero, zero-excluding, mixed, bottom, ineligible, and unsupported-ancestry combinations → statuses follow the frozen precedence table with no unknown operation inventing bottom.
- **AC-16** [US-2, C-13, EC-13]: Putting target sites anywhere within loop and recursive-evaluation regions → all such expressions remain `UNSUPPORTED`, and no status is justified through fixpoint, unrolling, guessed bounds, or widening.
- **AC-17** [US-2, US-3, C-14, EC-14]: Checking non-singleton/top transfer containment, restriction soundness, bottom/join laws, and census equations → numeric conformance fails on any false exclusion or false bottom even when census arithmetic remains valid.
- **AC-18** [US-1, US-3, C-15, EC-15]: Supplying compatible implementation CMTs and each exposed incompatible/unsupported/malformed annotation class → only compatible implementations succeed, failures are atomic and diagnosed at the reader's supported granularity, and reports record the linked compiler/trusted-build assumptions without claiming forward ABI compatibility.
- **AC-19** [US-1, US-3, C-16, EC-16]: Exercising missing/invalid/ghost/cross-file locations, overlong/missing operand spellings, all reason classes, and duplicate coordinates → every site remains uniquely represented, no UTF-8 or coordinate is fabricated, reason vocabulary and sorting are exact, and text/JSON agree on required semantic fields and counts.

- **AC-20** [US-3, C-5, FR-036; R2 ratchet]: Reporting owned empty and classified artifacts through the actual CLI in both formats → compiler version, integer width, trusted-build/no-source-freshness assumptions, and all shared limitations are present, explicitly denying coverage of indirect operations and omitted artifacts. The standalone regression must fail by assertion on the recorded pre-fix revision and pass on the corrected implementation.

## FR-to-AC trace matrix

| Acceptance criterion | Functional requirements |
|---|---|
| AC-1 | FR-001, FR-004, FR-005, FR-007, FR-009 |
| AC-2 | FR-015, FR-017, FR-018, FR-021, FR-032 |
| AC-3 | FR-033, FR-034, FR-035, FR-037, FR-038, FR-043, FR-047 |
| AC-4 | FR-001, FR-002, FR-003 |
| AC-5 | FR-005, FR-006 |
| AC-6 | FR-007, FR-008, FR-009 |
| AC-7 | FR-010, FR-044, FR-045, FR-046 |
| AC-8 | FR-012, FR-036, FR-047 |
| AC-9 | FR-022, FR-023 |
| AC-10 | FR-031, FR-036 |
| AC-11 | FR-019, FR-020 |
| AC-12 | FR-025, FR-026 |
| AC-13 | FR-016, FR-027, FR-041 |
| AC-14 | FR-029, FR-030 |
| AC-15 | FR-015, FR-016 |
| AC-16 | FR-028 |
| AC-17 | FR-022, FR-024, FR-042 |
| AC-18 | FR-010, FR-011, FR-036 |
| AC-19 | FR-013, FR-014, FR-033, FR-039, FR-040, FR-041 |
| AC-20 | FR-012, FR-033, FR-036, FR-043 |

Every FR appears in at least one matrix row; the bracketed citations on each FR identify its originating story scenario and/or resolved challenge.

## Runnable Checks

The following commands are implemented checker interfaces. Run a full `dune build --root .` first, under the configured compiler environment, to build the CLI and private probes. Every mode MUST use exit `0` for pass, `1` for a contract assertion failure, and an exit code of at least `2` for checker setup, execution, timeout, malformed-fixture, or internal error. The checker MUST cap each spawned process at 120 seconds and 16 MiB of captured output.

- **CHECK-1** [AC-1, AC-4, AC-5, AC-6]: `rtk proxy node scripts/check-arch-guard.js inventory` → compiles/uses the inventory fixture and independently checks primitive identity, immediate-site uniqueness, original slot 2, shadow exclusion, stable ordering, canonical deduplication, and collision failure.
- **CHECK-2** [AC-2, AC-10, AC-11, AC-12, AC-13, AC-14, AC-15, AC-16]: `rtk proxy node scripts/check-arch-guard.js numeric` → checks the five-status precedence and closed reasons across aliases, guards, joins, binder scope, fresh function entries, opaque calls, unsupported ancestry, and non-iterative exclusions.
- **CHECK-3** [AC-9, AC-17]: `rtk proxy node scripts/check-arch-guard.js domain` → uses an independent JS `BigInt` signed-modular oracle for exhaustive widths 3–8 plus selected 31/63-bit extrema, non-singleton/top containment, restriction soundness, bottom/join laws, and wrap-to-zero cases.
- **CHECK-4** [AC-6, AC-7, AC-18]: `rtk proxy node scripts/check-arch-guard.js inputs` → checks canonical path rules, symlink rejection, duplicate module/source rejection, hash-change handling, annotation compatibility classes, every inclusive/one-over input and traversal limit, atomic stderr diagnostics, exit `2`, and exactly empty stdout.
- **CHECK-5** [AC-3, AC-7, AC-8, AC-10, AC-13, AC-19]: `rtk proxy node scripts/check-arch-guard.js report` → validates exact JSON keys/types/enums/order, census equations, reason vocabulary, location/spelling rules, empty-inventory wording, conditional limitations, full-buffer size failures, and semantic text/JSON agreement.
- **CHECK-6** [AC-3, AC-8]: `rtk proxy node scripts/check-arch-guard.js owned` → runs the built CLI on the explicitly selected owned `lib/arch_index` artifacts and checks that the actual artifact/site/status census is reported honestly, including a zero-site result, without adding another corpus.
- **CHECK-7** [AC-20]: `rtk proxy node scripts/check-guard-report-context.js` → independently checks actual empty/classified CLI JSON and text for the complete shared compiler, assumption, and limitation context; no arguments or external corpus.

The checker modes are independently invocable: no mode's pass result depends on another mode having run first. Fixture compilation or discovery needed by a mode is part of that mode's setup and setup failure is an execution error (`>=2`), never an assertion failure.

### R1 correction obligations (existing FR/AC retained)

CHECK-1 must explicitly exercise later saturation, overapplication, labelled and missing-original-slot operands, combined unsupported ancestry, unresolved/non-native types, and byte-identical reversal of distinct accepted inputs. CHECK-2 must cover the complete binding/function-entry/exclusion cases of AC-11 through AC-16 with exact reason arrays, not status counts alone. CHECK-5 must enforce status-specific semantic reasons, reject numeric-only reasons for UNSUPPORTED, compare every required text site field and census with JSON, and include wrong-reason and omitted-text-field negative controls; duplicate coordinates and 256/257 UTF-8-byte spelling boundaries remain required. Public installation tests must verify CLI presence, private library absence, and working private probes.

The self-contained R1 regression is now CHECK-7 / AC-20. Only that file is overlaid into pre-fix revision `d44c0c6ae8f4991549f6de5bbc2bdb3f24eb25ec`; authentic RED must be an assertion failure, not a build/setup failure. R2 full convergence gate verified RED and current GREEN, with unchanged check blob `8108aa657905871c8693120bb3168ce40b9d6c0f` (see `briefs/guard-division-analysis-gate-report.json`). This executable ratchet is not a formal proof. Existing 47 FRs, the original 19 ACs, numeric fragment and closed JSON schema are unchanged; AC-20 adds permanent regression coverage of existing obligations.


## Claims Metadata

Metadata remains draft: no installed claims reconciler/authority, so deterministic validation/projection is unavailable. No active evidence tier claimed.

```claims
{"record":"claims-header","schema_version":1,"namespace":"guard-division-analysis","spec_lifecycle":"draft"}
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
{"record":"requirement","id":"FR-039","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-040","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-041","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-042","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-043","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-044","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-045","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-046","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-047","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"acceptance-criterion","id":"AC-1","for":["FR-001","FR-004","FR-005","FR-007","FR-009"]}
{"record":"acceptance-criterion","id":"AC-2","for":["FR-015","FR-017","FR-018","FR-021","FR-032"]}
{"record":"acceptance-criterion","id":"AC-3","for":["FR-033","FR-034","FR-035","FR-037","FR-038","FR-043","FR-047"]}
{"record":"acceptance-criterion","id":"AC-4","for":["FR-001","FR-002","FR-003"]}
{"record":"acceptance-criterion","id":"AC-5","for":["FR-005","FR-006"]}
{"record":"acceptance-criterion","id":"AC-6","for":["FR-007","FR-008","FR-009"]}
{"record":"acceptance-criterion","id":"AC-7","for":["FR-010","FR-044","FR-045","FR-046"]}
{"record":"acceptance-criterion","id":"AC-8","for":["FR-012","FR-036","FR-047"]}
{"record":"acceptance-criterion","id":"AC-9","for":["FR-022","FR-023"]}
{"record":"acceptance-criterion","id":"AC-10","for":["FR-031","FR-036"]}
{"record":"acceptance-criterion","id":"AC-11","for":["FR-019","FR-020"]}
{"record":"acceptance-criterion","id":"AC-12","for":["FR-025","FR-026"]}
{"record":"acceptance-criterion","id":"AC-13","for":["FR-016","FR-027","FR-041"]}
{"record":"acceptance-criterion","id":"AC-14","for":["FR-029","FR-030"]}
{"record":"acceptance-criterion","id":"AC-15","for":["FR-015","FR-016"]}
{"record":"acceptance-criterion","id":"AC-16","for":["FR-028"]}
{"record":"acceptance-criterion","id":"AC-17","for":["FR-022","FR-024","FR-042"]}
{"record":"acceptance-criterion","id":"AC-18","for":["FR-010","FR-011","FR-036"]}
{"record":"acceptance-criterion","id":"AC-19","for":["FR-013","FR-014","FR-033","FR-039","FR-040","FR-041"]}
{"record":"acceptance-criterion","id":"AC-20","for":["FR-012","FR-033","FR-036","FR-043"]}
{"record":"check","id":"CHECK-1","for":["AC-1","AC-4","AC-5","AC-6"]}
{"record":"check","id":"CHECK-2","for":["AC-2","AC-10","AC-11","AC-12","AC-13","AC-14","AC-15","AC-16"]}
{"record":"check","id":"CHECK-3","for":["AC-9","AC-17"]}
{"record":"check","id":"CHECK-4","for":["AC-6","AC-7","AC-18"]}
{"record":"check","id":"CHECK-5","for":["AC-3","AC-7","AC-8","AC-10","AC-13","AC-19"]}
{"record":"check","id":"CHECK-6","for":["AC-3","AC-8"]}
{"record":"check","id":"CHECK-7","for":["AC-20"]}
```

## Entities

- GuardArtifact: one accepted, canonically attributed implementation CMT input.
- GuardSite: one immediate recognized primitive-headed application within a GuardArtifact.
- GuardAbstractValue: the selected overapproximation of native OCaml integer values with distinct top/bottom.
- GuardClassification: local conditional NONZERO/ZERO/MAY_ZERO/UNREACHABLE/UNSUPPORTED status, not any existing graph or raise-set verdict.
- GuardCensus: the closed counts derived from accepted artifacts and their sites.

## Validation and consistency record

2026-09-13, root read-only review of existing specs' Entities sections and neighboring status definitions.

- New entity names will be GuardArtifact, GuardSite, GuardAbstractValue, GuardClassification and GuardCensus. None duplicates an existing Entities definition.
- specs/actionable-review-reports.md:229 defines DivisorOperandContext as syntax metadata, never a value-analysis result. Keep it unchanged: GuardSite is a separate CLI record, not a DB origin enrichment or exemption.
- specs/exn-raise-sets.md:212 reserves verdict for BOUNDED/UNBOUNDED/BOUNDED_UNDER_HYP. GuardClassification is not that verdict and never rewrites it.
- specs/cfg-postdom-dominance.md:144 defines graph unreachable query behavior. GuardClassification.UNREACHABLE means only a local supported branch contradiction under fresh function-entry contexts, not graph unreachability. Documentation must state this distinction explicitly.
- specs/origin-recurring-consumer.md:289-292 keeps its reference and package meaning. This slice must not edit its corpus/reference to manufacture green results or interpret GuardCensus as production origin counts.
- No conflicting existing canonical entity definition found; no user arbitration required.
- Claims reconciler/authority/KB installation was absent at intake; metadata remains draft until actual tooling can validate/project it. Do not call generated claims active.

Fresh independent researcher, clarifier, challenger and formalizer; root resolved eight clarifications and sixteen challenges. Three stories, 47 FRs, 19 ACs, six planned executable-check modes. Root corrected formalizer FR-031 from 'every classified site' to 'every numerically supported site': unsupported sites require exclusion reasons, not numeric assertions. All underlying semantics are frozen here; domain representation is deliberately a plan choice. No implementation/test success inferred from this document.

Human quiz and repeated approval prompts are superseded by explicit user authorization to run the complete pipeline autonomously. This is operator validation under that authorization, not a quiz performed. Missing claims tooling is disclosed; technical review, QA, exact-head CI and merge gates are not waived.
