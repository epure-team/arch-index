# Adversarial specification resolutions — working artifact

2026-09-15. Independent challenger: cfa_spec_challenger (Sol), 20 challenges.
Root resolutions below stay within validated intake. No product code changed.
This is input to formalization, not a completed/validated specification.

| ID / story | Challenge | Resolution |
|---|---|---|
| C-1 US1 | Product semantics and reason witnesses unspecified | A value is (finite target identities, finite reason kinds). Componentwise subset order, equality and union; bottom=(empty,empty). Unknown-only is not bottom. Diagnostic witnesses do not participate in semantic equality or scheduling. |
| C-2 US1/2 | Consumer translation of bottom missing | An invoked unresolved bottom cell emits an unknown callback_param head in main, not zero rows. Flat preserves its existing unknown-head display contract, with no fabricated callee file. Pure solver bottom remains bottom. Deadness never licenses erasing the occurrence. |
| C-3 US1 | Constraint vocabulary incomplete | Stage2 has target seed, unknown-reason seed and inclusion/copy. Branch join is multiple copies into a result cell. Both components propagate identically; independent saturation oracle tests equivalence. No call/return/argument transfer claimed. |
| C-4 US2 | Lexical eligibility unspecified | Follow resolved compiler binders, not spelling or whole-unit name lookup. Required new support: root structure nonrecursive single-variable bindings and same-callable nonrecursive single-variable lets; branch-valued top-level bindings included. Nested-module/include/open syntax does not gain new substitution support. Preserve established static/owned-module paths. Recursive-group value transfer stays unsupported. Later shadowing cannot retarget an earlier alias. |
| C-5 US2 | Match joins vs excluded patterns | Join all normal-return RHS values conservatively, including exception-case RHS; do not assume case feasibility or exhaustiveness. Guards and scrutinees retain existing call/effect collection. No destructured/scrutinee-to-pattern value transfer: references to case-bound values seed unknown. Constant known RHS can contribute even under complex patterns. An unhandled exception has no returned function value; preserve its error channel rather than inventing a target. |
| C-6 US2 | Physical identity lifetime/stability missing | Physical expression identity and compiler Ident identity exist only inside one OCaml5.3 CMT session. Session-local opaque IDs may represent them; no serialization/reparse equality claim. Source positions only display/provenance. Final names/actual stored identities survive export. |
| C-7 US2 | Flat cannot faithfully name all targets | Keep flat's established caller namespace and explicit limitations, not a new identity schema. New candidates require a unique faithful same-file target mapping; missing/ambiguous target mappings become unknown with no callee_file, never bind a homonym. An ambiguous caller namespace must not generate newly bounded CFA facts: emit unknown at that existing caller. Flat remains kind-less, never advertised as equivalent proof-bearing schema. Main must resolve actual ordinal-qualified identities. |
| C-8 US2 | Provisional literal reconciliation undefined | Collector notification maps the exact physical literal to its actual assigned name and owner. Missing/rejected/wrong-owner notification cannot produce a bounded target; rejected/unobserved body uses dropped_node. Existing names/collision ordinals are not reimplemented by a second pass. |
| C-9 US2 | Top-level visibility vs capture conflated | Unit-level binders are available in nested callable bodies if their resolved Ident is visible. A binder owned by another callable is a capture and unknown for new value-flow transfer, even if its initializer is known. Preserve previously supported direct literal calls; do not infer new capture flow. |
| C-10 US2 | Occurrence correspondence not defined | Each collected application has an opaque session occurrence identity independent of location. Expansion clones that occurrence's finalized metadata. Separate raw occurrences and independent escape/residual edges never deduplicate against one another. Identity is internal; no schema expansion required. |
| C-11 US2 | Different candidate arities/residuals | CFA candidates remain MAY_ENUMERATED. Preserve original partiality and additionally mark candidate partial when fewer supplied arguments than its known arity. Count supplied arguments under current labeled-argument contract; unsupported omitted-label reasoning remains unknown. Any known overapplication adds/retains one returned-function residual for the original occurrence, not one per candidate. Unknown arity cannot imply saturation: keep an unknown contribution. Existing independent residual and opaque-head frontier remain distinct causes, even if persisted TOP reason strings coincide. |
| C-12 US2 | Direct/CFA/alias precedence | Existing resolved static occurrence handling wins, so no duplicate CFA replacement for it. Refine only the unresolved supported head contribution; candidate dedup uses actual target identity within that head. value_alias/module_alias and independent escape facts remain separate and unchanged. |
| C-13 US2 | Closed reasons/failure mapping | Unsupported capture/pattern/opaque value and bottom map to callback_param. Known dropped/unobserved body maps to dropped_node; established module_param and ambiguous_unit causes survive. Flat representation ambiguity uses unknown display/no callee_file; it cannot persist a reason column it does not have. Missing main caller keeps existing extraction failure/drop behavior, never invents caller rows; it is not a supported authentic success path. Anchor remains original call site. |
| C-14 US1/2 | Check commands and errors unspecified | Define CHECK1 node roster/ocaml-cfa-foundation/check-domain.js, CHECK2 node roster/ocaml-cfa-foundation/check-cmt.js, CHECK3 node roster/ocaml-cfa-foundation/check-tezos.js. Prefix rtk proxy at execution. Each: 0 pass, 1 only explicit assertion failure, >=2 environment/load/build failure. CHECK1 independent finite closure oracle; CHECK2 real compiled main/flat fixtures including bottom, collisions and consumer queries; CHECK3 separately reports exact frozen-corpus relation changes and resource observations. Missing external corpus is >=2 unavailable, not green or native CI failure; CI runs native coverage and CHECK1/2 where self-contained. |
| C-15 US1 | Might state saturation vs copy-cell engine | This is a finite inclusion-analysis foundation, not full higher-order 0CFA. Sparse copy closure is the supported stage2 constraint fragment; application/environment state transitions remain stage3. Tests establish least closure of this fragment only. |
| C-16 US1 | Darais store/cache iteration vs sparse queue | Adopt monotone joined-store fixed-point principle, not a definitional interpreter or its cache implementation. Cell sets plus inclusion dependencies provide a simpler finite equation system; independent repeated-scan oracle must match worklist result for target and reason sets. |
| C-17 US1 | Scalar Top absorbs known constants | Function targets are useful positive may-candidates beside an open frontier. Scalar guard concretization has different meaning. Tests pin mixed known+unknown preservation and unchanged numeric tests; no copying of guard scalar lattice or API. |
| C-18 US1/2 | Exception witnesses vs finite reasons | Reuse known-plus-unknown principle, not exception witness semantics. Reasons are finite kinds, witnesses optional bounded diagnostics outside semantic state. Multiple same-kind reasons may join within one head; independent occurrences/residual causes remain separate rows. |
| C-19 US2 | Compiler IDs/API vs physical occurrence | OCaml5.3 is the supported build/CMT version. Ident distinguishes resolved binders; physical expressions distinguish literal occurrences without stable source coordinates. No cross-version/session or independently compiled identity claim; stage4 handles variants separately. |
| C-20 US2 | Transitive value closure vs predecessor alias rows | Application target refinement does not replace declaration provenance. Alias rows stay immediate-predecessor and caller-query exclusion stays unchanged. Source/run/target provenance is not a full derivation proof. |

## Edge cases to retain in formalization

- EC-1 US1: empty targets + reason is unknown-only, not bottom (C1/2).
- EC-2 US1: same reason via different diagnostic witnesses joins semantically once (C1/18).
- EC-3 US1: seeds reaching an already-visited cycle reschedule to identical closure (C3/16).
- EC-4 US2: alias before later same-name binder retains earlier actual identity (C4/7).
- EC-5 US2: equal/ghost literal locations retain actual distinct identities; unrepresentable flat target is unknown (C6–8).
- EC-6 US2: exception-case RHS joins normal returned values, error channels unchanged (C5).
- EC-7 US2: pattern-bound function values are unknown, independent known RHS still retained (C5).
- EC-8 US2: visible top-level target plus enclosing-callable capture yields known+unknown (C9).
- EC-9 US2: candidate arities1/2 under one argument keep conservative per-candidate partiality (C11).
- EC-10 US2: same-line applications with distinct scopes/deadness retain both occurrences (C10).
- EC-11 US2: opaque branch and independent overapplication residual both survive (C11/18).
- EC-12 US2: main shadow identity resolved; flat unrepresentable identity never points to wrong bare homonym (C7).
- EC-13 US2: effectful sequence prefix retains calls/channels; result value alone propagates (C5/10).
- EC-14 US2: recursive-group alias remains unsupported new transfer (C4).

## Still to verify before spec validation

Independent formalizer must check that these resolutions are internally coherent
and every observable obligation has an AC/check. In particular, flat kind-less
representation limits and per-candidate arity must not be hidden by happy-path
counts. No declared spec completion until that review and cross-spec check finish.
