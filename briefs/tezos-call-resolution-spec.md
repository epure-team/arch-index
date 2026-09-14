# Spec Completion — tezos-call-resolution

**Status: VALIDATED**
**Date:** 2026-09-14

Specification: specs/tezos-call-resolution.md. Scope: first local structured-module target candidate and its fixed410 comparison setup, within the approved five-attempt loop.

Two independent user stories, eleven GWT scenarios, eight clarifications, eight resolved adversarial challenges, fifteen functional requirements, eleven acceptance criteria and three planned runnable checks. Source research, clarification, challenge and formalization used fresh sequential Sol/Terra roles; concurrent dispatch was unavailable at the runtime thread limit. Source traversal was explicitly corrected not to imply module ownership. Durable details: roster/tezos-call-resolution/spec-input.md and spec-resolutions.md.

Validation uses the user's standing autonomous execution instruction. No interactive quiz answers are claimed. Claims metadata remains draft because canonical validation/projection tools are absent; this status is workflow validation, not formal verification or executed-check evidence. All three checker commands are implementation deliverables, not existing successful checks.

No product change or retained iteration yet. Next: roster-plan from the validated intake; comparator setup and baseline verification must precede the product edit.

## Review round1 return — existing contract revalidated

The persisted review NO-GO names FR-007/AC-6. Existing C-5/C-6 already require
syntactic-arity preservation; three independently executed reviews and a native
counterexample establish the omitted-slot issue. The spec is reviewed/extended,
not overwritten or weakened. Clarification: count supplied Some expressions for
new owned heads, preserve actual overapplication residuals and existing non-owned
head/CFG behavior. AC-12/CHECK-4 adds a self-contained native ratchet; AC-13/CHECK-5
addresses the separate FR-014 negative-test gap. Totals now13 ACs/5 checks;15 FRs
and the original stories remain. No fresh full-story research or quiz is claimed:
this bounded revalidation uses existing adversarial evidence and the user's
standing autonomous approval, with no unresolved choice or expanded product scope.
Claims tooling remains unavailable. Return to the existing plan's focused
implementation with these tests; no keep/QA/CI approval is implied.
