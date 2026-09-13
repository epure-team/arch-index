# Intake Brief — functor-binding-resolution

**Date:** 2026-09-13
**Status: VALIDATED**
**Type:** feature
**Trust boundary:** yes

## Goal

Continue the functor roadmap after catalogue PR102. Establish compiler-identity
formal-to-actual bindings, with reproducible Tezos/Irmin observations, before
claiming target-resolution gains. The latest measurement is research instrumentation,
not a new product capability or a passed implementation/review/QA pipeline.

First product slice: persist application-to-declaration/formal/actual provenance
for named local functor declarations within a single OCaml5.3 Implementation CMT.
Expose it via a read-only `arch-query DB functor-bindings [limit]` command.
Every application of a collected catalogue input receives either a matched formal
binding or an explicit unresolved reason. Existing graph facts and v1 catalogue
outputs remain unchanged; this does not replace any MAY_TOP edge.

Supported heads are local Path.Pident binders, constraint-peeled identity-based
Tmod_ident alias chains to such binders, and syntactically nested application heads
whose direct declaration has consecutive literal Tmod_functor result nodes.
For F(A)(B), the inner occurrence binds formal1 to A and the outer binds formal2
to B. Actual operands remain symbolic; their contents/types are not substituted.

## Scope Boundary

- No general closure0CFA, new security scanning, or changes to Tezos sources.
- No publication of the held private issue draft; no change to open PR93.
- No name-only binding joins, per-instance function cloning, inferred closed world,
  or MUST promotion. Existing calibre/allowance semantics stay unchanged.
- No interpreting syntactic counts as resolved call targets.
- Cross-unit heads and all Path.Pdot/Papply/Pextra_ty heads are unresolved here.
- Inline functor heads and module binders with application-valued RHS are excluded;
  the latter are not silently treated as ordinary aliases.
- Parameter-supplied heads, module unpacking, anonymous definition indexing, arbitrary
  body interpretation, resource/value flow and exception specialization are excluded.

## Relevant Files

| File | Role | Key snippet |
|---|---|---|
| lib/arch_index/arch_index_cmt.ml | Existing lexical alias and exposure facts | Ident.unique_name; Hashtbl.mem exposed_tbl |
| lib/arch_index/arch_index_functors.ml | Existing syntax-only catalogue | Path.name path; Tmod_apply |
| lib/arch_index/arch_index.ml | Graph certainty classification | edge_form = Some "module_alias" |
| tezt/tests/module_alias_heads.ml | Preserved negative controls | MAY_TOP/module_param/unmarked |
| roster/functor-binding-resolution/measurement/ | Supplemental sizing, not product | per-CMT Ident.same and raw application counts |
| architecture-schema.sql | Additive provenance persistence | functor_applications primary key |
| lib/arch_tools/arch_functor_catalogue.ml | Existing read-only validation pattern | snapshot; complete validation before limit |
| lib/arch_index/arch_index_functors.mli | Current private collector interface | occurrence list |
| tezt/tests/functor_catalogue.ml | Native success/negative compatibility fixtures | composition_files; module Inline |

## Architecture Notes

Research completed with four documentary roles. Fresh census:410 digest-verified
CMTs,1275 immediate ordinary applications.658 heads are application expressions;
149 path roots bind to a functor RHS and376 are persistent unit roots. None of
those categories proves target resolution. Irmin has160 argument occurrences
rooted in named parameters; protocol has481 application-headed occurrences and
286 anonymous structure arguments. Direct named cases alone cannot be sold as
covering most measured syntax.

The earlier roadmap shortcut functions.exposed=0 is rejected as a closure proof:
the producer simply tests membership in a positive table from scanned CMTIs
(arch_index_cmt.ml:349,:3038). Missing interfaces also yield false. A selected-CMT
catalogue marker establishes neither functor visibility nor application-set closure.
Generative exception identity and consumers of MAY_ENUMERATED need explicit review
before any future edge replacement (docs/exception-raise-sets.md:107).

Trust boundary yes is operator-confirmed conservatively: future consumers could
misinterpret a binding assertion. The deterministic normalized-description keyword
probe returned false; this stronger explicit boundary is deliberate, not a claimed
keyword hit. No managed-claims harness exists. Standard interactive validation is
covered by repeated explicit autonomous continuation; no quiz answers are fabricated.

Decisions closed after independent Sol scope challenge:
1. One result per existing occurrence, not per whole curried chain; failed catalogue
   inputs have no occurrences and receive no fabricated binding result.
2. Pre-index named Tstr_module/Tstr_recmodule/Texp_letmodule binders, including
   nested/deferred contexts, inside each artifact. Ident.same proves local identity;
   persist artifact-scoped keys only, never join rendered names across artifacts.
3. Alias chains follow only local Pident RHS after peeling constraints. Cycles,
   missing binders, parameter roots, unsupported path/RHS shapes are explicit refusals.
4. Only consecutive constraint-peeled literal functor nodes form the declaration
   telescope. Curried depth identifies a formal, not an instantiated type or target.
   Unit/anonymous formals have positions but no invented named binder identity.
5. Actual descriptors retain existing catalogue JSON byte-for-byte. An additional
   local root identity, when available, is symbolic provenance, not resolved contents.
6. Add an independent binding-completion contract. It accounts for every collected
   input including zero-application cases, and every application result; failed
   binding collection cannot earn it or invalidate an otherwise valid syntax catalogue.

## Quality Gates

Spec clarification for the implementation plan: add three independent provenance
tables (binding inputs, declarations with literal formal telescopes, occurrence
results), an independent v1 completion marker, and the read-only six-format query.
The exact closed grammar is frozen by the spec, not implementer discretion.
Keep catalogue ordinals/descriptors unchanged and isolate binding storage failures.
Implement four plain-Node check families, with exit0 pass, exit1 semantic assertion,
and exit>=2 infrastructure error; these are planned checks, not current passes:

```sh
rtk proxy node scripts/check-functor-bindings.js inventory
rtk proxy node scripts/check-functor-bindings.js lifecycle
rtk proxy node scripts/check-functor-bindings.js query
rtk proxy node scripts/check-functor-bindings.js compatibility
```

Inventory includes native compiler-identity/curried fixtures and premise-checked
synthetics for unavailable valid-source edge cases; lifecycle includes real partial
storage failure and independent marker boundaries; query includes whole-database
corruptions at limit0 and six independent renderer byte oracles; compatibility
compares old catalogue and graph facts. Additive schema version1.15 is provisional
until the ship-time version-slot check; flat schema is unchanged.

Documented product commands, when implementation is scoped:

```sh
rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune build --root .
rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune test --root . --force
rtk proxy node scripts/review-bundle-verify.js
rtk proxy git diff --check
```

No configured standalone formatter/linter. Preflight build and collection passed;
no fresh full product suite is claimed in this research cycle. A future product
branch must pass the full roster and exact-head CI before PR merge.

## Open Questions

None for this slice. Cross-unit and higher-order bindings, closed-world completeness,
and per-instance exception semantics are explicit subsequent scopes, not implementer
discretion. The spec must freeze the exact record grammar/refusal precedence and
derive executable native/corruption/compatibility checks from the decisions above.
Fresh same410-manifest observations must report matched-formal counts and refusals,
not call-target gains. No additional calibration allowance is granted by this intake.
