# Spec Completion — rust-soundcg-whole-program

**Date:** 2026-09-03
**Status: VALIDATED**

`specs/rust-soundcg-whole-program.md` written and validated. 2 user stories (US-1 sound
whole-program-safe skeleton, P0; US-2 whole-program trait-impl enumeration, P1), 18 adversarial
challenges raised and resolved (including 3 prior-art-divergence challenges against this repo's
own Go producer and against rust-analyzer/rustc's cross-crate mechanisms), 12 edge cases recorded,
6 falsifiers, 8 runnable checks.

Key resolutions from the adversarial pass, carried into the spec as binding decisions:
- **Post-process merge architecture** (not a single in-process whole-workspace compilation) —
  justified as the only option rustc's per-crate compilation model actually permits, mirroring
  this repo's own OCaml CMT indexer's write-then-resolve pattern from issue #41.
- **Workspace-wide flat union, dependency-direction-agnostic** — sound (over-inclusive candidates
  only make `unreachable` verdicts more conservative, never less sound), simpler than replicating
  rust-analyzer's dependency-graph-aware merge, with the precision cost documented as an accepted,
  revisitable tradeoff.
- **Publish-boundary safety gate** (new, found during the challenge pass, not present in either
  prior branch): `MAY_ENUMERATED` is refused for any trait whose defining crate doesn't set
  `publish = false`, since workspace-scope enumeration is otherwise unsound for a published
  library an external, unseen crate could extend.
- **Missing-facts fallback** (new, found during the challenge pass): the merge step must fail
  closed to `MAY_TOP` for any trait touched by a missing/incomplete/stale per-crate fact set,
  rather than ever proceeding with a partial `MAY_ENUMERATED` candidate list — this closes the
  single highest-value gap the challenge agent found (C-13): the merge step is itself a new
  soundness-critical seam that neither prior branch had to reason about.
- **US-1/US-2 dependency made explicit, not hidden**: US-1 must emit the intermediate per-crate
  trait-impl fact records even though it doesn't act on them yet, so US-2 can be built as a pure
  post-process addition later — the two stories were not fully independent as first drafted.

All Open Questions from intake are resolved in the spec's Architecture decision section. No
question required user input — all were resolvable by engineering judgment against rustc's actual
compilation model, this repo's own established prior art (the Go producer, the OCaml two-phase
resolution pattern), and the project's own precedent for documenting accepted residuals rather
than solving everything upfront (the `arch_query.ml` cross-module homonym hazard).
