# QA Brief — lsp-runner-diagnostics

**Date:** 2026-09-12T16:52:10+02:00
**Status:** GO ✅
**Round:** 1 (qualifying 0/5)

## Round state

Fresh cycle 2, round 1; `qa_no_go_round` reset to 0. Causes: none.

## Quality Gates

| Gate | Command | Result | Duration |
|---|---|---|---|
| Build | `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune build --root . @install` | ✅ PASS (exit 0) | 0.11s |
| Full tests | `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune test --root . --force` | ✅ 231/231 Tezt plus all Alcotest groups (exit 0) | 129s |
| Format/style | `rtk git diff --check` | ✅ PASS; no formatter configured (exit 0) | <0.01s |
| Focused diagnostics | `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune exec --root . tezt/tests/main.exe -- --file lsp_runner_diagnostics.ml` | ✅ 4/4 (exit 0) | 10.0s |
| Self-index smoke | CI-equivalent `arch_callgraph_ocaml.exe` into `/tmp/arch-index-qa-self.OsyP5r`, SQLite census, then golden diff | ✅ exact golden: 23 modules, 820 functions, 5193 calls (exit 0) | 0.15s |
| Architecture rules | `rtk proxy ./arch-rules /tmp/arch-index-qa-self.OsyP5r/self.db arch-rules.txt --on-vacuous fail` | ✅ exit 0; 1 proved, 0 failing, 3 policy-allowed UNKNOWN, 0 vacuous | <0.01s |

## Tests: detail

- New task tests: 4 actual-CLI diagnostic regressions; the portability repair also adds two positive controls for the exact Eio 1.3/1.5 permission-denial renderings and one negative control for an unrelated `Not_found` process error.
- Existing/full suite: 231 Tezt pass, all Alcotest groups pass, 0 skip, 0 fail.
- Focused behavior coverage: lookup failure, startup failure, timeout/partial-result diagnostic, and unexpected spawn exception; stderr visibility without `--verbose`, quiet stdout/exit-0 contract, and verbose single-emission behavior.
- Regression detected: NO.
- Coverage limit: timeout deterministically covers the partial-result message with zero collected rows; it does not force a timeout after non-empty extraction.
- Coverage limit: the generic exception fixture covers POSIX permission denial through a present non-executable server, now accepting only the two concrete Eio 1.3 and Eio 1.5 representations observed locally and in CI.

## Prior CI portability failure

PR #98 CI run `34699363906` on `38070e20b842f3b0467c16e3ed1a448dc4540ca2` provided an actual RED: 230/231 Tezt tests passed, while the unexpected-exception test rejected Eio 1.5's `Eio.Io Process Permission_denied <path>` reason despite preserving the correct stderr label, exit 0, and empty stdout. Local Eio 1.3 rendered `Permission denied`. The test-only repair under QA at `2b34579395de6bb4b74e7065dc6b0c5d929372f3` accepts precisely those two observed representations and rejects unrelated process errors; production and dependencies are unchanged.

## Self-index detail

The generated census matched `test/fixtures/self-index-stats.txt` byte-for-byte:

```text
modules: 23
functions: 820
calls: 5193
```

No self-count drift and no golden update.

## Spec and installed harness checks

- Task spec runnable checks: skipped (no `specs/lsp-runner-diagnostics.md`; Fast route has no task spec artifact).
- Claims reconciler: skipped (no installed claims reconciler or task context manifest).
- KB/property checks: skipped (no task KB or `kb/properties.md`).
- Code-intel gate: skipped (no installed code-intel gate packs and no code-intel property block).
- TUI matrix: skipped (the slice has no TUI interface or TUI scenarios).
- Skill hooks: skipped (no installed task hooks/harness).

## Cross-runtime QA

The process-only availability check using `OPENCODE_CONFIG_CONTENT='{"model":"github-copilot/gpt-5.6-sol"}'` returned exit 0 with `status: "skipped-degraded"`: runtime degraded during review with unchanged runtime version. Cross-runtime QA: skipped (review breaker, unchanged runtime version). Per breaker policy, no human retry was inferred and the QA wrapper was not invoked.

Fresh review cycle 2 records the actual Sol-backed OpenCode attempt as degraded for non-conforming output after 34.597s with runtime exit 0; the transcript was discarded and provides no verified QA coverage.

## Supplemental non-gating lint

`rtk proxy opam lint arch-index.opam` did not pass (exit 1). This is known pre-existing metadata debt, not a documented CI gate for this slice. Raw output:

```text
/home/mathias/dev/arch-index-worktrees/lsp-runner-diagnostics/arch-index.opam: Errors.
             error 23: Missing field 'maintainer'
           warning 25: Missing field 'authors'
           warning 35: Missing field 'homepage'
           warning 36: Missing field 'bug-reports'
           warning 68: Missing field 'license'
```

No unrelated metadata fix was made.

## Verdict

**GO** — all documented primary gates passed at `2b34579395de6bb4b74e7065dc6b0c5d929372f3`; ready for `/roster-ship`.
