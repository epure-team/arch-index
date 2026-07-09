# Spec Brief — cfg-postdom-dominance
**Date:** 2026-07-09
**Status:** VALIDATED
**Spec file:** specs/cfg-postdom-dominance.md
**User stories:** 4
**Clarifications:** 9
**Challenges resolved:** 26/26
**Functional requirements:** 20
**ACs:** 7
**Runnable checks:** 7 (5 automated, 2 manual)

Notes: quiz round 1 surfaced two corrections (handler-drop misread → confirmed record-demoted;
reaches-through-MAY_ENUMERATED proposal → rejected, contract kept MUST-only). US-4 (enumerated
demotion, OCaml+Go) added during clarification — a contract-level precision win beyond the
original R1+R2 scope.
