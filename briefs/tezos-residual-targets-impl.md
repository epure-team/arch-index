# Implementation Brief — tezos-residual-targets

**Date:** 2026-09-14
**Mode:** full
**Status:** COMPLETED

## Current handoff: review and QA GO, hosted delivery pending

Product436cbfc is validated by all three personally executing reviewers,
the actual normalization/convergence gate (round1 GO) and fresh root QA
(round1 GO,332/332 and CHECK1..5). Fresh pristine four-cell calibration is
SOURCE_ONLY and all owned calibration worktrees/builds were removed.
QA fixed410 output attempt2-2026-09-14T17-35-08-875Z-1047006 confirms124gains,
+9Irmin/+115protocol,zero loss/errors,unchanged45052rows/candidate digest.
The sole critical finding is fixed, not waived; historical RED and resolved
history are preserved. Crossruntime timed out120s/degraded, notPASS;
mechanical red_verified remains null for the uncommitted-tree RED setup.
See review.json, qa.md and roster/tezos-residual-targets/review-round1-summary.md.
Only exact-head hosted CI and rebase merge remain before retention. Still1/5
delivered. The sections below are chronological historical handoffs, including
their then-pending obligations; they do not override this current status.

## Historical review-round-1 repair handoff

The completion below describes975c73b, not a final delivery verdict. Independent
spec review found that alias-owned names changed three unrelated legacy flat
forms (direct call, parameter call, bare callback). Its historical OPEN finding
and native reproduction are preserved in spec-compliance-round1-report.md and
spec-compliance-round1-findings.json. Standing user authority covers the bounded
in-scope correction; no invariant is waived and no spec is weakened.

pending_call now carries occurrence-specific local_module_invocation provenance,
default false, set only by successful qualified invocation lookup. The flat
extractor uses this flag, not head/name membership, for alias-only attribution.
Root's permanent check-flat.js first failed with an assertion on the old product,
then passed after the fix. The independent reproduction also passed: six legacy
rows equal, four qualified controls retained, two point-free rows equal; see
roster/tezos-residual-targets/spec-repair-confirmation.md.

Build0 and CHECK1/2 passed after repair. CHECK1 now additionally asserts the flag
for qualified application/callback/letop, point-free and return residual rows in
both contexts. Full guard exit0:332/332 (16:52:22–16:56:10), raw log
improvement/2026-09-14-tezos-resolution/attempt2-full-guard-3.log.
CHECK3 frozen replay and CHECK5 exact25/989/6275 passed. CHECK4 exit0 in
attempt2-2026-09-14T16-57-25-539Z-740371 confirms124gains/+9Irmin/+115protocol,
zero loss/errors and the unchanged00f1769d... candidate digest on45052rows.
Bundle22, scope and whitespace gates also exit0. Final committed-head specialist
gates and pristine recalibration remain pending; no review GO is implied.

Fresh independent C/D self measurements are25/989/6275/564 with every origin group
equal across frozen/current producers (self-attribution-review-fix.md). Exact
references were refreshed to these observations, conditional on another pristine
four-cell check before shipping. No threshold changed. Sole assertion relocation
1557->1559 preserves form/exception/x1 under the explicit user approval.
Reference source-manifest digest e8eef8003b1d5bf32ac1ae6b56249e279133d3ef06826984d75c23023f2f325d
is SHA256 of UTF8 JSON.stringify(run.provenance.sources), no newline, from
attempt2-origin-occurrence-fix/run.json; root rehashed every source successfully.
The initial consumer correctly rejected stale coordinates and coverage before
this refresh. Pristine calibration975c73b remains historical, not evidence for
the repaired bytes. Still1/5 iterations delivered.

## Ratchet

Finding spec:flat-alias-ownership-leaks-legacy-occurrences, raised round1:
check roster/tezos-residual-targets/check-flat.js, check_encodable true.
Red command: node roster/tezos-residual-targets/check-flat.js on975c73b product
with the new permanent legacy assertions (actual exit1 before product edits).
Green command: same command on the repaired working tree (actual exit0).
This is a same-round repair; no mechanical convergence-gate red_verified claim
has yet been made. Preserve its finding history even if final round1 is GO.

## Completion after approved scope extension

User approved the coordinate-only self.allow refresh on resume. SOURCE_ONLY
self attribution is recorded in roster/tezos-residual-targets/self-attribution.md:
A=B25/980/6245/561 and C=D25/989/6276/564, with only option/raise312->315.
Exact references now match; rule and one-entry allowance cardinality unchanged.
The source-manifest digest and its byte encoding are recorded in that report.

Fresh full guard exit0:332/332 Tezt,16:27:53–16:31:33, raw log
improvement/2026-09-14-tezos-resolution/attempt2-full-guard-2.log.
CHECK3 fresh frozen replay exit0; CHECK4 fresh reviewed fixed410 exit0 at
attempt2-2026-09-14T16-29-41-936Z-598259, still124gains/+9Irmin/+115protocol,
zero losses or other movement; CHECK5 exit0 exact25/989/6276. CHECK1/2
native/refusal coverage passed and all new5 tests passed in the full guard.
Consumer actual fresh run exit0/held at attempt2-origin-reference-refresh;
the rule evidence remains UNKNOWN, not a proof. Bundle22 and diff/scope gates0.

One attempted CHECK3 overlapped the new self-attribution report's creation and
correctly refused archStatus drift (setup2). Serialized retry0 above; no input
gate was weakened. Final committed-tree pristine calibration, independent review,
QA and exact-head CI/merge remain delivery gates, not claimed completed here.
The earlier PARTIAL event and the historical diagnosis below are preserved.
No owned disposable worktree remains; the independently built baseline worktree
and four diagnostic DBs were removed after small evidence was retained.
Task-scoped files will be committed before review. The seven pre-task unrelated
untracked paths remain deliberately untouched, so global cleanliness is not claimed.

## Implementation and evidence

One-hop bare arrow-typed Pident aliases in already-owned structures now resolve
qualified applications, callbacks and letops to existing body identities. The
body-only table, syntactic arity, supplied arguments and unsupported refusals
remain separate. Direct-only point-free lookup preserves immediate predecessors.
The flat extractor selects separate direct-only and invocation ownership sets.
No module/functor application expansion or config/CFG policy change is included.

Modified product: arch_index_cmt.ml/.mli and call_graph_extractor.ml. Tests:
local_value_targets.ml plus main/dune registration and the exact old
value_alias_call expectation in local_module_targets.ml. Documentation:
edge-kind-contract.md. Task-local baseline, comparison, probe, witness and
native/flat check scripts supply reproducible evidence.

The independent evidence review is roster/tezos-residual-targets/evidence-review.md.
Its exact draft was preserved and its actual reviewer identity recorded in
improvement/2026-09-14-tezos-resolution/attempt2-reviewed-witness.json.
After the flat correction, CHECK4 actually PASSED again in
improvement/2026-09-14-tezos-resolution/attempt2-2026-09-14T09-05-47-231Z-3290537:
45052 rows both sides, 124 paired transitions, +9 Irmin/+115 protocol relations,
zero losses, zero unexplained movement, unchanged candidate digest
00f1769d6db7f6ee91ee51becabccd7b4ce13975acb6610c95ace69a7f620e9b.
This is a candidate verdict, NOT retention authorization. Still 1/5 delivered.

## Quality gates actually run

- Build: opam exec --switch=/home/mathias/dev/arch-index -- dune build --root . PASS.
- CHECK1: node roster/tezos-residual-targets/check-native.js PASS, both native
  contexts and all five new Tezt cases, after the flat correction.
- CHECK2: node roster/tezos-residual-targets/check-comparison.js PASS (38 controls,
  3 positive native consumers/12 refusals, paired admission positive/10 refusals).
- CHECK3: predecessor frozen replay passed before product work; no new run claimed.
- CHECK4: reviewed 410-CMT comparison PASS as cited above.
- Full guard: 330/332 passed BEFORE the final flat correction; two failures in
  attempt2-full-guard-1.log. Not rerun or declared green after that correction.
- CHECK5: descriptive self golden is stale; not refreshed without attribution.
- review-bundle-verify.js PASS, 22 pinned files; git diff --check PASS.
- Formatter/coverage: not configured, no pass claim.

## Scope blocker and next action

Resume 2026-09-14: user explicitly approved this exact-coordinate-only scope
extension. The implementer brief and manifest now include self.allow, whose
single identity was updated without changing form, exception, cardinality or
policy. Historical PARTIAL event remains; implementation is active again, with
calibration and full gates still required before COMPLETED.

Actual producer diagnostic at improvement/2026-09-14-tezos-resolution/attempt2-origin-diagnostic
reports policy-failed. The only assertion site is unchanged in source, but its
identity moved from <fun:1495:21>.<fun:1506:36>/line1509 to
<fun:1543:21>.<fun:1554:36>/line1557. self.allow still pins the former location;
the gate reports exactly one new site and one stale entry matching nothing.
This file is absent from the manifest and the brief explicitly excludes allowlist
changes. No edit was made to that file, to the manifest, or to the rule.
Request only permission to replace that one coordinate, preserving the one-entry
cardinality, assert/Assert_failure identity and x1 count, not a policy relaxation.

Latest self observation is 25 modules/989 functions/6276 calls/564 origins
(option/raise group315, formerly312). These are observations, not approved
reference replacements: pristine predecessor/candidate attribution remains
required before updating the already-in-scope exact reference and golden.
Do not reuse the earlier pre-flat-fix 988/6270 measurement.

After scope approval: update the brief/manifest narrowly, attribute the self
movement with pristine builds, refresh reviewed exact observations/coordinates,
rerun all required checks/full guard, then scoped commit, full independent roster
review, QA, exact-head CI, PR/rebase merge. No product commit or PR yet; no
implementation COMPLETED or review/QA verdict is claimed. ACTIVE_TASK remains
owned by this task for resume. No attempt2 worktree was created. Unrelated dirt,
foreign worktrees, Tezos sources and held PR93 remain untouched.

## Review attention and corrections

Core native assertion RED genuinely preceded product code. Exhaustive requested
coverage was completed by root after Terra's initial GREEN; no retroactive RED
claim. A shadow fixture initially tested an explicitly unsupported unqualified
alias; corrected to qualified use while retaining the refusal test. Native
compiler helpers needed explicit local opam switch selection in temporary dirs.

Root additionally established a real flat attribution assertion RED: a new
alias-owned target name changed a legacy point-free edge's callee_file. Splitting
direct-only/invocation ownership fixed it; check-flat.js and CHECK1 are now GREEN.
The fixture deliberately preserves the pre-existing foreign-homonym point-free
attribution rather than expanding this task into a broader flat resolver change.
The narrow signature/implementation UID witness rule and its refusals need full
product review; semantic-evidence GO alone is not a pipeline GO.
