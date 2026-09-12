# Reviewer Brief — guard-division-analysis

**Date:** 2026-09-13
**Status: VALIDATED**

Planned scope, not implementation-complete claim. Review after actual impl brief exists. Workdir /home/mathias/dev/arch-index-worktrees/guard-division-analysis. Read full intake, specs/guard-division-analysis.md, plan and implementation brief; no change to underlying task intent.

Audit first lib/arch_guard/ domain/input/inventory/interpreter and bin/arch_guard/ atomic error/output path; then test-only probe/JS checker authenticity and Tezt wiring. Enforce scope: existing lib/arch_index/lib/arch_tools, schema, rules, corpus/reference and allow-lists unchanged. Public standalone component only.

Highest risks: modular wrap false nonzero; unsupported ancestry and function entry reset; syntax inventory completeness including defaults; binder shadowing/simultaneous groups; type-resolved guard primitive identity; partial application slots; result/census reconciliation; reader version assumptions; inclusive resource limits and empty stdout failures; fake small-width oracle/self-derived expected values; empty corpus overclaim. Check schema and closed reason vocabulary exactly; every numerically supported site needs conditional reason, unsupported sites need exclusion reasons instead.

Domain constant-zero-v1 concretization/join/restriction must match plan; no intervals or additional precision requirement invented. No vulnerability/proof/guaranteed execution claims. UNREACHABLE is local supported branch contradiction, not existing graph verdict.

Trace all47 FR/19AC/sixCHECK to evidence with explicit PASS/FAIL/UNTESTED. Use full roster-review and specialist/convergence gates, preserve independent/cross-runtime evidence or explicit degraded classification. No fabricated specialist invocation or fake review trace. Fix-first only within scope; novel scope/direction changes escalate.

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


