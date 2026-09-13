# QA scope — functor-binding-resolution

**Date:** 2026-09-13
**Status: VALIDATED**

## Product scope

Same OCaml5.3 Implementation CMT named functor formal-to-actual provenance only.
Support local Pident heads, constraint-peeled local identity alias chains and consecutive
literal functor result telescopes for F(A)(B). One result per existing collected
catalogue occurrence, matched formal or explicit refusal. No fabricated ordinals
for failed catalogue inputs. Actual descriptors stay byte-identical; root keys
are symbolic artifact-local identity. No cross-build stability promise.
Do not change calls, catalogue output, MAY_TOP, exception/alias consumer semantics,
flat schema, Tezos source, held private issue draft or PR93. No cross-unit,
Pdot/Papply/Pextra_ty head resolution, inline head support, application-valued
binder evaluation, actual substitution, 0CFA, closure or target-resolution claims.
No additional calibration allowance is authorized.

## Exact quality gates

```sh
rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune build --root .
rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune test --root . --force
rtk proxy node scripts/check-functor-bindings.js inventory
rtk proxy node scripts/check-functor-bindings.js lifecycle
rtk proxy node scripts/check-functor-bindings.js query
rtk proxy node scripts/check-functor-bindings.js compatibility
rtk proxy node scripts/review-bundle-verify.js
rtk proxy git diff --check
```

No standalone formatter and no TUI in scope. Run all tests, not just new fixtures.
The four new commands are planned, currently absent; missing tools/fixtures are errors,
not successful exclusions or semantic red evidence.

## Behaviors to verify independently

- Native direct/alias/curried bindings; exact per-occurrence positions, compiler
  identity shadowing, nested/deferred/local/recursive binders and all nine refusals.
- Catalogue JSON/ordinals and graph/alias/exception semantics unchanged.
- Unit/anonymous formals, symbolic actuals, zero-application accounting.
- Real partial-storage failure, failed-row recording and marker lifecycle isolation.
- Whole valid/invalid DB at limit0; provenance/orphan/count/type/grammar/link checks.
- CLI usage/schema/marker/inconsistency/operational precedence and empty error stdout.
- All six output formats with independent fixed bytes, nulls and escaping; readonly DB.
- Exact410-CMT digest-verified benchmark reports matches/refusals/failures separately
  from any target-resolution assertion; no Tezos mutation.

Read frozen spec12AC and implementation/review evidence. Produce actual QA verdict
and convergence state. No GO from spec/preflight alone. Ship requires this GO and
review GO, exact-head green CI, rebase merge and roadmap/worktree cleanup.
