# Ship gate — functor-instance-resolution

2026-09-13. Full roster review GO (round1cycle1) and QA GO (round1cycle1).
Explicit user authorization covers autonomous PR creation, exact-head green CI,
fix/re-gate as necessary and sequential rebase merge. No quiz/approval result is
fabricated; standard step prompts are superseded by that explicit instruction.

Branch feat/functor-instance-resolution; target epure-team/arch-index main.
Fetch succeeded, rebase origin/main is already up to date. Main schema1.13 and
no competing schema PR; this additive change takes1.14, flat1.3 unchanged.
Product source c2a8add; final implementation/QA checkpoints recorded in ledger.

Scope: syntax-only application catalogue, full validation query, tests/docs,
source-growth calibration specifically approved by user, bounded Irmin/protocol
observation with exact manifest. No target resolution,0CFA or Tezos precision gain.
Prior local guard post-merge ledger commit1d21487 is included as bookkeeping;
no guard product behavior change is added. Private issue draft remains unpublished;
no fabricated closing issue and no changes to existing open PR93.

Local gates: build0; forced266Tezt+64Alcotest0; four catalogue groups0;
three origin checks0; fresh origin held0/package0 with policy still UNKNOWN;
bundle22SHA1.6.0; scope0; branch hygiene0; review/QA convergence0.
Review retains three MEDIUM architecture advisories (function size and repeated
per-input scans). OpenCode timeout120s is degraded; QA shared breaker skips it.

Pending: push/PR, exact-head CI including self-index/recalibration/rules/origin
package/impact, rebase merge, local synchronization and exact owned worktree cleanup.
MCP credentials-dependent job is not inferred passed from overall CI green.
