# QA scope — tezos-open-bodies

**Date:** 2026-09-14
**Status: VALIDATED**

```sh
opam exec -- dune build
opam exec -- dune exec tezt/tests/main.exe -- --no-color
node scripts/review-bundle-verify.js
node roster/tezos-open-bodies/prepare-baseline.js --check
git diff --check
```

Also execute all runnable checks in specs/tezos-open-bodies.md. Require genuine
native producer positive/refusal cases, exact shadow/body identity, arity and
omitted arguments, partial and overapplied semantics, missing/dropped/ambiguous
target refusal, old effect/CFG/body ownership and exact flat multiset preservation.
Native witness input negative controls must fail as assertions, not setup errors.
Fixed410 candidate is compared to immutable attempt3-baseline:45052canonicalrows,
digest00f1769d6db7f6ee91ee51becabccd7b4ce13975acb6610c95ace69a7f620e9b,
Irmin4781/protocol11730. Strict positive gain, zero lost nonnull old relations,
zero unexplained changes/new MUST; each replacement/residual independently
witnessed with duplicate multiplicity conserved. No gains from census alone.

Full pre-product332 pass is baseline only, never candidate QA. No TUI scope.
No configured formatter/coverage; report unavailable. Any self-reference update
requires exact pristine source attribution without loosening existing policy.
Serialize root builds and source-state checks against edits. Use full roster QA
round controls, then ship only with exact-head required green CI and rebase merge.
