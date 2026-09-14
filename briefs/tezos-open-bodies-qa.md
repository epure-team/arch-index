# QA Brief — tezos-open-bodies

**Date:** 2026-09-14T22:22:54Z
**Status:** GO ✅
**Round:** 1 (qualifying 0/5)

## Round state

Fresh cycle 1, round1; causes: []; convergence gate exit0, no warnings or violations.
Reviewed source cd3cb3c; no product/checker changes during QA. Routine validation
uses the user's explicit standing autonomous authorization; no quiz answers invented.

## Quality Gates

| Gate | Command | Actual exit | Duration |
|---|---|---:|---:|
| Build | `opam exec -- dune build` | 0 | 0.346s |
| Full tests | `opam exec -- dune exec tezt/tests/main.exe -- --no-color` | 0, 336/336 | 243.628s |
| Bundle | `node scripts/review-bundle-verify.js` | 0, 22 SHA-matched files | 0.030s |
| Frozen baseline | `node roster/tezos-open-bodies/prepare-baseline.js --check` | 0 | 3.679s |
| Whitespace | `git diff --check` | 0 | 0.005s |

Formatter/full lint and coverage: not configured; unavailable, not PASS.
Raw logs and exact command/exit/duration arrays are in
`improvement/2026-09-14-tezos-resolution/attempt3-qa-primary.json` and
`attempt3-qa-checks.json`; full log `attempt3-qa-full.log` in that directory.
Four new tests and332 existing tests passed; no test skipped or failed.

## Runnable checks

All paths below are under `roster/tezos-open-bodies/`; all commands personally
executed by main, serially, with no source/report writes during CHECK3/4.

| Check | Command (node) | Actual exit | Duration |
|---|---|---:|---:|
| CHECK1 | `check-native.js` | 0 | 29.966s |
| CHECK2 | `check-witness-inputs.js` | 0 | 6.702s |
| CHECK3 | `check-baseline.js --replay` | 0 | 4.004s |
| CHECK4 | `verify.js --witness improvement/2026-09-14-tezos-resolution/attempt3-reviewed-witness.json` | 0 | 7.518s |
| CHECK5 | `check-self.js` | 0 | 0.250s |
| CHECK6 | `check-residual-witness.js` | 0 | 2.147s |

CHECK1 covers exact shadow/physical body identity, arity/omitted arguments,
partial/overapplied behavior, missing/dropped/ambiguous refusal, complete paired
rich functions/effects/ownership/CFG/scopes/origins/carriers and counted flat facts.
Computed structure/application/unpack opens and configured value channels are
non-vacuous; allowed transitions and three residual sites are individually pinned.
CHECK2 checks316 actual DB pairs and13 refusals. CHECK3 preserves the immutable
baseline,17 malformed-record refusals, no-overwrite and cwd independence.
CHECK6 compiles genuine native groups: two positive controls and two reuse refusals.
CHECK5 preserves exact self references and frozen guard policy with pristine attribution.

Raw CHECK4: PASS, witnessed=true, retention_authorized=false, old_rows=45052,
new_rows=45052, removed_rows=316, added_rows=316, relation_losses=0,
relation_gains=316; Irmin0/protocol316/other0; errors=[].
Candidate `attempt3-candidate-atEmf8`, digest
`9ab4e0b13457247fb93dc83bf80323fcc5cec67866a18f56995ac0ec4a20867e`;
baseline digest `00f1769d6db7f6ee91ee51becabccd7b4ce13975acb6610c95ace69a7f620e9b`.
No new MUST, lost retained relation or unexplained movement. Retention still
requires exact-head green CI and merge, not this comparator alone.

## Code-intel gate

`node /home/mathias/dev/agent-roster/scripts/code-intel-resolve.js gate --timeout 120`
exit0,0.033s; raw output: `SKIP: no code-intel block` / `RESULT: skip`.
TUI: not applicable, no TUI change. Hooks and claims reconciler/context manifest
are absent; manual pipeline fallback, no invented managed checks.

## Cross-runtime QA

Provider-free `node scripts/xruntime-review.js opencode --task tezos-open-bodies
--phase qa --check-availability --write` returned exit0, `skipped-degraded`,
reason `runtime degraded during review with unchanged runtime version`, source
`review-go`, digest `opencode:76f897c73342fdbf` (QA sandbox digest).
Cross-runtime QA: skipped (review breaker, unchanged runtime version).
Review's actual120s timeout remains DEGRADED, never PASS. Tool warning:
`xruntime-review: warning — briefs/ is not git-ignored in this repo; the append-forever journal will be a standing untracked file visible to the scope gate (D-8).`

## Verdict

**GO** — ready for roster-ship; exact-head required CI and rebase merge remain pending.
Seven unrelated untracked paths and held PR93 remain untouched.
