## Summary

- Resolve calls through compiler-identity-backed, same-CMT structured modules in
  both OCaml collectors, retaining conservative refusal for aliases, parameters,
  application results and unproven paths. No schema or public CLI change.
- Preserve omitted-label partial-call precision and add native identity,
  shadowing, arity, storage and cross-file regressions, plus fail-closed corpus
  comparison and an exact self-index smoke ratchet in the local test suite.
- Fixed410 Tezos measurement: **+400 Irmin / +395 protocol distinct
  caller/location/target relations, zero losses**.831 resolved rows include31
  value aliases excluded from this metric;34 computed-return TOP rows are
  independently witnessed. This is not general defunctorization or0CFA.

## Test plan

- [x] Full forced Dune suite:327/327 Tezt and other suites pass.
- [x] Native target/refusal checks7/7, labeled arity4 callers ×2 contexts,
  comparator28 controls, verifier-input39 controls, wrapper5 controls.
- [x] Exact self-index golden25/980/6245, genuine pre-fix RED and post-fix GREEN.
- [x] Hash-locked410 CMT comparison and baseline self replay; independently
  reviewed compiler UID target/arity witnesses, unchanged canonical snapshot
  across repair rounds, no existing relation loss.
- [x] Pristine2×2 recalibration passes without changing the ceiling bound;
  temporary worktrees/builds removed.
- [x] Roster review GO and QA GO with actual convergence gates. One initial QA
  timing-wrapper setup failure is retained in the audit; no code change needed.
- [ ] Hosted CI succeeds on the exact PR head before rebase merge.

Evidence: briefs/tezos-call-resolution-qa.md and
roster/tezos-call-resolution/{uid-witness-report,pristine-recalibration-round3}.md.
OpenCode review degraded on timeout; its shared QA breaker prevents an unsupported
approval claim. No coverage percentage or universal semantic proof is claimed.
This is the first of five user-approved bounded improvement attempts. PR93 and
unrelated local work are intentionally excluded.
