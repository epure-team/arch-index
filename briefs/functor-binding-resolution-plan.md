# Plan — functor-binding-resolution

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

## Basis and governance

Decomposition source is the validated intake only. Spec completion brief was checked
as a status gate; its detailed contract remains implementation input, not new scope.
User's repeated autonomous instruction covers routine validation quizzes and execution;
no quiz answers fabricated. Sol and Terra ran sequential independent analyses.
Claude unavailable in this runtime; user-authorized Sol used for voice1.
This is ONE bounded product PR, with internal checkpoints, not four shipped features.

## Sequential steps

1. **Direct native binding end to end.** Capture manifest/base before baseline tests.
   Add genuine failing native single-functor/application expectation and plain Node
   wrapper with pass0/assertion1/infrastructure>=2. Implement the minimal path through
   additive tables, identity-aware collection, isolated persistence and basic read-only
   query. Check original catalogue/graph facts in the same checkpoint. Frozen output
   grammar applies immediately; no temporary public schema. Checkpoint ends green.
2. **Alias and curried provenance end to end.** Expand the same path with pre-indexed
   named module/recmodule/local-expression binders across nested/deferred contexts,
   identity-based local aliases, consecutive literal formal telescopes and one
   accounted result per occurrence. Add shadowing, anonymous/unit, curried position,
   nested-head reference, actual descriptor/root and every refusal test alongside.
   Unsupported native-source shapes require explicitly premise-checked synthetics;
   never claim they prove source-valid behavior.
3. **Complete lifecycle and trustworthy query.** Add zero-application accounting,
   independent marker eligibility and real partial-storage failures, including
   failure recording and uncertain rollback. Complete whole-database validation
   before limit0/output, strict CLI errors and all six independent renderer oracles.
   Existing catalogue and graph must survive binding failure. All four check
   families are executable and green by this checkpoint.
4. **Verify, measure and land one product PR.** Full gates, fresh digest-verified
   exact410-CMT observation with matched-formal/refusal/failed-input counts, and
   documented limitations. Roster review then QA, fix any gate failures within
   pipeline rules; check schema slot, open PR, wait for exact-head green CI,
   rebase merge, refresh local main and roadmap. Remove only the exact owned
   now-unused worktree/build artifacts after verifying preservation of changes.

## Dependencies

1 → 2 → 3 → 4. Tests and documentation accompany each capability; no all-schema,
all-query, all-tests staging. Root alone owns Dune; delegate only disjoint scopes.
A single owned worktree may be created for implementation so user dirt remains
untouched; do not create per-agent build trees.

## Consensus Table

| Point | Voice 1 (Sol) | Voice 2 (Terra) | Status |
|---|---|---|---|
| Same-CMT scope, no graph promotion | Preserve | Preserve | AGREE |
| First complete native path | Refined after layered first proposal | Accepted four-checkpoint refinement | AGREE |
| Aliases/curried/identity refusal tests alongside code | Required | Required | AGREE |
| Independent persistence and marker | Required | Required | AGREE |
| Full validation before limit and all format oracles | Required | Required | AGREE |
| One PR only after full gates | Required | Required | AGREE |
| No old-DB migration or cross-build identity promise | Corrected unsupported assumptions | Corrected unsupported assumptions | AGREE |

No remaining DISAGREE or USER-CHALLENGE item. Initial horizontal proposals were
revised for vertical delivery, not used to defer testing. Both raised exact-contract
questions already delegated by intake to the completed spec.

## Identified risks

| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| Ordinal drift or name-only identity match | Medium | False provenance | Native shadowing/curried controls and old catalogue comparisons |
| Partial writes falsely earn completion | Medium | Incomplete report appears complete | Independent savepoint/marker failure probes |
| Synthetic impossible input mistaken for native proof | Medium | Overstated semantics | Native happy path, explicit synthetic premise checks |
| Query limit hides corrupt data | Medium | Invalid report | Whole validation and limit0 negative controls |
| Whole-input traversal and validation costs | Medium | Slow Tezos runs | Bounded same410 manifest, record runtime without inventing acceptance threshold |
| Schema slot collision or calibration changes | Medium | CI cannot land | Recheck slot; attribute regressions, no unapproved allowance increase |
| Missing specialist profile or orchestration tooling | Known | False pipeline claims | Explicit fallback, actual manual gates and truthful skipped-tool records |

## Decisions made

Existing catalogue is authoritative for occurrence IDs/descriptors. Bindings are
additive, independently complete provenance, not target-resolution evidence.
Version1.15 remains provisional. No automatic old-database data migration added.
CLI-path and new module placement are integration assumptions to verify before edits.

## Files / permitted scope

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

## Quality gates

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

No standalone formatter configured. Planned checks are not yet implemented/passed.

## Assumptions and legacy checks

Identical CMT/compiler inputs only, artifact-scoped keys; no global identity.
Exact410 manifest remains available and digest verification is mandatory before reuse.
No performance threshold is invented. Claims reconciler, managed context manifest,
KB and hooks are absent; managed freshness/projection checks unavailable, not passed.

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
