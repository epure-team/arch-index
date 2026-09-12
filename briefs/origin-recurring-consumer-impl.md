# Implementation Brief — origin-recurring-consumer

**Date:** 2026-09-12T19:08:35Z
**Mode:** full
**Status:** COMPLETED

## Modified files

| Files | Change | Reason |
|---|---|---|
| scripts/origin-consumer.js | addition | Fixed owned-library consumer; native fixture seam, current/reference drift, closed outcomes and attributable publication. |
| scripts/origin-consumer-artifacts.js | addition | Independent read-only status-dependent artifact validation. |
| checks/origin-recurring-consumer.js | addition | Authentic, adverse and package controls with exact checker exit mapping. |
| test/fixtures/origin-consumer/ | addition | Reviewed rule/allow/reference and owned native fixture. |
| tezt/tests/origin_recurring_consumer.ml, main.ml, dune | addition/registration | Three check modes and two checker-exit controls. |
| .github/workflows/ci.yml | addition | Dedicated consumer, validator and known-file14-day retention in existing build job. |
| docs/origin-consumer.md, README.md, CHANGELOG.md | addition/documentation | Usage, policy versus coverage, manual reference/allow review, provenance limits. |
| briefs/, roster/origin-recurring-consumer/, skills-meta/friction.jsonl | evidence | Pipeline records; no production evaluator/schema/library edits. |

## Decisions and deviations

One existing evaluator path; no value analysis, autoaccept or corpus download. Production CLI
only exposes --out. Exported runner has explicit owned-fixture/fault seams, never an environment
success bypass. Parent resolved physically, output leaf exclusive, report staging owned,
completion last; no atomic filesystem or source-to-CMT freshness guarantee.

Root found and requested corrections before handoff: actual SARIF serialization/parity,
input population/config presence, portable compiler lookup, cleanup/final-record errors,
policy retention before copies, physical provenance and detached HEAD, native violations even
with matching updated reference. All are within the frozen acceptance contract.

TDD deviation is explicit: the first red tested runner file existence only; production was
drafted before the full native behavioral test. Later real SARIF parity red1/green0 does not
retroactively establish strict test-before-code. Cleanup and stderr controls each had actual
behavioral red1 before their fixes and green0 afterward. Evidence in roster task records.

## Quality Gates

Executed by Sol product owner; independent roster review and root QA follow.

- Build: `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune build --root . @install` — exit0.
- Full suite: `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune test --root . --force`
  — final session60629 terminal0,245/245Tezt plus64Alcotest; last Tezt success19:07:58.378Z.
  Prior post-request session82217 also terminal0; only60629 includes final stderr fixes.
- Standalone: `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- node checks/origin-recurring-consumer.js <mode>`
  — authentic/failures/package each0; deliberate checker assertion1/execution2.
- Production consumer then validator — each0; latest retained owned package
  `/tmp/origin-consumer-evidence-final.NHLnhy/output`, held UNKNOWN,23/828/5223/491,
  zero drift,46sources/48CMT-family inputs, schema1.13+producer metadata, actual Git root,
  detached=false, physical output and explicit trusted-build assumption.
- `rtk proxy git diff --check` — exit0. No separate configured formatter/full linter or
  coverage framework; do not claim a coverage percentage. Existing self golden/recalibration/
  reachability/impact gates remain unchanged and required in QA and exact-head remote CI.

## Points of attention for review

Read every FR/AC, not just happy-path counters. Preserve UNKNOWN as unproved. Validate error
precedence and no complete-success marker after failed finalization. Artifact validation is
not a policy gate. Two real new/count controls also run with updated matching raw references,
still policy-failed1. Main DB/staging cleanup and final-record faults are deterministic
injections, not actual chmod permission tests. Outside-Git, detached state and physical-source
escape are exercised; a compiler-version relocation matrix is not.

Residual coverage: not every malformed verdict/census variant, signal/abnormal exit subtype,
WAL/SHM/journal or report-unlink failure has a separate injected case; shared branches are
implemented and related controls run. Remote artifact delivery remains unexecuted until CI.
No claims of formal proof, completeness or resistance to coordinated policy weakening.

## Identified out-of-scope

No evaluator or extraction refactor. arch-guard remains the separately authorized next slice,
not implemented here. No KB/claims authority/hooks installed, no invented projection.
One shared worktree/build; native fixture constructor now cleans setup failures. Two verified
stale owned native fixture directories were removed; no remaining owned native fixture dirs
at handoff. Retained compact reports are intentional until evidence is recorded for shipping.
