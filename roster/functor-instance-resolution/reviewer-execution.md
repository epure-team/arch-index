# Reviewer execution — functor-instance-resolution

Review round 1, cycle 1. Independent reviewer at `b947c0ab780db355ae7b945b3d29a7d56e6488fa`; implementation source checkpoint `c2a8add`. Scope assessment was deferred to the already-green deterministic scope gate, as instructed.

## Commands and observed exits

| Command | Exit | Evidence |
|---|---:|---|
| `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune build --root .` | 0 | Fresh invocation; no stderr/stdout. |
| `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune test --root . --force` | 0 | Fresh forced run; all 266/266 integration checks completed successfully, together with the emitted Alcotest suites. |
| `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- node scripts/check-functor-catalogue.js inventory` | 0 | `18 apply + 1 apply_unit`; 5 contexts; 3 external/shadowed cases. |
| `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- node scripts/check-functor-catalogue.js lifecycle` | 0 | Selection 3; rollback true; all five failure outcomes and three lifecycle cases reported. |
| `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- node scripts/check-functor-catalogue.js query` | 0 | 3 valid cases, 6 formats, 19 corruption cases; extended run reported 31 successes and 22 mutations. |
| `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- node scripts/check-functor-catalogue.js compatibility` | 0 | Versioned rich baseline; 16 semantic tables/contracts, 3 legacy queries, 2 indexing passes. |
| `rtk proxy node scripts/review-bundle-verify.js` | 0 | Bundle 1.6.0: 22 files present and SHA-matched. |
| `rtk proxy git diff --check main...HEAD` | 2 | `briefs/functor-instance-resolution-qa-scope.md:42` and `briefs/functor-instance-resolution-reviewer.md:50` each have a new blank line at EOF. These are brief-only hygiene failures, outside the requested product finding focus; no product fix was authorized. |

## Review evidence

Read the complete `main...HEAD` changeset and the full changed product/test implementation, concentrating on catalogue traversal and identity (`lib/arch_index/arch_index_functors.ml:56-123`), per-input savepoint publication (`lib/arch_index/arch_index_functors.ml:132-148`), marker eligibility (`lib/arch_index/arch_index_functors.ml:164-178`), isolated producer callbacks and outcome precedence (`lib/arch_index/arch_index_cmt.ml:2751-2774`, `lib/arch_index/arch_index_cmt.ml:2817-2855`), run integration (`lib/arch_index/arch_index.ml:614-697`), full-snapshot validation before limiting (`lib/arch_tools/arch_functor_catalogue.ml:96-249`), and usage-before-open dispatch (`bin/arch_query/arch_query.ml:138-160`).

The review also covered the schema and reindex drop/marker wiring (`architecture-schema.sql:61-87`, `lib/arch_index/arch_index_support.ml:29-61`), the native and crafted-DB oracles (`scripts/check-functor-catalogue.js:49-245`, `tezt/fixtures/functor_catalogue/query_checks.js:1-71`, `tezt/fixtures/functor_catalogue/lifecycle_checks.js:1-113`), and Tezt registration/coverage (`tezt/tests/functor_catalogue.ml:39-187`).

I specifically audited the fallback outcome path: `record_missing_outcome` prepares its presence query at `lib/arch_index/arch_index.ml:625-630`; a prepare failure in the normal path is caught by the enclosing handler at `lib/arch_index/arch_index.ml:682-689`, whose second fallback call could itself escape. I did not report this as a product finding: on the supported producer path the just-created catalogue table is present (`lib/arch_index/arch_index.ml:393-418`), ordinary per-input insertion failures are already contained by the callback and savepoint paths (`lib/arch_index/arch_index_cmt.ml:2848-2854`, `lib/arch_index/arch_index_functors.ml:132-148`), and no in-scope reproducible catalogue-only operational failure was established that aborts graph publication.

No correctness, regression, lifecycle, traversal, read-only query, or missing-test finding met the reporting threshold. The raw findings artifact is therefore an empty JSON array.
