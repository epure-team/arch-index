# Research — tezos-recursive-typed-bodies

Generated: 2026-09-15. Mode: full, two fresh no-history Sol documentarians (combined local locator/analyzer/pattern role and separate external role). Online research: enabled. Input: validated neutral questions manifest. Neither researcher received task.md or the change description.

## Q1 — Existing syntax and compiler representation

The three inspected source families have both locally abstract type annotations and an intervening local open before the function expression:

- `/home/mathias/dev/tezos/tezos/src/proto_alpha/lib_protocol/script_ir_translator.ml:2857`: make_proof_argument, then Result_syntax open at 2860, then function at 2861.
- Same file at 5784: aux, then Lwt_result_syntax open at 5796, then function at 5797.
- `/home/mathias/dev/tezos/tezos/src/proto_alpha/lib_protocol/storage_description.ml:301`: build_handler, open at 303, function at 304.

Source syntax alone does not establish the actual CMT descriptor. The current classifier only accepts immediate Texp_function; constraints/coercions in exp_extra do not alter that test (`lib/arch_index/arch_index_cmt.ml:878`).

## Q2 — Identity and scope

Ordinary local literal entries use Ident.unique_name (`arch_index_cmt.ml:1488`). The recursive active stack uses Ident.same (`:1536`). Admission requires Recursive, singleton group, Tpat_var and immediate function; the descriptor retains the physical RHS, arity, observed name/count and storage flag (`:1991`). Fun.protect restores scope after RHS traversal (`:2005`). An exact active Pident receives the private recursive marker (`:2379`); an unsupported local identifier becomes callback_param (`:2396`).

## Q3 — Arity

`fn_arity` sums leading function parameters and a terminal cases argument (`arch_index_cmt.ml:889`). Recursive applications use descriptor arity (`:2330`) and count supplied Some arguments (`:2306`). Partiality also checks arrow result type (`:2355`). Over-application retains an additional unknown-return occurrence, including the prior conservative type-arrow residual for recursive heads (`:2455`).

## Q4 — Allocation and storage

Synthetic names use caller and source location with a collision ordinal (`arch_index_cmt.ml:1509`). Physical expression equality associates the active expected body with its actual allocated name and counts observations (`:1942`). Successful function insertion confirms storage (`:3632`). Equal locations alone are not identity.

## Q5 — Conservative outcomes

Exactly one observed, named, stored body permits enumeration (`arch_index_cmt.ml:3974`). Dropped bodies become dropped_node; other ambiguity becomes callback_param (`:3987`). Storage emits MAY_ENUMERATED or MAY_TOP, not MUST (`lib/arch_index/arch_index.ml:1477`).

## Q6 — Metadata and corpus

Pending occurrences retain caller, head, partiality, control/dead flags, call site, exception/channel contexts, propagation and edge form (`arch_index_cmt.ml:616`). Synthetic bodies have their own contexts (`:673`), solved control flags (`:3020`) and stored exception/channel data (`:3680`). Scope references are rewritten independently (`:3790`). Flat calls carry kind, reason, anchor, producer and form, with scope/propagation links (`arch_index.ml:1558`).

The manifest provenance identifies OCaml 5.3.0 and 410 artifacts (`roster/functor-instance-resolution/tezos-irmin-candidate/provenance.json:2`). Its historical raw report contains only aggregate initial metrics (`raw-run-410.txt:21`) and cannot establish current occurrence-specific metadata. That old report is not the PR108 retained baseline. Current candidate preservation must be measured separately.

## Q7 — Official compiler representation

OCaml 5.3 keeps constraints and newtypes in expression extras. Newtypes before a function's first parameter appear there; later ones are associated with parameters. Function bodies distinguish an expression from terminal cases. These are documented compiler structures, not inferred source wrappers. [OCaml Typedtree interface](https://github.com/ocaml/ocaml/blob/5.3.0/typing/typedtree.mli).

The implementation of newtype/constraint typing preserves the underlying expression descriptor while adding extras. Binding annotations are translated through the corresponding syntax before typing. Thus a locally abstract annotation alone does not imply a non-function descriptor. [OCaml typecore implementation](https://github.com/ocaml/ocaml/blob/5.3.0/typing/typecore.ml#L4243-L4253), [binding constraints](https://github.com/ocaml/ocaml/blob/5.3.0/typing/typecore.ml#L3233-L3268).

## Q8 — Official identity, location and arity contracts

Ident.same compares binding identity; Ident.equal is name-based. No cross-compilation stability follows from that interface. [Ident interface](https://github.com/ocaml/ocaml/blob/5.3.0/typing/ident.mli#L16-L58).

UIDs identify declarations, but the Internal variant is explicitly not actually unique; shape reduction can also be unresolved or approximate. [Shape interface](https://github.com/ocaml/ocaml/blob/5.3.0/typing/shape.mli#L52-L73), [Shape reduction](https://github.com/ocaml/ocaml/blob/5.3.0/typing/shape_reduce.mli#L18-L26).

Source locations contain start/end positions and a ghost flag; the interface promises no uniqueness. [Location interface](https://github.com/ocaml/ocaml/blob/5.3.0/parsing/location.mli#L25-L36).

Function parameter lists and terminal cases provide syntactic arity. Application argument slots can be None, so slot count is distinct from supplied arguments. [Typedtree function/application contract](https://github.com/ocaml/ocaml/blob/5.3.0/typing/typedtree.mli#L173-L195). CMT annotations may be complete implementations or partial trees; there is no independent universal arity field. [CMT format](https://github.com/ocaml/ocaml/blob/5.3.0/file_formats/cmt_format.mli#L36-L71).

## Patterns found

- Direct function RHS plus annotation extras: immediate-descriptor admission, extractor :878.
- Recursive lexical scope: exact Ident.same and protected stack restoration, :1536/:1991.
- Physical body observation and collision-aware allocation: :1509/:1942.
- Separate storage confirmation and conservative final rewrite: :3632/:3974.
- Source local-open followed by function: three cited Tezos definitions.

## Coverage gaps and execution limits

- No CMT runtime observation or build was performed by either researcher. Exact descriptors at the cited source sites remain to be observed.
- The historical corpus report cannot supply current per-occurrence metadata or prove a candidate's preservation.
- Root ran the upstream official manifest-neutral validator, exit 0. Local documentarian independently checked the same digest, but lacked the repository-local script; its manual check is not described as that official invocation.
- Root's upstream graph resolver reported no installed orientation packs; documentarian's repository-local resolver was absent. Live source research was used.
- Full research roles were combined into two fresh agents rather than four; model names available here are Sol/Terra, not the skill's Claude tiers. Root's prior knowledge is not represented as blind research.

## Subsequent native observation (root; not attributed to blind researchers)

`observe-rhs.ml` is a compiler-only documentary probe. Compiled and executed successfully on the two SHA-checked manifest CMTs at 2026-09-15T02:00:38.897Z; no arch-index imports or DB reads. Both input hashes and probe source hash were unchanged. Evidence: ignored `improvement/2026-09-14-tezos-resolution/attempt5-rhs-observation.json`. Temporary probe build was removed.

Observed RHSs at script_ir_translator binding lines 2857, 2895, 2928, 3069, 3094 and 5784, and storage_description binding line 301: exactly `open(ident)->function`; syntax arities respectively 2,2,2,2,2,8,2. Extras include newtype and constraint. Two additional observed direct-function bindings also carry those extras, confirming that annotation presence and open descriptor are distinct facts.

Immutable prior native occurrences enumerate 14 rejected self-heads across exactly seven binders: five one-head make_proof_argument bindings, one seven-head aux binding, one two-head build_handler binding. The earlier selection researcher's report of eight binders was corrected by direct enumeration, not silently retained.
