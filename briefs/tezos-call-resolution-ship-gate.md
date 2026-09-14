# Ship gate — tezos-call-resolution

Branch: feat/tezos-local-module-targets. Target: main (PR, rebase merge only).
User explicitly authorized autonomous full roster, PR, exact-head green CI and
merge sequentially; use that standing authority, not invented quiz answers.
Held PR93 and all unrelated dirt remain untouched. pre_pr_checks is empty.

Product commits:
- 12ab1fc feat: resolve same-cmt structured-module call targets
- d4d9455 fix(ocaml): preserve omitted-label partial call precision
- 8bc4fb0 fix: ratchet the self-index smoke golden locally

The branch also carries the preceding census handoff documentation ea8e5b4 and
the final review/QA delivery-evidence commit. No broad git-add or force-push.

Review GO round3 (all three independent full327/checks passes); QA GO round2
(build, full327, all6 checks, fixed410/self), actual convergence gates0.
QA round1 setup127 is preserved as history, not hidden. Cross-runtime OpenCode
review timed out and QA breaker skipped unchanged runtime; no external approval
claimed. Formatter/coverage/managed claims not configured.

Fixed410: Irmin4372→4772 (+400), protocol11220→11615 (+395) distinct
caller/location/target relations,0 losses.831 newly resolved rows include31
value_alias excluded from metric;34 justified computed-return TOP additions.
Compiler UID evidence and source/target positions reviewed; counts alone do not
certify soundness. No general alias/functor instance/0CFA expansion.

Pristine CI recalibration0: self golden source-only25/956/6145→25/980/6245;
ceiling537 remains inside unchanged524±25. All owned diagnostic worktrees cleaned.
Hosted CI has not run yet: create PR, verify exact head and required checks,
repair any in-scope failures, then rebase merge. No keep until that completes.
