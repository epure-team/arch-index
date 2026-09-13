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

Shipped: PR https://github.com/epure-team/arch-index/pull/102 rebase-merged
2026-09-13T12:16:49Z as a232eac2bb39eb8d8197095fde0cf88b23a20ee7.
CI34756126234 completed successfully on exact head
b0c86071600e7ab1c29ec42b93c7b27298821cb7; build and credentials check passed.
MCP was skipped for absent credentials, release skipped on PR; neither is a test pass.
Main synchronized by rebase, dropping already-applied bookkeeping1d21487.
Exact task-branch/main tree comparison returned0 before cleanup. Clean owned
worktree /home/mathias/dev/arch-index-worktrees/functor-instance-resolution
and its regenerable builds removed (~802MiB); unrelated worktrees untouched.
Remote branch deleted. Normal local branch deletion refused rewritten ancestry;
exact tree equality and verified PR merge justified scoped branch -D, now removed.
Main untracked user files preserved. Post-merge CI34756657988 subsequently
confirmed successful on a232eac; both pre-merge and post-merge CI are verified.

Ship housekeeping: KB/harness/projection sync/canonical friction checker absent;
local JSON shape and phase-coverage checks used, not a canonical checker claim.
Cost telemetry skipped (advisory); existing untracked cost log not staged.
Post-merge ledger bookkeeping stays local for a subsequent reviewed PR, not a
direct unreviewed push to main. Roadmap updated with actual merge and benchmark limits.
