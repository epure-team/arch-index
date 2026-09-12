# Plan — actionable-review-reports

**Date:** 2026-09-12
**Status: VALIDATED**

## Sequential steps

1. **A — optional evaluated-rule report, end to end.** Start with authentic failing CLI
   tests/checks for rules/witnesses/order/compatibility. Mechanically share parser/evaluation,
   keep arch-rules gate policy local, and add --rules to report collection plus JSON/SARIF/HTML.
   Preserve unavailable no-rules behavior and all evaluator result semantics. Include exact
   census, ordinals, explanation, safe provenance and error-before-write handling. Update
   report documentation in this increment. Complete only when new focused tests, existing
   report/rules/SARIF regressions, build and whitespace checks pass.
2. **B — typed divisor context, end to end.** Start with failing authentic CMT fixture and
   query/report cases. Add nullable metadata and versioned schema documentation, capture
   original slot-2 syntax, read with capability guards and strict validation, attach bounded
   contexts without changing allow identities/counts, and render in all report artifacts.
   Include old/malformed metadata, both budgets, UTF-8 limits, changed source and unsupported
   producer cases. Complete only with its immediate green tests and docs.
3. **Integrated delivery.** Run the full checker/Tezt/build and self-analysis gates, explain
   any source-driven golden movement per ADR 001, then roster-review → roster-qa → roster-ship.
   Open one complete feature PR, correct failures, merge only exact-head green, resync main,
   update roadmap and remove this delivery worktree/build. No feature tests are deferred here.

## Dependencies

B uses A's shared result/report transport; A is independently useful without operand changes.
Inside either increment, contract/extraction/storage/rendering are internal work, not independent
completed product milestones. All accepted requirements belong to this one roadmap delivery;
do not call the feature complete or merge a partial-contract PR after A alone.

## Consensus Table

| Point | Sol voice 1 | Terra voice 2 | Status |
|---|---|---|---|
| Shared parser/evaluator with gate policy kept separate | Agree | Agree | AGREE |
| Rule reporting and divisor context as two vertical increments | Corrected initial layering | Confirmed grouping of initial internal steps | AGREE |
| Tests/docs accompany each increment | Agree | Agree | AGREE |
| Preserve allow counts/identities and no-rules compatibility | Agree | Agree | AGREE |
| Distinct census, verdict, coverage, provenance and display order | Agree | Agree | AGREE |
| No product question or direction change | None | None | AGREE |

Voices ran sequentially, intake-only, without receiving each other's output. New-thread creation
was unavailable; completed Sol/Terra agents were reused, not fresh contexts. Root required both
to replace horizontal milestone lists with vertical grouping. There are no unresolved DISAGREE
or USER-CHALLENGE items. Standing user autonomy replaces repeated quiz/approval; none is claimed.

## Identified risks

| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| Extraction changes rule verdicts/diagnostics/exits | Medium | High | Characterization/parity before and after; keep policy at CLI boundary |
| Report/evaluator dependency cycle | Medium | High | Shared evaluator below report; one existing verdict vocabulary |
| Availability/provenance conflation | High | High | Mixed verdict and native/imported controls, explicit separate fields |
| Wrong optional argument slot or inferred value | Medium | High | Original-slot fixture and constant/identifier/other/missing controls |
| Site/context cap or exemption-count conflation | Medium | High | Independent limits and same-line multiplicity controls |
| Old DB query refusal hidden as empty success | Medium | High | Guard absent columns; strictly reject malformed present metadata |
| Artifact disagreement or fabricated SARIF locations | Medium | High | One report value, direct cross-format comparisons and schema validation |
| Partial I/O output mistaken as success | Medium | Medium | Nonzero write errors/no success summary; document non-atomic output |
| New indexer functions move golden | High | Medium | Measure; no guessed counts or gate weakening |
| Excess disk or Dune contention | Medium | High | Sole delivery worktree, serial Dune with explicit root; exact temporary cleanup |

## Decisions made

Use optional in-process evaluation, not detached JSON or persisted runs. Use typed-AST syntax,
not current source rereads or abstract inference. Keep unsupported data explicitly unavailable.
Do not alter vendor review tooling, unrelated issues or existing blocked PR #93.

## Assumptions

Implementation may choose additive field/module names and serializers within the complete
intake contract, documenting the machine interface and testing it. It must first read relevant
files and verify dependencies/Typedtree representation rather than assuming a helper exists.
No new runtime package is needed. The existing project switch and schema validator are ready.

