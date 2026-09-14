# Plan — tezos-call-resolution

**Date:** 2026-09-14
**Status: VALIDATED**

Source of decomposition: validated intake only. Spec completion gate is VALIDATED. Validation authority is the user's standing autonomous five-iteration instruction; no quiz answers are fabricated. This plan covers preparation and the first focused product attempt, not five promised gains.

## Consensus Table

| Point | Sol | Terra | Status |
|---|---|---|---|
| Comparator tested and replayed before product edits | Required | Required | AGREE |
| Compiler ownership, not display-name matching | Required | Required | AGREE |
| Explicit include/constraint/recursion semantics before edits | Required | Required | AGREE |
| Same optional per-CMT input in both collectors | Required | Required | AGREE |
| Native identity/refusal tests plus multiset guards | Required | Required | AGREE |
| No guaranteed gain from named witnesses | Required | Required | AGREE |
| Review/QA/green head then sequential rebase merge | Required | Required | AGREE |

No competing design or change of user direction was proposed. Both voices noted the intake delegates compiler cases to spec; that gate has now completed. Terra's numbered implementation-before-tests ordering is normalized to mandatory TDD, not adopted as permission to skip RED. Both voices operated independently from the full intake, without code/context injection. Claude model dispatch is unavailable; authorized Sol/Terra models supplied the two fresh voices.

## Sequential steps

1. **Prove the comparison path end to end.** In roster/tezos-call-resolution/, add a standalone canonical DB snapshot/comparator, check-comparison.js mutation tests and verify.js fixed410 runner. Tests precede implementation. Hash-lock the existing manifest and artifacts; bind baseline DB and canonical snapshot digest to the recorded source/producer provenance. Verify same-binary/self comparison before product edits. Add improvement/ ignore before logs. Record baseline iteration0 only after executable verification and the existing full guard pass. Completion: comparison tests, self comparison and fresh fixed410 neutral replay pass. This is setup, not a retained product iteration.
2. **Resolve one local-module capability end to end.** Add native local_module_targets tests, first recording an actual failing resolution assertion, then implement the smallest same-CMT ownership helper and thread it through rich and flat collection. Use existing stored binding names, preserve refusal/metadata/arity/edge-kind contracts, and cover shadowing/includes/constraints/recursive declarations/functor-local structures according to the validated specification. Completion: native positives/refusals pass, old suite passes, fixed410 comparison shows only permitted changes with target witnesses. Helper and both wiring paths are one vertical product slice, not separate retained attempts.
3. **Measure and make the keep/discard decision.** Run complete native/full gates; inspect every changed canonical group and its source/target positions. Report Irmin/protocol separately. Positive justified new relations are necessary, not sufficient: no existing-target loss, unexplained TOP/metadata/multiplicity loss or new MUST. Neutral/invalid product changes are discarded within owned scope and recorded as an attempt, never called a gain. Preserve comparison setup as measurement infrastructure, explicitly excluded from product gain claims.
4. **Review, QA and ship this slice.** Update capability limits and external roadmap, commit only owned files, execute full roster-review/qa/ship including exact-head hosted CI and rebase merge. No held PR93 changes. If the slice is retained, start the next attempt only after merge; choose its scope from measured residuals and route through roster. Delete only owned disposable outputs after durable evidence exists; keep the baseline needed by remaining attempts.

## Dependencies

Step1 gates all product edits in step2. Step2's test RED precedes implementation. Step3 requires the full integrated capability, not a helper-only count. Step4 needs positive justified gain plus all gates. The user approved exactly five bounded attempts; preparation consumes none. Do not preclaim remaining outcomes.

## Operational decisions

- Manifest: roster/functor-instance-resolution/tezos-irmin-candidate/manifest-410.tsv, SHA256 9e38880a52f855c58081b1a171af5879058cbaa2697aaa5694827cbd16f8ecd1. Compiler is installed OCaml5.3, not OCaml4.10. Tezos checkout is read-only at /home/mathias/dev/tezos/tezos.
- Baseline: /tmp/arch-index-resolution-baseline-OmhcEs/baseline.db and provenance.json. Canonical full-row multiset digest: 4ce3270de370cc9db7b449531610c0dfaa7eb45647ce4dd68601fa417933fecd (45,018 rows). Refuse missing/mismatched baseline; do not silently regenerate it from changed product code.
- Verify: `node roster/tezos-call-resolution/verify.js --baseline /tmp/arch-index-resolution-baseline-OmhcEs/baseline.db --witness improvement/2026-09-14-tezos-resolution/attempt1-reviewed-witness.json`. The reviewed witness input is now concrete; use `--self` instead of `--witness FILE` for baseline self-comparison. Default runs the current built producer over hash-checked fixed410 inputs and refuses changed rows without a witness. Zero change is valid verification but never a keep.
- Reports: ignored improvement/2026-09-14-tezos-resolution/results.tsv plus per-run directories containing report.json, changes.json, producer.log and provenance.json. Each report records whether it is self, neutral replay or candidate. Never overwrite previous evidence. Temporary selection/DB directories are created with mkdtemp and removed only by their owning runner after canonical data is saved; keep failures' bounded diagnostics. No worktree required.
- Canonical rows include caller source/name, call_site, target source/name, display callee, kind, edge_form, top_reason, top_anchor; preserve multiplicity and nulls. Reports additionally carry stored source/target positions. IDs are foreign-key consistency checks, not cross-run identity. Slice by caller path irmin/ versus src/proto_alpha/.
- Compare unchanged rows as multisets first. Every residual changed group must have an explicit supported transition witness; ambiguous same-line mixtures refuse, rather than pairwise joins. Existing relations must remain, no new MUST is allowed. A computed-return residual needs separate source/arity witness, never generic permission to add TOP rows.
- Checker exits: 0 pass, 1 observed assertion/forbidden transition, >=2 setup/parse/tool failure. Do not relabel every test runner failure as an assertion.
- Workflow retention is not a boolean inferred by the comparator alone: positive relation gain, native semantic checks, full guard and independent roster review/QA/CI are all needed.

## Quality gates

```sh
rtk proxy node roster/tezos-call-resolution/check-comparison.js
rtk proxy node roster/tezos-call-resolution/verify.js --baseline /tmp/arch-index-resolution-baseline-OmhcEs/baseline.db --self
rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune build --root .
rtk proxy node roster/tezos-call-resolution/check-native.js
rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune runtest --root . --force
rtk proxy node roster/tezos-call-resolution/verify.js --baseline /tmp/arch-index-resolution-baseline-OmhcEs/baseline.db --witness improvement/2026-09-14-tezos-resolution/attempt1-reviewed-witness.json
rtk proxy node scripts/review-bundle-verify.js
rtk proxy git diff --check
```

New checker commands are deliverables, not already passing checks. No configured formatter or coverage tool; do not invent coverage percentages. Hosted checks must all finish successfully at the exact PR head; a rebase invalidates earlier head evidence.

## Identified risks and assumptions

| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| Same spelling mistaken for ownership | High | Incorrect target | Per-CMT actual identities and homonym refusal tests |
| Includes/shadowing/constraints lose export provenance | High | Incorrect body | Source-order masks and native edge cases per spec |
| Flat fallback captures another file | Medium | Incorrect target | Exact same-file attribution or none, no coverage expansion |
| Same-line duplicates hide loss | High | False gain | Full multisets and refuse ambiguous changed groups |
| Comparator shares emitter assumptions | Medium | False confidence | Independent mutation tests, native semantics and source review |
| Temporary baseline lost | Medium | Invalid comparison | Refuse missing provenance/DB; retain owned directory until loop done |
| Remote CI unavailable/fails | Medium | Cannot ship yet | Fix in scope and wait; never merge on local checks alone |

Assumptions: current private APIs can carry per-CMT ownership without schema/public CLI changes; validate during implementation before widening scope. Existing unrelated dirty files remain untouched, so literal global clean-status requirements cannot override user-data preservation. Review records task-owned commit baseline and residual unrelated dirt honestly. Hooks, KB and canonical claims tools are absent; no successful execution of them is claimed.
