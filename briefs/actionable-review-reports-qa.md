# QA Brief — actionable-review-reports

**Date:** 2026-09-12
**Status:** GO ✅
**Round:** 1 (qualifying 0/5), cycle 1

## Round state

Fresh cycle derived by `rtk proxy node scripts/lib/review/review-lifecycle.js --prior briefs/actionable-review-reports-qa-state.json`: round 1, cycle 1. Draft convergence exit 0 with no warnings/violations before persisting state, removing draft, then writing this report. Causes: [].

Root QA independently executed the following at clean input HEAD
`9649df1927223394ea9570fa5d393f9834c9f0f9` after review GO `66e966f`.
All commands ran in `/home/mathias/dev/arch-index-worktrees/actionable-review-reports`.
No product-code edits in QA. Dune commands were sequential with explicit root/switch.

## Quality Gates

| Gate | Exact command | Result | Duration |
|---|---|---|---|
| Build | `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune build --root . @install` | exit 0 | 0.122s |
| Full suite | `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune test --root . --force` | terminal exit 0, 240/240 Tezt plus Alcotest | whole-command duration not retained; first-to-last Tezt successes 131.562s |
| Committed whitespace | `rtk proxy git diff --check 932211be1ecd2b950d7cee6ef8dbbdd7bbed0460..HEAD` | exit 0 | <1s |
| Focused report | `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune exec --root . tezt/tests/main.exe -- --file report.ml` | exit 0, 6/6 | 0.873s |
| CHECK-1 | `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- node checks/actionable-review-reports.js rules` | exit 0, expected silent success | <1s |
| CHECK-2 | `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- node checks/actionable-review-reports.js ordering` | exit 0, expected silent success | <1s |
| CHECK-3 | `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- node checks/actionable-review-reports.js operands` | terminal exit 0, expected silent success | not retained across polling |
| CHECK-4 | `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- node checks/actionable-review-reports.js compatibility` | terminal exit 0, expected silent success | not retained across polling |
| Self index | `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- ./_build/default/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe --build-dir=_build/default/lib/arch_index --db-path=/tmp/arch-report-rootqa.nEsKtA/self.db --schema-path=architecture-schema.sql` | terminal exit 0 | not retained across polling |
| Recalibration | `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- env DUNE_CACHE=enabled DUNE_CACHE_STORAGE_MODE=copy ./scripts/recalibrate.sh --check` | terminal exit 0 | not retained across polling |
| Architecture rules | `rtk proxy ./_build/default/bin/arch_rules/arch_rules.exe /tmp/arch-report-rootqa.nEsKtA/self.db arch-rules.txt --on-vacuous fail` | exit 0 | 1.968s |
| Impact smoke | `rtk proxy ./_build/default/bin/arch_impact/arch_impact.exe /tmp/arch-report-rootqa.nEsKtA/self.db --diff 932211be1ecd2b950d7cee6ef8dbbdd7bbed0460..HEAD --repo .` | exit 0, informational | 1.356s |

No separate formatter/full-linter command is documented. Compiler checks and ranged whitespace
checks ran; existing opam maintainer metadata lint debt is not represented as passing.

## Tests: detail and behavioral coverage

240/240 Tezt succeeded versus the pre-feature 231-test baseline (net +9); no Tezt failure/skip
reported. Alcotest also succeeded (effects 8, tools 3, capabilities 17, parsers 10, CFG 7,
compare 5, URI 14). Controlled assertion/execution errors and foreign-key errors in the full
suite are expected negative-test output, not suppressed failures. Focused report tests also
validated SARIF against the vendored 2.1.0 schema. No regression detected by these checks.

All four frozen-spec executable checks passed, exercising authentic CLIs and assertions:

- Rules/census/witnesses: evaluated rules versus no-rules NOT_COMPUTED, faithful verdicts,
  exactness, sizes, reasons and ordered repeated logical witnesses in JSON/SARIF/HTML; no fake
  physical URI or target proof at an UNKNOWN frontier; report success distinct from gate policy.
- Ordering: declaration ordinals and duplicate names, explicit alert tiers, ordinal-only ties
  including reverse-lexical UNKNOWN/NOT_COMPUTED, complete results versus non-PASS alerts.
- Operands: original typed-AST slot 2, native literal kinds/identifier/other/missing handling,
  negative constant versus unary syntax, independent 200-site/context caps, exact occurrence
  totals and order, bounded representation, no source reread after source change/removal.
- Compatibility: old/NULL metadata unavailable, malformed present metadata refused, strict SQL
  type/completeness/cross-field checks, mixed producer attribution, invalid rules before writes,
  write errors and HTML escaping. Full suite additionally covers allow-count multiplicity,
  channel scope, selected-row identity, schema validation and checker exit 1 versus >=2 controls.

These are syntax/evaluation tests, not abstract interpretation or machine-checked certificates.
See the review's separate 18/18 FR matrix in `actionable-review-reports-spec-compliance.md`.

## Self-analysis raw evidence

SQLite count output was compared byte-for-byte by Node `assert.equal` to
`test/fixtures/self-index-stats.txt` (exit 0):

```text
modules: 23
functions: 828
calls: 5223
```

Recalibration measured all four cells, not a reused stale corpus:

```text
A base bin/base src: modules 23 functions 820 calls 5193
B new bin/base src:  modules 23 functions 820 calls 5193
C base bin/new src:  modules 23 functions 828 calls 5223
D new bin/new src:   modules 23 functions 828 calls 5223
attributable to source change only (B = A); pinned value is current
ceiling: pin 383; A=387 B=387 C=396 D=396
within headroom: measures 396 against pinned 383 (+/-25); pinned value is current
```

Architecture output:

```text
4 rule(s): 1 proved, 0 violation, 0 possible, 3 unknown, 0 unknown-no-contract, 0 vacuous, 0 not-computed
gate: 0 failing — violation=always possible=fail unknown=warn vacuous=fail not-computed=fail
```

UNKNOWN remains unproved. Impact output explicitly marked non-indexed changed files UNKNOWN,
reachability counts as lower bounds, and effects/decision analysis not computed.

## Code-intel gate

`rtk proxy node /home/mathias/dev/agent-roster/scripts/code-intel-resolve.js gate --timeout 120`
exited 0 with `SKIP: no code-intel block` / `RESULT: skip`. Skipped, not passing invariants.

## Cross-runtime QA

Provider-free shared-breaker command:

```bash
rtk proxy env OPENCODE_CONFIG_CONTENT='{"model":"github-copilot/gpt-5.6-sol"}' node scripts/xruntime-review.js opencode --task actionable-review-reports --phase qa --check-availability --write
```

Terminal exit 0:

```json
{"status":"skipped-degraded","reason":"runtime degraded during review with unchanged runtime version","config_digest":"opencode:76f897c73342fdbf","source":"review-go"}
```

Cross-runtime QA: skipped (review breaker, unchanged runtime version). No provider invocation,
no human-retry and no independent external QA pass claimed.

## Preflight corrections and limits

Wrapper presence and review static convergence passed. Claims reconciler/freshness authority
not installed: legacy/draft metadata only, no claims-validation pass. QA schema absent in the
consumer was read from the installed roster source instead. Initial friction preflight found
eight invalid category values; reviewer made metadata-only repair `9649df` BEFORE product gates.
Actual compiled validator then passed: 29 current entries checked, 86 historical entries skipped.
This is not a clean preflight and not a product-gate NO-GO cycle.

No TUI in scope. MCP not verified without its private dependency/token. Local Eio 1.3 is not CI's
Eio 1.5: remote CI still required. Focused Tezt reported preexisting `/tmp/tezt-*` leftovers;
ownership was not assumed and they were not removed. Recalibration's temporary worktrees have
terminated; root retains only the active delivery worktree until merge, then removes it.
Whole-command timings lost across polling are explicitly unavailable, never fabricated.

## Verdict

**GO** — ready for `/roster-ship`, round 1, qualifying 0/5. Standing user authorization covers
PR/green-CI/merge progression; no new interactive validation is claimed. Green remote CI and
exact-head merge checks remain mandatory.
