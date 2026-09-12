# Ship gate — lsp-runner-diagnostics

**Mode:** fast
**Status:** READY FOR PR; not yet shipped

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
