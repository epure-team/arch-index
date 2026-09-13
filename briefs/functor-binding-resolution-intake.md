# Intake Brief — functor-binding-resolution

**Date:** 2026-09-13
**Status: DRAFT — pending scope freeze**
**Type:** feature
**Trust boundary:** yes

## Goal

Continue the functor roadmap after catalogue PR102. Establish compiler-identity
formal-to-actual bindings, with reproducible Tezos/Irmin observations, before
claiming target-resolution gains. The latest measurement is research instrumentation,
not a new product capability or a passed implementation/review/QA pipeline.

Candidate first product slice: direct application-to-declaration/parameter/operand
provenance, separate from calls. The next specification must choose exact supported
identity and composition boundaries, including cross-unit and curried applications.
No default graph demotion is approved by this draft.

## Scope Boundary

- No general closure0CFA, new security scanning, or changes to Tezos sources.
- No publication of the held private issue draft; no change to open PR93.
- No name-only binding joins, per-instance function cloning, inferred closed world,
  or MUST promotion. Existing calibre/allowance semantics stay unchanged.
- No interpreting syntactic counts as resolved call targets.

## Relevant Files

| File | Role | Key snippet |
|---|---|---|
| lib/arch_index/arch_index_cmt.ml | Existing lexical alias and exposure facts | Ident.unique_name; Hashtbl.mem exposed_tbl |
| lib/arch_index/arch_index_functors.ml | Existing syntax-only catalogue | Path.name path; Tmod_apply |
| lib/arch_index/arch_index.ml | Graph certainty classification | edge_form = Some "module_alias" |
| tezt/tests/module_alias_heads.ml | Preserved negative controls | MAY_TOP/module_param/unmarked |
| roster/functor-binding-resolution/measurement/ | Supplemental sizing, not product | per-CMT Ident.same and raw application counts |

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

Trust-boundary proposal yes is conservative: a binding or closure assertion can
affect evidence used for negative reachability. No managed-claims harness exists.

## Quality Gates

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

- [ ] Freeze direct versus curried/nested application semantics and exact persisted
  declaration/parameter identity contract without leaking per-CMT stamps across units.
- [ ] Specify the missing/ambiguous/external binding statuses and which actual
  operand definitions are indexed, including anonymous structures.
- [ ] Establish a separate, explicit application-set completeness contract before
  replacing any MAY_TOP; exposed=0 and selected-input completeness are insufficient.
- [ ] Define paired occurrence/target metrics and per-instance exception controls
  for any later graph-changing slice; raw syntax counts remain sizing only.

These are technical scope-freeze questions, not user approval requests and not
implementer discretion. Intake has not emitted VALIDATED; ledger remains research.
