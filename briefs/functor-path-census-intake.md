# Intake Brief — functor-path-census

**Date:** 2026-09-13
**Status: VALIDATED**
**Type:** chore
**Trust boundary:** no

## Goal

Produce a reproducible, internal research census of the fixed410-CMT sample's
unsupported_path applications. This is measurement tooling under roster/, not a
new installed CLI or resolution behavior. Preserve per-application records and
describe syntax, root identity category, repetition and selected-unit availability.
Use the data to prioritize the subsequent separately scoped resolution feature.

## Scope Boundary

No production code/schema/API/test-suite changes, no environment-based resolution,
member substitution, new targets,0CFA, Tezos writes/builds or source freshness claim.
No arbitrary filesystem scan: only the named manifest artifacts. No CMI loads or
dependency installation. No assumptions that identical display names are identities,
or that selected-unit name presence establishes matching declaration ownership.
No recalibration, rules/headroom changes, held issue/PR93 or user-file changes.

## Relevant Files

| File | Role | Key snippet |
|---|---|---|
| lib/arch_index/arch_index_bindings.mli | existing exact outcome API | collect : Typedtree.structure -> collection |
| lib/arch_index/arch_index_functors.mli | existing exact ordinal callback | on_application ~ordinal ~head |
| roster/functor-binding-resolution/measurement/binder_census.ml | existing syntax/root measurement pattern | Ident.same stored id |
| roster/functor-binding-resolution/measure-bindings.js | existing digest validation/snapshot pattern | hash(fs.readFileSync(file))!==digest |
| roster/functor-instance-resolution/tezos-irmin-candidate/manifest-410.tsv | immutable selected inputs | slice,sha256,absoluteCMTpath |
| roster/functor-path-census/ | only new code/fixture/results/docs area | standalone probe and wrapper |

## Architecture Notes

Reuse the real collect API and catalogue ordinal callback; do not reimplement
the binding classifier. Two-pass identity census (module/letmodule binders and
module-expression/type parameters) then classify the terminal head path of each
unsupported_path, peeling constraints and literal applications. Fail on missing,
duplicate or unmatched ordinals. Keep exact source location, artifact, unit, slice,
ordinal, path syntax (including applied/extra-type forms), printed path and local
root key/category. Identity equality within one decoded artifact uses Path.same
or Ident.same; aggregate display-name counts explicitly remain display counts.
Cross-artifact unit presence is named inventory only; retain imported CRC metadata
without claiming it proves member ownership. Unknown/absent are explicit categories.

Wrapper builds the standalone probe using exact checkout library staging and
OCaml5.3 switch. Builds/probe/fixture compilation occur only in an owned temporary
directory; the wrapper creates no Git worktree. One clean task worktree may be
used for implementation isolation and removed after landing. Check manifest syntax, uniqueness, readability and
content hashes before and after; use temp-only generated outputs and always clean.
Successful JSON report is saved only after all checks pass. Include source/binary,
manifest/input provenance and all rows; no stdout success on malformed inputs.

Test native fixture for local structured-member head, persistent projected head,
parameter-member head, alias root and curried qualified head, including repetition
and shadowed names. Independently verify exact outcome/ordinal correspondence,
partition totals and non-conflation of identity/display counts. Add negative
manifest/digest checks and deterministic replay. Then run the fixed corpus and
independently review interpretation; update roadmap with measured limits.

## Quality Gates

Existing build: rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune build --root .
Existing full suite: rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune test --root . --force
Bundle: rtk proxy node scripts/review-bundle-verify.js
Whitespace: rtk proxy git diff --check
No standalone formatter configured. Census fixture/negative/replay commands will
be explicitly defined in the plan; they are new task checks, not existing gates.
Required before shipping: roster review/QA and exact-head green hosted CI.

## Open Questions

None for this internal census. The choice of product resolution extension is
explicitly deferred until measured results, not silently assumed by implementers.
Operator validates chore/no product trust-boundary under standing autonomy; task
metadata words authority/evidence are not an application trust-boundary change.
No KB/claims reconciler installed. No interactive answer fabricated.
