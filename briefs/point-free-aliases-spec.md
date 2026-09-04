# Spec completion — point-free-aliases

**Status: VALIDATED**
**Date:** 2026-09-04
**Spec file:** `specs/point-free-aliases.md`

4 user stories, 9 FRs, 5 runnable checks, 21 challenges + 11 edge cases raised
adversarially, 12 resolved in the spec's own table.

Three findings changed the design the intake brief handed down. Each was measured,
not argued:

1. **Edge kind is MAY_ENUMERATED, not MUST.** Three frozen documents forbid MUST for
   a non-application relationship, and the existing kind matrix reaches the same
   answer on its own (`partial` demotes it). Effect propagation is unaffected —
   `Arch_exn` does not distinguish MUST from MAY_ENUMERATED.
2. **US-3's premise was wrong.** `open M` makes a bare identifier syntactically local
   and semantically qualified; `local_fn_stamps` holds only same-module top-level
   definitions. The 248/87 source-syntax split is not the resolution split, so it
   cannot be a work breakdown. US-3 now delivers the measurement.
3. **The marker cannot be called "alias".** `module_deps.dep_kind = 'alias'` already
   means module alias. Column is `edge_form`, value `'value_alias'`.

Implementation still waits on roadmap-1.6 for the qualified case; the spec does not.
