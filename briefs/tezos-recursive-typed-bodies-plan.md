# Plan — tezos-recursive-typed-bodies

**Date:** 2026-09-15
**Status: VALIDATED**

Fifth and final product attempt, not a new five-attempt loop. Single decomposition
source: validated intake. Spec consulted as a VALIDATED gate, not a second brief.
Routine plan approval uses the user's explicit standing autonomy. No interactive
quiz was administered and no comprehension answers are claimed. Material scope
changes remain subject to user decision.

## Independent analyses and consensus

Voice 1: fresh Sol `open_recursive_plan_sol`, intake only, completed first.
Voice 2: fresh Terra via read-only ephemeral Codex CLI, intake only, exit0;
session 01a0a3a7-6114-7ab0-9371-2d1ef7787cd4. Native spawn and completed-agent
followup both failed with agent thread limit; CLI was an actual second-model
analysis, not a root self-review. No code, database or report writes by voice 2.
Claude is not the selected runtime; user explicitly permits Sol/Terra delegation.

| Point | Sol | Terra | Status |
|---|---|---|---|
| Pre-product runnable witness and preservation checks | Required | Required | AGREE |
| Sealed v2 only, fixed 410 inputs, original invalid package rejected | Required | Required | AGREE |
| Original inner function, no mask/ordinary table changes | Required | Required | AGREE |
| Native identity independent of candidate SQL | Required | Required | AGREE |
| Invocation arity, partiality, residual capacities | Explicit controls | Explicit controls | AGREE |
| Positive distinct relations, zero loss, exact-head CI | Required | Required | AGREE |

Clarifications against the intake, not discretionary direction changes:
- Native evidence establishes identity; SQL establishes storage. Sol's question
  about storage proof without SQL cannot impose a contradictory requirement.
- A private descriptor may exist before insertion; only the final bounded target
  requires successful storage. Neither voice authorizes moving SQL into extraction.
- Full duplicate-group agreement and single-use capacities are verifier admission
  rules, not permission to add global duplicate analysis to the product.
- Existing identity/storage/arity machinery is reused and tested, not rewritten
  as Terra's separate accounting slice might otherwise suggest.
No DISAGREE or USER-CHALLENGE requiring a new scope decision remains.

## Sequential steps

1. **Runnable acceptance slice before product edits.** Add task-native fixtures,
   compiler-only witness and fixed-input comparison tooling under the task's
   roster directory; register the dedicated Tezt module. Pin sealed v2 provenance,
   producer, schema, database and manifest. Establish real semantic RED on the
   predecessor, distinct from missing-input/runtime failures. Completion: checks
   are runnable, native identity does not consume candidate SQL, refusal and
   preservation controls are non-vacuous. No product source changes yet.
2. **Exact open-recursive invocation slice.** In the private singleton-recursive
   admission branch of arch_index_cmt.ml, accept only Tpat_var with one
   Texp_open(Tmod_ident, immediate Texp_function). Point at the original inner
   object, derive existing fn_arity, preserve default traversal and Ident.same
   scope. Completion: native RED becomes GREEN; stored, exactly-once observed
   original root yields MAY_ENUMERATED and conservative failures remain TOP.
   No binding_literals/local_lam_stamps additions or parent-occurrence removal.
3. **Measured corpus acceptance slice.** Run independent witness and candidate
   production on the fixed 410 CMTs. Compare against v2 with counted occurrence
   capacities and full duplicate-group agreement. Completion: strictly positive
   distinct relation gain, zero old relation loss, only witnessed head-field
   changes and justified single returned-call residuals; all other rich/flat and
   shape/context facts preserved. Fourteen observed heads do not guarantee gain.
4. **Integrated release slice.** Full build, tests, task checks, roster review and
   QA, then exact-head required CI and guarded rebase merge. Update results and
   external roadmap only with actual outcomes. Remove only owned disposable
   artifacts; retain pinned evidence. End loop after fifth KEEP/DISCARD, no sixth.

## Dependencies

1 precedes any product edit in 2: a setup failure is not RED. 2 precedes candidate
gain in 3. 3 and all local gates precede review/QA/ship in 4. Build/check/probe
execution is serialized against every source/report/git write, including agents.
These are end-to-end acceptance slices inside one product attempt, not separate
PRs or extra loop iterations.

## Identified risks

| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| Wrong physical root or collision suffix | Medium | False target | Compiler-only original-root/allocation witness; refusal controls |
| SQL teaches witness its expected target | Medium | Circular proof | No SQL input to witness; storage checked separately |
| Positive tests hide changed parent/continuation/flat facts | High | Regression | Complete multiplicity/context preservation, nonempty controls |
| Residual/duplicate reuse inflates gain | Medium | False retention | Single-use per-application capacities, complete group agreement |
| Baseline mutation via SQLite | Observed and repaired | Invalid comparison | Sealed v2 pins, read-only real DB, mutable tests on copies only |
| Fourteen heads yield no distinct gain | Unknown | No KEEP | Strict gain rule; discard without relaxing scope or threshold |
| Unchanged intermittent LSP test hangs | Observed in iteration4 | Gate failure | Record actual NO-GO; diagnose, no silent success/retry claim |
| Agent session quota | Observed | Delayed independent gates | CLI fresh read-only voice worked; record actual limitations later |

## Decisions and assumptions

No new API/schema/Tezos changes; no global function classifier or general 0CFA.
One physical observation means the original expression object visited once in
the relevant artifact traversal, not equal names or ranges. SQL insertion failure
must remain conservative; verifier probes exercise dropped roots and storage
refusal. Witness schema encodes artifact, binder/group, admitted constructor,
physical-root allocation ordinal, caller, full application range and arity.
Gain means new distinct canonical resolved relations by Irmin/protocol partition,
not head counts or row counts. Complete multiplicities remain separately checked.
Self-reference updates need pristine attribution AND explicit path authorization;
there is no presumed authorization or CI exemption.

KB, project claims reconciler, managed context and hooks are absent as recorded
in preflight. No global freshness/projection PASS claimed. Isolated spec parsing
is not a substitute. Formatter/full lint/coverage remain unconfigured.

## Quality gates

All commands run with `rtk proxy` in this workspace:

```sh
opam exec -- dune build
opam exec -- dune exec tezt/tests/main.exe -- --no-color
node scripts/review-bundle-verify.js
git diff --check
node roster/tezos-recursive-typed-bodies/prepare-baseline.js --check
```

Additional task-native/witness/preservation/capacity/corpus checks are step1
deliverables, not existing PASS claims. Exact command mapping belongs in the
implementation artifact and QA scope before product edits.
