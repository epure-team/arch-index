# Spec completion — error-channels

**Status: VALIDATED**
**Spec:** `specs/error-channels.md` (v1.0.0, extends `specs/exn-raise-sets.md`)
**Mode:** autonomous; 25 challenges + 10 edge cases from the adversarial pass, all resolved from
sources or by recorded decision. Rule changes forced by the challenger: closing arms for value
channels = unguarded ∧ bound variable absent from the RHS; `transforms.mode` add/replace;
`converters` role (`Error_monad.catch`); head-call-only coverage for scopes and sinks; carrier
parameters contribute nothing; per-path config warnings vs whole-carrier fatal; `NOT_A_CARRIER`.
Stories US-1..US-4, FR-021..FR-034, AC-15..AC-20, CHECK-5..7.
