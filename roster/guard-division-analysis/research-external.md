# External ecosystem research: OCaml compiler APIs and abstract interpretation

Scope: ecosystem questions Q6 and Q7 from `questions.manifest.json`. This report uses primary sources only and records facts, version distinctions, and unresolved documentation gaps. It does not infer project intent.

## Q6 — How do existing OCaml compiler APIs expose Typedtree/CMT primitive identities and machine-integer operations across supported compiler versions?

### CMT and Typedtree access

- `Cmt_format.read_cmt : string -> cmt_infos` exposes `cmt_annots`. In OCaml 5.5.1, annotations are `Implementation of Typedtree.structure`, `Interface of Typedtree.signature`, packed annotations, or partial typed-tree fragments. The generic `read` handles `.cmi`, `.cmt`, and `.cmti`; `.cmti` always embeds CMI information, while a `.cmt` embeds it only when there is no corresponding `.cmti`.
  - Source: OCaml project, **“Module Cmt_format”**, official OCaml compiler 5.5.1 package documentation (2026): https://ocaml.org/p/ocaml-compiler/latest/compiler-libs.common/Cmt_format/index.html
- In both OCaml 4.14 and 5.2, a value occurrence is `Texp_ident of Path.t * Longident.t loc * Types.value_description`, and application is `Texp_apply` whose callee is itself a typed expression. The compiler-resolved path and value description are therefore present independently of source spelling.
  - Sources: OCaml project, **`typing/typedtree.mli`**, branch 4.14 (first released 2022): https://github.com/ocaml/ocaml/blob/4.14/typing/typedtree.mli
  - OCaml project, **`typing/typedtree.mli`**, branch 5.2 (released 2024): https://github.com/ocaml/ocaml/blob/5.2/typing/typedtree.mli
- In both versions, `Types.value_description.val_kind` distinguishes `Val_reg` from `Val_prim of Primitive.description`. The primitive description contains `prim_name`, arity, allocation/raising flag, native name, and native argument/result representations.
  - Sources: OCaml project, **`typing/types.mli`**, branch 4.14: https://github.com/ocaml/ocaml/blob/4.14/typing/types.mli
  - OCaml project, **`typing/types.mli`**, branch 5.2: https://github.com/ocaml/ocaml/blob/5.2/typing/types.mli
  - OCaml project, **`typing/primitive.mli`**, branch 4.14: https://github.com/ocaml/ocaml/blob/4.14/typing/primitive.mli
  - OCaml project, **`typing/primitive.mli`**, branch 5.2: https://github.com/ocaml/ocaml/blob/5.2/typing/primitive.mli
- Compiler-internal primitive translation maps textual identities such as `%addint`, `%subint`, `%mulint`, and `%divint` to Lambda primitives; `%divint` maps to `Pdivint Safe`. Boxed integer families have separate identities, for example `%int64_div` maps to `Pdivbint { size = Pint64; is_safe = Safe }`.
  - Source: OCaml project, **`lambda/translprim.ml`**, trunk snapshot (2026): https://github.com/ocaml/ocaml/blob/trunk/lambda/translprim.ml

### Version distinctions and compatibility

- The relevant OCaml 4.14 and 5.2 `Texp_ident`, `Texp_apply`, `Val_prim`, and primitive-description fields agree. Other Typedtree shapes do not: notably, `Texp_function` changed from a single-parameter record in 4.14 to `function_param list * function_body` in 5.2.
  - Sources: the versioned `typedtree.mli` files above.
- Primitive native representation renamed `Untagged_int` in 4.14 to `Untagged_immediate` in 5.2.
  - Sources: the versioned `primitive.mli` files above.
- OCaml explicitly gives no backward-compatibility guarantee for compiler-libs/front-end interfaces. Code using them is expected to depend on particular compiler versions.
  - Sources: OCaml project, **“Compiler_libs”**, OCaml Manual 4.08 (2019): https://ocaml.org/manual/4.08/compilerlibref/Compiler_libs.html
  - OCaml project, **“The compiler front-end”**, OCaml Manual 5.5 (2026): https://ocaml.org/manual/5.5/parsing.html
- Compilation artifact formats are compiler-version-sensitive; changes to type representation can require artifact-format and magic-number changes.
  - Source: OCaml project, **“Bootstrapping the compiler”**, trunk snapshot (2026): https://github.com/ocaml/ocaml/blob/trunk/BOOTSTRAP.adoc

### Machine-integer semantics

- OCaml `int` is `Sys.int_size` bits wide, two's-complement, and arithmetic is modulo `2^Sys.int_size`; overflow does not raise. `max_int = 2^(Sys.int_size-1)-1`, and `min_int = -2^(Sys.int_size-1)`. Division truncates toward zero and raises `Division_by_zero` for a zero divisor.
  - Source: OCaml project, **“Module Int”**, API version 5.5 (2026): https://ocaml.org/manual/5.5/api/Int.html
- The runtime computes `Sys.int_size` as `8 * sizeof(value) - 1`, reflecting the tagged representation: normally 31 bits on a 32-bit target and 63 bits on a 64-bit target.
  - Source: OCaml project, **`runtime/sys.c`**, trunk snapshot (2026): https://github.com/ocaml/ocaml/blob/trunk/runtime/sys.c
- OCaml 5.5 added separately named floor, ceiling, and Euclidean division operations (`Int.fdiv`, `Int.cdiv`, `Int.ediv`, and `Int.erem`); ordinary `Int.div` retained truncation toward zero.
  - Source: OCaml project, **“Module Int”**, API version 5.5 (2026): https://ocaml.org/manual/5.5/api/Int.html

### OCaml 5.3-specific check

- The versioned OCaml 5.3 `Int` API says `int` values are `Sys.int_size` bits wide and use two's-complement representation. All operations are modulo `2^Sys.int_size` and do not fail on overflow. It gives `min_int = -2^(Sys.int_size-1)` and `max_int = 2^(Sys.int_size-1)-1`.
  - Source: OCaml project, **“Module Int”**, API version 5.3 (2025): https://ocaml.org/manual/5.3/api/Int.html
- The OCaml 5.3 `Stdlib` interface repeats the modulo-arithmetic/no-overflow rule and binds integer operations to these primitive names:
  - unary negation `%negint`;
  - `succ` `%succint` and `pred` `%predint`;
  - addition `%addint`, subtraction `%subint`, multiplication `%mulint`;
  - division `%divint` and remainder `%modint`;
  - bitwise operations `%andint`, `%orint`, `%xorint`, `%lslint`, `%lsrint`, and `%asrint`.
  - Source: OCaml project, **`stdlib/stdlib.mli`**, branch 5.3 (2025): https://github.com/ocaml/ocaml/blob/5.3/stdlib/stdlib.mli
- The same 5.3 interface states that integer division rounds the real quotient toward zero and raises `Division_by_zero` when the second argument is zero. For nonzero `y`, remainder satisfies `x = (x / y) * y + x mod y`, `abs (x mod y) <= abs y - 1`, and is negative only if `x < 0`; a zero divisor raises `Division_by_zero`.
  - Source: OCaml project, **`stdlib/stdlib.mli`**, branch 5.3 (2025): https://github.com/ocaml/ocaml/blob/5.3/stdlib/stdlib.mli
- The OCaml 5.3 compiler maps `%addint` to `Paddint`, `%subint` to `Psubint`, `%mulint` to `Pmulint`, `%divint` to `Pdivint Safe`, and `%modint` to `Pmodint Safe`. It maps specialized integer comparison identities `%eq`, `%noteq`, `%ltint`, `%leint`, `%gtint`, and `%geint` to `Pintcomp Ceq`, `Cne`, `Clt`, `Cle`, `Cgt`, and `Cge`, respectively.
  - Source: OCaml project, **`lambda/translprim.ml`**, branch 5.3 (2025): https://github.com/ocaml/ocaml/blob/5.3/lambda/translprim.ml
- Source-level polymorphic comparisons have different declared primitive identities in 5.3: structural `=` is `%equal`, `<>` is `%notequal`, `<` is `%lessthan`, `>` is `%greaterthan`, `<=` is `%lessequal`, `>=` is `%greaterequal`, and `compare` is `%compare`. Physical equality and inequality are `%eq` and `%noteq`. Thus the compiler table's specialized `%ltint` and related names are distinct from the source declarations of polymorphic comparison operators.
  - Source: OCaml project, **`stdlib/stdlib.mli`**, branch 5.3 (2025): https://github.com/ocaml/ocaml/blob/5.3/stdlib/stdlib.mli

## Q7 — How do established intraprocedural abstract interpreters represent integer division, overflow, branches, joins, top/bottom, and conservative unknown results?

### State lattice, branches, and joins

- Frama-C Eva defines an abstract domain as states propagated through a control-flow graph; each state over-approximates the concrete states possible at that point.
  - Source: Frama-C project, **`Eva.Abstract_domain` API**, current documentation (2026): https://www.frama-c.com/api/frama-c-eva/Eva/Abstract_domain/index.html
- Eva's concrete memory abstraction exposes `bottom` as a state reachable only in dead code, `top` as the least precise state, `join` for merging states, inclusion, and widening.
  - Source: Frama-C project, **`Cvalue.Model` API**, current documentation (2026): https://www.frama-c.com/api/frama-c/Frama_c_kernel/Cvalue/Model/index.html
- Branch conditions can produce `True`, `False`, a reduced but still unknown state, or `Unreachable`; discovering a contradiction yields bottom.
  - Source: Frama-C project, **Eva evaluation API**, current documentation (2026): https://www.frama-c.com/api/frama-c-eva/Eva_gui/Gui_eval/module-type-S/Analysis/Eval/index.html
- Infer's official intraprocedural analysis lab requires a `join` once branching is introduced, then `leq` and `widen` for loops; it introduces a `Top` value greater than every finite integer to ensure termination.
  - Source: Meta, **“Build your own Resource Leak analysis”**, Infer repository, current `main` snapshot (2026): https://github.com/facebook/infer/blob/main/infer/src/labs/README.md
- Goblint's official tutorial constructs a sign lattice with explicit top and bottom. Joining positive and zero in a flat lattice produces top, while a powerset refinement can represent their union as non-negative.
  - Source: Goblint project, **“Your first analysis”**, current documentation (2026): https://goblint.readthedocs.io/en/latest/developer-guide/firstanalysis/

### Integer division, overflow, and conservative unknowns

- Frama-C's integer interval API specifies `scale_div` as an over-approximation and distinguishes C99-style truncating division from Euclidean division. General `div` returns an interval or bottom.
  - Source: Frama-C project, **`Int_val` API**, current documentation (2026): https://www.frama-c.com/api/frama-c/Frama_c_kernel/Int_val/index.html
- Goblint checks the divisor abstract value before abstract division: definitely zero emits an error, possibly zero emits a warning, and definitely nonzero is marked safe; it then invokes the integer domain's `div`. Unsupported integer binary operators return type-appropriate top, while bottom operands propagate bottom.
  - Source: Goblint project, **`src/analyses/base.ml`**, current `master` snapshot (2026): https://github.com/goblint/analyzer/blob/master/src/analyses/base.ml
- Eva reports possible signed overflow as an alarm while continuing with an over-approximation. Its published example derives a non-negative return interval while alarming on negation of the smallest signed integer.
  - Source: Frama-C project, **“Eva, an Evolved Value Analysis”** (2026): https://www.frama-c.com/fc-plugins/eva.html
- Eva query results explicitly distinguish “not evaluated” (`Top`) from infeasible (`Bottom`) and successfully over-approximated values. Its widening operation is documented as an over-approximation of join.
  - Sources: Frama-C project, **`Eva.Abstract_domain` API**: https://www.frama-c.com/api/frama-c-eva/Eva/Abstract_domain/index.html
  - Frama-C project, **`Eva.Domain_product.Make` API**: https://frama-c.com/api/frama-c-eva/Eva/Domain_product/Make/index.html
- Frama-C's interval abstraction supports finite or unbounded bounds, bottom detection, join, and widening with bit-size and threshold hints.
  - Source: Frama-C project, **`Ival` API**, current documentation (2026): https://www.frama-c.com/api/frama-c/Frama_c_kernel_base/Ival/index.html

## Conflicts, caveats, and evidence gaps

- There is no semantic conflict among the sources once their concrete languages are distinguished. OCaml `int` overflow is defined as modular arithmetic. Eva and Goblint analyze C and therefore document C-specific overflow and division cases. Their C semantics must not be transferred to OCaml.
- No cited official source defines one cross-version stable primitive-identity API. OCaml compiler-libs explicitly disclaims backward compatibility.
- The external sources establish OCaml 4.14, 5.2, 5.3, and 5.5 behavior and interfaces, but they do not state which of those versions any particular third-party repository supports. That requires repository evidence outside this report's external-only scope.
- Neither the OCaml 5.3 `Int` API nor the 5.3 `Stdlib` interface separately documents the exceptional operand pair `min_int / -1` or `min_int mod -1`. The general modulo/no-overflow statement and division/remainder laws are present, but these public documents provide no dedicated result or exception clause for that pair. Its behavior is therefore recorded here as an explicit documentation gap rather than inferred.
- The cited analyzer APIs establish conservative results, joins, top/bottom, division, overflow alarms, and widening. They do not prescribe one universal interval-division formula when a divisor interval straddles zero; implementations differ in whether they split values, issue alarms, or return a coarser abstraction.
