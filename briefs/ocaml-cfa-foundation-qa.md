# QA Brief — ocaml-cfa-foundation

**Date:** 2026-09-16
**Status:** GO ✅
**Round:** 1 (qualifying0/5, cycle1)
**Head:** 8eb28f4dcd04a0538a7bd17a519db60f75d3a47e

## Quality gates

All gates ran serially, stopping on any failure. Commands use `rtk proxy`.

| Gate | Command | Result | Observed duration |
|---|---|---|---|
| Build | `opam exec -- dune build` | exit0 | <1s |
| Fullsuite | `opam exec -- dune runtest --force` | exit0;345/345 Tezt,6/6 CFA native groups | <=314.817s including polling |
| Bundle/hygiene/scope | `node scripts/review-bundle-verify.js`; `git diff --check`; `bash scripts/check-scope-diff.sh briefs/ocaml-cfa-foundation-manifest.txt` | all0;22 bundle hashes | included below |
| CHECK1 | `node roster/ocaml-cfa-foundation/check-domain.js` | exit0;517 independent oracle cases | combined checks <=50.660s including polling |
| CHECK2 | `node roster/ocaml-cfa-foundation/check-cmt.js` | exit0;authentic fixture1/1 | included above |
| CHECK3 | `node roster/ocaml-cfa-foundation/check-tezos.js` | exit0;pinned410 replay | producer2.842s |
| Controls | `check-domain-test.js`, `check-tezos-test.js`, `calibrate-self-test.js` in the same roster directory | all0 | included above |

No configured formatter/full-linter/coverage command, as recorded in QA scope;
not claimed as executed. No coverage percentage. No TUI scope, skipped.
Full log: `improvement/2026-09-16-cfa/qa-runtest.log`, SHA256
`fb6daac5c8750b79ed0f7a9329408303ce4e54e411c393d3527391d170373679`.
Trailing setup/assertion/foreign-key diagnostics are negative controls within
the passing fullsuite, not hidden failures. No regression observed.
One new Tezt test and six kernel groups versus pre-stage baseline; existing
local-target/point-free expectations migrated only for the approved subset.

## Source and behavior qualification

286 tracked source/check/config files have equal before/after inventory digest
`c9b1b303e35cee3eb61106f0e42a7c1a66e7c72642825c2c3e66252524010e6d`.
Five executable SHA256s are unchanged. Detailed commands/hashes/results are in
`roster/ocaml-cfa-foundation/qa-execution.json`.
Product diff from reviewed791d1f9 to QA8eb28f4 is empty.

The44FR/19AC matrix in `roster/ocaml-cfa-foundation/spec-round2-report.md`
was checked against these fresh executable results. It covers domain closure,
bottom vs unknown, literal/alias/if/match/sequence targets, physical identities,
metadata/arity/independent residuals, flat refusal, static/alias preservation,
consumer query limits and the new opaque-root-alias known+unknown regression.
CHECK1/2/3 map to AC1–6/AC4,7–18/AC19 respectively as specified.

Tezos:45054 rows, canonical08f491da…, Irmin4849→4850,
protocol12171→12173,0losses/newMUST, sampled145152KiB.
Frozen baseline and pinned CMTs unchanged. Exact accounting only: no general
0CFA, functor substitution, cross-variant identity or soundness proof claimed.
Report: `improvement/2026-09-15-ocaml-cfa/check3-1789558871518-556652.json`.

## Code-intel gate

`node /home/mathias/dev/agent-roster/scripts/code-intel-resolve.js gate --timeout 120`
returned exit0, `SKIP: no code-intel block`, `RESULT: skip`.
Canonical claims reconciliation unavailable;3/3 local context digests verified
unchanged during review, with no subsequent input edits.

## Cross-runtime QA

Shared availability checker returned `skipped-degraded` (review breaker,
unchanged runtime version). OpenCode was not re-invoked. No cross-runtime
approval is claimed. Review's null pre_fix_sha/manualRED limitation remains.

## Verdict

GO — ready for roster-ship. QA convergence gate exit0, no causes/violations.
Routine validation/quiz delegated by explicit user autonomy, not fabricated.
Required exact-head remote CI remains mandatory before merge. Foreign7 preserved.
