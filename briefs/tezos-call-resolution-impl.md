# Implementation Brief — tezos-call-resolution

**Date:** 2026-09-14
**Mode:** full
**Status:** COMPLETED

## Modified files

- `lib/arch_index/arch_index_cmt.ml` and `.mli`: same-CMT compiler-identity structured-module ownership, source-order masking and optional collector context.
- `lib/arch_index/call_graph_extractor.ml`: both collector paths receive context; exact same-file flat target attribution.
- `tezt/tests/local_module_targets.ml`, registration in `tezt/tests/main.ml`: four native identity/refusal/arity/storage/fallback cases.
- `roster/tezos-call-resolution/`: canonical comparison, mutation checks, native wrapper and independent compiler UID endpoint evidence.
- `.gitignore`, task briefs/spec, `docs/edge-kind-contract.md`, friction log and external roadmap: scoped measurement, workflow and capability documentation.

## Decisions made

Comparison setup was verified before product edits and consumes no product iteration. An authentic failing native resolution assertion preceded implementation. New ordinary targets remain MAY_ENUMERATED, not MUST. Overapplication preserves explicit computed-return TOP rows. UID endpoint evidence is independent of product ownership resolution, but does not replace its refusal-policy tests or roster review.

The first real-corpus comparator refused pending explicit reviewed witnesses. The subsequent comparator update handles exact qualified-display corrections, duplicate transition multiplicity and separately witnessed return residuals; its28 assertions pass. Fresh approved-witness verification now passes (session77121), with exact canonical candidate digest90e76d6b40b2d7f108fcc25523f85de1cb533a98565a8a7d6d284c1654939d4b. Report: improvement/2026-09-14-tezos-resolution/2026-09-14T05-46-32-165Z-candidate-2339422/report.json.

The user approved the six-file scope extension on resume. Sol recalibrated only the two concrete A.run expectations/query outputs and the reviewed self-analysis origin reference/assertion location. Existing X.run/M.run TOP refusals, exact-table comparisons and failure injections remain. Historical gate observations are preserved. Root's compiler-probe review found location-only occurrence keys could combine PPX identifiers; the corrected probe keys complete located Longidents and rejects ambiguous native bodies before looking at DB targets. All831 endpoints still match. Eight identical native duplicates are consumed with multiplicity, not guessed unique.

## Quality Gates

- Baseline full build/test guard: PASS, Tezt320/320, before product implementation.
- Product build: PASS (session50326 and fresh final root build exit0).
- `rtk proxy node roster/tezos-call-resolution/check-native.js`: PASS, four native cases (session76644).
- `rtk proxy node roster/tezos-call-resolution/check-native.js --self-test`: PASS, five wrapper-classification assertions, root rerun.
- `rtk proxy node roster/tezos-call-resolution/check-comparison.js`: PASS, 28 assertions, root rerun.
- Fixed410 candidate measurement: +400 Irmin / +395 protocol distinct relations, no existing-relation loss; not an approved keep. 831 transitioned rows include31 aliases excluded from the primary metric;34 return TOP additions.
- Independent UID evidence v2: 831 endpoints and34 residuals, all810 caller/site buckets covered. Raw evidence SHA2568811a7e0b1d93c25eb5e40c2f680112add0d54e2a7f764f1a2aa1668e094c909; prior location-only report retained as historical, not used for approval.
- First full post-product guard: FAIL, Tezt321/324 (session8451), diagnosed and corrected under user-approved scope extension. Final full `dune runtest --root . --force`: PASS, exit0, Tezt324/324 (session3501); raw trace retained in improvement/2026-09-14-tezos-resolution/attempt1-guard-green-trace.csexp.
- Review bundle preflight: PASS,22 files hash-matched, bundle1.6.0.
- `rtk proxy git diff --check`: PASS. No configured formatter/coverage percentage claimed.
- Round ready for owned-file commit and independent review. No review/QA GO, PR or merge claimed. Unrelated user dirt preserved; the task manifest remains for scope verification after its active slot is deactivated.

## Points of attention for review

Review identity/member masking and flat attribution; native positive tests alone cannot establish safety of all refusal cases. Examine exact compiler UID witnesses and residual arity before approving fixed410 changes. CHECK-3 now names the concrete witness; verifier accepts a deactivated slot but refuses a foreign active task and still requires the pinned task manifest. Keep comparison approval versus retention distinct. Review all six recalibrated golden/query/origin evidence files explicitly.

## Identified out-of-scope

The previously requested six-path extension is approved and implemented; the diagnosis remains historical. Review round2's sole OPEN non-scope finding adds the exact test/fixtures/self-index-stats.txt path via roster-implement's loop-back union rule. This is CI oracle collateral, not a resolution-scope change; original manifest base/dirty entries remain pinned. Do not change historical gate results, Tezos inputs, schema, dependencies, held PR93 or unrelated worktrees. Product attempts delivered remain0/5; attempt1 awaits independent review/QA/CI, not yet discarded or kept.

## Ratchet

Round2 NO-GO repair (completed, full327/327 PASS): finding
`test/fixtures/self-index-stats.txt:2:integration#3f5e6e18` is assigned new
`roster/tezos-call-resolution/check-self-index-smoke.js` (CHECK-6/AC-14).
Red command: `node roster/tezos-call-resolution/check-self-index-smoke.js`.
check_encodable: true. Self-contained current-producer/SQLite exact golden
comparison with owned runtime DB cleanup; no automatic refresh or threshold.
Genuine RED preceded the fixture edit; execution evidence is recorded
in self-smoke-ratchet-evidence.md. Null pre_fix_sha remains honest dirty-tree
metadata, not an automatically red-verified historical checkout.

Round1 NO-GO repair (full guard now PASS326/326): all three observations of omitted-label
arity share `roster/tezos-call-resolution/check-labeled-arity.js` (CHECK-4/AC-12).
Finding fids: lib/arch_index/arch_index_cmt.ml:2174:correctness#e6e59b53,
lib/arch_index/arch_index_cmt.ml:2150:spec#208245bb,
lib/arch_index/arch_index_cmt.ml:2150:correctness#0e5e8ad3.
Red command: `node roster/tezos-call-resolution/check-labeled-arity.js`.
check_encodable: true. New self-contained native fixture/probe, authentic pre-fix
assertion exit1 and post-build exit0; see arity-ratchet-evidence.md. Historical
gate red_verified must remain null while pre_fix_sha is null/dirty-tree; manually
observed RED/GREEN is recorded separately and does not manufacture a clean SHA.

FR014 coverage finding roster/tezos-call-resolution/check-comparison.js:116:spec#36ef3d4f
is covered by new `roster/tezos-call-resolution/check-verifier-inputs.js`
(CHECK-5/AC-13), command `node roster/tezos-call-resolution/check-verifier-inputs.js`,
check_encodable: true.39 negative/positive assertions pass. The run-set strengthening
has retrospective old-code failure evidence, not a falsely claimed pre-edit RED;
see verifier-input-evidence.md.

## Round1 repair completed — handoff for review round2

The revalidated spec adds AC12/CHECK4 and AC13/CHECK5. The15-line producer delta
counts Some arguments only for newly owned structure heads; legacy head and
noreturn CFG accounting are unchanged. The self-contained arity check verifies
four real compiled callers in both collector contexts, including omitted optional
and named arguments, actual partial metadata and exact residual counts. Both new
checks are registered in the full native suite and tracked as Dune dependencies.

The comparator now binds both input tables to the declared run, requires distinct
410 artifacts and validates required provenance columns. It has39 isolated
negative/positive checks; exports for expected/file test fixtures do not alter
pinned CLI defaults. This strengthening has retrospective old-code assertion
evidence, not a falsely claimed pre-edit RED. No Tezos or baseline mutation.

Current exact executions: build exit0; full forced runtest exit0, Tezt326/326
(session96167; raw trace improvement/2026-09-14-tezos-resolution/attempt1-arity-guard-trace.csexp);
CHECK1 native6/6 exit0 (session77767); wrapper self5 exit0; CHECK2 comparison28
exit0; CHECK4 arity exit0 after genuine pre-fix assertion1; CHECK5 inputs39 exit0;
bundle22 hashes exit0; whitespace exit0. CHECK3 candidate exit0 at
2026-09-14T06-26-30-653Z-candidate-2526704, same canonical90e76d6... digest,
+400/+395 relations and zero losses; self replay exit0 at
2026-09-14T06-27-04-107Z-self-2550553. Exact previous witness still applies because
every canonical row is unchanged. Producer SHA c953970a15b64d026f7b502ba5d61be537c3ab5b51e219435b4a3483d57764b8.

Only self reference call count changed6241→6245 with source-manifest provenance;
functions980/origins561 and all origin groups unchanged, self.allow unchanged.
Full recurring-consumer/fault tests passed after this authorized recalibration.
No additional compatibility oracle movement. Existing round1 reviews remain
historical NO-GO evidence. Round2 review, QA, exact-head hosted CI and merge are
not yet approved;0/5 product attempts delivered. Unrelated dirt remains excluded
from the task commit; do not misreport the whole checkout as clean.

## Round2 repair completed — handoff for review round3

The separate CI smoke golden is now25/980/6245, matching the exact current
producer/SQLite output. CHECK6/AC14 reproduces that comparison locally with no
threshold or runtime fixture rewrite. Sol observed genuine assertion RED before
the golden-only update, then GREEN; the checker is registered in Tezt and its
script/golden are explicit Dune dependencies. The required native titles are7.
Root caught and corrected CI portability during integration: use the local opam
switch only when present, otherwise inherited environment. Root independently
ran that inherited path PASS and missing-producer control SETUP2. Cleanup failure
also maps to SETUP2; subprocesses have bounded timeouts.

Sol independently executed build0, native7/7, wrapper5 and full forced327/327.
Root reran CHECK2(28), CHECK4 and CHECK5(39), all0, plus exact fixed410 candidate0
at2026-09-14T07-00-21-646Z-candidate-2740926 and self0
at2026-09-14T07-00-37-906Z-self-2741604. Canonical rows remain90e76d6...,
795 relation gains (+400/+395), zero losses. No additional product/source change
occurred; the existing UID witnesses and all refusal boundaries still apply.
Bundle22/scope/whitespace pass. No formatter/coverage/claims tool is configured.

Round2 review is durably NO-GO for this now-corrected golden; review round3 has
not run. Prior strike requires full fan-out. Pristine committed-tree recalibration,
QA and hosted exact-head CI/merge remain required before keep; still0/5 delivered.
Removed only25MiB regenerable compiled artifacts from the owned round1 label
diagnostic; its source/DB evidence and the necessary baseline remain retained.
