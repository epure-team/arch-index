# QA Brief — functor-binding-resolution

**Date:** 2026-09-13T19:07:14.855Z
**Status:** GO ✅
**Round:** 1 (qualifying 0/5)

## Round state

Fresh QA cycle1, round1. No qualifying cause; convergence gate0, no warnings/violations.
Tested b558a78 (product49bc78b); no product changes during QA.

## Quality Gates

| Gate | Command | Result | Duration |
|---|---|---|---|
| Build | opam exec --switch=/home/mathias/dev/arch-index -- dune build --root . | exit0 | 0.276s |
| Full suite | opam exec --switch=/home/mathias/dev/arch-index -- dune test --root . --force | exit0;320Tezt+64Alcotest | Tezt log span 167.06s |
| whitespace | `rtk proxy git diff --check` | exit0 | 0.000s |
| inventory | `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- node scripts/check-functor-bindings.js inventory` | exit0 | 1.043s |
| lifecycle | `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- node scripts/check-functor-bindings.js lifecycle` | exit0 | 0.698s |
| query | `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- node scripts/check-functor-bindings.js query` | exit0 | 2.405s |
| compatibility | `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- node scripts/check-functor-bindings.js compatibility` | exit0 | 0.249s |
| CHECK5 | `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- node roster/functor-binding-resolution/check-global-rollback.js` | exit0 | 0.948s |
| bundle | `rtk proxy node scripts/review-bundle-verify.js` | exit0 | 0.000s |
| scope | `rtk proxy bash scripts/check-scope-diff.sh briefs/functor-binding-resolution-manifest.txt` | exit0 | 0.000s |

## Tests: detail

54 feature Tezt tests included in320; plus standalone CHECK5 two-input rollback
and three-input continuation cases.64Alcotest pass. No test failures/skips in the
full executed suite. No standalone formatter/linter configured; whitespace gate0.
Raw log: roster/functor-binding-resolution/qa-full-tests.log.
Standalone raw summaries: roster/functor-binding-resolution/qa-checks.json.

All five spec CHECKs executed in this QA, not inferred from review:

- Inventory: direct/alias/curried identity,11 traversal contexts, duplicate identity,
  cross-CMT lookalikes, nullable/unit formals, all nine refusal premises PASS.
- Lifecycle: direct APIs and real CLI partial write/failed-row failure, reindex,
  zero/unreadable input and marker boundaries PASS.
- Query: six formats,36 byte oracles,57 limit0 corruptions,10 schema and7 marker
  refusals, default50-of60, accessed SQL failure and read-only behavior PASS.
- Compatibility:16 old semantic surfaces,3 legacy and3 flat oracles, unchanged
  database/catalogue bytes PASS.
- CHECK5: exact-checkout build; healthy controls then actual schema-only global
  rollback, full old facts and surviving binding rows equal, failed row persisted
  with no children, marker absent, later input processed PASS.

No call-target/0CFA/closure improvement asserted. Prior exact410CMT observation
(202 matched formals,1073 unresolved) remains separately attributed to its saved
producer hash; no new Tezos run in this QA. Neither Tezos sources nor held work changed.

## Code-intel gate

Skipped: no KB properties/code-intel block. Managed claims tooling absent.

## TUI

Not applicable: CLI/database feature, no TUI changes.

## Cross-runtime QA

Helper availability exit0, skipped-degraded: review breaker, unchanged runtime
version opencode:76f897c73342fdbf. No second-runtime execution or PASS claimed.

## Verdict

GO — ready for roster-ship. User's explicit standing autonomy covers routine
validation; no fabricated quiz response or gate waiver. Exact-head hosted CI and
ship-time schema slot check remain required before merge.
