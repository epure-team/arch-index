---
name: roster-spec
type: spec
status: draft
feature: OCaml CFA qualification
stage: 5
date: 2026-09-17
---

# Spec — OCaml CFA qualification

## Purpose

Qualify the already-delivered bounded OCaml CFA/functor precision through
truthful existing-query semantics, a repeatable useful-query fixture, and a
pinned Tezos/Irmin measurement. This is not a new solver, a completeness claim,
or the later public query/profile/recurrence roadmap.

## Requirements

- **FR-001:** Any change-impact closure over `MUST ∪ MAY_ENUMERATED` MUST be
  labelled possible/bounded, never definite or ground truth. Definite language
  is reserved for a MUST-only path.
- **FR-002:** `arch-impact` text, Markdown, JSON field documentation and tests
  MUST distinguish the resolved bounded cone from the additional TOP-open cone.
  No closed-world conclusion is permitted when TOP is reachable or the contract
  is absent.
- **FR-003:** A task-local useful-query checker MUST run authentic indexed CMT
  input and prove one MUST-only positive path, one bounded MAY path, one retained
  MAY_TOP frontier, and the distinction in `arch-impact` output.
- **FR-004:** The checker MUST refuse old/flat/markerless or malformed setup as
  an operational/setup failure and distinguish it from an assertion mismatch.
- **FR-005:** The pinned 410-CMT qualification MUST preserve exact semantic
  relation accounting (no resolved loss, no new/upgraded MUST), report separate
  Irmin/protocol changes, and label wall/RSS values as observations.
- **FR-006:** Target-v2 relations MAY be used as evidence only when their exact
  witness chain validates. The checker MUST NOT classify arbitrary
  `MAY_ENUMERATED` rows as CFA/functor facts.
- **FR-007:** Documentation must give a short operator-facing explanation of
  MUST, bounded MAY and TOP; examples must match executed checker output.

## Acceptance criteria

1. A fixture where `entry -> helper` is MUST and `helper -> target` is
   MAY_ENUMERATED yields a possible impact cone containing `entry`, without a
   claim that `entry` definitely reaches `target`.
2. The same fixture retains a `MAY_TOP` path and reports its frontier distinctly;
   removing the TOP may establish a closed *bounded* cone but not turn MAY into
   MUST.
3. Text/Markdown do not contain "definitely reach" for a mixed MUST/MAY closure;
   JSON carries an explicit machine-readable scope/limitation rather than relying
   on prose.
4. A control mutating the checker expectation exits 1; a missing contract/input
   exits 2; normal execution exits 0.
5. The frozen Tezos replay is input-hash bound and reports its resource evidence
   with no performance-bound claim.

## Non-goals

No cross-unit/whole-program CFA, target cloning, target-v2 schema redesign,
generic user benchmark CLI, CI policy gate, risk score, or automated report
profile belongs to this stage.
