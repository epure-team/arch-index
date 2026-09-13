# Architecture review — functor-instance-resolution

Round 1, cycle 1. Reviewed at `3d92e73`; implementation source commit is
`c2a8add` and the source review target was unchanged from the supplied
`b947c0a` checkpoint except for root-owned documentation/manifest follow-up.

## Verdict

Architecture risk: **medium**. No critical structural or contract-isolation finding
was identified. `architect-findings.json` records two maintainability warnings for
new functions above the configured 50-line threshold and one bounded, objective
scalability warning: complete query validation rescans decoded applications for
each selected input.

The implementation keeps the catalogue additive and separated from graph facts:

- `architecture-schema.sql:54-81` gives the catalogue producer-owned tables and
  foreign-key boundaries; existing graph tables are not repurposed.
- `lib/arch_index/arch_index.ml:496-506` creates the catalogue header only for a
  nonempty selected set, and `lib/arch_index/arch_index.ml:626-699` records
  per-artifact outcomes without changing the existing `process_cmt` result path.
- `lib/arch_index/arch_index_functors.ml:132-148` publishes a collected input and
  its applications under one savepoint; `:164-178` earns the marker only after
  header, provenance, input and application count checks.
- `lib/arch_tools/arch_functor_catalogue.ml:116-249` reads inside one snapshot,
  validates the complete state before limiting output, and rejects incomplete or
  inconsistent state rather than exposing a partial catalogue. Its lines 232-244
  should be regrouped by artifact before a large catalogue makes the current
  O(inputs × applications) validation cost material; this is advisory and does
  not change the required validate-before-limit behavior.

The spec’s acceptance criteria and entities were read before assessment
(`specs/functor-instance-resolution.md:202-252`, `:313-318`). No `kb/` or
`kb/architecture.md` exists in this repository, so repository schema and feature
documentation were used as the available architectural constraints.

## Gates run by this reviewer

| Gate | Exit | Evidence |
| --- | ---: | --- |
| `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune build --root .` | 0 | Explicitly re-run after the spec specialist released the Dune baton. |
| `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune test --root .` | 0 | Explicitly re-run cached after that build. The independently observed earlier forced run, `dune test --root . --force`, passed 266/266 Tezt checks; its expected negative-fixture diagnostics were emitted on stderr. |
| `check-functor-catalogue.js inventory` | 0 | 18 apply + 1 apply_unit; five traversal contexts. |
| `check-functor-catalogue.js lifecycle` | 0 | all five incomplete outcomes plus stale-row, zero-selection, and zero-application lifecycle checks. |
| `check-functor-catalogue.js query` | 0 | 31 successes, 22 corruption cases, six formats. |
| `check-functor-catalogue.js compatibility` | 0 | two indexing passes, 16 semantic tables/contracts. |
| `review-bundle-verify.js` | 0 | 22 bundle files present with matching SHA values. |
| `git diff --check main...HEAD` | 0 | root’s docs-only follow-up at `3d92e73` resolved the earlier historical EOF-whitespace report. |

The scope gate was run by root and deferred from this specialist’s role. Current
untracked review-trace and reviewer artifacts were preserved; they are not product
findings and were not modified.
