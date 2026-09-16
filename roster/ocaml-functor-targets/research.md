# Research — ocaml-functor-targets

_Generated: 2026-09-16T20:19:36+02:00_
_Mode: full_
_Online research: enabled_

## Question 1: Where are OCaml functor definitions, formal parameter bindings, and functor applications represented, and which stable identities link these records across indexing stages?

**Finding:** `Arch_index_bindings` pre-indexes named module binders and local
`let module` binders. A binder becomes a declaration when its constraint-peeled
right-hand side is immediately a `Tmod_functor`; consecutive functor nodes form a
one-based formal telescope. Compiler-side comparisons use `Ident.same`, while
persisted declaration and binder keys use `Ident.unique_name`.

`Arch_index_functors` inventories immediate `Tmod_apply` and `Tmod_apply_unit`
occurrences in preorder. Each occurrence receives an ordinal, and an outer curried
application can point to its inner application ordinal. Collection of the catalogue
and bindings is performed over the same decoded implementation structure.

The persisted application identity is `(producer_run_id, artifact, ordinal)` and
the declaration identity is `(producer_run_id, artifact, declaration_key)`.
`formal_position` selects the declaration slot and `actual_root_key` stores the
eligible actual module's local compiler identity. These compiler identities are
deliberately artifact-scoped.

**References:**
- `lib/arch_index/arch_index_bindings.ml:41` — declaration and formal records.
- `lib/arch_index/arch_index_bindings.ml:44` — persisted compiler key construction.
- `lib/arch_index/arch_index_bindings.ml:57` — named module-binder pre-indexing.
- `lib/arch_index/arch_index_bindings.ml:93` — local module-binder pre-indexing.
- `lib/arch_index/arch_index_bindings.ml:106` — functor telescope extraction.
- `lib/arch_index/arch_index_functors.ml:56` — preorder occurrence collection.
- `lib/arch_index/arch_index_functors.ml:73` — ordinary application occurrence.
- `lib/arch_index/arch_index_functors.ml:90` — unit application occurrence.
- `lib/arch_index/arch_index.ml:668` — catalogue and binding jobs from one structure.
- `architecture-schema.sql:77` — application primary key.
- `architecture-schema.sql:101` — declaration primary key.
- `architecture-schema.sql:124` — binding-to-application foreign key.

---

## Question 2: How does the current target-resolution pipeline represent module members, member targets, unknown contributions, and ambiguous or unresolved correspondences?

**Finding:** Same-CMT structured module ownership is a map keyed by compiler
`Ident.t`. Export records map member names to either `Direct_body`,
`One_hop_alias`, or `None`; the last form records that a named contribution exists
without claiming a body. Structures and peeled constraints can establish owners,
whereas functor definitions and applications are traversed but do not themselves
become concrete owners.

CFA cells independently accumulate known target names, uncertainty reasons and
partial-application residuals. Joins union all three components. Expansion emits
known `Head_enumerated` contributions and separate `Head_unknown` contributions;
bottom preserves the original unresolved contribution.

Final qualified correspondence has three outcomes: one resolved function id,
ambiguity, or no indexed match. Ambiguity becomes `MAY_TOP/ambiguous_unit`, a
known dropped body becomes `MAY_TOP/dropped_node`, and a true not-found target
remains an external leaf with a null callee id.

**References:**
- `lib/arch_index/arch_index_cmt.ml:1155` — compiler-identity module ownership.
- `lib/arch_index/arch_index_cmt.ml:1165` — concrete member target variants.
- `lib/arch_index/arch_index_cmt.ml:1183` — owned-structure collection boundary.
- `lib/arch_index/arch_index_cmt.ml:1207` — opaque value contribution.
- `lib/arch_index/arch_index_cmt.ml:1248` — opaque include contribution.
- `lib/arch_index/arch_index_cfa.ml:3` — value-cell representation.
- `lib/arch_index/arch_index_cfa.ml:117` — monotone component-wise join.
- `lib/arch_index/arch_index_cmt.ml:676` — CFA target expansion.
- `lib/arch_index/arch_index_cmt.ml:713` — bottom fallback preservation.
- `lib/arch_index/arch_index.ml:1386` — qualified-candidate correspondence.
- `lib/arch_index/arch_index.ml:1525` — ambiguous qualified target persistence.

---

## Question 3: Which explicit functor-application identity forms are currently recognized, and where are unsupported or incomplete identities rejected, ignored, or preserved as unknown?

**Finding:** The syntax catalogue recognizes `Tmod_apply` and
`Tmod_apply_unit`. Its shallow operand descriptors preserve paths, structures,
functors, unpacks, constraints, nested application ordinals and unit arguments.
`Path.Papply` embedded in a path remains path data marked `contains_apply`; it is
not a separate occurrence.

Binding resolution recognizes a constraint-peeled local `Path.Pident` head, local
identity-alias chains and curried heads formed by nested apply/apply-unit nodes.
An actual root key is recorded only for a constraint-peeled `Tmod_ident` whose
path contains no `Papply` and starts from a nonpersistent identifier.

Unsupported heads remain explicit unresolved binding rows with closed reasons,
including `cross_unit_head`, `parameter_supplied_head`, `alias_cycle`,
`local_declaration_missing`, `unsupported_alias_rhs`, `unsupported_path`,
`unsupported_head_shape`, `curried_result_not_functor` and
`formal_kind_mismatch`. The catalogue likewise retains opaque occurrences and
attaches diagnostics such as `opaque_functor_head`, `anonymous_argument` and
`unpacked_expression`.

**References:**
- `lib/arch_index/arch_index_functors.ml:5` — occurrence and operand kinds.
- `lib/arch_index/arch_index_functors.ml:18` — structural path descriptor.
- `lib/arch_index/arch_index_functors.ml:120` — opaque-form diagnostics.
- `lib/arch_index/arch_index_bindings.ml:139` — local head/alias resolution.
- `lib/arch_index/arch_index_bindings.ml:148` — curried formal advancement.
- `lib/arch_index/arch_index_bindings.ml:169` — accepted head shapes.
- `lib/arch_index/arch_index_bindings.ml:179` — accepted actual-root shape.
- `lib/arch_index/arch_index_bindings.ml:199` — unresolved-row preservation.
- `lib/arch_index/arch_index_cmt.ml:1274` — local lookup excludes `Papply`.

---

## Question 4: How does the codebase distinguish independently compiled variants originating from the same source, and which compilation-unit or artifact identities participate in matching?

**Finding:** Catalogue inputs are scoped by exact artifact path and store their
resolved source, compiler unit and module id. Graph reuse is keyed by
`(project_root, resolved_source, cmt_modname)` but is admitted only when the full
artifact bytes and saved SHA-256 fingerprint match. A reuse hit shares graph facts
through `module_id` while re-running per-artifact catalogue and binding collection.

Nonidentical same-source artifacts do not reuse the graph. Because the main graph
has one module row per unique source path, a later nonidentical variant can be
recorded as a dropped module. Cross-unit target matching uses `cmt_modname` mapped
to every distinct source-relative path observed for that unit; one resulting
function id resolves, multiple ids are ambiguous, and none is not found.

**References:**
- `architecture-schema.sql:66` — per-artifact catalogue input fields.
- `lib/arch_index/arch_index_cmt.ml:51` — compiler-unit-to-source mapping.
- `lib/arch_index/arch_index_cmt.ml:3291` — graph reuse representative.
- `lib/arch_index/arch_index_cmt.ml:3295` — graph reuse key.
- `lib/arch_index/arch_index_cmt.ml:3307` — byte/fingerprint reuse guard.
- `lib/arch_index/arch_index_cmt.ml:3395` — per-artifact collection on reuse.
- `lib/arch_index/arch_index_cmt.ml:3421` — normal module insertion path.
- `lib/arch_index/arch_index_cmt.ml:3458` — dropped-variant registration.
- `lib/arch_index/arch_index.ml:1064` — compiler-unit qualified matching.

---

## Question 5: What deterministic tests and benchmark fixtures currently cover OCaml module resolution, functor bindings, large Irmin or Tezos analyses, and reported precision or coverage metrics?

**Finding:** Native Tezt fixtures cover catalogue shapes, ordinary and unit
applications, nested/curried applications, alias chains, shadowed declarations,
formal-position matching and closed unresolved reasons. Lifecycle checks cover
unreadable and missing inputs, exact copies, same-source changed-byte variants,
symlinks and reindexing. The composition fixture asserts that inventorying an
application does not clone instantiated functions or add call edges.

The committed pinned Tezos/Irmin corpus contains 410 selected CMT inputs. Its
existing functor census reports 1,275 syntactic applications: 202 matched and
1,073 unresolved, including 1,050 `unsupported_path`; it explicitly does not claim
a call-graph precision gain. It also distinguishes 128 display strings from 240
artifact-local `Path.same` identity classes.

**References:**
- `tezt/tests/functor_bindings.ml:405` — curried application/formal assertions.
- `tezt/tests/functor_bindings.ml:434` — shadowed declarations remain distinct.
- `tezt/tests/functor_catalogue.ml:127` — non-instantiation composition contract.
- `tezt/fixtures/functor_catalogue/lifecycle_checks.js:62` — exact-copy lifecycle case.
- `tezt/fixtures/functor_catalogue/lifecycle_checks.js:99` — changed-byte variant case.
- `roster/functor-instance-resolution/tezos-irmin-candidate/manifest-410.tsv:1` — pinned corpus manifest.
- `roster/functor-path-census/measurement.md:12` — fixed-corpus counts.
- `roster/functor-path-census/measurement.md:56` — limits of the measurement claim.
- `briefs/functor-path-census-pr.md:5` — shipped result records no Tezos precision gain.

---

## Question 6: [ecosystem] How do existing OCaml compiler artifacts and analysis tools encode functor parameters, applications, module paths, and identities across separate compilation?

**Finding:** The OCaml typed representation distinguishes named and unit functor
parameters (`Mty_functor`; `Tmod_functor`) and ordinary from unit applications
(`Tmod_apply`; `Tmod_apply_unit`). Resolved paths are structural trees of
`Pident`, `Pdot` and `Papply`. Local `Ident.t` equality follows binding identity;
persistent roots representing separately compiled units compare by name, with
compiled-interface digests enforcing consistency.

Current CMT/CMti information also contains imported digests, declaration
dependencies, a UID-to-declaration table, implementation `Shape` and identifier
occurrences with shape-reduction results. Shapes represent module operations with
variables, abstraction, application, structure, projection, alias and compilation
unit nodes. Tooling such as Merlin and `ocaml-index` uses UIDs, shapes and occurrence
tables for cross-file navigation. Items reachable only through a functor parameter
can have local opaque UIDs because the concrete definition is not known in the
functor body.

Odoc maintains a distinct documentation identity model with explicit functor
parameter/result hierarchy and resolved/unresolved `Apply` paths. It is not the
compiler UID scheme. The OCaml frontend guide's MD5 wording conflicts with current
trunk's `Digest.BLAKE128.t`; the separate-compilation consistency role is the same,
but the documented algorithm is stale.

**References:**
- [OCaml `Types` interface](https://github.com/ocaml/ocaml/blob/trunk/typing/types.mli) — functor module types and UIDs.
- [OCaml Typedtree interface](https://github.com/ocaml/ocaml/blob/trunk/typing/typedtree.mli) — functor and application nodes.
- [OCaml path interface](https://github.com/ocaml/ocaml/blob/trunk/typing/path.mli) — `Pident`, `Pdot` and `Papply`.
- [OCaml CMT format](https://github.com/ocaml/ocaml/blob/trunk/file_formats/cmt_format.mli) — typed payload, imports, occurrences, UIDs and shapes.
- [OCaml module Shapes](https://github.com/ocaml/ocaml/blob/trunk/typing/shape.mli) — module-calculus representation and reduction.
- [Module Shapes for Modern Tooling](https://icfp22.sigplan.org/details/mlfamilyworkshop-2022-papers/10/Module-Shapes-for-Modern-Tooling) — Réfis, Gérard and White, 2022.
- [Merlin changelog](https://github.com/ocaml/merlin/blob/main/CHANGES.md) — shape-based locate and project indexing history.
- [Odoc path model](https://github.com/ocaml/odoc/blob/master/src/model/paths_types.ml) — documentation identities and apply paths.
- [Current CMI format](https://github.com/ocaml/ocaml/blob/trunk/file_formats/cmi_format.mli) — interface digest representation.
- [OCaml compiler frontend guide](https://ocaml.org/docs/compiler-frontend) — separate-compilation interface checking and stale MD5 wording.

## Patterns found

| Pattern | File | Lines | Notes |
|---|---|---:|---|
| Artifact-scoped application identity | `architecture-schema.sql` | 77–86 | Run, artifact and preorder ordinal form the occurrence key. |
| Compiler-identity formal binding | `lib/arch_index/arch_index_bindings.ml` | 106–189 | Declaration/formal/actual identities stay local to one typed artifact. |
| Known plus unknown union | `lib/arch_index/arch_index_cfa.ml` | 117–128 | Target, reason and residual sets join independently. |
| Owned member with opaque body | `lib/arch_index/arch_index_cmt.ml` | 1207–1248 | `None` preserves a named contribution without inventing a target. |
| Exact-artifact graph reuse | `lib/arch_index/arch_index_cmt.ml` | 3291–3410 | Same-source reuse additionally requires byte and fingerprint equality. |

## External prior art

| Tool / approach | Source | Key finding |
|---|---|---|
| OCaml Shapes | [Compiler source](https://github.com/ocaml/ocaml/blob/trunk/typing/shape.mli) | Represents functor abstraction/application and reduces cross-unit paths toward UIDs. |
| Merlin / ocaml-index | [Merlin history](https://github.com/ocaml/merlin/blob/main/CHANGES.md) | Uses compiler occurrences, UIDs and shapes for project-wide navigation. |
| Odoc paths | [Odoc source](https://github.com/ocaml/odoc/blob/master/src/model/paths_types.ml) | Keeps a separate documentation-oriented identity hierarchy and explicit apply paths. |

## Coverage gaps

- The existing repository evidence contains no general cross-artifact compiler-identity join for nonidentical same-source CMT variants.
- The committed Tezos/Irmin census measures catalogue/binding classifications; it does not measure target-resolution precision attributable to concrete functor arguments.
