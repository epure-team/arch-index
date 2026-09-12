# QA Scope — guard-division-analysis

**Date:** 2026-09-13
**Status: VALIDATED**

Workdir /home/mathias/dev/arch-index-worktrees/guard-division-analysis. Independently execute gates after reviewed exact committed head. Read full frozen spec, all19AC, implementation and review artifacts. No TUI/MCP/Tezos scanning in scope. Behavioral results are experimental report-only, never safety policy.

## Exact quality gates

All commands cwd this task worktree. Never run concurrent Dune here. Capture terminal exit codes.

- `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune build --root . @install`
- `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune test --root . --force`
- `rtk proxy git diff --check`
- `rtk proxy node scripts/check-arch-guard.js inventory`
- `rtk proxy node scripts/check-arch-guard.js numeric`
- `rtk proxy node scripts/check-arch-guard.js domain`
- `rtk proxy node scripts/check-arch-guard.js inputs`
- `rtk proxy node scripts/check-arch-guard.js report`
- `rtk proxy node scripts/check-arch-guard.js owned`
- `rtk proxy node checks/origin-recurring-consumer.js authentic`, then failures and package modes separately.
- Fresh `rtk proxy node scripts/origin-consumer.js --out <new-owned-leaf>`, then `rtk proxy node scripts/origin-consumer-artifacts.js <same-leaf>`. Resolve a fresh owned parent with mktemp -d; never execute placeholders. Preserve compact evidence before removing owned DB/build scratch.
- Existing fresh self golden, `scripts/recalibrate.sh --check`, arch-rules self with --on-vacuous fail and arch-impact self: execute current CI commands unchanged during verification, record exact resolved paths/commands. No pin/reference/allow edits. Exact-head remote CI must independently pass before merge.

Standalone check exits0 pass/1 assertion/>=2 execution error. Tezt must also exercise deliberate assertion and execution controls. Every check mode sets up independently; authentic native fixtures cannot be replaced by static schema-only mocks. Limit tests can use test-only internal fixture/probe seams for inaccessible malformed typed trees and serialization boundaries, with actual CLI failure-path integration; disclose seam-only checks rather than claim CLI exercise where absent. No configured coverage-percentage target: report behavioral coverage honestly, do not invent percentage.


## Required observations

Actual native fixtures for all8primitive identities, shadowed operators, partial applications,0/2/unknown/aliases/zero guards/reversed guards/joins/shadowing/and-groups/fresh nested functions/unsupported ancestry. Test each status and eligible/top/bottom/unsupported precedence. Domain independent JS BigInt concrete containment at widths3–8 with non-singleton samples and31/63extrema; false zero exclusion or false bottom is failure regardless census arithmetic. Actual text/JSON equivalence and closed schema; invalid/missing/ghost locations; artifact duplicates/symlinks/annotations/malformed/midread-change paths; limits exact/oneover with honest seam-vs-real-CLI evidence labels. Checker execution/setup errors must never be assertion passes.

Report exact owned-library artifacts/counts even0; keep fixture precision separate from production/Tezos gains. Existing full suite and self baseline unchanged. QA convergence state and mechanical gate required, no GO while failures or required work remain. Retain compact logs and exact head, clean only positively owned scratch later.

