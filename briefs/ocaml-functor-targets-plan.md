# Plan — ocaml-functor-targets

**Date:** 2026-09-16
**Status: VALIDATED**

## Consensus Table

| Point | Voice 1 | Voice 2 | Status |
|---|---|---|---|
| Freeze the complete artifact/application/formal/actual/member/occurrence identity before broadening cases | Required first | Core correctness risk if omitted | AGREE |
| Deliver vertical slices rather than schema, collector and persistence layers separately | Direct end-to-end slice first | Layer boundaries are independently lossy | AGREE |
| Retain `module_param` beside every known target and prohibit `MUST` end-to-end | Explicit lattice invariant | Local enum choice alone is insufficient | AGREE |
| Persist attribution separately from canonical relation deduplication | Needed for corpus attribution | Witness granularity and idempotence are otherwise undefined | AGREE |
| Handle nonidentical variants only after direct same-artifact proof works | Variant slice after direct resolution | Variant reconciliation is the highest-risk join | AGREE |
| Gate on exact relation sets and identity-chain witnesses, not counts | Required by pinned comparison | Counts can hide losses and duplicate gains | AGREE |
| Change the validated feature direction | No | No; objections concern proof and sequencing | AGREE — KEEP |

## Sequential steps

1. **Direct authenticated correspondence, end to end** — Start with an authentic compiled fixture containing local `A`, `F(X)` and one physical `X.f` call. Add a RED checker assertion, define the durable witness lifecycle in `architecture-schema.sql`, expose the complete in-artifact proof from `arch_index_bindings.ml`, reuse `local_module_exports` in `arch_index_cmt.ml`, and thread the result through `arch_index.ml`. Completion requires one `MAY_ENUMERATED A.f`, the original `MAY_TOP/module_param`, no `MUST`, no cloned graph entity, and one exact-chain witness through real SQL and `arch-query`.

2. **Composition, slot isolation and fail-closed boundaries** — Extend the same vertical path for repeated `F(A)`, `F(B)`, curried formals, nested concrete `Pdot` owners/includes and invocation-safe one-hop value aliases. Add shadowing/equal-location occurrence controls plus opaque, missing, persistent, module-alias, anonymous, unpack and `Papply` negatives. Completion requires order-independent target union, canonical relation deduplication with complete witness multiplicity, exact formal-position isolation, no extra TOP rows, and unchanged flat/LSP unknown output.

3. **Exact-copy and nonidentical-variant safety** — Preserve byte/fingerprint-guarded graph reuse with per-artifact witnesses. Collect a nonidentical variant's positive local proof before module insertion can discard it, then attach it only through a unique stable-field match to an existing representative occurrence. Add missing/ambiguous/unrelated-ID and discovery-order controls. Completion requires additive facts only, no cross-artifact compiler-ID comparison, no general graph merge, deterministic rows/witnesses/refusal counts, and existing incomplete-input behavior on collection failure.

4. **Independent gates and frozen Stage-3 attribution baseline** — Finish `roster/ocaml-functor-targets/check-cmt.js` with pass/assertion/setup controls, add `check-native.js` to normalize the full Tezt and four independent binding-checker modes, and build `check-tezos.js` from a hash-validated Stage-3 snapshot rather than the older Stage-1 comparison alone. Completion requires every candidate-only resolved relation to join to a persisted witness, any baseline-existing witness to be excluded from gain counts, zero global losses, zero new/upgraded `MUST`, and at least one combined Irmin/protocol gain.

5. **Full qualification, documentation and delivery readiness** — Run build, focused tests, CHECK-1/2/3, full single-job Tezt, repeat the pinned replay after the full suite, and verify dirty-state/input stability. Update `briefs/ocaml-cfa-five-stages.md`, the relevant public contract documentation, and `/home/mathias/notes/2026-09-01-arch-index-roadmap.md` with exact gains, limitations and Stage-5 handoff. Completion requires all gates green, no unsupported whole-program/completeness/performance claim, and a reviewable branch ready for independent Roster review/QA.

## Dependencies

- Step 1 precedes every other step because it fixes the complete positive proof and persistence identity through all lossy boundaries.
- Step 2 precedes variants because unique occurrence/formal/member identity and deterministic deduplication must work within one artifact before cross-artifact reconciliation is safe.
- Step 3 precedes the pinned baseline gate because variant-origin witnesses must already serialize canonically for attribution.
- Step 4 precedes documentation and shipping because the corpus claim is an acceptance condition, not a Stage-5 follow-up.
- Each implementation step uses RED → GREEN → refactor and reruns its focused authentic checks before the next step.

## Identified risks

| Risk | Probability | Impact | Mitigation |
|---|---:|---:|---|
| Application/formal/actual/member identities do not coexist at one producer boundary | Medium | Critical | Prove the direct authentic slice before generalization; persist the complete exact-key witness, never reconstruct from display names. |
| Singleton or normalization logic removes TOP or promotes a target to `MUST` | Medium | Critical | Assert separate rows at producer, DB and query boundaries; reject every new/upgraded `MUST` in CHECK-1 and CHECK-3. |
| Equal source locations conflate physical calls | High | High | Use a deterministic physical occurrence discriminator and negative same-location fixtures; refuse ambiguous variant reconciliation. |
| Witness rows duplicate while call relations deduplicate | High | High | Give relation identity and witness identity separate keys; retain all proofs in canonical sorted order and test repeated applications/copies. |
| Nonidentical variants attach valid local proof to the wrong representative call | Medium | Critical | Require exactly one stable-field match after local proof; zero/multiple matches add nothing and are counted as refusals. |
| Pinned corpus has no gain inside the supported subset | Medium | High | Measure after the direct and composition slices, inspect refused categories, and continue only within the approved identity envelope; do not weaken the positive gate. |
| New witness schema makes old/partial databases appear complete | Medium | High | Version and finalize a dedicated contract only after complete collection; readers/checkers refuse absent/incomplete contracts. |
| Authentic checks accidentally exercise an older alias/CFA path | Medium | High | Mutation controls break one identity premise at a time and require the target/witness to disappear while TOP remains. |
| Tezos replay drift or stale cache produces false evidence | Medium | High | Freeze Stage-3 producer/schema/snapshot/revision, rehash all 410 inputs, freshly copy candidate inputs, and compare pre/post source state. |
| Large application/member cross-products regress resource use | Low | Medium | Index correspondences by declaration/formal and requested member path; never enumerate unused exports; record wall/RSS without declaring a bound. |

## Decisions made

| Point | Decision | Reason |
|---|---|---|
| Analysis boundary | Main CMT producer only; flat/LSP is regression-only | Flat has no authentic binding identities and guessing is forbidden. |
| Known/unknown interaction | Additive `MAY_ENUMERATED` plus retained `MAY_TOP/module_param` | The corpus is open and a known subset cannot close it. |
| Provenance | Durable main-schema witness contract, separate from call-row identity | Corpus attribution and multiple proofs per relation must survive persistence. |
| Curried identity | Declaration + named formal binder + formal position | Head ordinal is provenance and cannot substitute for slot identity. |
| Variants | Local proof first, unique stable-field representative reconciliation second | Compiler identifiers cannot cross artifacts and source position alone is insufficient. |
| Gain gate | Exact Stage-3-to-candidate relation delta, all gains witnessed | Stage-1 aggregate counts cannot attribute Stage-4 behavior. |
| Prior art | Defer Shapes/UID/odoc identities | They expand compiler-version, storage and cross-unit scope without proving runtime closure. |

## Assumptions

- The existing main schema may evolve to add a versioned witness contract; replacing SQLite or redesigning public query commands is excluded.
- A stable representative occurrence can be identified from already available source-level caller, normalized call site, formal-member path and occurrence-shape facts; ambiguous cases fail closed.
- The fixed 410-input corpus and local Tezos checkout remain available for CHECK-3; absence is setup failure, never a green skip.
- The implementation may add focused fixtures/check scripts and public contract documentation within the files named by the intake.
- No backward-compatibility promise is made for old databases beyond explicit refusal instead of silent empty results.

## Validation Quiz

1. Why must the direct same-artifact correspondence slice pass before nonidentical-variant reconciliation begins?
2. Should attribution be persisted as a versioned SQLite witness contract, or exist only as temporary checker output?
3. Would moving the positive pinned410 gain requirement to Stage 5 remain consistent with this plan?

The user repeated the explicit directive to finish the roadmap after these questions
were presented, validating the plan and its recommended decisions. No verbatim quiz
answers are fabricated. The binding plan answers are: direct same-artifact proof must
precede variants because cross-artifact reconciliation depends on its identity; witnesses
are a versioned SQLite contract; and the positive pinned410 gain remains a Stage-4 gate.
