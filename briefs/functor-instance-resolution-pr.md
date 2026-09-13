## Summary

- Add a source-backed OCaml functor-application catalogue and read-only
  `arch-query DB functor-applications [limit]`: shallow operand structure,
  deterministic occurrence IDs, source provenance and explicit diagnostics.
- Add main schema1.14 (flat1.3 unchanged), atomic per-input publication,
  independent completion eligibility and whole-snapshot validation before limits.
  Full reindex is required. This does **not** resolve targets, specialize calls,
  implement0CFA, or establish a closed world.
- Include full Roster evidence, native/probe fixtures and a bounded real-data
  observation:410 collected CMTs,384 Irmin +891 Alpha protocol applications.
  Three Dune aliases and one source-less generated wrapper are excluded from
  the raw414 inventory. Exact digest manifest and reproduction are included;
  no before/after resolution gain is claimed.

## Calibration and review

User explicitly approved clean_measured430→468 (ceiling455→493), unchanged
headroom25/floor8000. Pristine2×2 measured A=B437,C=D468;15 common semantic
tables agree for same-corpus old/new producers.31 added MUST/null rows are
attributed to new source, not improved/worsened resolution. Golden becomes
24modules/859functions/5440calls; origin reference495, allowances unchanged.
Reference source snapshot is c2a8add5e394c162eeef4d204a73e1058a436df2.

Independent reviewer, architecture and spec-compliance passes plus QA are GO.
Three MEDIUM architecture advisories are retained (two long functions and
O(inputs×applications) validation scans). OpenCode's120s timeout is a degraded
extra review, not a pass; QA respects its breaker. No configured formatter/KB
or managed-claims tool was fabricated. Prior guard merge bookkeeping is included;
no guard behavior change, held issue publication or change to PR93.

## Test plan

- [x] Fresh full build and forced266Tezt+64Alcotest.
- [x] Four standalone inventory/lifecycle/query/compatibility groups.
- [x]19 native occurrences including unit; synthetic Papply/ghost/location premises.
- [x] All selected-input outcomes, real storage rollback, marker/reindex boundaries.
- [x] Whole-data corruptions beyond limit0, six exact formats and unchanged DB bytes.
- [x]16 legacy semantic-table/contract oracles,3 old query byte oracles,2 index passes.
- [x] Origin authentic/failures/package checks; held observation remains UNKNOWN.
- [x] Bundle, scope, hygiene and review/QA convergence gates.
- [ ] Exact-head CI, including pristine recalibration and evidence package.

No MCP build is claimed when its credentials-dependent job is skipped.
