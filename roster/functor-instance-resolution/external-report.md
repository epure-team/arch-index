# External ecosystem report

_Role: external researcher (Sol mapping for unavailable Sonnet)_
_Web baseline: OCaml 5.5 / compiler-libs 5.5.1. The coordinator reports the local compiler as OCaml 5.3.0. Compiler-libs explicitly provides no cross-revision compatibility guarantee, so the 5.5 artifact details below are current ecosystem facts, not guarantees about the locally installed 5.3 interfaces._

## Compiler artifacts

- `.cmt`/`.cmti` files contain typed trees when binary annotations are emitted; compiler-libs front-end APIs do not promise compatibility between compiler revisions. Source: [The compiler front-end — OCaml Manual 5.5](https://ocaml.org/manual/5.5/parsing.html), OCaml authors, 2026.
- `Typedtree.module_expr_desc` distinguishes `Tmod_functor`, `Tmod_apply`, and `Tmod_apply_unit`. `Tmod_apply` retains both functor and argument module expressions, so an anonymous `Tmod_structure` can remain structurally present as the argument. `Tmod_ident` retains both resolved `Path.t` and source `Longident`. Source: [typedtree.mli — OCaml compiler 5.5](https://github.com/ocaml/ocaml/blob/5.5/typing/typedtree.mli#L2837-L2890), OCaml project.
- A module binding has `mb_id : Ident.t option` and `mb_uid : Uid.t`; `mb_id = None` denotes `module _ = ...`. The application expression itself has no documented UID field. Source: [typedtree.mli — module_binding](https://github.com/ocaml/ocaml/blob/5.5/typing/typedtree.mli#L2940-L2957), OCaml project.
- `Path.t` has `Pident`, `Pdot`, and `Papply`; the official nested example is `Map.Make(Set.Make(Int))`. Source: [path.mli — OCaml compiler 5.5](https://github.com/ocaml/ocaml/blob/5.5/typing/path.mli#L403-L419), OCaml project.
- Module `Shape` exists specifically to track definitions through functor application and module operations, with `Abs`, `App`, `Struct`, `Alias`, `Proj`, and `Leaf`. Reduction may yield a definition UID, aliases, a locally generated UID when stuck, or an approximation. Sources: [Module Shape — ocaml-compiler 5.5.1](https://ocaml.org/p/ocaml-compiler/latest/compiler-libs.common/Shape/index.html), [Module Shape_reduce — ocaml-compiler 5.5.1](https://ocaml.org/p/ocaml-compiler/latest/compiler-libs.common/Shape_reduce/index.html), OCaml project, 2026.
- Exception artifacts distinguish declarations from rebindings: `Text_decl` versus `Text_rebind (Path.t, Longident.t)`, with compiler identities on the declaration structures. Sources: [typedtree.mli — type_exception](https://github.com/ocaml/ocaml/blob/5.5/typing/typedtree.mli#L3401-L3453), [types.mli — extension_constructor](https://github.com/ocaml/ocaml/blob/5.5/typing/types.mli#L2692-L2711), OCaml project.

## Language guarantees

- Ordinary functor application is applicative for result type components when applied to the same defined module. A unit functor `functor () -> ...` is generative and each application produces distinct result type components. Source: [Generative functors — OCaml Manual 5.5 §12.15](https://ocaml.org/manual/5.5/generativefunctors.html), OCaml authors/INRIA, 2026.
- This guarantee concerns type components, not equality of runtime module values. Functor application evaluates the functor and argument module expressions and evaluates the result module expression in the extended environment. Source: [Module expressions — OCaml Manual 5.5 §§11.2–11.3](https://ocaml.org/manual/5.5/modules.html), OCaml authors/INRIA, 2026.
- Each ordinary exception declaration creates a new exception distinct from all others; `exception F = E` is an alternate name for the existing exception. Combined with functor-body evaluation, an exception declaration in the body creates a fresh runtime exception on each body evaluation. Source: [Type and exception definitions — OCaml Manual 5.5 §11.8.2](https://ocaml.org/manual/5.5/typedecl.html), OCaml authors/INRIA, 2026; [Module expressions](https://ocaml.org/manual/5.5/modules.html).
- Type-level aliases participate in static path equality, including `F(N) = F(P)` when `N` aliases `P`. Source: [Type-level module aliases — OCaml Manual 5.5 §12.8](https://ocaml.org/manual/5.5/modulealias.html), OCaml authors/INRIA, 2026.

## Explicit limits

- UID stability across clean rebuilds, compiler versions, or source movement: **UNKNOWN**.
- Direct equivalence between `Path.same` and language-level applicative type equality: **UNKNOWN**.
- Runtime exception slot representation and direct mapping to `ext_uid`: **NOT_ANALYSED**.
- Third-party ASTs, Merlin/odoc identities, and corpus behavior: **NOT_ANALYSED**.
