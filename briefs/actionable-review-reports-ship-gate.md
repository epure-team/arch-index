# Ship gate — actionable-review-reports

**Date:** 2026-09-12
**State:** MERGED — PR #99
**Branch:** `feat/actionable-review-reports`
**Target:** `main`, rebase merge only

## Summary

- Add `arch-report <db> --out <dir> [--rules <rules-file>]` with shared rule evaluation,
  complete JSON results, actionable alert ordering, witnesses and explicit uncertainty across
  JSON/SARIF/HTML. Preserve the no-rules NOT_COMPUTED behavior and arch-rules gate policy.
- Add schema 1.13 bounded, nullable, typed-AST divisor context for integer division/remainder
  origins: syntax evidence only, with strict malformed-metadata refusal and old-index fallback.
- Update user/schema/report documentation and executable specification. Carry prior #98 ship
  bookkeeping and #29 evidence-based requalification; no new issue closure is requested here.

## Test plan

- [x] Independent roster review GO (`66e966f`), architect review, 18/18 specification matrix.
- [x] Independent root QA GO (`80509c9`), cycle 1 round 1, qualifying 0/5; draft convergence 0.
- [x] Build @install, 240/240 Tezt plus Alcotest, focused report 6/6 and SARIF schema validation.
- [x] Four standalone authentic-CLI checks: rules, ordering, operands, compatibility.
- [x] Self-index golden exact: 23 modules, 828 functions, 5223 calls; 2x2 recalibration current.
- [x] Architecture policy passes: 1 proved, 3 UNKNOWN, no failures or vacuous rules.
- [x] Committed-range whitespace, bundle/convergence and repaired friction schema checks.
- [x] Required remote `build` green on exact PR head, up-to-date base, then guarded rebase merge.

## Limits and authority

User explicitly authorized autonomous sequential PR/CI/fix/merge progression; standing authority
replaces fresh push/merge quizzes, not the review/QA/CI gates. No blanket fresh human review claim.
Remote main was fetched and rebase reported already up to date at `932211b`.
External runtime review degraded (timeout/tree-mutation); QA respected its persisted breaker and
did not invoke the provider again. No external-runtime verification pass. Code-intel skipped
(no block), claims authority absent, MCP untested without dependency/token, no TUI scope.
Known unrelated opam metadata lint debt remains. Reporting does not perform value inference,
certify freshness or support concurrent index writers; partial publication after I/O failure is
unusable. Old indexes lack the new context until reindexed, but remain readable as unavailable.

Only the active delivery worktree is owned by this slice. QA DB removed, recalibration worktrees
cleaned. After actual merge, root will sync main preserving unrelated untracked files, delete
the remote feature branch and remove the clean delivery worktree/build; durable evidence stays
in Git. No release or deploy action is included.

## Actual ship evidence

PR https://github.com/epure-team/arch-index/pull/99 merged at `2026-09-12T17:49:31Z`
as `d7112964df679fb44bc033e878059537208f58da`. Exact-head guard used
`121fd12c1df134b0757d2cef0fe1f2e9a8ae275b`; pre-merge state CLEAN, base `932211b`.
CI https://github.com/epure-team/arch-index/actions/runs/34708914566 passed first attempt:
required build 8m50s, all tests/self-index/recalibration/rules/impact steps successful.
No gate bypass or CI rerun. MCP and release explicitly skipped.

Local main fast-forwarded to the actual merge, preserving six unrelated untracked entries.
Remote feature branch deleted. `git cherry origin/main HEAD` marked every delivery commit
patch-equivalent to main. Post-ship metadata commit is retained locally for the next delivery;
the clean worktree/build can then be removed without force. Main CI `34709378209` is running.

ccusage was available: day-bounded offline aggregate captured locally in main's untracked
`skills-meta/cost.jsonl`, not posted to GitHub because it includes unrelated concurrent work.
Its actual totalCost field was used rather than treating missing totalCostUSD as zero.
No harness metabolism file or KB exists. All eight completed pre-ship phases had friction
entries (no reconstruction needed). Nine old Tezt temporary directories were examined read-only:
none had proven ownership by this delivery, so none was removed.
