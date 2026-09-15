# QA Brief — tezos-recursive-typed-bodies

**Date:** 2026-09-15T07:32:19Z
**Status:** GO ✅
**Round:** 1 (qualifying 0/5), fresh cycle 1

## Quality Gates

Actual sequential subprocess receipts: `improvement/2026-09-14-tezos-resolution/attempt5-qa1.json`;
raw outputs: matching `attempt5-qa1-gateN.log`. Every command below starts with `rtk proxy`.

| N | Command after prefix | Exit | Duration ms |
|---|---|---|---|
| 1 | `opam exec -- dune build` | 0 | 482 |
| 2 | `opam exec -- dune exec tezt/tests/main.exe -- --no-color` | 0, 342 SUCCESS | 272111 |
| 3 | `node scripts/review-bundle-verify.js` | 0 | 59 |
| 4 | `git diff --check` | 0 | 33 |
| 5 | `git diff main...HEAD --check` | 0 | 37 |
| 6 | `node roster/tezos-recursive-typed-bodies/prepare-baseline.js --check` | 0 | 4488 |
| 7 | `node roster/tezos-recursive-typed-bodies/check-native.js` | 0 | 3195 |
| 8 | `node roster/tezos-recursive-typed-bodies/check-witness-inputs.js` | 0 | 3864 |
| 9 | `node roster/tezos-recursive-typed-bodies/check-baseline.js` | 0 | 5778 |
| 10 | `node roster/tezos-recursive-typed-bodies/check-comparison.js` | 0 | 29723 |
| 11 | `node roster/tezos-recursive-typed-bodies/check-compatibility.js` | 0 | 4033 |
| 12 | `node roster/tezos-recursive-typed-bodies/check-residual-capacity.js` | 0 | 7147 |
| 13 | `node /home/mathias/dev/agent-roster/scripts/code-intel-resolve.js gate --root . --timeout 120` | 0, RESULT: skip | 53 |

## Tests and scoped acceptance

340 existing plus two new tests passed, zero failures. No regression observed;
this does not claim to fix historical intermittent LSP stalls. No formatter,
full lint or coverage configured; not asserted PASS.

CHECK-1 PASS: AC-1/4/5/6/7/8/10/12/13/14/20/21 — exact admission and rejected
neighbors, active identity, original physical root, arity, storage/collisions,
non-vacuous contexts and complete counted rich/flat preservation.
CHECK-2 PASS: AC-2/3/4/5/10/11/15/16/17/21 — independent native witness,
tampering, ordinal/multiplicity, source identity and single-use permissions.
CHECK-3 PASS: AC-2/15 — sealed immutable v2 baseline, read stability and neutral replay.
CHECK-4 PASS: AC-1/2/3/7/11/13/15/16/17/18 — fresh pinned410 replay,
14 distinct additional protocol relations, zero Irmin gain, zero loss, 45052 rows.
CHECK-5 PASS: AC-7/12/14 and local portions of AC-18/19 — public/schema/self-policy
and non-resolution preservation. CHECK-6 PASS: AC-8/9/17 — partiality and residual capacity.
AC-18 retention and AC-19 exact-head CI/merge remain shipment obligations, not local PASS claims.

## Automatically captured custody

QA ran on `c1ed896e07d562fa5955b97d6bef1fd32533ff14`. The runner persisted actual
pre-state before executing gates and independently captured actual post-state
after all 13. Complete state equality and manifest validation passed; integrityError
is null. No source/report/Git writes occurred during the sweep. Seven unrelated
untracked user files and the Tezos checkout state remained unchanged.
Source fingerprint before/after: `8c63aaaf2c155ce2b190c7e5d84c136eb42bf362dba16d9115c60d129e2313d1`.
Actual current producer before/after: `1cb7943cefa15a56f0df39fd2c2e741832d1acefaeedb92d189eb643075e9593`.
This is measured evidence, not the discarded aggregate reviewer claims.

## Conditional gates

Code-intel gate: skipped (no code-intel block). No KB/managed claims reconciler,
context freshness manifest or harness hooks installed. TUI: not applicable.
Cross-runtime QA: skipped (review breaker, unchanged runtime version).
Actual availability helper returned skipped-degraded; OpenCode's review timeout
is not an independent PASS. No implicit retry or invented human answers.

## Verdict

GO for roster-ship under standing explicit user autonomy. Lifecycle returned
round1/cycle1/fresh_cycle=true. QA convergence gate exited0 with no warnings or
violations before state persistence and this report. Fifth candidate remains
unretained until required CI succeeds on the exact PR head and guarded rebase merge.
