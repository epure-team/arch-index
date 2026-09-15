# Implementation Brief — tezos-recursive-typed-bodies

**Date:** 2026-09-15
**Mode:** full
**Status:** COMPLETED

## Modified files

- lib/arch_index/arch_index_cmt.ml: narrow private recursive descriptor admission
  for exactly one named-path local open around the original function object.
- tezt/tests/recursive_open_body_targets.ml and main.ml: two native integration
  tests and registration; no dune change required.
- roster/tezos-recursive-typed-bodies/: native independent witness, sealed baseline
  loader, preservation/comparison/compatibility/capacity checks and audit reports.
- Matching task briefs/spec and skills-meta/friction.jsonl: pipeline evidence.
- External authorized roadmap and ignored improvement evidence: candidate status.

## Decisions made

Only original inner object/arity selection changes. Ident.same scope, storage
gating, ordinary lookup tables, continuation, parent occurrences, flat output,
public API and schema remain unchanged. No new MUST. No mutual recursion or
general 0CFA. Original invalid WAL baseline retained; separate sealed v2 is the
only accepted baseline. No self-reference refresh needed or authorized.

## Quality Gates

- Build: `rtk proxy opam exec -- dune build`, exit0.
- Full tests: `rtk proxy opam exec -- dune exec tezt/tests/main.exe -- --no-color --keep-going`,
  exit0, 342 SUCCESS, two new tests, 273189ms; attempt5-native-green-1.json/.log.
- TDD: corrected full RED before product edit had 340 SUCCESS and the two new
  tests failing on ten semantic assertions; initial warning33 setup failure is
  separately retained, not counted as semantic RED.
- CHECK1–6: all exit0, attempt5-postproduct-checks-1.json plus individual logs;
  source state unchanged across the complete sweep. CHECK4 produced fresh pinned
  410-CMT independently witnessed gain +14 protocol/+0 Irmin, zero loss, 45,052 rows.
- `rtk proxy node roster/tezos-recursive-typed-bodies/prepare-baseline.js --check`:
  exit0, exact neutral predecessor replay.
- `rtk proxy node scripts/review-bundle-verify.js`: exit0, 22 files, bundle1.6.0.
- `rtk proxy git diff --check`: exit0. Formatter/lint/coverage unconfigured,
  therefore not asserted PASS or represented by a coverage percentage.

## Points of attention for review

Audit independence and exact native identity versus SQL storage, duplicate-group
agreement, capacity accounting, complete rich/flat preservation and failure-code
classification. Native-pair Sol review is not final Roster review or human proof.
Seven unrelated user files remain untracked and must not be staged/deleted to
satisfy the global clean-tree convention. Task changes are committed separately;
any review pre_fix_sha requiring globally clean status must report dirty-tree.

Runtime adaptations: native agent quota exhausted; fresh actual Sol/Terra CLI
subagents used with bounded scope. Root authored JS acceptance helpers while Sol
wrote only the dedicated native test; OCaml-first mixed-scope sequencing was
adapted to the required pre-product witness/RED slice. No OCaml-specialist,
harness freeze hook, CWR or managed KB/reconciler installed. Manual control edits
used apply_patch under the higher-priority host constraint. No worktree created.

## Identified out-of-scope

No wider wrapper peeling, mutual recursion, Irmin-specific new capability,
formal proof or sixth product attempt. Historical LSP intermittency remains
unresolved; no LSP fix claimed. Candidate retention still requires independent
Roster review, QA, exact-head green CI and guarded merge.
