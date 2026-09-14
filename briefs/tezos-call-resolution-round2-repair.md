# Round2 review return — CI self-index golden

Standing user autonomy covers routine roster implementation and CI repairs.
The sole OPEN non-scope finding is
`test/fixtures/self-index-stats.txt:2:integration#3f5e6e18`.
Per roster-implement loop-back manifest derivation, add only its exact path to
the existing entries, preserving original base and dirty header. No CI workflow,
product semantics, must_null_ceiling bounds, dependencies or Tezos input changes.

1. Add self-contained Node ratchet `roster/tezos-call-resolution/check-self-index-smoke.js`.
   Run the built producer over `_build/default/lib/arch_index` into an owned
   temporary DB; execute the exact CI SQLite query and byte-compare the fixture.
   Exit0 PASS, assertion1, setup>=2; clean owned DB in finally. Record authentic
   RED before updating the golden. Missing tools/producer must not count as RED.
2. Refresh only measured fixture to25 modules/980 functions/6245 calls, following
   ADR001 and already-reviewed source/precision changes. Preserve exact comparison.
3. Register this checker in existing local-module Tezt list and Dune deps,
   update wrapper's required titles; add CHECK6/AC14 to existing specification and
   declare ratchet in implementation brief. No unrelated behavior change.
4. Run all existing checks, new smoke, full guard and fixed410/self. Commit only
   owned files. Run pristine committed-tree recalibration diagnostics before ship;
   remove only newly owned worktrees/builds afterwards. Retain evidence.
5. Review round3 full fan-out required by previous strike; then QA and exact-head
   hosted CI/merge. This is attempt1 rework, not another product iteration.

Current root build/full326 and all three independent round2 runs pass. Exact CI
smoke alone currently fails assertion1; no keep or PR has been authorized by a
positive local count. pre_fix_sha remains null because unrelated dirt is preserved.
