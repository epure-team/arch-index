# QA Scope — guard-division-analysis

**Date:** 2026-09-13
**Status: VALIDATED**

## R1 corrective plan — validated under standing autonomy

Sequential fresh intake-only voices: `roster/guard-division-analysis/correction-plan-voice1.md` (Sol), then `correction-plan-voice2.md` (Terra). Original completed steps above are history, not work to repeat.

| Point | Voice 1 | Voice 2 | Adjudication |
|---|---|---|---|
| Public CLI/private implementation library; shared report context | yes | yes | AGREE; correct existing implementation, no new embedding surface. |
| Missing native/seam and exact oracle cases | yes | yes | AGREE; preserve complete existing numeric contract. |
| Ratchet after production fix | yes | yes | Correct both against mandatory TDD: write/run authentic RED before report production edits; archive RED repeats later. |
| Captured unsupported ancestry and opaque calls | sticky ancestry | some text drops nested ancestry / excludes indirect calls | Correct voice2 against explicit intake: unsupported ancestry is sticky across entries; ordinary/unlisted/indirect applications return Top, independently visit operands. No new exclusion semantics. |
| Duplicate coordinates | asks clarification | rejects | Existing contract retains separate site IDs; reject duplicate artifact module/source identities only. No coordinate rejection. |
| Domain implementation | retain audited domain | select/redesign | Existing implementation is present; no redesign without an actual failing acceptance case. |
| Child cap | asks memory cap | memory cap | Both misread captured-output cap: 16 MiB output, 120 seconds, not OS memory isolation. |
| Direction | keep | keep | No USER-CHALLENGE; erroneous inferences rejected, no new user choice. |

1. **Report-context regression through the CLI.** Declare the new standalone ratchet file, activate the original manifest plus that exact path, build baseline, write/run RED on actual empty/classified CLI outputs before report edits. Minimal shared limitation and text projection correction, then GREEN. Keep JSON schema and numerical statuses unchanged.
2. **Private package/public command boundary.** Test fresh install manifest and public help/version/wrapper dispatch; remove public implementation-library installation while preserving executable/private probes. Missing-binary wrapper test uses an owned isolated copied wrapper, never moves/deletes the active binary. Complete package verification and docs.
3. **Complete native/seam acceptance coverage.** OCaml specialist extends the existing private fixture seam and owned fixture data for R1 malformed types/applications, binder/entry/exclusion and metadata cases. No product semantic changes merely to fit an oracle; any actual mismatch requires a demonstrated failing test and minimal correction.
4. **Independent exact oracles and suite integration.** Non-OCaml implementer strengthens six modes, all-five-status text equivalence, status/reason sensitivity controls, ordering, UTF-8 boundaries, package/CLI controls, and registers standalone context check in Tezt. Fixture data may use existing scoped fixture directory. New report ratchet remains self-contained.
5. **Corrective-head evidence and delivery gates.** Full build before forced suite, all standalone checks, fresh self/golden/origin/rules/impact, committed pristine recalibration; independent full roster R2 with seven findings still OPEN until verified closure, then QA, PR, exact-head CI, rebase merge. Retain compact evidence and clean owned scratch.

Steps1–3 may share OCaml specialist ownership but each production correction has RED first. Root may prepare the standalone regression test as a test prerequisite before specialist production work; non-OCaml implementation follows OCaml. Dune ownership is exclusive; no new worktrees.

Files: existing manifest scope plus only `scripts/check-guard-report-context.js`. Preserve base6704a5b and existing dirty declaration. Ratchet: finding `lib/arch_guard/arch_guard.ml:213:spec#cd378d70`, pre-fix `d44c0c6ae8f4991549f6de5bbc2bdb3f24eb25ec`, command `rtk proxy node scripts/check-guard-report-context.js`, check_encodable=true.

Risks: archive setup errors must be >=2 not RED; no stale install manifest/binary; package privacy is not global-state restoration; no numeric-only reasons for UNSUPPORTED; no hidden new scope/calibration weakening; source-growth attribution must remain exact. Full build is `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune build --root .`, not @install-only. Claims/KB/hooks remain unavailable. Standing autonomy replaces repeated human quizzes, not technical gates. No new approval or test success is claimed by this plan.

Workdir /home/mathias/dev/arch-index-worktrees/guard-division-analysis. Independently execute gates after reviewed exact committed head. Read full frozen spec, all19AC, implementation and review artifacts. No TUI/MCP/Tezos scanning in scope. Behavioral results are experimental report-only, never safety policy.

## Exact quality gates

All commands cwd this task worktree. Never run concurrent Dune here. Capture terminal exit codes.

- `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune build --root .`
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
