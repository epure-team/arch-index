# Reviewer — functor-binding-resolution

**Date:** 2026-09-13

## Authorized calibration amendment (2026-09-13)

User explicitly approved attribution-gated reference recalibration after the
first native checkpoint. Headroom remains25; graph semantics and allowances
remain unchanged. Extend this task's scope solely to measured reference updates:
tezt/tests/must_null_ceiling.ml (clean_measured and attribution comment only),
test/fixtures/self-index-stats.txt, test/fixtures/origin-consumer/reference.json,
and checks/origin-recurring-consumer.js (authentic frozen totals only).
Require fresh symmetric2x2 engine/corpus measurements; refuse behavioral drift.
No revision is invented for uncommitted product sources: record base+snapshot
content digest. Original script requires clean commits, so use documented
fresh disposable snapshots, not incremental builds or a fake script pass.
**Status: VALIDATED**

## Intended change (not a claim of completed implementation)

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

## Audit priority

Read the implementation brief and diff, then frozen spec26FR/12AC. Audit collector
identity/ordinal correspondence and constraint peeling first, then schema/input counts,
savepoint rollback/marker clearing and independent catalogue behavior, then whole-query
validation/format/error boundaries. Audit new tests for real RED evidence, native
success, premise-checked synthetic negatives, six independent byte oracles and
0/1/>=2 wrapper distinction. No implementation is currently claimed.

## Files to audit

- architecture-schema.sql
- lib/arch_index/arch_index_db.ml (verified main schema version owner)
- docs/schema.md (matching schema history)
- lib/arch_index/arch_index_functors.ml
- lib/arch_index/arch_index_functors.mli
- lib/arch_index/arch_index.ml
- lib/arch_index/arch_index_support.ml
- lib/arch_index/arch_index_bindings.ml (new collector/persistence integration as needed)
- lib/arch_index/arch_index_bindings.mli (new)
- lib/arch_index/dune (only required module wiring)
- lib/arch_tools/arch_functor_catalogue.ml (minimal validation reuse, preserve old API)
- lib/arch_tools/arch_functor_catalogue.mli (only needed reusable interface)
- lib/arch_tools/arch_functor_bindings.ml (new)
- lib/arch_tools/arch_functor_bindings.mli (new)
- lib/arch_tools/dune (only required module wiring)
- bin/arch_query/ (CLI dispatch and its build wiring only; verify actual path before edits)
- tezt/tests/functor_bindings.ml (new)
- tezt/tests/functor_catalogue.ml (compatibility controls only)
- tezt/tests/main.ml (test registration)
- tezt/tests/dune (test wiring)
- scripts/check-functor-bindings.js (new)
- README.md (public command documentation)
- specs/functor-binding-resolution.md (evidence/status corrections only)
- briefs/ and roster/functor-binding-resolution/ (pipeline and bounded benchmark evidence)
- skills-meta/friction.jsonl

## Expected behaviors and risks

F(A)(B) binds different formal positions of one local declaration without evaluating
actual contents. Every existing collected occurrence gets match/refusal, zero inputs
are accounted, failed collection never fabricates occurrence IDs. Identity collisions,
alias cycles and unsupported shapes never guess. Failed binding persistence cannot
invalidate old catalogue/graph or earn binding completion. Query validates beyondlimit0.
Same410 observations are matched-formal/refusal counts only, never resolvedtargets.

## Gates and handoff

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

Run roster-review with actual independent specialist/tool evidence, convergence and
scope checks. Do not invent second-runtime approval when unavailable. Emit GO only
after contract coverage and fixes are verified; QA follows before ship.

## Review correction plan — 2026-09-13 (supersedes initial execution order)

**Status: VALIDATED** under standing autonomous continuation; no quiz answers fabricated.
Decomposition source: intake Review correction gate. Spec brief checked as status gate.
Earlier implementation is complete historically, but review remains NO-GO for FR-014/AC-8.

One vertical corrective slice, with tests and product changes together:
1. Preserve original manifest base7df5c03 and clean pre-fix review SHA5338a81; reactivate
   task slot. Existing full320Tezt+64Alcotest baseline applies to unchanged product.
2. BEFORE product edits, add standalone self-contained
   roster/functor-binding-resolution/check-global-rollback.js (CHECK-5). Build the
   exact checkout producer and compile owned native fixtures; no installed binary or
   imported new helper. Healthy two-input control must precede genuine ordinal-2
   global rollback. Capture semantic RED exit1, never a setup error as proof.
3. Change only producer orchestration in lib/arch_index/arch_index.ml: collect and
   queue immutable data without Typedtrees; after all old producer transactions,
   drain each job independently, preserving old facts, earlier successful binding
   inputs, failure-row attempts, warning and false eligibility latch. Never place
   the drain inside a shared transaction or skip later jobs after a failure.
4. Run CHECK-5 GREEN plus a three-input continuation case in that checker: fault
   after an earlier success, suppress further injected faults once a failed row is
   recorded, prove the remaining input succeeds. No reliance on artifact names or
   traversal order. Preserve the required two-input control/fault case separately.
5. All five Node checks, full build/test, scope, bundle and whitespace gates. Run
   CHECK-5 separately under selected opam environment, never nested inside Dune.
   Recalibrate only if fresh symmetric attribution proves neutral source effects;
   headroom25 and all graph semantics remain unchanged.
6. Commit the completed round with clean status; roster-review verifies the linked
   new ratchet against pre-fix SHA (git archive export), then roster-qa. Only both
   GO verdicts permit PR/exact-head green CI/rebase merge and owned-worktree cleanup.

Consensus: sequential independent Sol then Terra agreed on isolation, immutable
payloads, failure-aware finalization, authentic rollback and later-job preservation.
Root corrected Sol's initial test-after-refactor order to mandatory TDD; Terra
independently required test-first. Sol's 'partial state queryable' means SQL evidence
only: the public command still refuses absent-marker databases. These are corrections
from the existing contract, not alternate product choices. No DISAGREE/USER-CHALLENGE.

Risks: hidden enclosing transactions, stale binary in RED export, vacuous trigger,
shared drain transaction, short-circuited later input, false marker and incomplete old
fact comparison. Assert full semantic old tables and catalogue marker, premise-check
healthy fixtures, identify good/failed inputs by persisted outcomes, and preserve all
existing acceptance tests. No new schema/API/refusal/target-resolution capability.

Additional exact gate:
```sh
rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- node roster/functor-binding-resolution/check-global-rollback.js
```

Required coverage now26FR/13AC and five checks. CHECK-5 is separate from Dune;
review and QA must run it explicitly. No claim that hosted CI already invokes it.
Claims/KB/hooks remain absent; manual pipeline retained. Root owns all Dune builds.
