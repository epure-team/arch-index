# Roster intake — change-review semantic contract

## Objective

Extend recurring analysis packages beyond an API inventory without inventing a
security verdict.  Define a versioned `change-review` contract which can
compare a current `arch-impact --format json` briefing with a reviewed
baseline, preserving the distinction between MUST, bounded MAY, and `MAY_TOP`
frontiers.

## Required design work before implementation

1. Identify stable semantic keys for touched functions, exported upstream
   candidates, tests, forward frontier holders and decision findings.  SQLite
   row ids, ordering, display truncation and raw Git diff text are forbidden
   keys.
2. Carry the input range, exact changed-line map, producer/tool identity,
   edge-kind contract and corpus/configuration scope as explicit provenance.
3. Separate four comparison outcomes: compatible change, incompatible
   baseline, unavailable/partial analysis, and execution failure.  Absence of
   a path/API/test must not mean a correction when scope changed or TOP exists.
4. State whether a first implementation should enrich `arch-impact` JSON,
   create a consumer-side sidecar, or both.  It must preserve the existing
   human briefing contract.

## Non-goals

- No automatic index build, baseline promotion, CI policy gate, severity/risk
  score, Git-text heuristic, or conversion of MAY to MUST.
- No claim that `MAY_TOP` is enumerable in the forward direction.

## Exit criteria for this intake

An implementable, testable contract with an explicit refusal vocabulary and a
minimal fixture matrix.  Code begins only after this contract review is GO.
