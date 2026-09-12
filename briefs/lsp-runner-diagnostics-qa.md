# QA Brief — lsp-runner-diagnostics

**Date:** 2026-09-12T16:24:50+02:00
**Status:** GO ✅
**Round:** 1 (qualifying 0/5)

## Round state

Fresh cycle, round 1; `qa_no_go_round` reset to 0. Causes: none.

## Quality Gates

| Gate | Command | Result | Duration |
|---|---|---|---|
| Build | `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune build --root . @install` | ✅ PASS (exit 0) | 0.13s |
| Full tests | `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune test --root . --force` | ✅ 231/231 Tezt plus all Alcotest groups (exit 0) | 132s |
| Format/style | `rtk git diff --check` | ✅ PASS; no formatter configured (exit 0) | <0.01s |
| Focused diagnostics | `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune exec --root . tezt/tests/main.exe -- --file lsp_runner_diagnostics.ml` | ✅ 4/4 (exit 0) | 10.0s |
| Self-index smoke | CI-equivalent `arch_callgraph_ocaml.exe` into a `mktemp -d` database, SQLite census, then `diff test/fixtures/self-index-stats.txt <actual>` | ✅ exact golden: 23 modules, 820 functions, 5193 calls (exit 0) | 0.25s |
| Architecture rules | `rtk proxy ./arch-rules /tmp/tmp.2rGocsrZB8/self.db arch-rules.txt --on-vacuous fail` | ✅ exit 0; 1 proved, 0 failing, 3 policy-allowed UNKNOWN, 0 vacuous | <0.01s |

## Tests: detail

- New tests added: 4.
- Existing/full suite: 231 Tezt pass, all Alcotest groups pass, 0 skip, 0 fail.
- Focused behavior coverage: lookup failure, startup failure, timeout/partial-result diagnostic, and unexpected spawn exception; stderr visibility without `--verbose`, quiet stdout/exit-0 contract, and verbose single-emission behavior are asserted by the focused file.
- Regression detected: NO.
- Coverage limit: timeout deterministically covers the partial-result message with zero collected rows; it does not force a timeout after non-empty extraction.
- Coverage limit: the generic exception fixture covers deterministic POSIX permission denial through a present non-executable server.

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

## Cross-runtime QA

`OPENCODE_CONFIG_CONTENT='{"model":"github-copilot/gpt-5.6-sol"}' node scripts/xruntime-review.js opencode --task lsp-runner-diagnostics --phase qa --check-availability --write` returned exit 0 with `status: "skipped-degraded"`: runtime degraded during review with unchanged runtime version. Cross-runtime QA: skipped (review breaker, unchanged runtime version). Per breaker policy, no human retry was inferred and the QA wrapper was not invoked.

The persisted review evidence records the original degradation honestly: OpenCode timeout after 120.1s, runtime exit 124. This is not represented as verified coverage.

## Supplemental non-gating lint

`rtk proxy opam lint arch-index.opam` did not pass (exit 1). This is the known pre-existing metadata debt and is not a documented CI gate for this slice. Raw output:

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

**GO** — all documented primary gates passed at `eac5cdef1a540f5b13592472d0385a74f90d85d7`; ready for `/roster-ship`.
