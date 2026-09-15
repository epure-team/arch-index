# Reviewer report — ocaml-data-preservation

## Verdict

**approve**

No correctness, security, regression, test-impact, or maintainability finding was identified in the stage-1 diff from `c10d1a4f2bee4f72907fe6ce88cdc0338153398d` through `126a0086d1a7016139ac26fa466d676ad889e292`.

The review treated raw effect paths as preserved payload identity while applying lexical normalization only to function association. Exact-copy graph reuse was reviewed as a run-local optimization for immutable, byte-identical inputs after successful graph extraction; it is not a general filesystem-race guarantee or independently compiled CMT equivalence. Independently compiled variants remain stage 4 and issue #68 remains partial, as specified.

## Review coverage

- Read the reviewer role, validated reviewer/implementer briefs, implementation handoff, and complete stage-1 specification.
- Reviewed the complete commit-range diff and the changed effects persistence, source producer, CMT graph-reuse, lifecycle, native-test, standalone-check, documentation, and measured-golden surfaces.
- Checked source-aware main/alternative/flat association, raw NULL/empty distinctions, reload association repair, transactional preparation/write failure, legacy duplicate refusal, Typedtree shadow order, exact-byte reuse eligibility, independent catalogue/binding callbacks, nonidentical collision refusal, failed representative behavior, and per-run cache construction.
- Confirmed the approved measured changes: MUST-with-NULL reference `554` with unchanged headroom `25`; self-index `1013` functions and `6425` calls; origin reference `583` with option/raise `331`.
- `.claude/patterns/` is absent, so no repository language-pattern document was available to apply. This is evidence availability, not a finding.
- Deferred scope findings to the separately completed scope gate, per reviewer brief. The seven manifest-listed pre-task untracked paths were not modified.

## Independently executed gates

All commands ran at the reviewed HEAD and completed before the report was written. Logs and receipts are under ignored `improvement/2026-09-15-ocaml-cfa/reviewer-*`.

| Gate | Exit | Duration | Evidence |
|---|---:|---:|---|
| `opam exec -- dune build` | 0 | 0 s | `reviewer-build.log`, `reviewer-build.receipt` |
| `opam exec -- dune runtest --force` | 0 | 289 s | 344/344 Tezt successful; `reviewer-runtest.log`, `reviewer-runtest.receipt` |
| `node check-effects.js` | 0 | 1 s | CHECK1 PASS; `reviewer-check-effects.log`, receipt |
| `node check-cmt-copies.js` | 0 | 1 s | CHECK2 PASS; `reviewer-check-cmt-copies.log`, receipt |
| `node check-tezos.js` | 0 | 4 s | CHECK3 PASS; `reviewer-check-tezos.log`, receipt |
| bundle verification | 0 | 0 s | bundle 1.6.0, 22 files SHA-matched; `reviewer-integrity.receipt` |
| `git diff --check` | 0 | 0 s | `reviewer-integrity.receipt` |

CHECK3 independently observed 410 selected CMTs, 45,052 canonical rows, digest `1799c07fd3eb87d4bca433b15b7daeb47f466f90cb098541372e1dd9dd7bac7a`, 4,849 Irmin relations, 12,171 protocol relations, and unchanged inputs/source status. Effects observations were 360 emitted, 139 distinct stored, 63 bound, and 76 unbound. These are fixed-corpus non-regression observations, not completeness or resolution-gain claims.

## Findings and open questions

Findings: none (`reviewer-findings.json` is `[]`).

Open questions: none for stage 1. Final-head required CI and the later Roster QA/ship gates remain lifecycle requirements, not review findings.

## Final corrected-head addendum — 10d75e2

The preceding report records the first review pass at `126a0086d1a7016139ac26fa466d676ad889e292`. Its green gates were real, but CHECK1 at that head did not cover a schema-valid nullable-path homonym. After that report, root reproduced an alternative schema with `(1, 'f', NULL)` and `(2, 'f', 'a.ml')`; loading an effect for `f` at `a.ml` aborted with `non-text function path` instead of selecting ID 2. I independently assessed this as a correctness defect: NULL is a nonmatching candidate under the frozen exact-path contract, not malformed schema.

Commit `10d75e2ea6bc3e35b7dbdb35c7621a29719a27d2` resolves the defect by excluding NULL candidates from the supplied-path queries for both main-schema `modules.path` and alternative-schema `functions.file_path`. Missing effect paths retain unique-name behavior. The expanded CHECK1 covers both schemas, verifies that a NULL-path homonym cannot hide an exact match, then deletes the exact candidate and verifies unmatched diagnostics, retained payload identity, stale association clearing to NULL, and no name fallback.

I reviewed the complete `126a008..10d75e2` delta and personally reran every required final gate on the corrected head:

| Final gate | Exit | Duration | Evidence |
|---|---:|---:|---|
| `opam exec -- dune build` | 0 | 1 s | `reviewer-final-build.log`, receipt |
| `opam exec -- dune runtest --force` | 0 | 297 s | 344/344 successful; `reviewer-final-runtest.log`, receipt |
| CHECK1 effects | 0 | <1 s | nullable-path regression included; `reviewer-final-check-effects.log`, receipt |
| CHECK2 CMT copies | 0 | <1 s | `reviewer-final-check-cmt-copies.log`, receipt |
| CHECK3 pinned Tezos/Irmin corpus | 0 | 4 s | `reviewer-final-check-tezos.log`, receipt |
| Bundle verification | 0 | <1 s | bundle 1.6.0, 22 files SHA-matched |
| `git diff --check` | 0 | <1 s | `reviewer-final-integrity.receipt` |

Final CHECK3 again observed 410 selected CMTs, 45,052 canonical rows, canonical digest `1799c07fd3eb87d4bca433b15b7daeb47f466f90cb098541372e1dd9dd7bac7a`, 4,849 Irmin relations, 12,171 protocol relations, and unchanged inputs/source status. Effect observations remained 360 emitted, 139 distinct stored, 63 bound, and 76 unbound. The same limitations stated above continue to apply.

The discovered correctness finding is resolved and covered at the final reviewed head. No open reviewer finding remains, so `reviewer-findings.json` correctly remains `[]`. Final verdict: **approve**.
