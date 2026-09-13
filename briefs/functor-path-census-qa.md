# QA Brief — functor-path-census

**Date:** 2026-09-13
**Status:** GO ✅
**Round:** 1 (qualifying 0/5)

## Round state

Fresh cycle round1; causes []; convergence gate exit0, no warnings/violations.
Reviewed implementation ba4393a; no code changes after review.

## Quality Gates

All shell commands prefixed with rtk proxy. Build/test/native/census additionally
use opam exec --switch=/home/mathias/dev/arch-index --.

| Gate | Command | Result | Duration |
|---|---|---|---|
| Build | dune build --root . | PASS exit0 | 0.28s |
| Full tests | dune test --root . --force | PASS exit0,320Tezt+64Alcotest | 161.097s |
| Whitespace | git diff --check | PASS exit0 | <1s |
| Bundle | node scripts/review-bundle-verify.js | PASS exit0,22/22 | <1s |
| Scope | bash scripts/check-scope-diff.sh briefs/functor-path-census-manifest.txt | PASS exit0 | <1s |
| Native | node roster/functor-path-census/check.js | PASS exit0 | not separately timed |
| Corpus | node roster/functor-path-census/run.js --manifest roster/functor-instance-resolution/tezos-irmin-candidate/manifest-410.tsv --out roster/functor-path-census/qa-replay.json | PASS exit0 | not separately timed |

Complete QA test log: roster/functor-path-census/qa-full-suite.log.
Formatter/standalone linter not configured; not claimed run.

## Tests: detail

320 existing Tezt and64Alcotest pass; no existing test-suite changes.
Native checker covers10 fixture applications,9unsupported/1matched, repeated
and shadowed paths, class/display distinction; malformed/empty/digest/duplicate/
nonabsolute/nonregular manifests; injected write failure, temp cleanup,
exclusive publication and unchanged preexisting output; deterministic replay.
QA corpus compared totals, unit_inventory and every artifact record against
the committed report using strict deep equality: PASS. Owned replay removed.
1,275 applications,202matched unchanged,1,050unsupported; exact410 digests
validated before and after. No target gains or declaration ownership inferred.
No regression detected.

## Code-intel gate

Skipped: no resolver installed, no KB/properties.md block or installed gate pack
in this legacy consumer. Claims reconciler and task-context projection absent.

## Spec and TUI

Skipped: internal chore has no product spec; no TUI scope. Native extra-type
module-head branches not naturally exercised; no invented coverage percentage.

## Cross-runtime QA

Shared availability check actually ran: skipped-degraded, review breaker with
unchanged runtime version, config_digest opencode:76f897c73342fdbf, source review-go.
No new runtime attempt and no cross-runtime approval claimed.

## Verdict

GO — ready for roster-ship under standing explicit user autonomy.
