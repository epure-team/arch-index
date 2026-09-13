# QA Brief — functor-instance-resolution

**Date:** 2026-09-13T12:03:20.358Z
**Status:** GO ✅
**Round:** 1 (qualifying 0/5)

Fresh cycle1. Reviewed product source c2a8add; HEAD ec64644, no product changes
since independent review. Standard confirmations covered by explicit autonomy.

## Quality Gates

All compiler commands used rtk proxy opam exec --switch=/home/mathias/dev/arch-index --.

| Gate | Command | Result | Duration |
|---|---|---|---|
| Build | dune build --root . | exit0 | 0.260s |
| Full tests | dune test --root . --force | exit0,266Tezt+64Alcotest | Tezt159.505s |
| Hygiene | rtk proxy git diff --check main...HEAD | exit0 | <0.01s |
| CHECK-1 | node scripts/check-functor-catalogue.js inventory | exit0 | 0.161s |
| CHECK-2 | node scripts/check-functor-catalogue.js lifecycle | exit0 | 0.309s |
| CHECK-3 | node scripts/check-functor-catalogue.js query | exit0 | 1.304s |
| CHECK-4 | node scripts/check-functor-catalogue.js compatibility | exit0 | 0.169s |
| Bundle | rtk proxy node scripts/review-bundle-verify.js | exit0,22SHA1.6.0 | <0.01s |

Raw full suite: roster/functor-instance-resolution/qa-full-suite.log.
Exact supplemental results: roster/functor-instance-resolution/qa-gate-results.json.
No configured formatter/linter: hygiene is not reported as a full lint pass.

## Tests: detail and behavioral scope

Ten added Tezt cases;256 existing Tezt and64 Alcotest pass; no failure or reported
skip in the raw log. Expected negative-fixture stderr remains preserved, not hidden.
No regression detected on the exercised corpus. This is not a universal proof.

| Scope ACs | Actual checks |
|---|---|
| AC-1,3,4,8,14,15 | Inventory:19 native apps, ordinary/unit,5 contexts; synthetic premises, topology, paths/anonymous/shadowed/external boundaries |
| AC-5,6,7,10 | Lifecycle: exact selections, copies/symlinks, all5 failed outcomes, real savepoint rollback, marker boundaries/reindex/empty selection and collected0apps |
| AC-2,11,12,13,16 | Query: crafted valid3rows,19 core corruptions plus22 mutations,31 extended successes,6formats, usage/refusal precedence, invalid rows beyond limit0, empty JSON, readonly hashes |
| AC-1,2,6,9 | Compatibility:16 semantic-table/contracts,3 legacy query byte oracles,2 indexing passes, unchanged catalogue and database hashes |

Detailed FR001–030/AC1–16 mapping: roster/functor-instance-resolution/spec-compliance-report.md.
Lifecycle interruption coverage exercises real lifecycle boundaries, not SIGKILL.

## Code-intel gate

Skipped: no kb/properties.md or code-intel invariant block installed; claims
reconciler/hooks also absent. No fabricated managed-claims pass.

## TUI

Not applicable: batch CLI, no TUI/web/MCP change in scope.

## Cross-runtime QA

Actual provider-free breaker command:
rtk proxy node scripts/xruntime-review.js opencode --task functor-instance-resolution --phase qa --check-availability --write
returned exit0, skipped-degraded, source review-go, unchanged runtime version.
Cross-runtime QA: skipped (review breaker, unchanged runtime version).
No second-runtime QA pass is claimed; review timeout120s is preserved in its journal.

## Verdict

**GO** — ready for roster-ship. QA convergence gate exit0, round1/cycle1,
no cause and no escalation. CI still must verify the exact PR head, including
self-index/recalibration/rules/origin evidence/change-impact. No Tezos resolution
gain, held-issue publication, MCP build or formal verification is claimed.
