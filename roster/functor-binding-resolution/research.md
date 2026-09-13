# Research — functor-binding-resolution

_Generated: 2026-09-13_
_Mode: full; online research enabled for Q6 only._

Independent Sol analyzer, Terra pattern finder, Sol external documentarian;
Terra locator ran subsequently because root plus three agents exhausted available
concurrency. Input: closed neutral six-question manifest. No task/brief/roadmap
was supplied to the documentary roles. Code-intel resolver and claims reconciler
absent; live source references used. This report describes existing behavior only.

## Q1: Existing representations

Catalogue occurrence records carry preorder ordinal, kind, location, head,
argument and diagnostics. Typedtree Tmod_apply/Tmod_apply_unit are collected;
Tmod_functor descriptors expose unit/named parameter and optional spelling.
Path operands are serialized with Path.name plus source Longident spelling;
the original compiler identity is not a persisted binder key. Nested application
operands refer to another ordinal. Per-CMT module-alias tables instead use
Ident.unique_name, scoped within that artifact.

References: lib/arch_index/arch_index_functors.ml:5, :27, :56, :75, :95;
lib/arch_index/arch_index_cmt.ml:1044, :1068; architecture-schema.sql:61, :66, :77.
The targeted search found no separate project substitution table; this is a
search boundary, not a universal absence proof.

Locator paths: lib/arch_index/arch_index_cmt.ml and .mli; arch_index.ml and .mli;
lib/arch_index/arch_index_functors.ml and .mli;
lib/arch_tools/arch_functor_catalogue.ml; bin/arch_query/arch_query.ml;
scripts/check-functor-catalogue.js; architecture-schema.sql.
No independently named resolver module was found by filename search; the
content analyzer locates classification in arch_index.ml.

## Q2: Existing binding and resolution behavior

module_target_path unwraps constraints but only accepts Tmod_ident. Alias tables
accept persistent roots; parameters, local structures, application results and
unpacks are not accepted targets. Rewriting matches the local binder stamp and
Pdot segments; Papply/Pextra_ty are declined. A non-persistent qualified root
without a supported alias rewrite remains Head_unknown/module_param.
module_alias edges are demoted to MAY_ENUMERATED. Functor body definitions are
indexed once under their definition paths; applications do not clone graph rows.

References: lib/arch_index/arch_index_cmt.ml:721, :728, :1072, :1079, :1333,
:1365, :1374, :1425, :2948; lib/arch_index/arch_index.ml:1447, :1495;
tezt/tests/callgraph_nested.ml:168, :202;
tezt/tests/functor_catalogue.ml:72, :128.

## Q3: Recorded uncertainty

Catalogue syntax warnings are opaque_functor_head, anonymous_argument,
unpacked_expression and unusable_location. Input outcomes distinguish unreadable,
unsupported_annotation, missing_source, dropped_module, collection_failed and
collected. These are separate from graph kind/top_reason/callee_id/edge_form.
The graph's module_param category includes both functor and first-class-module
paths. Existing regression tests explicitly retain unknown targets for direct
parameters and parameter aliases, including shadowed names and several wrappers.
Neither catalogue nor graph uses a numerical confidence score.

References: lib/arch_index/arch_index_functors.ml:102;
architecture-schema.sql:66, :77, :247, :267;
lib/arch_index/arch_index_cmt.ml:549, :595;
tezt/tests/module_alias_heads.ml:428, :445, :468.

## Q4: Existing metrics

An ordinary fixture asserts one catalogue application, zero calls and zero M.*
cloned functions. Composition tests count eight immediate applications and
separately inspect unit/nested/anonymous shapes. Persistence validates expected
row counts, while query summary reports selected/total/returned/truncated rather
than resolved targets. Existing benchmark documentation separates syntax IDs
from same-occurrence graph outcomes and says lower aggregate MAY_TOP alone does
not establish improved precision.

References: tezt/tests/functor_catalogue.ml:54, :72, :134;
lib/arch_index/arch_index_functors.ml:132, :164;
lib/arch_tools/arch_functor_catalogue.ml:245;
roster/functor-instance-resolution/tezos-irmin-benchmark-inventory.md:66, :84.

## Q5: Existing fixed comparison artifacts

The prior inventory references Tezos1727d7e192f2374edda7ad7adceef6f4ec51f71a,
dirty46 entries, and OCaml5.3.0. Raw414 CMTs become an effective410 selected
manifest:66 core,17 pack,52 Unix,275 protocol. Three Dune aliases and one
unresolved generated source wrapper are excluded. The exact path/SHA256 manifest
digest is9e38880a52f855c58081b1a171af5879058cbaa2697aaa5694827cbd16f8ecd1.
The single candidate run records1275 applications (384 Irmin,891 protocol),
12373 functions and45018 calls (13601 MUST,23209 MAY_ENUMERATED,8208 MAY_TOP).
It explicitly disclaims A/B target-resolution gains.

References: roster/functor-instance-resolution/tezos-irmin-benchmark-inventory.md:8,
:39, :98; roster/functor-instance-resolution/tezos-irmin-candidate/provenance.json:2;
roster/functor-instance-resolution/tezos-irmin-candidate/report.md:27, :46, :62, :82;
roster/functor-instance-resolution/tezos-irmin-candidate/manifest-410.tsv:1.

## Q6: Existing OCaml5.3 compiler interfaces

Ident.same distinguishes non-persistent binding identity from spelling; persistent
identifiers compare by name. Path retains resolved Pident/Pdot/Papply structure.
Types.Uid aliases Shape.Uid, whose declaration identity distinguishes compilation
units/items and interface/implementation provenance. These are related but not
interchangeable identity domains.

Official OCaml5.3.0 API sources:
[Ident](https://ocaml.org/p/ocaml-compiler/5.3.0/compiler-libs.common/Ident/index.html),
[Path](https://ocaml.org/p/ocaml-compiler/5.3.0/compiler-libs.common/Path/index.html),
[Shape.Uid](https://ocaml.org/p/ocaml-compiler/5.3.0/compiler-libs.common/Shape/Uid/index.html).

Types represents module aliases as Mty_alias paths. Env exposes contextual
lookups and alias-path normalization. Subst provides identity-to-path mappings
and context translation, including signature binder refreshing. An exposed API
does not establish that all needed environments/artifacts are present in a
particular corpus.

Sources: [Types](https://ocaml.org/p/ocaml-compiler/5.3.0/compiler-libs.common/Types/index.html),
[Env](https://ocaml.org/p/ocaml-compiler/5.3.0/compiler-libs.common/Env/index.html),
[Subst](https://ocaml.org/p/ocaml-compiler/5.3.0/compiler-libs.common/Subst/index.html).

Typedtree carries resolved paths, binder IDs, environments, coercions and explicit
substitution nodes alongside source spelling. Cmt_format contains full/partial
annotations, initial environment, UID/declaration dependencies and implementation
shape information. These findings describe the5.3.0 API only.

Sources: [Typedtree](https://ocaml.org/p/ocaml-compiler/5.3.0/compiler-libs.common/Typedtree/index.html),
[Cmt_format](https://ocaml.org/p/ocaml-compiler/5.3.0/compiler-libs.common/Cmt_format/index.html).

## Patterns found

| Pattern | Reference | Concrete representation |
|---|---|---|
| Artifact-scoped identity | arch_index_cmt.ml:1078 | Ident.unique_name id |
| Shallow display descriptor | arch_index_functors.ml:30 | Path.name path |
| Uncertain binding | module_alias_heads.ml:442 | MAY_TOP/module_param/unmarked |
| Separate syntax metric | functor_catalogue.ml:54 | count(*) FROM functor_applications |
| Separate graph metric | functor_catalogue.ml:72 | count(*) FROM calls |

## Coverage gaps

- No same-manifest before/after target-resolution experiment exists in the checked
  prior reports. Syntactic application counts do not fill that gap.
- Dirty checkout SHA alone is insufficient to identify exact artifact bytes;
  recorded CMT digests exist, but no clean-checkout assertion was observed.
- Descriptor path spelling is not evidence of a resolved lexical binding.
- Compiler documentation exposes capabilities, not measured availability of all
  declaration/environment links on these410 artifacts.
- Locator scheduling was sequential after other specialists because of runtime
  concurrency; all four roles completed, without claiming four parallel agents.
