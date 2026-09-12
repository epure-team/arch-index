# Spec research — guard-division-analysis

Research date: 2026-09-12. Scope: repository and configured OCaml 5.3 compiler-libs, read-only. This note reports codebase facts and semantic decisions that the specification must freeze; it does not prescribe an implementation.

## Existing surfaces and boundaries

- The repository already detects the eight requested primitive names through typed value identity: `%divint`, `%modint`, and the int32/int64/nativeint division/remainder pairs are recognized only when the application head is a `Texp_ident` whose value description is `Val_prim` (`lib/arch_index/arch_index_exn.ml:435-447`, `lib/arch_index/arch_index_exn.ml:464-478`). This is the relevant precedent for separating compiler-resolved primitives from shadowed source operators.
- Existing extraction labels a division operand syntactically from original slot 2 as literal, identifier, other, or missing; it does not evaluate it. It distinguishes integer families by primitive name (`lib/arch_index/arch_index_exn.ml:479-506`). The adjacent fixture pins identifier, literal, complex-expression, and partial-application behavior (`tezt/tests/exn_raise_sets.ml:117-120`, `tezt/tests/exn_raise_sets.ml:295-311`). This existing database metadata is therefore not an abstract-value result and cannot silently acquire guard semantics without conflicting with the brief's “separate library/CLI” boundary.
- CMT consumption currently calls `Cmt_format.read`, ignores a missing info payload, and proceeds only for `Implementation`; source resolution can also return `None` and cause an empty result (`lib/arch_index/arch_index_cmt.ml:2755-2765`). That tolerant extraction precedent conflicts with the intake's fail-closed input contract and must not be inherited implicitly.
- The declared project floor is OCaml 5.3 and the installed libraries already include compiler-libs, Unix, Yojson, Cmdliner, and Digestif (`dune-project:1-17`, `lib/arch_index/dune:1-20`, `bin/arch_callgraph_ocaml/dune:1-4`). There is no existing `lib/arch_guard`, `bin/arch_guard`, `docs/arch-guard.md`, or guard-specific canonical spec in the live tree. The durable task artifacts are the validated intake and roster research; repository `specs/` covers adjacent analyses but not this one.

## Semantic assumptions requiring an explicit freeze

### Function parameters, cases, and defaults

OCaml 5.3 represents one source function as `Texp_function` with a list of `function_param` records and either `Tfunction_body` or `Tfunction_cases` (`/home/mathias/dev/arch-index/_opam/lib/ocaml/compiler-libs/typedtree.mli:187-197`, `:336-349`). Each ordinary parameter has both a compiler binder identity (`fp_param`) and a pattern in `fp_kind`; its pattern match may be `Partial` (`typedtree.mli:303-334`). A `Tfunction_cases` body introduces an additional compiler identifier `param`, distinct from the leading parameter list (`typedtree.mli:336-349`). Therefore the spec must state, independently:

- which identities enter an initial unknown environment: every `fp_param`, every identifier bound inside its `Tparam_pat`, and the final `Tfunction_cases.param`;
- whether a parameter's pattern contributes facts to the body, merely binds unknown scalar components, or makes the entire body/affected region unsupported;
- whether refutable parameter patterns and guarded/refutable `function` cases can yield `UNREACHABLE` arms under the model, or are wholly `UNSUPPORTED`;
- whether case guards are interpreted only when they are the same pure zero comparisons allowed for `if`, and what state reaches the RHS after a true guard versus the next case after a false guard.

This cannot be inferred from the current CFG walker. It peels the root parameter chain, records refutable parameters as possible `Match_failure`, branches all `function` cases, and walks guards before RHSs, but it does not bind numeric facts from patterns or model ordered pattern selection (`lib/arch_index/arch_index_cmt.ml:2538-2580`, `lib/arch_index/arch_index_cmt.ml:2653-2669`).

Optional defaults are a separate execution regime. The typedtree says parameter effects run left-to-right at saturation and identifies defaults as expressions (`typedtree.mli:191-196`, `typedtree.mli:328-334`). The adjacent walker deliberately analyzes defaults in isolated/deferred blocks because they execute only when omitted (`lib/arch_index/arch_index_cmt.ml:2538-2557`, `lib/arch_index/arch_index_cmt.ml:2671-2675`). The intake excludes “optional/default-argument semantics”; the spec must freeze whether (a) only the default expression is an unsupported execution region, (b) the entire function containing such a parameter is unsupported, or (c) only sites data-dependent on the optional parameter are unsupported. It must also freeze whether ordinary labelled parameters without defaults remain supported.

### Nested functions and captures

The existing walker gives every nested `Texp_function` its own context and walks its body there (`lib/arch_index/arch_index_cmt.ml:1685-1709`), matching the intake's separate-entry rule. However, “unknown parameters/captures” needs a precise environment boundary: all free scalar identifiers in a nested function must be defined either as unknown values or as unsupported dependencies, even when their outer binding is a literal or branch-refined. The spec must freeze whether unrelated local bindings created wholly inside the nested function can still be tracked, and whether a nested function located syntactically inside an unsupported loop/handler inherits `UNSUPPORTED` from that enclosing syntax or starts a fresh unknown entry context. Those choices change site classification and are not resolved by “never inheriting a branch's execution guarantee.”

Identity must not be reconstructed from spelling. Existing code keys binders and aliases on `Ident.unique_name`, explicitly because shadowing produces new identities (`lib/arch_index/arch_index_cmt.ml:1266-1273`, `lib/arch_index/arch_index_cmt.ml:1710-1751`). This is the directly adjacent convention for parameters, locals, compound-pattern components, and captures.

### Partial primitive application and arity

`Texp_apply` carries `(arg_label * expression option) list`, and an element can be `None` when that original labelled slot is abstracted over (`typedtree.mli:198-212`). Existing division inventory deliberately asks for original slot 2 and reports `missing` if absent (`lib/arch_index/arch_index_exn.ml:486-506`); the fixture demonstrates `( / ) 1` as that case (`tezt/tests/exn_raise_sets.ml:117-120`, `tezt/tests/exn_raise_sets.ml:308-311`).

The spec must freeze the distinction among:

- fewer than two original primitive slots;
- two slots present but one expression option absent;
- two operands supplied through nested applications rather than one typedtree node, if that shape is possible for compiler primitives in accepted artifacts;
- over-application after a saturated primitive;
- labelled/optional holes that exist in the general `Texp_apply` representation but are invalid for these primitives.

The required invariant is already directional in the intake: a partial primitive occurrence remains in syntax inventory but is not an executed division and its semantic result is `UNSUPPORTED`. What remains to freeze is site identity/location for that occurrence and whether later saturation is inventoried as one site or produces a second site. Existing `fn_arity` counts source function parameters and `function` cases (`lib/arch_index/arch_index_cmt.ml:890-898`), but that is callgraph machinery and not evidence for primitive saturation.

### Compound patterns and local bindings

Typedtree patterns include wildcard, variable, alias, constant, tuple, constructor, variant, record, array, lazy, and recursively nested or-pattern forms (`typedtree.mli:77-150`). The brief promises immutable local variables/aliases and separately calls out shadowing, but does not say what a compound `let` or parameter pattern contributes. The spec must freeze at least:

- `let x = e` and `let x = y` versus `let (x, y) = e`, record/constructor destructuring, and `p as x`;
- whether literal components of a syntactic tuple/constructor RHS are projected, or every compound destructure binds unknown/unsupported values;
- whether a failed/refutable `let` pattern creates an unsupported region, a possible exceptional exit, or branch-sensitive bottom;
- whether or-pattern binders share the compiler identity exposed by the typed tree and whether facts common to all alternatives survive;
- whether recursive value groups are wholly unsupported even when a particular RHS looks scalar, consistent with “recursive evaluation” being excluded.

Adjacent code is intentionally narrower in one local-binding analysis: only a single `Tpat_var` plus one function literal is stamped, while tuple patterns and conditional bindings remain unknowable (`lib/arch_index/arch_index_cmt.ml:1266-1272`, `lib/arch_index/arch_index_cmt.ml:1720-1736`). This is useful precedent for explicit conservatism, not an implied guard policy.

### Branch predicates and arithmetic identities

The recognized comparison primitive set includes `%equal`, `%notequal`, ordering comparisons, and `%compare`, all obtained through `Val_prim` (`lib/arch_index/arch_index_exn.ml:437-447`, `lib/arch_index/arch_index_exn.ml:464-477`). Because equality is polymorphic at source level, the spec must freeze the additional type test establishing that both compared expressions are native `int`, which operand may be zero, whether aliases and reversed forms (`0 = d`) are accepted, and whether negation or syntactic wrappers are normalized. Primitive name alone is insufficient to establish the numeric family.

For “basic int arithmetic,” the exact compiler primitive identities and supported operand shapes/operators require a closed list. In particular, the spec must freeze transfer behavior for unary negation, addition, subtraction, multiplication, division, and remainder; constant folding versus interval transfer; and overflow widening at both 31- and 63-bit widths. Without a closed set, an unknown ordinary call returning top can be accidentally conflated with an unsupported arithmetic operator, and unbounded host arithmetic could prove a false nonzero result after modular wrap.

### Locations and stable site identity

Existing call sites use only `src_path:line` (`lib/arch_index/arch_index_cmt.ml:1217-1220`), while nested lambda identity uses line, one-based column, and an encounter-order suffix for collisions (`lib/arch_index/arch_index_cmt.ml:1284-1293`). Existing origin columns also compute line and one-based column from `loc_start` (`lib/arch_index/arch_index_exn.ml:357`, `lib/arch_index/arch_index_errch.ml:277`). The source-availability precedent rejects `pos_lnum = 0` but explicitly retains usable ghost locations because PPX/desugared nodes can be ghosted (`lib/arch_index/arch_index_cmt.ml:2433-2451`).

The new report contract therefore needs an explicit freeze for:

- which location belongs to a site: the whole `Texp_apply`, primitive-head identifier, or divisor expression;
- whether it emits start/end filename, line, byte column, `pos_cnum`, and `loc_ghost`, and how line 0 is represented;
- how two sites with identical compiler locations are distinguished without traversal-order instability;
- whether identity includes canonical artifact path/digest, compiler module name, source filename, location, primitive name, and a deterministic within-location ordinal;
- whether compiler `Uid.t` or `Ident.unique_name` may appear in public JSON. They are appropriate within one artifact for binding lookup, but repository comments only claim stamps are unique within a compilation unit (`lib/arch_index/arch_index_cmt.mli:383-391`), so they are not already established as stable cross-build report IDs.

These choices are essential because the intake treats source locations and source/CMT correspondence as trusted metadata, while demanding stable sorted output; “sort by location” alone is not total when compiler-generated or PPX sites collide.

## Nearby tests and contract patterns

- The authentic CMT division fixture already covers native-int identifier/literal/expression/partial syntax and asserts exact database metadata (`tezt/tests/exn_raise_sets.ml:117-120`, `tezt/tests/exn_raise_sets.ml:295-311`). It is the closest regression surface for ensuring the separate tool does not alter existing extraction.
- Shadowed binder tests explicitly document why compiler identities, not names, are required (`tezt/tests/shadowed_definitions.ml:69-119`). Error-channel fixtures exercise nested and arm-level or-patterns and note compiler alpha-renaming behavior (`tezt/tests/error_channels.ml:118-166`). These are adjacent pattern-shape evidence for the guard spec's binder rules.
- The central Tezt helper treats skipped tests as failure and provides fixture/build command infrastructure (`tezt/lib/arch_tezt.ml:304-315`, `tezt/lib/arch_tezt.ml:731-807`). Generated executable-path dependencies are wired at library compile time (`tezt/lib/dune:20-40`).
- Existing standalone checks use a `0` pass, `1` assertion failure, and higher execution/infrastructure failure convention; the intake repeats that convention for the new checker. Exact commands are not yet present in the repository and must be frozen by the eventual spec rather than inferred from filenames.

## Conflicts and residual ambiguities to carry into specification

1. “Syntax inventory is complete” and “unsupported execution regions stay unsupported” are compatible only if every recognized primitive is inventoried before semantic pruning; the report must retain sites nested under loops, try/handlers, effects, mutation, optional defaults, and partial applications even though none may receive a supported abstract result.
2. “Nested functions are separate entry contexts” does not by itself settle nested functions textually contained in unsupported regions or capture-dependent expressions. This affects whether such sites are `MAY_ZERO` from fresh top or `UNSUPPORTED`.
3. “Immutable local variable bindings/aliases” does not define compound/refutable patterns, recursive groups, parameter-pattern refinement, or simultaneous nonrecursive `and` visibility. Typedtree exposes all of these distinctly.
4. “Pure if branches” does not define expression evaluation order, exceptional/diverging conditions, `if` without `else`, or whether only zero comparison predicates refine. These must not be borrowed from the current CFG, which is exception-insensitive in several paths and has no numeric state.
5. The status phrase “ZERO when reached” is a divisor-value property, not a guaranteed execution claim. `UNREACHABLE` needs a closed cause set under this bounded model (for example contradictory zero restrictions), especially because loops and exceptions are excluded and cannot supply reachability proofs.
6. The intake requires “unknown ordinary calls return top” while also declaring effectful/structural regions unsupported. A closed boundary is needed between a supported expression containing an opaque call result and a call/construct that makes the enclosing execution region unsupported.
7. No dedicated KB or claims-authority file exists for arch-guard. Existing `specs/exn-raise-sets.md` and `docs/reporting.md` describe syntax-only division origins and existing rule behavior; they are adjacent contracts, not authority for the new status semantics (`docs/reporting.md:53-58`, `specs/exn-raise-sets.md:26-41`).
