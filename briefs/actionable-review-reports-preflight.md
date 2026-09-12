# Preflight — actionable-review-reports

**Mode:** full
**Status:** READY

Base: `932211be1ecd2b950d7cee6ef8dbbdd7bbed0460` (PR #98 merged). This is the only active
delivery worktree created by this session. The previous worktrees/builds were removed;
main's six pre-existing untracked entries remain untouched.

The branch carries #98 post-merge bookkeeping and #29 read-only requalification as local
documentation commits `8d4db99` and `c79206b`. No production changes yet.

Deterministic routing: Full because report-interface decisions are required. Task-description
trust-boundary and critical keyword checks are false; no adjacent formal artifact or existing
ledger, and no task hooks. No KB, claims reconciler or code-intel pack is installed.

- Review bundle verified: 22 sha-matched files, bundle 1.6.0.
- Explicit project-switch `dune build --root . @install`: exit 0.
- Explicit project-switch Tezt collection: exit 0, 231 registered tests. Nine historical
  `/tmp/tezt-*` warnings were observed; no blanket deletion of unattributed files.
- Toolchain is the existing project opam switch; local Eio 1.3, CI Eio 1.5.
- No configured formatter; use existing style and `git diff --check`.
- Existing opam metadata lint error 23 remains non-gating debt, not a passing lint result.

Do not run Dune concurrently. Every Dune call must name `--root .` and use
`opam exec --switch=/home/mathias/dev/arch-index -- ...`. Capture real final process exit
codes. Retain compact audit evidence; remove disposable scratch DBs and the delivery
worktree/build after landing.

## Fresh baseline before implementation — 2026-09-12

Root ran `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune test --root . --force`
in this worktree, before any code/test edit. Actual process session 36741 completed with explicit
exit 0: all 231 Tezt tests and Alcotest suites passed. Expected negative-fixture SQL constraint
diagnostics were present, not terminal failures. No Dune process from this baseline remains.
