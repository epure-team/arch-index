# Research — tezos-open-bodies

_Generated: 2026-09-14_
_Mode: fast_
_Online research: enabled_

## Question 1: How does lib/arch_index/arch_index_cmt.ml classify value-binding right-hand sides, including nested wrappers, and which expression forms does its traversal currently descend through or stop at?

**Finding:** The top-level function-body classifier is deliberately a one-constructor test: a binding is a function body only when its RHS `exp_desc` is directly `Texp_function`. Type constraints and coercions do not create another `exp_desc` layer in this API; they remain in `exp_extra`, so those constrained functions still match. An arrow-typed conditional or identifier does not match. `fn_arity` follows only a leading chain of `Texp_function`: each parameter list contributes its length; a terminal `Tfunction_cases` contributes one additional argument; any other expression ends the count at zero. Consequently the pre-pass records only single-variable `Tpat_var` bindings whose immediate RHS passes that classifier, keyed by the compiler's `Ident.unique_name` and paired with the indexed binding name and syntactic arity.

The call walker has a different, broader job. It specializes control/effect behavior for functions, lets, conditionals, matches, tries, loops, assertions, binding operators, applications, sequences, constructors and other forms, and otherwise delegates to `Tast_iterator.default_iterator`, which recursively visits the compiler-defined children. A nested literal is promoted to its own node. Within a `Texp_let`, however, the literal-binding table recognizes only the immediate pair `Tpat_var` / `Texp_function`; after visiting that RHS it records the lambda stamp and arity before walking the let body. Function-root peeling likewise descends only through `Texp_function (..., Tfunction_body body)`; it stops on `Tfunction_cases` or the first non-function expression. Optional-parameter default expressions are collected while peeling and later walked in isolated/deferred CFG blocks. After peeling, a bare arrow-typed identifier is separately treated as a point-free value alias only when the root is physically the original expression; otherwise the peeled function is not reclassified as an alias.

**References:**
- `lib/arch_index/arch_index_cmt.ml:870` — `is_arrow_ty` checks the raw `Types` descriptor for `Tarrow`.
- `lib/arch_index/arch_index_cmt.ml:879` — `is_function_rhs` documents non-function RHS exclusions and matches only `Texp_function`.
- `lib/arch_index/arch_index_cmt.ml:889` — `fn_arity` traverses the leading function chain and stops on all other descriptors.
- `lib/arch_index/arch_index_cmt.ml:974` — `build_local_fn_stamps` scans the whole structure and keys accepted binders by `Ident.unique_name`.
- `lib/arch_index/arch_index_cmt.ml:1840` — the specialized iterator promotes `Texp_function` and uses `default_iterator.expr` for deferred/default traversal.
- `lib/arch_index/arch_index_cmt.ml:1888` — nested-let literal recognition requires the immediate `Tpat_var` / `Texp_function` pair.
- `lib/arch_index/arch_index_cmt.ml:1960` — explicit CFG traversal begins for conditional and match forms.
- `lib/arch_index/arch_index_cmt.ml:2165` — `Texp_letop` explicitly walks operator expressions and its conditional continuation.
- `lib/arch_index/arch_index_cmt.ml:2191` — application traversal computes saturation and records the head after walking its evaluated components.
- `lib/arch_index/arch_index_cmt.ml:2601` — sequences walk both children and mark the first result as sunk.
- `lib/arch_index/arch_index_cmt.ml:2745` — `walk_function_root` collects optional defaults and peels only leading function bodies.
- `lib/arch_index/arch_index_cmt.ml:2820` — point-free alias emission requires `root == e0`, an arrow type, and an identifier root.

---

## Question 2: How are compiler identity, syntactic arity, call-versus-value classification, and effect metadata collected, represented, and consumed across arch_index_cmt.ml and call_graph_extractor.ml?

**Finding:** Compiler identity is preserved at collection time through `Ident.unique_name` for local binders and through resolved `Path.t` values for identifiers and qualified names. The pre-pass associates a local function stamp with `(indexed name, fn_arity)`. Calls are represented before database resolution by the `call_head` sum: same-module bodies (`Head_local`), persistent qualified paths (`Head_qualified`), bounded local callbacks/owned-module bodies (`Head_enumerated`), and unknown callable values (`Head_unknown` plus a reason). `pending_call` adds occurrence facts: whether owned-module invocation was used, partiality, CFG-derived conditionality and deadness, source site, exception and value-channel scope IDs, value-channel propagation, and alias edge form.

For applications, arity selection is syntax-first for known same-module functions, recorded lambda literals, and owned local-module targets, and otherwise falls back to counting leading `Tarrow` descriptors. The number of supplied argument expressions is compared with the selected arity; an arrow result or too few supplied expressions marks the head partial, while excess supplied expressions produce a separate unknown computed-return call. Head classification distinguishes a compiler-resolved local body, a stamped local lambda, a local/parameter value, a qualified persistent path, a dynamic module root, an owned local-module member, an immediately applied literal, and a computed expression.

Effect-related metadata is gathered in the same walk but is orthogonal to head identity. `add_call` captures the current exception scope and creates a value-channel propagation candidate only when caller and callee types carry the same configured channel and the head is not a declared bind. CFG solving later derives `cond` and `dead`, suppresses propagation for sunk heads, and independently attaches any value-channel handler scope. The collector returns calls, lambda nodes, per-node exception facts, and per-node value-channel facts. The rich CMT path writes carrier/scope/origin rows, translates the two independent local scope-ID spaces to database row IDs, and retains all `pending_call` metadata for later resolution.

The flat `call_graph_extractor.ml` CMT fallback invokes those same identity/arity/context builders and the same collector, but destructures and discards lambda, exception, and value-channel fact collections. It then projects each pending call through `pending_display` to the smaller `call_row` shape: caller/callee display names, caller/callee files, call site, and edge form. `local_module_invocation` is used only to select the proper owned-name set for same-file attribution; partiality, call kind inputs, scopes, propagation, and other rich metadata are not fields in the flat result. The LSP route constructs the same flat row shape directly and always uses `edge_form = None` because call hierarchy observes applications rather than point-free bindings.

**References:**
- `lib/arch_index/arch_index_cmt.ml:601` — `call_head` encodes local, qualified, enumerated, and unknown identity classes.
- `lib/arch_index/arch_index_cmt.ml:617` — `pending_call` defines identity-adjacent, control-flow, scope, propagation, and edge-form metadata.
- `lib/arch_index/arch_index_cmt.ml:668` — `pending_display` intentionally flattens a rich head to name plus optional module.
- `lib/arch_index/arch_index_cmt.ml:974` — the function-stamp pre-pass stores compiler identity with syntactic arity.
- `lib/arch_index/arch_index_cmt.ml:1383` — `add_call` captures scopes and computes the same-channel propagation candidate.
- `lib/arch_index/arch_index_cmt.ml:1494` — fallback arity counts raw leading type arrows.
- `lib/arch_index/arch_index_cmt.ml:2198` — application arity selects syntax-backed tables before type-arrow fallback.
- `lib/arch_index/arch_index_cmt.ml:2241` — partiality combines result-arrow and supplied-argument tests.
- `lib/arch_index/arch_index_cmt.ml:2260` — `record_head` performs the call-versus-value/identity classification.
- `lib/arch_index/arch_index_cmt.ml:2325` — over-application emits a separate unknown computed-return occurrence.
- `lib/arch_index/arch_index_cmt.ml:2876` — CFG finalization derives conditional/dead facts and finalizes effect-channel metadata.
- `lib/arch_index/arch_index_cmt.ml:3447` — the rich path receives all four collector products.
- `lib/arch_index/arch_index_cmt.ml:3565` — value-channel carriers, scopes, catches, and origins are stored.
- `lib/arch_index/arch_index_cmt.ml:3610` — local exception and value-channel scope IDs are independently rewritten to stored row IDs.
- `lib/arch_index/call_graph_extractor.ml:9` — the flat `call_row` has only names/files/site/edge form.
- `lib/arch_index/call_graph_extractor.ml:248` — the flat fallback builds the same local function, local-module, and alias contexts.
- `lib/arch_index/call_graph_extractor.ml:308` — it calls the shared collector while discarding lambda and effect fact outputs.
- `lib/arch_index/call_graph_extractor.ml:327` — it projects pending calls and uses owned-module identity only for file attribution.

---

## Question 3: Which deterministic corpus and Tezt assertions currently compare extracted resolution results, and what ordering, normalization, equality, and regression-guard behavior do they enforce?

**Finding:** There are three related deterministic layers in the inspected paths. First, `tezt/tests/local_module_targets.ml` embeds a fixed OCaml fixture covering owned modules, nested modules, shadowed values, aliases, includes, constrained/recursive modules, functor parameters/applications, callbacks, point-free aliases, let-operators, arity, conditionality, and dead sites. Its Tezt cases index that fixture and make exact SQL cardinality assertions about resolved target IDs, same-file ownership, kinds, TOP metadata, edge forms, over-application residuals, rejection behavior, and flat-path attribution. It also registers three Node ratchets and maps exit 1 to assertion failure while treating other nonzero exits as setup failure.

Second, `tezt/tests/callgraph_soundness.ml` embeds a separate fixed two-module dominance corpus. It normalizes command output to a verdict token before strict string equality, requires refusal by exit code, and compares scalar SQL results by exact string equality. Its fixture and comments explicitly make formerly gated/XFAIL expectations unconditional, and it contains non-vacuity counterchecks such as requiring the fixture's `exported` result to remain empty and requiring unrelated dead code to remain reported while reachable nodes are excluded.

Third, `roster/tezos-call-resolution/comparison.js` defines canonical resolution snapshots. It validates a fixed ten-field row schema, omits position fields from semantic equality, serializes fields in declared order, sorts the serialized rows lexicographically, and hashes the compact JSON array plus one newline. Comparison itself is multiset-based, so reordering is neutral while duplicate multiplicity is preserved. Exact reviewed witnesses consume one removed and one added occurrence; a witness cannot be reused beyond its multiplicity. The accepted transition shape is narrowly checked, over-application residuals require integer `arguments > arity` and capacity from an accepted head transition, all unmatched additions/removals fail, existing relation loss fails, any newly added MUST row fails, and relation gains must equal the accepted transition-derived set. `check-comparison.js` exercises these properties with reversed order, duplicates, target/kind mutation, malformed rows, same-file/cross-file cases, witness multiplicity, residual arity, database shape/integrity, complete 410-input provenance, retained positions, and a 64-character digest.

The Tezt registration inspected in `local_module_targets.ml` does not invoke `check-comparison.js`; it invokes labeled-arity, verifier-input, and self-index scripts. The self-index script builds a fresh database from the fixed built `lib/arch_index` corpus, queries exact module/function/call counts, and byte-compares the resulting buffer with `test/fixtures/self-index-stats.txt`. Thus the canonical snapshot comparator is an existing deterministic checker, while the directly registered Tezt comparison in the inspected module consists of exact SQL/verdict assertions and three named ratchets.

**References:**
- `tezt/tests/local_module_targets.ml:10` — declares the fixed identity-backed local-module fixture and its refusal decoy.
- `tezt/tests/local_module_targets.ml:81` — the basic Tezt test checks non-vacuity and exact resolved call attributes.
- `tezt/tests/local_module_targets.ml:139` — boundary assertions enumerate exact caller/target pairs and unsupported-owner outcomes.
- `tezt/tests/local_module_targets.ml:221` — cross-CMT and flat-path checks assert file-local attribution.
- `tezt/tests/local_module_targets.ml:260` — registers three external checker scripts with distinct assertion/setup exit handling.
- `tezt/tests/callgraph_soundness.ml:8` — documents the fixed dominance corpus and unconditional regression assertions.
- `tezt/tests/callgraph_soundness.ml:286` — verdict and SQL expectation tables encode exact expected results.
- `tezt/tests/callgraph_soundness.ml:330` — Tezt normalizes verdict output and uses strict equality/refusal comparisons.
- `roster/tezos-call-resolution/comparison.js:4` — declares canonical versus positional fields and validates canonical rows.
- `roster/tezos-call-resolution/comparison.js:24` — canonical strings are sorted; digest encoding is fixed.
- `roster/tezos-call-resolution/comparison.js:28` — database validation requires schema, integrity, referential completeness, and exactly 410 collected inputs.
- `roster/tezos-call-resolution/comparison.js:84` — snapshots join stored caller/target identities and retain positions outside semantic canonical rows.
- `roster/tezos-call-resolution/comparison.js:100` — subtraction is multiset-based and preserves duplicate counts.
- `roster/tezos-call-resolution/comparison.js:111` — witness consumption and transition/residual guards define accepted changes.
- `roster/tezos-call-resolution/check-comparison.js:25` — executable assertions cover reorder neutrality, multiplicity, mutation, witness, residual, and malformed-input behavior.
- `roster/tezos-call-resolution/check-self-index-smoke.js:10` — the self-index ratchet fixes producer, corpus, schema, and golden inputs.
- `roster/tezos-call-resolution/check-self-index-smoke.js:41` — measured bytes are compared directly with the golden file.

---

## Question 4: [ecosystem] How do OCaml 5.3 Typedtree APIs represent wrapped expressions, value bindings, function bodies, applications, identifiers, arity-relevant syntax, and effect-related constructs?

**Finding:** In the immutable OCaml `5.3.0` compiler interface, an expression record separates `exp_desc` from an `exp_extra` list; constraints, coercions, polymorphic annotations, and locally abstract-type additions are represented as extras rather than general wrapper expression constructors. A value binding contains a typed pattern and expression plus recursive-binding classification, attributes, and location (there is no value-binding UID field in this interface). `Texp_let` carries a recursive flag, a list of value bindings, and its body. `Texp_function` carries a list of `function_param` records and a `function_body`; `Tfunction_body` wraps an expression, while `Tfunction_cases` carries cases and represents one final pattern-matched argument. The source explicitly says this typed construct preserves the originating parsed function's arity and that parameter effects run left-to-right upon saturation.

Applications in `5.3.0` are `Texp_apply (function_expression, (arg_label * expression option) list)`: `Some expression` is supplied and `None` is an abstracted/omitted slot. The official example shows `f ~y:3` as `[(Nolabel, None); (Labelled "y", Some ...)]`, so list length and number of supplied expressions are distinct quantities. Identifiers are `Texp_ident` values containing a resolved `Path.t`, source long identifier, and value description. Generalized open syntax has its own `Texp_open (open_declaration, expression)` descriptor, whereas constraints/coercions are extras.

The earlier moving GitHub `5.3` branch rendering conflicts with both immutable `5.3.0` and the installed compiler: it currently presents a later `apply_arg = Arg | Omitted` representation. That moving branch is not evidence for the released 5.3.0 API. The local switch reports `ocamlc 5.3.0`, and its installed `compiler-libs/typedtree.mli` byte-shape agrees with the immutable tag on `expression option`, case continuations as `Ident.t option`, and the value-binding fields described above.

OCaml 5.3.0 effect-handler syntax is represented in typed matches/tries rather than by a standalone effect expression descriptor: `Texp_match` separates computation cases from value effect-handler cases, and `Texp_try` separates exception cases from effect cases. A case has `c_cont : Ident.t option` in addition to its pattern, optional guard, and RHS. Effect performance itself is exposed by the `Effect.perform : 'a Effect.t -> 'a` library primitive; the 5.3 manual states that deep-handler syntax was introduced in 5.3 and that an effect arm receives the delimited continuation. The manual also states that effects are not statically effect-safe: an unmatched effect raises `Effect.Unhandled`.

**References:**
- `_opam/lib/ocaml/compiler-libs/typedtree.mli:154` — installed OCaml 5.3.0 expression and extra representation.
- `_opam/lib/ocaml/compiler-libs/typedtree.mli:187` — installed function-body and arity-relevant syntax.
- `_opam/lib/ocaml/compiler-libs/typedtree.mli:198` — installed application representation uses `(arg_label * expression option) list`.
- `_opam/lib/ocaml/compiler-libs/typedtree.mli:214` — installed match/try effect-case collections.
- `_opam/lib/ocaml/compiler-libs/typedtree.mli:287` — installed `Texp_open` expression wrapper.
- `_opam/lib/ocaml/compiler-libs/typedtree.mli:496` — installed 5.3.0 value-binding fields.
- [OCaml 5.3.0 `typing/typedtree.mli`](https://github.com/ocaml/ocaml/blob/5.3.0/typing/typedtree.mli) — immutable official release source matching the installed compiler interface.
- [OCaml 5.3 effect-handler manual](https://ocaml.org/manual/5.3/effects.html) — official language semantics and 5.3 deep-handler syntax.
- [OCaml 5.3 `Effect` API](https://ocaml.org/manual/5.3/api/Effect.html) — official `Effect.t`, `perform`, and unhandled-effect API.

## Patterns found

| Pattern | File | Lines | Notes |
|---|---|---:|---|
| Immediate syntactic body classification | `lib/arch_index/arch_index_cmt.ml` | 879–899 | Direct `Texp_function`; recursive leading-parameter arity only. |
| Compiler-stamp identity table | `lib/arch_index/arch_index_cmt.ml` | 974–995 | Whole-structure map from unique binder identity to indexed name and arity. |
| Rich-then-flat call representation | `lib/arch_index/arch_index_cmt.ml`, `lib/arch_index/call_graph_extractor.ml` | 601–671, 308–354 | Rich pending facts are retained by the main index and projected by the flat fallback. |
| Multiset canonical comparison | `roster/tezos-call-resolution/comparison.js` | 4–25, 96–173 | Declared fields, sorted serialization, multiplicity, exact witness consumption. |

## External prior art

| Tool / Paper / Approach | Source | Key finding |
|---|---|---|
| OCaml 5.3.0 Typedtree | [immutable official source](https://github.com/ocaml/ocaml/blob/5.3.0/typing/typedtree.mli) | Functions preserve parsed arity; applications use `expression option` for supplied/omitted slots; effect arms live in match/try case collections. |
| OCaml 5.3 effect handlers | [official manual](https://ocaml.org/manual/5.3/effects.html) | Deep effect-handler syntax is present in 5.3; arms receive continuations and unmatched effects are dynamically unhandled. |
| OCaml `Effect` | [official API](https://ocaml.org/manual/5.3/api/Effect.html) | `perform` invokes an extensible typed effect and may raise `Unhandled`. |

## Coverage gaps

- Q1: The live code has no generic named concept of “wrapper”; the report distinguishes `exp_extra`, immediate `exp_desc` matching, function-root peeling, and default recursive traversal. Runtime/PPX-specific Typedtree shapes were not generated because this phase was read-only and prohibited builds/tests.
- Q3: The inspected Tezt registration does not invoke `check-comparison.js`; no claim is made here that another uninspected orchestration layer invokes it.
- Q4: The immutable official source and installed 5.3.0 interface agree. The moving `5.3` branch currently exposes a different, later application-argument representation and is explicitly excluded as release evidence.
