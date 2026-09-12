# Formalized requirements — guard-division-analysis

This artifact formalizes the accepted stories and challenge resolutions. It does not select a numeric-domain representation or claim that the planned checker exists.

## Contradiction audit

No unresolved contradiction was found in the supplied artifacts. The public binary name `arch_guard` and the root dispatcher `arch-guard` are distinct, explicitly accepted entry points. The domain representation remains an intentionally open engineering choice constrained by the obligations below.

## Shared entity terminology

- **GuardArtifact**: one accepted, canonically attributed implementation CMT input.
- **GuardSite**: one immediate recognized primitive-headed application within a GuardArtifact.
- **GuardAbstractValue**: the plan-selected overapproximation of native OCaml integer values, including distinct top and bottom.
- **GuardClassification**: exactly one of `NONZERO`, `ZERO`, `MAY_ZERO`, `UNREACHABLE`, or `UNSUPPORTED` assigned to a GuardSite.
- **GuardCensus**: the closed aggregate counts derived from accepted GuardArtifacts and their GuardSites.

`GuardClassification.UNREACHABLE` means bottom only in the bounded supported value-analysis context. It MUST NOT be conflated with any existing arch-index graph-unreachable verdict or alter that verdict's meaning.

## Functional requirements

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
- **FR-027** [US-2; US-2.6; Q-1; Q-3; Q-5; AC-13]: Optional/default or refutable/compound function parameters, function cases, recursive binding subtrees, compound/alias/refutable/or-pattern local lets, matches, handlers, loops, let-operators, lazy/object/record/array/field-mutation/local-module/extension constructs, effects, and `%sequand`/`%sequor` subtrees MUST be treated as unsupported lexical regions, including their nested expressions; later independent siblings MUST NOT be poisoned.
- **FR-028** [US-2; US-2.6; C-13; AC-16]: V1 MUST NOT derive any semantic status from loop iteration, recursive evaluation, fixpoints, guessed bounds, unrolling, or widening; join and top remain permitted non-iterative domain operations.
- **FR-029** [US-2; US-2.7; C-11; AC-14]: Ordinary, unlisted, and indirect applications MUST return top without callee expansion and MUST visit head and arguments independently in the incoming immutable environment; therefore an eligible divisor produced by an opaque ordinary call MUST classify `MAY_ZERO` unless unsupported ancestry applies.
- **FR-030** [US-2; US-2.7; C-11; AC-14]: Recognized div/mod applications MUST inventory and independently visit operands even when malformed; supported closed arithmetic applications MUST use their abstract transfers; methods and effect-specific structural nodes MUST remain excluded constructs rather than ordinary applications.
- **FR-031** [US-2; US-2.1; US-2.7; C-7; AC-10]: Every classified site MUST carry its closed conditional semantic reason—`divisor_nonzero_if_reached`, `divisor_zero_if_reached`, `divisor_may_be_zero`, or `contradictory_supported_branch`—and a successful report containing any status MUST exit `0`; `ZERO` MUST NOT be presented as proof of execution or a confirmed failure.
- **FR-032** [US-2; US-2.8; AC-2]: Adding arch-guard MUST NOT change arch-index extraction behavior, existing rule verdicts, origin corpus/reference data, or existing self-index counts.

### US-3 — Interpretable experiment result

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

## Acceptance criteria

- **AC-1** [US-1 happy path; US-1.1–3]: Supplying a compiled fixture containing all eight immediate primitive identities, native operand categories, a partial primitive, a shadowed operator, and repeated/reversed input paths → every genuine immediate occurrence appears once with stable attribution and slot-2 syntax metadata, the shadowed call is absent, and both input orders produce byte-identical JSON.
- **AC-2** [US-2 happy path; US-2.1–8]: Analyzing the owned native fixture and domain vectors → literals, aliases, guards, joins, contradictory branches, opaque calls, nested functions, shadowing, unsupported regions, and wrapped arithmetic produce exactly the required five-way conditional statuses while all existing arch-index regression gates remain unchanged.
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

Every FR appears in at least one matrix row; the bracketed citations on each FR identify its originating story scenario and/or resolved challenge.

## Planned independent checker contract

The following commands specify a planned checker interface; they do not claim `scripts/check-arch-guard.js` exists yet. Every mode MUST use exit `0` for pass, `1` for a contract assertion failure, and an exit code of at least `2` for checker setup, execution, timeout, malformed-fixture, or internal error. The checker MUST cap each spawned process at 120 seconds and 16 MiB of captured output.

- **CHECK-inventory** [AC-1, AC-4, AC-5, AC-6]: `node scripts/check-arch-guard.js inventory` → compiles/uses the inventory fixture and independently checks primitive identity, immediate-site uniqueness, original slot 2, shadow exclusion, stable ordering, canonical deduplication, and collision failure.
- **CHECK-numeric** [AC-2, AC-10, AC-11, AC-12, AC-13, AC-14, AC-15, AC-16]: `node scripts/check-arch-guard.js numeric` → checks the five-status precedence and closed reasons across aliases, guards, joins, binder scope, fresh function entries, opaque calls, unsupported ancestry, and non-iterative exclusions.
- **CHECK-domain** [AC-9, AC-17]: `node scripts/check-arch-guard.js domain` → uses an independent JS `BigInt` signed-modular oracle for exhaustive widths 3–8 plus selected 31/63-bit extrema, non-singleton/top containment, restriction soundness, bottom/join laws, and wrap-to-zero cases.
- **CHECK-inputs** [AC-6, AC-7, AC-18]: `node scripts/check-arch-guard.js inputs` → checks canonical path rules, symlink rejection, duplicate module/source rejection, hash-change handling, annotation compatibility classes, every inclusive/one-over input and traversal limit, atomic stderr diagnostics, exit `2`, and exactly empty stdout.
- **CHECK-report** [AC-3, AC-7, AC-8, AC-10, AC-13, AC-19]: `node scripts/check-arch-guard.js report` → validates exact JSON keys/types/enums/order, census equations, reason vocabulary, location/spelling rules, empty-inventory wording, conditional limitations, full-buffer size failures, and semantic text/JSON agreement.
- **CHECK-owned** [AC-3, AC-8]: `node scripts/check-arch-guard.js owned` → runs the built CLI on the explicitly selected owned `lib/arch_index` artifacts and checks that the actual artifact/site/status census is reported honestly, including a zero-site result, without adding another corpus.

The checker modes are independently invocable: no mode's pass result depends on another mode having run first. Fixture compilation or discovery needed by a mode is part of that mode's setup and setup failure is an execution error (`>=2`), never an assertion failure.
