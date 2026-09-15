# Plan — ocaml-data-preservation

**Date:** 2026-09-15
**Status: VALIDATED**

## Consensus Table

Independent sequential voices: Sol `01a0a637-4595-7fa2-a64b-cf17782ca85d`, Terra `01a0a638-0959-73c2-9d20-2cb0f2084ccc`. Both read only the validated intake. No blocking questions or direction change.

| Point | Sol | Terra | Status |
|---|---|---|---|
| Source-aware effect identity | First slice | First slice | AGREE |
| Transaction/dedup/error truthfulness | Two dependent slices | Two dependent slices | AGREE |
| Producer paths/shadowing | After persistence | Alongside identity | Compatible sequencing; producer after loader tests |
| Exact-copy graph reuse + per-artifact collection | Required | Required | AGREE |
| Nonidentical variants remain stage4 | Required | Required | AGREE |
| Regression and pinned corpus | Required | Required | AGREE |

Sol's suggestion of shipping each internal slice contradicts the approved one-PR-per-stage boundary; retain the user's boundary, not that suggestion. Routine ordering choices and quizzes covered by explicit autonomy; no user answers invented.

## Sequential steps

1. **Source-aware loader** — RED main/alternate/flat/homonym/path controls; implement association and reload correction through actual loader. Finish with targeted checks.
2. **Lossless writer** — RED payload distinctions, legacy migration, ID retention, errors/rollback and counters; implement transactional writer and truthful CLI behavior with native tests.
3. **Producer identity** — RED compiled paths and shadowed bindings; repair emitted source and supported binding names, documenting explicit-root limitations.
4. **Exact-copy CMT reuse** — RED copies/symlinks/provenance; implement run-local successful-representative reuse while retaining independent collections. Preserve negative nonidentical, failure and lifecycle controls; amend previous lifecycle contract/examples.
5. **Qualification** — standalone checks, native suite, fixed410 neutral callgraph/effect observations, documentation and measured self-index goldens only if required. Independent Roster review, QA, one PR, exact-head required CI and guarded merge.

## Dependencies

Loader identity precedes stale-ID repair; final loader semantics precede producer integration. CMT reuse is logically independent but serialized to avoid shared build-tree collisions. No stage2 work before this stage is merged.

## Identified risks

| Risk | Impact | Mitigation |
|---|---|---|
| Wrong normalized path or name fallback | Homonym misattribution | Exact-source negative controls, no suffix guessing |
| SQL IGNORE masks rejection | False successful load | Explicit duplicate comparison and atomic errors |
| Legacy migration deletes data | Irrecoverable loss | Row-ID/payload retention and failure rollback tests |
| Duplicate reuse loses catalogue identities | False completeness | Collect per artifact, test markers and failures |
| Same-source variants mistaken for copies | Incorrect graph | Full bytes/source/unit equality only; explicit stage4 residual |
| Golden refresh masks regression | False tests | Measured causal delta, independent review |

## Decisions made

Use existing schema variants, not a new variant model. No new worktree. Build/test processes and writes serialized. Native subagent quota requires ephemeral CLI agents. Missing OCaml specialist definition uses a fresh Sol implementer with explicit OCaml/compiler-libs context. CWR/templates absent: manual serialized skill chain, no installation or fabricated workflow.

## Assumptions

Immutable CMT inputs during a run; caller supplies matching source root. No global completeness claim. Existing unrelated files remain untouched. No separate configured lint/coverage command.
