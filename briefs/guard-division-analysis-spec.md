# Spec Brief — guard-division-analysis

**Date:** 2026-09-13 (Europe/Paris)
**Status: VALIDATED**
**Spec file:** specs/guard-division-analysis.md
**User stories:** 3
**Clarifications:** 8
**Challenges resolved:** 16/16
**Functional requirements:** 47
**ACs:** 19
**Runnable checks:** 6 implemented standalone modes; R1 corrections and one self-contained ratchet pending

Operator validation under explicit standing user autonomy. No new human quiz/approval claimed.
Fresh research, clarification, adversarial challenge and formalization artifacts retained in roster/guard-division-analysis/.
Root corrected FR-031's numeric-reason obligation to exclude unsupported sites; no unresolved challenges.
Cross-spec entities/statuses remain separate; no existing extraction/schema/rule/reference mutation.
Inline structural audit passed (unique 47 FR/19 AC/6 CHECK metadata), not a substitute for missing claims reconciler validation/projection. Claims remain draft.
Actual compiled fixture success and fail-closed input paths are required, not waived; no not-feasible marker.

R1 revalidation uses review-existing, preserving all 47 FRs and 19 ACs. Fresh independent bounded challenge: `roster/guard-division-analysis/spec-r1-correction-challenge.md`. CLI-only public v1 clarifies an unpublished implementation choice, not a user-requested embedding capability. Required report context and missing fixture/oracle cases are made explicit without weakening acceptance. The challenge's proposed new mode in the existing checker is corrected to a new self-contained `scripts/check-guard-report-context.js`: the review ratchet overlays only that file and invokes it without arguments. Implementation, RED/GREEN and public installation verification remain pending. Claims tooling is still unavailable; no formal/evidence tier claimed.
