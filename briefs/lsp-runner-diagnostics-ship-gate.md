# Ship gate — lsp-runner-diagnostics

**Mode:** fast
**Status:** SHIPPED — PR #98 merged

## Scope and authorization

Issue #23: emit the four existing runner failure/partial-result diagnostics on stderr
without `--verbose`. Progress remains verbose-only; exit/database behavior is unchanged.
Four actual-CLI regressions and user documentation accompany the minimal runner change.
The branch also carries the documentation-only post-merge ledger for PR #97.

The user explicitly authorized sequential autonomous PR creation, CI repair and green
rebase merges. No repeated push/merge quiz is required; quality gates remain mandatory.

## Evidence

- Implementation: `4751015339f96f61d478460a82f7b2720d550924`.
- Review GO: `eac5cdef1a540f5b13592472d0385a74f90d85d7`; Sol owner and Terra architect,
  no findings; full/static convergence passed. OpenCode timed out (120.1s/124), recorded
  degraded rather than successful; its unchanged breaker prevented a QA retry.
- QA GO: `b47003a72691ea4acfe8a397256866f630ef07c9`; build, 231/231 Tezt plus Alcotest,
  focused 4/4, whitespace, exact self-index golden (23/820/5193), architecture rules.
- Architecture result is 1 proved / 3 policy-allowed UNKNOWN / 0 failing / 0 vacuous.
- Root independently rechecked review static and QA convergence: exit 0.
- Existing opam metadata lint debt is non-green and non-gating; no unrelated fix.
- Timeout fixture exercises the partial-result diagnostic with zero collected rows only.

## Landing conditions

Fetch/rebase onto current `origin/main`; require `build` success on the exact PR head and
an up-to-date, mergeable branch. Rebase merge only. Append ship COMPLETED only after GitHub
confirms merge. Preserve the post-merge roster record in Git, then remove the inactive
delivery worktree and generated build outputs without force or loss of unrelated files.

## CI repair and fresh gates

PR #98 run `34699363906` failed at `38070e20b842f3b0467c16e3ed1a448dc4540ca2`:
230/231 tests passed; our new permission-denial assertion did not recognize Eio 1.5's
`Eio.Io Process Permission_denied` wording (local Eio 1.3 says `Permission denied`).
No infrastructure retry was used to conceal this test defect.

Test-only repair `738e313f93df8cee3430a2adfc0a367553a7cdcd` accepts both concrete reasons,
positive-controls both, and negative-controls an unrelated `Not_found` error. Production
and dependency files are unchanged by the repair.

- Fresh review GO `2b34579395de6bb4b74e7065dc6b0c5d929372f3` (cycle 2, round 1):
  owner/architect gates passed, no findings; full/static convergence exit 0.
- Fresh QA GO `4f638fb8e7639720da377b9fc707144dcbcac296`: build, full 231/231 plus
  Alcotest, focused 4/4, whitespace, unchanged 23/820/5193 golden and architecture rules.
- Root independently rechecked review static and QA convergence: exit 0.
- Fresh-cycle OpenCode probe was allowed by the helper, but its non-conforming output
  was discarded as degraded. QA honored that breaker; no cross-runtime pass is claimed.
- QA scratch databases and the initial temporary PR body have been removed; committed
  reports and GitHub retain the useful evidence. No extra worktree was created.

Push this reviewed/QA'd correction, then require green CI on its exact new PR head.

## Confirmed landing

- PR https://github.com/epure-team/arch-index/pull/98 merged by rebase at
  `2026-09-12T15:04:49Z`; merge commit `932211be1ecd2b950d7cee6ef8dbbdd7bbed0460`.
- Exact approved head `4dcc831a71f347b1f1bf1ca367298f6416601fe9` had required `build`
  SUCCESS and merge state CLEAN. CI run `34700676526` passed in 8m50s, including tests,
  self-index, recalibration, architecture rules and change-impact.
- Issue #23 closed at `2026-09-12T15:04:50Z`; remote feature branch deleted. Local main
  fast-forwarded to the merge commit, preserving its six pre-existing untracked entries.
- Preserve this post-merge ledger record in a local Git commit and carry it in the next
  delivery before removing the inactive worktree/build; no separate bookkeeping PR.
- Advisory ccusage day-window query succeeded, but its cross-project day total is not
  isolated to this task. Do not publish unrelated aggregate usage as task spend.
- No KB, harness metabolism counter or skill hooks are installed.
