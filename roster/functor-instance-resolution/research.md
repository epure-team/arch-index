# Research — functor-instance-resolution

_Generated: 2026-09-13T11:18:47+02:00_
_Mode: full_
_Online research: enabled_
_Concurrency adaptation: four specialist roles ran with at most two workers concurrently, in two waves. Unavailable Haiku/Sonnet tiers were mapped to Terra for locator/pattern work and Sol for analyzer/external work._
_Orientation: claims reconciler and acknowledged `research-orientation` resolver were absent. Manifest structure was checked locally; its upstream-validated digest was retained. The blind grep/read flow was used._
_Version boundary: primary ecosystem sources describe OCaml 5.5 / compiler-libs 5.5.1; the coordinator reports the local compiler as 5.3.0. Compiler-libs does not guarantee cross-revision compatibility, so ecosystem artifact findings are not asserted as guarantees of the installed 5.3 interfaces._

## Question 1: How does the analyzer currently decode OCaml module expressions, module applications, functor parameters, anonymous structures, and nested application chains from compiler artifacts?

**Finding:** The producer reads CMT `Implementation structure` annotations, derives compiler-unit identity from `cmt_modname`, and indexes nested definitions through one recursive Typedtree traversal. It descends named module bindings, recursive modules, includes, literal structures, functor bodies, and constraints. It does not descend `Tmod_apply`, `Tmod_apply_unit`, `Tmod_ident`, or `Tmod_unpack`; an unnamed binding (`mb_id = None`) is skipped. Thus functor bodies are definition sites, while applications do not materialize application-specific definitions. Functor bodies are separately walked in deferred execution blocks for call conditionality.

Dependency decoding is narrower: a module expression becomes a dependency path only when it is `Tmod_ident`, possibly beneath constraints. Path formatting recursively renders dotted paths; an applied prefix is rendered as `<apply>` rather than decoded into an instance.

**References:**

- `lib/arch_index/arch_index_cmt.ml:162-198` — shared module/structure traversal and terminal application shapes.
- `lib/arch_index/arch_index_cmt.ml:721-756` — module-path extraction and applied-path rendering.
- `lib/arch_index/arch_index_cmt.ml:2518-2528` — deferred functor-body call traversal.
- `lib/arch_index/arch_index_cmt.ml:2755-2767` — CMT annotation, source, and compiler-unit entry path.
- `lib/arch_index/arch_index_cmt.ml:2930-2945` — one definition row independent of application count; dependencies are file-scoped.

---

## Question 2: Where and how are module paths normalized today, including module-alias rewrites, unresolved paths, and the preservation of source-level versus canonical identities?

**Finding:** Source-file identity is the unique `modules.path`; compiler unit ownership comes from `cmt_modname`; definitions are identified by source module plus qualified definition name. Nested names are flattened as `Outer.Inner.f`.

Local module-alias normalization is per CMT and keyed by `Ident.unique_name`, preserving binder identity under shadowing. Only alias targets with a persistent root are recorded. Literal structures, applications, unpacking, aliases to functor parameters, and unit-local module roots are declined. Rewriting preserves dotted segments below the alias root. If a qualified root is non-persistent and cannot be rewritten, the call head remains dynamic and is emitted with `module_param` uncertainty.

Qualified resolution enumerates possible Dune-style compilation-unit prefixes and residual definition names, collects distinct function ids, and consults weaker facade/suffix readings only when prefix readings return nothing. Module-dependency normalization is separate: exact stored target path first, then final dotted segment through a basename map.

**References:**

- `architecture-schema.sql:61-64`, `architecture-schema.sql:81-126` — source module and definition identity.
- `lib/arch_index/arch_index_cmt.ml:152-160` — qualified nested definition names.
- `lib/arch_index/arch_index_cmt.ml:1044-1079`, `lib/arch_index/arch_index_cmt.ml:1080-1108` — alias-table identity and admitted/declined targets.
- `lib/arch_index/arch_index_cmt.ml:1333-1393`, `lib/arch_index/arch_index_cmt.ml:1453-1469` — dynamic roots, rewrite, and unresolved module-parameter heads.
- `lib/arch_index/arch_index.ml:896-922`, `lib/arch_index/arch_index.ml:992-1022`, `lib/arch_index/arch_index.ml:1318-1333` — qualified reading enumeration and verdict.
- `lib/arch_index/arch_index.ml:1611-1636` — module-dependency lookup.

---

## Question 3: What database entities and invariants currently represent definitions, bodies, module instances, call sites, and call-graph targets, and which uniqueness constraints govern them?

**Finding:** Source files are `modules` rows, unique by path. Definitions are `functions` rows owned by a module and unique on `(module_id, name)`, with source spans. No dedicated persisted `definitions`, `bodies`, or `module_instances` table exists in the inspected producer schema. Applied functor results intentionally create no additional definition rows. Body comparison reconstructs text from source path and line span rather than loading a stored body entity.

A call site is a `calls` row with required caller, nullable target id, required target display name, optional site, edge kind, producer, top reason/anchor, and edge form. The table has non-unique indexes but no uniqueness constraint over call tuples. Module dependencies preserve both a nullable resolved target and required textual target path. Exception aliases use `alias_path` as a primary key; call/exception-scope membership is unique by `(call_id, scope_id)`.

**References:**

- `architecture-schema.sql:61-126` — modules/functions and uniqueness.
- `architecture-schema.sql:208-284` — calls entity, constraints, and non-unique indexes.
- `architecture-schema.sql:294-308` — module dependencies.
- `architecture-schema.sql:494-502` — call-scope and exception-alias keys.
- `lib/arch_index/arch_index_compare.ml:71-125` — body reconstruction from path/span.
- `tezt/tests/ocaml_shapes.ml:256-265`; `tezt/tests/callgraph_nested.ml:202-207` — application non-materialization.

---

## Question 4: How does the current call-resolution pipeline distinguish a uniquely resolved target, multiple possible targets, and an unresolved or uncertain target?

**Finding:** Resolution state is distributed across `callee_id`, `kind`, and `top_reason`:

- one distinct indexed target preserves its id; unconditional saturated local/qualified calls are `MUST`, while conditional, partial, or alias-shaped calls are demoted to `MAY_ENUMERATED`;
- multiple distinct indexed qualified targets become `callee_id = NULL`, `MAY_TOP`, `ambiguous_unit`;
- no indexed result for a persistent qualified target remains a nullable external leaf with `MUST` or `MAY_ENUMERATED` according to demotion;
- computed/dynamic heads become `MAY_TOP` with a reason such as `callback_param` or `module_param`;
- a target known to have been dropped becomes `MAY_TOP/dropped_node`.

The loaded graph follows `MUST ∪ MAY_ENUMERATED`, preserves a separate MUST-only graph, turns nullable non-top callees into `ext:` leaves, and records `MAY_TOP` as a non-traversed frontier. Closure uses a visited set; witness paths use BFS.

Query-level `UNKNOWN` and `NOT_ANALYSED` remain distinct. `UNKNOWN` is computed when no resolved path is found but a reachable top/non-resolved frontier exists. Exception `NOT_ANALYSED` is a refusal caused by missing producer evidence/contract.

**References:**

- `architecture-schema.sql:208-253` — persisted state contract.
- `lib/arch_index/arch_index.ml:878-892`, `lib/arch_index/arch_index.ml:1006-1022`, `lib/arch_index/arch_index.ml:1458-1490` — classification and qualified outcomes.
- `lib/arch_tools/arch_graph.ml:28-33`, `lib/arch_tools/arch_graph.ml:84-120`, `lib/arch_tools/arch_graph.ml:129-207` — graph loading, closure, and witnesses.
- `bin/arch_query/arch_query.ml:358-395` — `REACHABLE` / `UNKNOWN` / `UNREACHABLE` query behavior.
- `lib/arch_tools/arch_exn.ml:22-26`, `lib/arch_tools/arch_exn.ml:91-93` — explicit `NOT_ANALYSED` refusal.

---

## Question 5: Which native fixtures and query-level tests currently exercise modules, functors, aliases, exception identities, and bounded graph-enumeration behavior?

**Finding:** Existing Tezt fixtures cover nested modules, curried functors and applications, local/first-class modules, anonymous `include struct`, nested qualified lookup, alias shadowing and intermediate segments, direct and aliased functor-parameter calls, ambiguous unit readings, point-free alias chains, exception declarations/rebindings, and graphs containing MUST, MAY_ENUMERATED, MAY_TOP, and nullable external leaves.

**References:**

- `tezt/tests/ocaml_shapes.ml:31-71`, `tezt/tests/ocaml_shapes.ml:202-321` — nested definitions, functors/applications, absence of applied definitions, and nested reachability.
- `tezt/tests/callgraph_nested.ml:130-207`, `tezt/tests/callgraph_nested.ml:235-250` — anonymous include, applied-module non-materialization, functor-body reachability and top frontier.
- `tezt/tests/module_alias_heads.ml:74-180`, `tezt/tests/module_alias_heads.ml:291-454`, `tezt/tests/module_alias_heads.ml:541-554` — alias variants, demotion, and scope identity.
- `tezt/tests/qualified_library_scoping.ml:342-364` — ambiguous qualified target.
- `tezt/tests/point_free_aliases.ml:318` — bounded alias-chain edges.
- `tezt/tests/exn_raise_sets.ml:28-35`, `tezt/tests/exn_raise_sets.ml:262-267`, `tezt/tests/exn_raise_sets.ml:395-411` — exception identity and rebinding.
- `tezt/tests/contract.ml:22-52`, `tezt/tests/contract.ml:138-167` — bounded graph/query outcomes and nullable leaf behavior.

---

## Question 6: [ecosystem] What identities and application structure do current OCaml compiler artifacts expose for functor applications, module arguments, aliases, anonymous structures, and generative definitions?

**Finding:** In the researched OCaml 5.5 interfaces, Typedtree distinguishes ordinary `Tmod_apply` from unit/generative `Tmod_apply_unit`; an ordinary application retains both complete module expressions, so an anonymous structure remains a `Tmod_structure` argument rather than being reduced to a path. Module identifiers carry a resolved `Path.t` plus source `Longident`. `Path.t` structurally represents applicative paths with `Papply`, including nested applications. Module bindings have compiler binder identities (`Ident.t`/`Uid.t`), but the application expression has no documented standalone UID field. These are 5.5 ecosystem facts, not a compatibility guarantee for local OCaml 5.3.

Compiler `Shape` is the artifact specifically intended to track definitions through module operations and functor application. Its algebra includes applications, structures, aliases, projections, leaves, and abstractions; reduction can yield exact UIDs, alias chains, locally generated stuck identities, or approximations. Exception artifacts distinguish declarations from rebindings.

**Sources:**

- [The compiler front-end — OCaml Manual 5.5](https://ocaml.org/manual/5.5/parsing.html), OCaml authors, 2026.
- [typedtree.mli — OCaml compiler 5.5](https://github.com/ocaml/ocaml/blob/5.5/typing/typedtree.mli#L2837-L2890), OCaml project.
- [path.mli — OCaml compiler 5.5](https://github.com/ocaml/ocaml/blob/5.5/typing/path.mli#L403-L419), OCaml project.
- [Module Shape — ocaml-compiler 5.5.1](https://ocaml.org/p/ocaml-compiler/latest/compiler-libs.common/Shape/index.html), OCaml project, 2026.
- [Module Shape_reduce — ocaml-compiler 5.5.1](https://ocaml.org/p/ocaml-compiler/latest/compiler-libs.common/Shape_reduce/index.html), OCaml project, 2026.

---

## Question 7: [ecosystem] What guarantees does the OCaml language and compiler documentation provide about applicative versus generative functors and the identity of exceptions defined within module or functor bodies?

**Finding:** Ordinary functor application is applicative for result type components when the same functor is applied to the same defined module. A unit functor is generative: each application produces different result type components. The guarantee is about type identity, not equality of runtime module values; functor application evaluates its result module expression.

Every ordinary exception declaration creates a new exception distinct from every other declaration, while an exception rebind is an alternate name for an existing exception. Therefore, by the documented evaluation and exception-declaration rules, evaluating a functor body containing a declaration creates a fresh runtime exception on each body evaluation. Type-level module aliases separately participate in static path equality.

**Sources:**

- [Generative functors — OCaml Manual 5.5 §12.15](https://ocaml.org/manual/5.5/generativefunctors.html), OCaml authors/INRIA, 2026.
- [Module expressions — OCaml Manual 5.5 §§11.2–11.3](https://ocaml.org/manual/5.5/modules.html), OCaml authors/INRIA, 2026.
- [Type and exception definitions — OCaml Manual 5.5 §11.8.2](https://ocaml.org/manual/5.5/typedecl.html), OCaml authors/INRIA, 2026.
- [Type-level module aliases — OCaml Manual 5.5 §12.8](https://ocaml.org/manual/5.5/modulealias.html), OCaml authors/INRIA, 2026.

## Patterns found

| Pattern | File | Lines | Notes |
|---|---|---:|---|
| Definition traversal stops at applications | `lib/arch_index/arch_index_cmt.ml` | 162-198 | Definitions are indexed once at their defining body. |
| Persistent-root alias rewrite | `lib/arch_index/arch_index_cmt.ml` | 1044-1108 | Binder-stamp keyed and per CMT. |
| Distinct-id qualified resolution | `lib/arch_index/arch_index.ml` | 1006-1022 | One, multiple, and zero indexed targets have separate outcomes. |
| Top frontier is retained but not traversed | `lib/arch_tools/arch_graph.ml` | 84-120 | Bounded edges remain traversable. |

## External prior art

| Tool / artifact | Source | Key finding |
|---|---|---|
| OCaml Typedtree 5.5 | [typedtree.mli](https://github.com/ocaml/ocaml/blob/5.5/typing/typedtree.mli#L2837-L2890) | Retains application and argument expression structure. |
| OCaml Path 5.5 | [path.mli](https://github.com/ocaml/ocaml/blob/5.5/typing/path.mli#L403-L419) | `Papply` structurally represents applicative paths. |
| OCaml Shape 5.5.1 | [Shape](https://ocaml.org/p/ocaml-compiler/latest/compiler-libs.common/Shape/index.html) | Tracks definitions through functor/module operations. |

## Coverage gaps

- No dedicated module-instance identity or persisted functor-argument relation was found in the current producer schema.
- Existing fixtures assert application non-materialization; no direct test was found for target resolution from a compiler value path containing `Papply`.
- No direct fixture was found for an unnamed `module _ = ...`; the available anonymous-structure fixture is `include struct`.
- Call rows have no schema uniqueness key, and no inspected test establishes a call-tuple deduplication invariant.
- UID stability across rebuilds, compiler versions, and source movement: **UNKNOWN**.
- Parity of every cited OCaml 5.5 compiler-libs constructor/field with the local OCaml 5.3 installation: **UNKNOWN**; cross-revision compatibility is not guaranteed.
- A documented equivalence between `Path.same` and language-level applicative type equality: **UNKNOWN**.
- Runtime exception-slot representation and direct mapping to compiler `ext_uid`: **NOT_ANALYSED**.
- Third-party AST formats, Merlin/odoc identity behavior, and external-corpus behavior: **NOT_ANALYSED**.

## Process skips

- Claims reconciler `manifest-neutral`: skipped because no claims reconciler is present in this worktree; the manifest was structurally checked and its digest was already validated upstream.
- Graph-first orientation: skipped because `scripts/code-intel-resolve.js` is absent, so no acknowledged `research-orientation` pack can be resolved.
- Four-way simultaneous specialist fan-out: adapted, not hidden-skipped; runtime capacity allowed two worker slots, so four roles ran in two waves.
- Builds, tests, Dune commands, production edits, pipeline ledger, friction log, and commits: intentionally not performed under coordinator ownership boundaries.
