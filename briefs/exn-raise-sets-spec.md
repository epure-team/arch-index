# Spec completion — exn-raise-sets

**Status: VALIDATED**
**Spec:** `specs/exn-raise-sets.md` (v1.0.0, 2026-09-03)
**Mode:** autonomous (user instruction); no question was put to the human. Two challenge
resolutions changed the design and are marked **[decision]** in the spec:

1. Raise heads are recognised by the `%raise`/`%raise_notrace`/`%reraise` primitive, not by the
   `Stdlib` path (C-10 — Tezos's protocol environment re-exports `raise` under its own path;
   `failwith` there is the error-monad one and must not be an origin).
2. Verdict vocabulary `BOUNDED / UNBOUNDED (⊤) / BOUNDED_UNDER_HYP(externals_pure)` replaces the
   intake's "SOUND" (C-17).

Plus a soundness rule from EC-11: a handler arm closes only if every raise in its RHS has a
literal constructor argument (indirect re-raise through `match e with …` never closes).

Stories: US-1..US-4 (4), scenarios: 10 + 10 + 4 + 3, challenges: 19 resolved, edge cases: 13,
FR-001..FR-020, AC-1..AC-14, CHECK-1..CHECK-4.
