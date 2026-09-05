---
task: roster-install
mode: fast
---
# Impl brief — install the full roster pipeline in arch-index

## Context
arch-index is the keystone every gate in the épure stack rests on; its own changes should go
through the same adversarial pipeline. This lands the pipeline itself (bootstrap: the change
installs the very tooling that reviews it).

## Changed files (53, all additive)
- .claude/commands/ — 21 pipeline + meta skills (copied from agent-roster next @ 2d2843c)
- .claude/agents/ — 8 agents (reviewer, architect, implementer, planner, qa, tech-lead, kb-agent, recruiter)
- scripts/ (+ scripts/lib/{review,qa,xruntime}/), schema/ — review bundle 1.6.0 + QA convergence gate
No source/lib/bin/tezt file touched. No behaviour change to any arch-index tool.

## Decisions
- Copied skills verbatim from the roster `next` branch (stable = main is ~139 commits behind).
- init-harness deliberately NOT used: it emits multi-runtime scaffolding (.opencode/.codex/.agents)
  that arch-index does not use.
- .claude is NOT gitignored in this repo (unlike épure), so the install is committable and shared.

## Verification (run)
- review-bundle-verify → OK, 22 files sha-matched
- check-qa-convergence → operational
- dune build → 0 ; dune runtest → 0
- self-dogfood reproduced: golden `modules: 19, functions: 426, calls: 3391` matches
  test/fixtures/self-index-stats.txt exactly; edge kinds MUST 1107 / MAY_ENUMERATED 2106 / MAY_TOP 178
- arch-rules self --on-vacuous fail → exit 0 — **1 proved / 0 violations / 3 UNKNOWN**. Recorded here as "4 rules, 0 failing", which was the tool's own summary collapsing a three-state verdict into one number; corrected in PR #70. Nothing was proved for three of the four rules; exit 0 means *the gate is unchanged*, not *the gate passes*. See specs/qualified-unit-resolution.md §10.5.
- arch-impact --diff main..HEAD → reports the 53 changed files as UNKNOWN (not zero) impact

## Ratchet
No HIGH+ findings from the implementer. No new checks (additive tooling install, no source change).
