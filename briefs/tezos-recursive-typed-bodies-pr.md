## Summary

- Resolve exact recursive self calls under one named local open around the original function body, without widening ordinary binding lookup or claiming general 0CFA.
- Fifth/final bounded Tezos attempt: pinned410 local replay adds 14 protocol relations, zero Irmin gain and zero losses; 45052 rows preserved. Candidate totals: 4849 Irmin / 12171 protocol.
- Add two native integration tests, compiler-identity witnesses and six adversarial acceptance checks. Include Roster evidence and predecessor delivery records.

## Test plan

- [x] Build and full 342-test suite; authentic semantic RED before implementation.
- [x] CHECK1–6: native admission/refusal, witness tampering, sealed baseline, fresh410 comparison, complete rich/flat preservation and residual capacity.
- [x] Three independent Sol/Terra Roster reviews, GO; final QA GO with automatically measured unchanged pre/post state and producer.
- [x] Bundle verification and complete diff whitespace checks.
- [ ] Required GitHub CI succeeds on exact final PR head before guarded rebase merge.

## Limits and evidence

Local QA tested c1ed896e07d562fa5955b97d6bef1fd32533ff14; successors contain reports only. Pinned Tezos corpus replay is local, not claimed as a GitHub CI job. Exact-head CI remains mandatory.

OpenCode cross-runtime review timed out (DEGRADED); QA correctly skipped its unchanged-version breaker. Two reviewer aggregate state claims were invalid and explicitly discarded; final main QA captured real pre/post snapshots automatically. Individual actual test/check passes remain recorded. No formal proof, no new MUST, no mutual recursion or general functor-flow analysis. No retention before merge.

Details: briefs/tezos-recursive-typed-bodies-{impl,review,qa,ship-gate} and roster/tezos-recursive-typed-bodies/.
