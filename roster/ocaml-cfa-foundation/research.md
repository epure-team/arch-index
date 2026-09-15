# Research — ocaml-cfa-foundation

Generated2026-09-15. Full mode; online research enabled. Four independent
fresh-context documentarians: locator, analyzer, pattern finder, external.
Unavailable Haiku/Sonnet model tiers substituted by user-authorized Terra/Sol.
Neutral manifest was their only project starting input; no source edits/builds.

## Q1 — identities and targets

Functions have persistent `(module_id,name)` uniqueness and run provenance;
compiler binder identities use `Ident.unique_name` within one CMT. Source-order
shadowing assigns earlier definitions `#N`, final definition the bare name.
Nested literals become named synthetic nodes. Pending heads distinguish local,
qualified, enumerated and unknown; unknown reasons distinguish callback, module,
dropped node and ambiguous unit.

References: `architecture-schema.sql:150`, `architecture-schema.sql:191`;
`lib/arch_index/arch_index_cmt.ml:898`,`:1016`,`:549`,`:601`,`:619`;
`lib/arch_index/arch_index_cmt.mli:333`; `lib/arch_index/arch_index.ml:813`.

## Q2 — literals, aliases, provenance

Function literals are promoted to separate nodes; named-lambda non-head
occurrences emit escape edges. No general scalar-literal/value-cell IR was found
in the callgraph path; arch-guard's separate value interpreter is detailed below.
The alias prepass recognizes arrow-typed variable bindings with bare identifier
RHS, keyed by compiler stamp. Point-free chains emit immediate predecessor edges,
not a transitive value-flow result. Source site, producer run, edge form and
target/top information survive persistence. No derivation-chain table was found.

References: `lib/arch_index/arch_index_cmt.ml:1241`,`:1254`,`:1639`,`:2049`,
`:2951`,`:2971`,`:2995`,`:3692`; `lib/arch_index/arch_index.ml:1561`;
`architecture-schema.sql:27`,`:291`,`:294`,`:324`.

## Q3 — existing fixed points and dependencies

Extraction accumulates calls, then a later pass resolves each against persisted
functions. There is no function-value constraint/worklist/fixpoint engine in this
path. The existing iterative engine is CFG post-dominance: finite block sets,
intersection across successors, iteration until equality. It determines execution
conditionality/deadness, not values. Candidate IDs are sorted/deduplicated.

References: `lib/arch_index/arch_index.ml:811`,`:940`,`:1170`;
`lib/arch_index/arch_index_cmt.ml:1230`,`:3028`;
`lib/arch_index/arch_index_cfg.ml:20`,`:85`.

## Q4 — known and unknown contributions

There is no value-flow join. Independent pending edges can coexist at a site:
overapplication retains the head and adds an unknown residual. Final classification
maps unknown to MAY_TOP and enumerated to MAY_ENUMERATED. Static heads can be MUST
unless conditional/partial/alias. Ambiguous or dropped definitions remain TOP.
The `unreachable` query follows bounded edges and checks reachable TOP before
claiming absence; `reaches` uses MUST, and `escapes` shows the frontier.

References: `lib/arch_index/arch_index_cmt.ml:2464`;
`lib/arch_index/arch_index.ml:946`,`:1461`,`:1479`,`:1525`,`:1549`;
`bin/arch_query/arch_query.ml:382`,`:413`,`:434`,`:448`.

## Q5 — parameter, return, capture and application representation

Parameters have no value cells. Unknown parameter calls retain callback TOP.
Captures have no explicit IR; nested bodies have separate function/CFG contexts.
Return-position named lambdas are escapes, not modeled general return values.
Recursive function stamps are precollected; owned recursive bodies have a separate
placeholder-to-observed-body rewrite. Partiality uses result arrow type and
known syntactic/type arity; omitted labeled arguments have special handling on
owned-body paths. Overapplication retains an unknown returned-function residual.

References: `lib/arch_index/arch_index_cmt.ml:1016`,`:2049`,`:2303`,`:2366`,
`:2388`,`:2404`,`:2464`,`:4019`; `architecture-schema.sql:150`,`:277`.

## Q6 — modules/functors and compilation-unit boundaries

Local owner maps accept concrete structures/constraints, not functor applications,
aliases or unpacked modules as owners. Separate catalogue/binding tables preserve
artifact-scoped syntax and same-CMT formal/actual provenance. Their explicit limits
include no target resolution or runtime instances; cross-unit heads remain an
unresolved reason. Ordinary qualified calls resolve later against global stored
functions and unit registry, with ambiguous/dropped distinctions.

References: `lib/arch_index/arch_index_cmt.ml:1068`,`:2419`;
`lib/arch_index/arch_index_cmt.mli:379`; `lib/arch_index/arch_index_functors.ml:3`;
`architecture-schema.sql:61`,`:90`; `lib/arch_tools/arch_functor_bindings.ml`;
`lib/arch_tools/arch_functor_catalogue.ml`.

## Q7 — executable characterization

Generated native fixtures cover callback TOP, named callbacks, conditional
function values, partial/overapplication and lambda attribution. Existing
one-hop alias tests explicitly require chained/computed/unqualified forms to
remain TOP; point-free predecessor identity is tested separately. These are
executable expectations, not all general language guarantees.

References: `tezt/tests/callgraph_soundness.ml:66`,`:129`,`:197`,`:239`,`:305`,
`:316`; `tezt/tests/point_free_aliases.ml:66`,`:115`,`:211`,`:233`;
`tezt/tests/local_value_targets.ml:16`,`:127`.

The pattern finder found no native Tezos fixture. Root documentary follow-up
located external pinned410 checks in `roster/ocaml-data-preservation/check-tezos.js:25`
and shared comparison support in `roster/tezos-call-resolution/comparison.js:43`.
The stage1 check asserts45052 canonical rows and4849/12171 Irmin/protocol relations
(`check-tezos.js:13`,`:36`,`:57`); older baseline modules intentionally have earlier
snapshots (`roster/tezos-residual-targets/baseline.js:24`). These are different
historical baselines, not interchangeable values.

## Q8 — external finite-domain analysis

Might's executable0CFA reference maps procedure flow to source lambdas and
saturates finite abstract states; joined stores use set union. Darais et al.
map abstract addresses to value sets, insert by union, and iterate caches to a
fixed point over finite domains. Neither establishes a universal queue API,
universal unknown-closure element or general derivation-provenance convention.
Source lambda identities are limited origin provenance, not proof traces.

Sources: Matthew Might, [k-CFA reference implementation](https://matt.might.net/articles/implementation-of-kcfa-and-0cfa/);
Darais, Labich, Nguyen, Van Horn (ICFP2017),
[Abstracting Definitional Interpreters](https://plum-umd.github.io/abstracting-definitional-interpreters/).

## Q9 — compiler-libs CMT information

OCaml5.3 CMT exposes typed implementation trees, source/build/import metadata,
declaration UIDs and shapes. Texp_function exposes parameters/body, Texp_ident
resolved paths/descriptions, and Texp_apply labeled optional argument expressions.
There is no explicit captured-free-variable set, general value-alias relation,
resolved higher-order target or partial-application flag. Functor/module forms
are syntactically represented, not runtime-instance analyses. The current5.5
typedtree uses apply_arg instead of5.3 expression option: internal APIs differ.

Sources: OCaml Developers,
[Typedtree5.3](https://github.com/ocaml/ocaml/blob/5.3/typing/typedtree.mli),
[Cmt_format5.3](https://github.com/ocaml/ocaml/blob/5.3/file_formats/cmt_format.mli),
[Typedtree5.5](https://github.com/ocaml/ocaml/blob/5.5/typing/typedtree.mli).

## Coverage gaps

- No existing callgraph value-cell/constraint domain semantics to describe;
  the initially omitted arch-guard domain has scalar semantics described below.
- No general capture/return/argument substitution implementation found.
- Miniature native fixtures and external pinned-corpus checks have different availability.
- External sources do not prescribe a universal unknown/provenance representation.
- Graph orientation/claims tools absent; live rg/read and manifest digest checks used.

## User-corrected prior-art coverage — arch-guard

The user identified a missed existing value-analysis component. The initial
absence conclusions apply to the callgraph path, not the whole project.
README already links arch-guard; limiting symbol searches to arch_index missed it.

`lib/arch_guard/guard_domain.ml:1` defines Bottom, Const(int64), Nonzero and Top.
Its `join` at line7 merges constants/nonzero with absorbing Top. Restrictions at
lines15–16 refine equality/inequality with zero; checked arithmetic conservatively
returns Top on possible overflow or unsupported precision.

`lib/arch_guard/guard_interpreter.ml:86` resolves variables by Ident.same in an
association-list environment. `analyze` at108 traverses Typedtree, and eval at125
propagates constants, local nonrecursive aliases, sequences and if branches.
Branches refine environments and join results (146–153). Each function body
starts with a fresh empty environment (138–139); ordinary applications return
Top except recognized numeric primitives (154–168). Recursion, loops and many
other forms are explicitly unsupported (49–83), not solved by a worklist.
Results reconcile to an independent site inventory by physical expression identity.

The private library has no public_name (`lib/arch_guard/dune:1`), depends directly
on compiler-libs/digestif/yojson/unix, and does not depend on arch_index. Its public
contract is CLI-only/report-only, not an embedding API (`docs/arch-guard.md:13`).
The numeric domain and interpreter therefore already exist; there is no existing
general function-target domain or shared worklist established by these files.
This is documentary prior art, not a decision to copy or expose the private API.

Independent numeric tests expose the private domain through a JSON probe
(`tezt/fixtures/arch_guard/domain_probe.ml:1`); a separate BigInt oracle tests
concrete containment at exhaustive small widths3–8 and sampled31/63-bit extrema.
It also checks join commutativity, associativity, leastness and transfer
monotonicity (`scripts/check-arch-guard.js:66`,`:121`). These are existing
executable checks, not rerun in this read-only research phase or formal proof.
An independent analyzer confirmed this corrective addendum against live code.
