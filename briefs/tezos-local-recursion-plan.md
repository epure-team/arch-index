# Plan — tezos-local-recursion

**Date:** 2026-09-15
**Status: VALIDATED**

## Sequential steps

1. **Freeze the comparison** — preserve existing attempt4-baseline producer/schema/
   DB/provenance and fixed410 inputs; add task-local verification/no-overwrite/replay
   controls. Pre-product full336 already passed. Completion: replay exactly matches
   45052rows,4781/12046 and digest9ab4e0b1…, with stable input/source state.
2. **Make the complete native oracle executable** — add task-native Tezt fixture,
   independent compiler witness and all six check entrypoints. Cover exact singleton
   RHS identity, stored/ambiguous/dropped/colliding roots, nested/default/refutable
   contexts, optional/partial/returned-call capacity, excluded groups/non-heads,
   complete configured rich/flat preservation and tampered witnesses. Completion:
   real predecessor assertion RED, not missing-file/tool failure, with preservation
   and witness premises established before product edits.
3. **Resolve the one bounded capability end-to-end** — edit only
   lib/arch_index/arch_index_cmt.ml for invocation-only recursive evidence tied to
   the actual observed/stored root. No early ordinary-table insertion, guessed name,
   public/schema/flat widening or new MUST. Completion: same native assertions GREEN,
   including body refusal and precise arity/residual behavior.
4. **Measure and preserve** — run serialized six checks and full guard on fixed410;
   account for every changed row and single-use witness. Investigate exact self-test
   references only if guards require it, using pristine crossed attribution and an
   explicit exact-path manifest amendment before refresh. Completion: positive gain,
   zero loss/unexplained/new MUST and all deterministic gates pass. Neutral candidate
   is discarded under the original loop; incomplete gates are pending, not KEEP.
5. **Review and deliver iteration4** — independent full roster review and QA, update
   evidence/docs, PR, exact-head required green CI, guarded rebase merge. Only then
   record KEEP and advance to attempt5; maintain roadmap and clean owned temporaries.

## Dependencies

Steps1–2 precede any product edit. Step3 is the only product capability, steps4–5
verify/deliver it. One iteration/PR, not five independent feature changes. Serialize
builds and source-sensitive checks against all repository/report writes. No new
worktree is needed for ordinary work; calibration may create owned disposable ones.

## Identified risks

| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| Ordinary table leaks certainty/non-head changes | Medium | High | Separate private invocation evidence; paired full controls |
| Name/position guesses bind wrong root | Medium | High | Actual physical root/ordinal/Ident and successful storage |
| Native witness is circular or reused | Medium | High | CMT-derived identities/ranges and distinct single-use capacities |
| Arity/contexts change unadmitted facts | Medium | High | Some-count, optional/default/refutable/nested paired tests |
| Snapshot/build contention | Medium | High | Main owns serialized gate schedule |
| Corpus gain is neutral | Medium | Medium | DISCARD, do not expand scope or relax thresholds |
| Legacy claims parser cannot validate global tree | Certain | Low for product | No managed context used; isolated new-spec validation; no false global pass |

## Decisions made

| Point | Decision | Reason |
|---|---|---|
| Scope | Singleton direct RHS self-head only | Exact user-approved loop/intake boundary |
| Certainty | New bounded targets MAY_ENUMERATED only | Identity is not definite execution |
| Baseline | Frozen PR107, no overwrite | Keep preceding three iterations attributable |
| Internal sequencing | Full oracle before product edits | Explicit spec/guard requirement dominates sketch ordering |
| Delivery | One PR after full gates | User requires green merge before next iteration |

## Assumptions

Existing stored synthetic bodies and enumerated-kind policy are available as
documented by intake. No contractually open question. Native observations must
confirm every empirical assumption; failures do not authorize scope expansion.
Dual Sol/Terra analyses were sequential and intake-only; thread quota required
worker reuse instead of fresh contexts. Consensus record: roster/tezos-local-recursion/plan-voices.md.
Standing explicit autonomy covers routine plan gates, with no fabricated quiz.
Project has no managed claims/context/KB. Upstream global parser exits2 on older
out-of-scope syntax; this is disclosed, not stale managed projection or PASS.

## Quality gates

`opam exec -- dune build`

`opam exec -- dune exec tezt/tests/main.exe -- --no-color`

`node scripts/review-bundle-verify.js`

`git diff --check`

Six task-local check commands specified in the validated spec become executable
in step2, with0pass/1assertion/2+error. No configured formatter/coverage is claimed.
