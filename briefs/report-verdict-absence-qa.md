# QA Brief — report-verdict-absence

**Date:** 2026-09-12T15:32:27+02:00
**Status:** GO ✅
**Round:** 1 (qualifying 0/5)

## Round state

Fresh cycle, round 1. No qualifying QA failure causes.

## Quality Gates

| Gate | Command | Result | Duration |
|---|---|---|---|
| Build | `opam exec --switch=/home/mathias/dev/arch-index -- dune build @install` | ✅ PASS (exit 0) | 0.4s initially; post-clean recovery exit 0 |
| Tests | `opam exec --switch=/home/mathias/dev/arch-index -- dune test --force` | ✅ 227/227 PASS (exit 0) | 106.8s recovery run |
| Format | `git diff --check` | ✅ PASS (exit 0) | <0.1s |
| Focused report CLI | `opam exec --switch=/home/mathias/dev/arch-index -- dune exec tezt/tests/main.exe -- --file report.ml` | ✅ 5/5 PASS (exit 0) | 0.8s |
| CI self-index golden | current-worktree index + `sqlite3` count query + `diff test/fixtures/self-index-stats.txt` | ✅ PASS (all exit 0) | <0.5s |
| CI architecture rules | `./arch-rules <temp-db> arch-rules.txt --on-vacuous fail` | ✅ PASS (exit 0; 0 vacuous) | <0.2s |

## Tests: detail

- New tests added: 0 during QA; the implementation’s report regression coverage is exercised.
- Existing tests: 227 pass, 0 fail; focused report CLI: 5 pass.
- Regression detected: NO.

## FR-021 / CHECK-6 behavior

The focused CLI suite emitted and checked actual `report.json`, `report.sarif`, and `report.html`.
`tezt/tests/report.ml` asserts JSON and SARIF have `verdicts_status: "NOT_COMPUTED"`, retain the eight compatibility count keys only with a placeholder explanation, and HTML presents unavailable totals rather than measured `<td>0</td>` values. It covers empty/native/imported findings; the imported case separately preserves provenance.

The fresh CI-equivalent self-index produced 23 modules, 820 functions, and 5193 calls; its golden comparison passed. `arch-rules --on-vacuous fail` reported 1 proved, 0 violations, 0 possible, 3 unknown, 0 vacuous, and 0 failing.

## Code-intel gate

Skipped: no `kb/properties.md` code-intel declaration or installed gate pack.

## TUI

Skipped: Fast mode has no QA scope or TUI scenario.

## Cross-runtime QA

OpenCode availability was checked through `scripts/xruntime-review.js` before invocation. The default local `ollama/qwen3.6:27b` issued two incomplete pseudo-tool outputs (one XML invocation and one fenced command) and did not execute gates; those invalid attempts are preserved in the QA evidence during this run and were not accepted as verification.

A process-only retry used `OPENCODE_CONFIG_CONTENT={"model":"github-copilot/gpt-5.6-sol"}` with the same shared wrapper, no config edit or human-retry override. It returned `VERDICT: GO`, tree unchanged, and independently observed: build exit 0; full tests 227/227 exit 0 after one runtime harness timeout/retry; diff check exit 0; report CLI 5/5 exit 0; self-index golden exit 0; and `arch-rules --on-vacuous fail` exit 0. Its first self-index flag typo (`--db`) was corrected to `--db-path` before the passing command. The raw Sol transcript was preserved while preparing this brief.

Compact evidence: wrapper command used model `github-copilot/gpt-5.6-sol`; raw transcript was `/tmp/report-verdict-absence-qa.hPYq0E/opencode-sol-qa.log`, SHA-256 `5526802e5dc5f154b7a16d8b73eb3ffec7fcc43585d768c69d8dc1644ea3166e`, before temporary cleanup.

## Infrastructure recovery

An earlier local full-suite attempt was interrupted by the execution wrapper and left only a stale Dune lock; after confirming no Dune process, the exact regenerable lock was removed. A subsequent captured attempt reached 227/227 but ended with Dune action-file permission denied; root ran `dune clean` after confirming no active Dune/Tezt process. The post-clean build and full suite above are the decisive explicit exit-0 gates. These are runner/build-artifact failures, not product-test failures.

## Non-CI supplemental finding

`opam lint arch-index.opam` remains a pre-existing metadata defect (missing maintainer plus warnings) documented by implementation/review. It is not a project CI gate and is not reported as green.

## Skipped checks

- Claims reconciliation: no reconciler installed in this project/harness.
- KB/code-intel pack: absent; see Code-intel gate.
- TUI: no applicable interface or scenario.

## Verdict

**GO** — ready for `/roster-ship`.
