# Plan — origin-recurring-consumer

**Date:** 2026-09-12
**Status: VALIDATED**

## Sequential steps

1. **Native complete success package (test-first).** Add a failing native clean fixture check,
   then the shared runner's complete discovery/index/evaluate/report/provenance/publication path
   and read-only artifact validator. One coherent package is independently demonstrable outside
   production CI. No synthetic DB substitutes for this authentic path.
2. **Adverse outcomes (test-first).** Add native new/count controls and labelled injected fault,
   population-drift, mutation, output-ownership, parity, timeout/overflow and publication tests;
   extend the same runner and validator. Correctly observed expected runner exit1 makes checker
   pass0; deliberate checker assertion1 and execution2 controls stay distinct. Complete tests
   before declaring this capability done.
3. **Production adoption (test-first).** Pin reviewed self.rules/self.allow/reference and assertion
   rationale, register controls in Tezt, exercise actual fixed production CLI, integrate consumer,
   separate retention validation and known-file upload into existing build job, document operations.
   All existing gates plus authentic/failures/package modes and exact-head CI must pass before merge.

## Dependencies

Step2 extends step1's real end-to-end package; step3 deploys those already tested behaviors.
All three are internal vertical implementation increments in one reviewed/QA'd PR; do not ship
an incomplete foundation as a separate consumer delivery. No additional worktree needed.

## Consensus Table

| Point | Terra voice1 | Sol voice2 | Status |
|---|---|---|---|
| Authentic end-to-end fixture first | Accepted after root rejected initial horizontal layering | Accepted | AGREE |
| Adverse outcomes and complete evidence before CI | Accepted | Accepted | AGREE |
| Production adoption and docs last | Accepted | Accepted | AGREE |
| Separate artifact validator explicitly in scope | Confirmed | Confirmed | AGREE |
| No direction change | None needed | None warranted | AGREE |

Voice1 initially put all tests after implementation; root required vertical/TDD revision before
voice2 ran. Voice2 used 'atomic publication' despite intake excluding that guarantee; binding
intake wins: validated staging and final completion record, no whole-filesystem atomicity claim.
Different batching of new/count tests is normalized to step2, no competing technical direction.
No unresolved DISAGREE or USER-CHALLENGE. Both independent inputs used intake only.

## Identified risks

| Risk | Mitigation |
|---|---|
| Compiler fixture identities | Pin native line/function/count details; investigate differences, no auto-regeneration. |
| Reporter field compatibility | Use current existing reporter contract; shared-field validation, not guessed extra schema or changed evaluator. |
| Output/cleanup or mutation | Exclusive leaf ownership, same-run hashes, final marker last, errors visible; no atomic-filesystem claim. |
| CI loses evidence/masks failure | Independent status-aware validator then upload after actual consumer start, known files only, no continue-on-error. |
| Tests look green after execution failure | Checker0 means expected results verified,1 assertion,>=2 execution; deliberate controls. |
| Fixed counters drift on legitimate change | Manual reviewed reference edits; separate allow-list; no completeness claim. |

## Decisions made

Use built existing CLIs, fixed production corpus, one policy, observational reference, one owned
worktree. Delegate product implementation to Sol/Terra with scoped shared checkout and exclusive
build ownership; root independently integrates/verifies and owns phase artifacts/ship.

## Assumptions

Existing CLI fields and CMT root verified in research; implementation rechecks live interfaces.
Trusted local build, no hostile concurrent parent changes, Node available; limits120s/16MiB remain
contractual. Claims reconciler/KB/hooks absent; neutral manifest questions digest verified exactly.
Full route, no formal-triage signal. Standing explicit autonomy replaces new quizzes; no new human
answers or approval conversation claimed. Plan derives only from validated amended intake.

## Files

- scripts/origin-consumer.js (create): narrow --out consumer/exported owned-fixture seam.
- scripts/origin-consumer-artifacts.js (create): read-only package integrity validator.
- checks/origin-recurring-consumer.js (create): authentic/failures/package standalone checks.
- test/fixtures/origin-consumer/ (create): self.rules/self.allow/reference.json and native fixture inputs.
- tezt/tests/origin_recurring_consumer.ml (create): three modes and checker-exit controls.
- tezt/tests/main.ml and tezt/tests/dune (modify only registration/dependencies as needed).
- .github/workflows/ci.yml (modify only dedicated consumer/validator/14-day known-file retention).
- docs/origin-consumer.md (create), README.md and CHANGELOG.md (document/link feature).
- briefs/, roster/origin-recurring-consumer/, specs/origin-recurring-consumer.md,
  skills-meta/friction.jsonl (pipeline evidence only).

## Quality Gates

- Build: `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune build --root . @install`
- Full suite: `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune test --root . --force` (baseline and green verification, terminal exit required).
- Whitespace: `rtk proxy git diff --check` (no separate formatter configured).
- `rtk proxy node checks/origin-recurring-consumer.js authentic`
- `rtk proxy node checks/origin-recurring-consumer.js failures`
- `rtk proxy node checks/origin-recurring-consumer.js package`
- Fresh production `rtk proxy node scripts/origin-consumer.js --out <new-owned-leaf>` then
  `rtk proxy node scripts/origin-consumer-artifacts.js <same-leaf>`; create parent with mktemp -d,
  no literal-placeholder execution. Record real measured corpus/status/package evidence.
- Existing self golden/recalibration/reach rules/impact smoke: current CI commands unchanged.
  Root QA executes them and exact-head remote CI checks all before ship.
