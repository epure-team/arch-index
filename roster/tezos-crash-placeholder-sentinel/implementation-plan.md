# Roster implementation plan — Tezos crash/unfinished-code sentinel

## Goal

Deliver S1 from `specs/tezos-defensive-sentinels.md` as a review obligation,
not a vulnerability verdict.  The consumer owns no new call-graph semantics:
it reads an exception-aware main-schema index and makes all missing evidence
visible.

## Ordered slices

1. **Qualification envelope.** Define and validate a target-owned policy with
   an explicit root selector, source-surface mapping and input artefact
   identities.  Missing/empty roots, duplicate/ambiguous surface rules,
   malformed policy and old/flat/incomplete indexes must refuse before a
   report can look empty.
2. **Attributed origin report.** Consume the producer forms
   `assert_false`, `assert`, `division`, `index`, `partial_match`,
   `failwith` and `invalid_arg`; emit guard class, location, configured
   surface, `MUST`/`MAY_ENUMERATED` reach class, lower-bound coverage and the
   named unresolved/TOP frontier.  Non-zero literal division remains absent
   because the producer, rather than this report, proved it impossible.
3. **Witnesses and independent oracle.** For each reported origin whose
   resolved cone establishes a route, retain a bounded root-to-origin witness
   with edge kinds.  A TOP frontier is never fabricated into that route.
   Owned CMT fixtures and an independently calculated expected JSON object
   cover unconditional/checked assertions, zero/variable division, MUST,
   MAY and TOP cases.
4. **Corpus qualification and recurrence.** Add a pinned, observational
   Tezos replay and a non-blocking recurring consumer which compares only
   compatible policy/manifest identities.  Deltas are review prompts, never a
   defect count or CI security gate.

## Guardrails

- A source-surface policy describes ownership, not runtime reachability.
- A feature-disabled path remains a row/frontier unless a later S3 entry
  policy establishes the deployment boundary.
- No Tezos checkout is modified; its dirty state is out of scope.
- Each slice needs an independent oracle, local controls, hosted CI and a
  guarded merge before the next slice.
