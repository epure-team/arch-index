# Reviewer Brief — guard-division-analysis

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

Resume amendment: full `dune build --root .` is mandatory before the suite; @install
alone under-builds the whole-repo ratchet corpus. Pin383→430 in must_null_ceiling.ml
is the single authorized source-growth exception, documented in ratchet-source-growth.md;
headroom25/query/extractor/references unchanged. Compiler-backed Node checks inherit the
same project opam environment as the build; do not use an incompatible system ocamlc.

Planned scope, not implementation-complete claim. Review after actual impl brief exists. Workdir /home/mathias/dev/arch-index-worktrees/guard-division-analysis. Read full intake, specs/guard-division-analysis.md, plan and implementation brief; no change to underlying task intent.

Audit first lib/arch_guard/ domain/input/inventory/interpreter and bin/arch_guard/ atomic error/output path; then test-only probe/JS checker authenticity and Tezt wiring. Enforce scope: existing lib/arch_index/lib/arch_tools, schema, rules, corpus/reference and allow-lists unchanged. Public standalone component only.

Highest risks: modular wrap false nonzero; unsupported ancestry and function entry reset; syntax inventory completeness including defaults; binder shadowing/simultaneous groups; type-resolved guard primitive identity; partial application slots; result/census reconciliation; reader version assumptions; inclusive resource limits and empty stdout failures; fake small-width oracle/self-derived expected values; empty corpus overclaim. Check schema and closed reason vocabulary exactly; every numerically supported site needs conditional reason, unsupported sites need exclusion reasons instead.

Domain constant-zero-v1 concretization/join/restriction must match plan; no intervals or additional precision requirement invented. No vulnerability/proof/guaranteed execution claims. UNREACHABLE is local supported branch contradiction, not existing graph verdict.

Trace all47 FR/19AC/sixCHECK to evidence with explicit PASS/FAIL/UNTESTED. Use full roster-review and specialist/convergence gates, preserve independent/cross-runtime evidence or explicit degraded classification. No fabricated specialist invocation or fake review trace. Fix-first only within scope; novel scope/direction changes escalate.

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
