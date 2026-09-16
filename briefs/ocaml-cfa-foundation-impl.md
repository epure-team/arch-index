# Implementation Brief — ocaml-cfa-foundation

**Date:** 2026-09-16
**Mode:** full
**Status:** COMPLETED — Implementation gates pass; formal review/QA/ship pending.

**Resume2026-09-16:** the user approved the point-free file extension. That
blocker is resolved. Targeted point-free5/5 passes; CHECK3 and self-reference
attribution are complete. The four reference files were also explicitly
approved with "oui!" and migrated; final full verification passes.

## Modified files

- `lib/arch_index/arch_index_cfa.{ml,mli}`: private finite product-set worklist.
- `lib/arch_index/arch_index_cfa_cmt.{ml,mli}`: whole-CMT binder/physical-expression
  flow and authoritative body reconciliation.
- `lib/arch_index/arch_index_cmt.{ml,mli}` and `call_graph_extractor.ml`:
  deferred candidate expansion and conservative flat identity mapping.
- Library/test Dune stanzas, `test/test_cfa.ml`,
  `tezt/tests/ocaml_cfa_foundation.ml`, `local_value_targets.ml`, `main.ml`,
  and `tezt/fixtures/ocaml_cfa/`: native integration, independent oracle and
  explicit same-CMT expectation migration within the approved manifest.
- `docs/edge-kind-contract.md`: supported finite-flow boundary and residuals.
- `roster/ocaml-cfa-foundation/`: standalone CHECK1/CHECK2, checker controls,
  measurements, design handoffs and implementation evidence.
- `briefs/` and `skills-meta/friction.jsonl`: pipeline records.

## Decisions and limits

Known target and unknown reason sets coexist. Finalization follows actual
collector/storage observations; physical identities do not collapse at equal
source locations. New candidates are MAY only, preserving occurrence metadata,
per-target arity and independent residuals. Flat refuses unfaithful identities.
No argument/return/environment transfer, capture transfer or functor substitution
is claimed. No schema or public API change.

Detailed chronology, including root review corrections, is retained in
`roster/ocaml-cfa-foundation/implementation-checkpoint.md`. Initial alias and
several later slices have genuine behavioral RED/GREEN evidence; match/sequence
code and later identity/metadata/oracle coverage were not all test-first.
Do not retroactively call that post-implementation coverage TDD.

## Quality gates

- Fresh pre-edit full baseline:344/344 pass.
- Full suite after approved reference migration:345/345 pass, exit0, plus
  native CFA6/6 groups. Log approved-reference-runtest.log SHA256
  4ae1fdca9c2362dc7cb96eda59616a5b9366c06a439e3d2dab2cb2cf9555efee.
  Earlier343/345 and341/345 runs are historical. The descriptive reference
  revision was corrected during this run; no production source changed.
- Independent preparatory review found missing unknown-arity CHECK2 coverage
  (AC-13). Corrected coverage uses known-only real-CMT scoped calls with
  injected arity0/-1: exactly2 candidates+1 unknown and metadata equality.
- Final forced full suite including this correction:345/345, native6/6, exit0.
  Source inventory313 and five executables are identical before/after;
  see roster/ocaml-cfa-foundation/final-implementation-run.json.
  Staged hygiene subsequently removed only four blank EOF lines; that full-run
  snapshot predates the whitespace cleanup. Build/CHECK1/CHECK2 rerun afterward;
  formal QA must run the committed head, not reuse old source hashes.
- Subsequent targeted native CMT/consumer fixture: pass, not a full-suite pass.
- CHECK1: fresh native build,517 independent JS-oracle cases pass; checker
  injection controls distinguish pass/assertion/setup exits0/1/2.
- CHECK2: fresh producer/query/test builds and authentic main/flat, metadata,
  identity and consumer checks pass in both delegated and root runs.
- CHECK3: implemented; authentic pinned410 replay passes. +1 Irmin/+2 protocol
  relations,0 relation loss/newMUST; exact row deltas and resources recorded.
  Root checked report/pure controls; not semantic proof.
- Self-index2x2: root fresh archive builds and complete matrix pass; exact
  same-corpus call/origin arrays agree under both engines, not just counts.
  See self-reference-evidence.md for pins and the source-only attribution.
- Fresh root CHECK1/2/3, checker pure controls, bundle22 hashes, scope-diff
  and whitespace gates pass. Formal independent Roster review/QA/CI remain
  pending. No formatter/coverage percentage is claimed.

## Scope approval and remaining work

The user-approved `tezt/tests/point_free_aliases.ml` migration is implemented.
The user explicitly approved ("oui!", 2026-09-16) these exact files:
`test/fixtures/self-index-stats.txt`,
`test/fixtures/origin-consumer/reference.json`,
`checks/origin-recurring-consumer.js`, and
`test/fixtures/origin-consumer/self.allow`.
Only measured observations and the coordinate of the same single exemption
change; no new exemption or rule change is authorized. These four files
are now included in the manifest and migrated. Sol independently checked all
five canonical fields for A=B and C=D, then exact D reference equality. Root
reviewed the four-file diff and updated the descriptive revision to identify
the measured c397efd source overlay. The single exemption comment is unchanged.

Reference migration and full implementation gates are complete. Commit only
task-owned changes and enter independent Roster review/QA/ship. No stage2 PR
or merge exists. Preserve foreign dirt and exclude it from the commit.

## Explicit architecture follow-up

Preparation identified medium future-integration risks (inconsistent guards
against private post-finalize mutation; string reason mapping) and low transfer
walker duplication. Current production orchestration finalizes last; no present
acceptance failure was demonstrated. These remain disclosed for formal review
and stage3 planning, not silently fixed or waived as high-severity findings.

## Review attention

Prioritize callable ownership, whole-CMT finalization, late literal conflicts,
flat homonyms, per-occurrence residual multiplicity, partiality and no new MUST.
Test-only private CMI include must work on clean CI. Checker self-test flags
are diagnostic controls, never evidence of a normal corpus pass. The numerical
Tezos observation is small and does not establish complete 0CFA.

## Preserved external work

Seven pre-task foreign paths remain excluded. Existing unrelated worktrees,
PR93 and the dirty Tezos checkout are untouched; no new worktree was created.
The separate defensive P1–P8 note is delivered, not a vulnerability-hunt mandate.
