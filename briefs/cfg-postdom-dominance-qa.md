# QA Brief — cfg-postdom-dominance

**Date:** 2026-07-09
**Status:** GO ✅

## Quality Gates

| Gate | Command | Result | Duration |
|---|---|---|---|
| Build (clean) | `rm -rf _build && dune build` (local `_opam` switch, `which dune` verified) | ✅ PASS (exit 0, 0 log lines) | 2s |
| Tests | `dune test` | ✅ 42 alcotest cases across 4 suites (8+17+7+10), 0 failed | 1s |
| selftest-contract | `./selftest-contract.sh` | ✅ PASS | 0s |
| selftest-load | `./selftest-load.sh` | ✅ PASS | 1s |
| selftest-effects | `./selftest-effects.sh` | ✅ PASS | 2s |
| selftest-callgraph-ocaml | `./selftest-callgraph-ocaml.sh` | ✅ PASS | 0s |
| selftest-callgraph-soundness | `STRICT=1 ./selftest-callgraph-soundness.sh` | ✅ `P1: 57 passed, 0 failed \| P2: 0 xfail, 19 xpass` | 1s |
| selftest-callgraph-go | `./selftest-callgraph-go.sh` | ✅ PASS (incl. DOM_ENUM + cgo-wrapper assertions) | 2s |
| Self-index golden | diff vs `test/fixtures/self-index-stats.txt` | ✅ GOLDEN OK (`19 / 366 / 3112`) | 0s |
| Determinism | index twice, compare | ✅ 3112 = 3112 | 0s |
| Kind integrity | NULL/invalid kinds | ✅ 0 | — |
| Contract flag | `callgraph_contract` | ✅ `v1` | — |
| Go build/vet | `go build ./... && go vet ./...` | ✅ PASS | 0s |
| Format/Lint | not documented for this repo | N/A | — |

## Tests: detail

- New tests added this branch: 7 CFG unit tests (`test_cfg.ml`) + 26 new soundness assertions (31→57 P1) + 19 P2 targets (all flipped to XPASS) + Go DOM_ENUM/cgo assertions.
- Existing tests: all pass, 0 skip, 0 fail.
- Regression detected: **NO**. The exhaustive population diff (`scripts/callgraph-diff.sh` vs main) reports **zero dropped edges**; kind movements are exactly the sanctioned set (MAY_TOP→MAY_ENUMERATED 747, MAY_TOP→MUST 9 lambda-related, MUST→MAY_ENUMERATED 123 divergence demotions).

## Spec Runnable Checks (specs/cfg-postdom-dominance.md)

| Check | Result |
|---|---|
| CHECK-1 build+test | ✅ PASS (Gates 1–2) |
| CHECK-2 STRICT soundness | ✅ PASS (57 P1, 0 failed — covers AC-1…AC-6 assertions incl. `reaches invoked_closure`=PATH EXISTS, `unreachable cond_if island`=UNREACHABLE, `escapes lam_map`=empty, dead-lambda no-edge) |
| CHECK-3 Go selftest w/ enumerated demotion | ✅ PASS |
| CHECK-4 golden + kind validity | ✅ PASS (`19/366/3112`, 0 invalid, v1 stamped) |
| CHECK-5 remaining selftests | ✅ PASS (contract/load/effects/callgraph-ocaml) |
| CHECK-6 (manual) kind distribution | ✅ recorded: **MAY_TOP 3.9%** (121) / MUST 32.3% (1004) / MAY_ENUMERATED 63.8% (1987) — target "well under 40%" exceeded (was 79% pre-branch) |
| CHECK-7 (manual) 15-subcommand audit table | ✅ present in `briefs/cfg-postdom-dominance-impl.md`; `find`/`exported` main-schema support added during review (205 lambda nodes locatable, 0 leaks into exported) |

## TUI

N/A — no TUI in scope.

## Cross-runtime QA

**Unavailable**: `codex` is on PATH but its workspace spend cap is exhausted
(`ERROR: You hit your spend cap…`, re-verified at QA time). Per the maintainer's standing
decision this cycle (recorded in `briefs/cfg-postdom-dominance-review.json`
`cross_runtime_findings`), Claude sub-agent substitutes covered the adversarial rounds for
steps 5–6 and the review; the QA deterministic gates above were run directly and are
reproducible by command. **Follow-up recorded:** codex re-verification of steps 5–6 + review
fixes when the cap resets.

## Verdict

**GO** — ready for `/roster-ship`
