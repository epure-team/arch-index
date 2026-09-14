# Ship gate — tezos-open-bodies

Review GO and QA GO; full mode, attempt3 of the existing five-attempt loop.
Standing user authorization explicitly permits PR creation, exact-head CI repair,
and merge before the next attempt. Human-validation.md is absent; no quiz answers
or waiver are fabricated. Seven unrelated untracked files are preserved.

Branch: feat/tezos-open-bodies. Target: origin/main a341adaa9c86911ebaa1d21605353f8449d9fc06.
Product commit a5ae981, handoff09b2823, same-round checker repair cd3cb3c.
The branch also includes the previous attempt's verified ship-record update e8d072e.
No product/checker changes after final review; only pipeline reports follow.

Change: direct same-CMT Pident calls to exact single-path-open-wrapped structural
function bodies now point to the uniquely stored synthetic root as MAY_ENUMERATED.
Existing body ownership, effects, CFG, flat calls, schema and public API remain
unchanged. This is not general0CFA or general defunctorization.

Fixed410: +316protocol/+0Irmin, zero losses/unexplained changes/new MUST;
45052rows; candidate digest9ab4e0b13457247fb93dc83bf80323fcc5cec67866a18f56995ac0ec4a20867e.
Two original review issues fixed in-round: residual native-head reuse and
non-vacuous rich preservation coverage. Three independent final reviewers and
main QA each passed build/full336/CHECK1–6. Roster convergence and QA gates pass.
Cross-runtime review120s timeout and QA breaker are explicitly DEGRADED/skipped,
not PASS. Formatter/coverage/hooks/claims are unavailable and documented.

Four self-reference constants were refreshed only after pristine source-only
crossed attribution; guard policy/allowance counts unchanged. Raw fixed410 data
are local ignored pinned evidence; four native Tezt cases are portable CI tests.

Pre-push: normal non-force push, scoped report commit, rebase on verified main.
Merge condition: exact PR head required build check SUCCESS, no bypass/admin,
guarded rebase merge. Held PR93 and foreign worktrees stay untouched.
PR/CI/merge pending at creation of this gate; no third KEEP recorded yet.
