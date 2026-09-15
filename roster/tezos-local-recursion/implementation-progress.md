# Implementation history — chronological evidence

Final implementation gates now pass; see briefs/tezos-local-recursion-impl.md.
Earlier statements below describe their historical execution stage, not current
delivery status. Review/QA/CI/merge remain pending and only3/5 are delivered.

Planning committed as9d21cf229409430cdda9831f89bbf3633aa74ac2. Product unchanged.
Active slot is tezos-local-recursion. Manifest captures that base and exactly the
seven unrelated dirty files, uses exact paths/directory prefixes and no globs.
An initial scratch allowlist used glob syntax; it was corrected to the pinned
grammar before any code edit. Developer apply_patch requirement overrides the
skill's Bash-only control-file instruction; no freeze hook is installed here.

Initial preflight full336 guard ran before product changes and completed0 in
243853ms. The manifest header was captured subsequently at the docs-only commit;
no product or generated tracked change intervened. New baseline build exit0 .221s.
Source-sensitive baseline/replay checks will run after workers finish their edits,
not concurrently with their writes. No new full guard is claimed from this build.

Installed general implementer role read; OCaml specialist and language patterns
are absent. User-approved Sol/Terra substitutes are scoped in the shared checkout
because the active control files and uncommitted tests must remain visible.
No worktree created. Native OCaml work precedes remaining JS implementation.

Assignments:
- Sol recursive_research_flow: new Tezt native tests and main registration only;
  no production/checker edits or builds until main grants serialized slot.
- Terra recursive_research_patterns: independent native CMT witness and its runner
  only; no production/Tezt/other-checker edits or builds until main grants slot.
- Main: scope/scheduling, baseline and remaining comparison/preservation checkers,
  eventual product change only after complete executable oracle and genuine RED.

Actual storage nuance: rejecting the recursive root also removes root-owned calls.
A meaningful target-refusal assertion needs a surviving nested caller; rejecting
the structural parent skips its whole collection. Do not assert impossible rows.

No CHECK1–6 pass, native RED, candidate gain, implementation completion or fourth
KEEP is claimed yet. Ledger remains plan/COMPLETED until implementation finishes.

First native test execution: build0; fixture compilation failed only on unused-rec
warning39 in deliberate negative controls. This was setup failure, NOT RED.
Disabled that warning in the owned fixture only, then build0 and focused run exit1
in25933ms (attempt4-tezt-red2.log). Genuine missing self-target/residual/storage
assertions fail, and structural-parent refusal passes. Two preservation assumptions
were independently refuted: existing mutual traversal yields one TOP and one
bounded cross-literal call; flat fixture already has21 synthetic-lambda callees.
Sol corrected those controls to preserve actual predecessor behavior, and added
default/refutable/nested-recursive/non-head-RHS tests. Revised run still pending.

Main review of unbuilt native witness found overly broad line grouping (must
include printed head, while retaining mixed-Ident refusals), lost outer-recursive
scope beneath inner recursion, and missing structural non-function caller owners.
Terra is correcting these before any native evidence is accepted. No product edit.

Subsequent executed evidence (not a completed implementation):
- Focused native red3: exit1,25943ms, only intended target/storage assertions fail.
- Full `--keep-going` TDD run: exit1,270344ms;340 tests played,338 pass,
  only two new target/storage tests fail. All original336 pass.
  Evidence: attempt4-full-red.log/json in the ignored improvement directory.
- Native smoke2: actual compiler/probe exit0,79 applications,13 eligible and
  unambiguous fixture heads. Fixture counts are not Tezos gains or storage proof.
- OCaml5.3 typedtree inspection refuted binder-annotation eligibility:
  `let rec aux : int -> int = fun ...` uses Tpat_alias(Tpat_any,...), excluded.
  Positive uses `let rec aux = (fun ... : int -> int)`; negative retained.
- CHECK3 actually passed:33 malformed-record refusals, overwrite refusal,
  cwd independence and copied PR107 producer replay exactly45052rows,
  digest9ab4e0b13457247fb93dc83bf80323fcc5cec67866a18f56995ac0ec4a20867e,
  Irmin4781/protocol12046. No baseline refresh.
- First CHECK2 execution failed setup2 (approved-map destructuring); first
  CHECK1 failed setup2 (OCaml reserved `effect` fixture binder). Neither is RED.
  Corrections pending rerun. Main review additionally required fresh CMT replay
  against editable witness evidence and precise counted native permissions for
  pending preservation instead of broad name-prefix normalization.

Remaining: all six executable controls, real native-check RED, bounded product
change, positive witnessed410 comparison, full guards/review/QA/CI/merge.
No product edit, attempt4 KEEP or attempt5 start. Ledger remains plan/COMPLETED.

Oracle execution before product implementation:
- CHECK1 exit1 only at independently observed basic self-target assertion, after
  complete paired pending/shape/channel/flat preservation. Genuine semantic RED.
- CHECK2 and CHECK6 exit0 with authentic compiled CMT and independent capacity,
  forged-evidence replay, duplicate-artifact/probe-provenance refusal controls.
- CHECK4 and CHECK5 execute and propagate the same CHECK1 semantic RED; no
  fixed410 positive gain or completed self-smoke claimed at this stage.
  All six commands exist and have been executed (CHECK3 PASS above).
- Independent follow-up review identified validator defense-in-depth gaps in
  UID/full-range/owner/group/canonical-root links. These are being strengthened
  before accepting any candidate witness; raw native replay remains mandatory.

Product implementation now assigned to Sol in arch_index_cmt.ml only. Root owns
serialized builds/probes; no test weakening and no foreign worktree cleanup.

First product verification:
- Main static review caught that a default empty descriptor table still enabled
  the private path in the flat wrapper. Changed to omitted=None, activation only
  through process_cmt; late success explicitly uses the observed body name.
- Build exit0; strengthened CHECK2 exit0; CHECK1 native admission and complete
  rich/flat preservation exit0 (before alias-hidden regression fixture addition).
- Full340 exit1 in269483ms, source state unchanged.338PASS, new4 allPASS.
  Failures: self-index golden expected25/998/6335 vs25/1004/6382, and origin
  recurring consumer authentic. Their reference/coordinate dependencies need
  pristine crossed attribution; no reference has been changed or authorized yet.
- First fixed410 candidate attempt4-candidate-2Mp4Vh: gains68Irmin/111protocol,
  0resolved-relationloss,45051rows vs45052. REFUSE, no witness/KEEP.
  Exactly one legacy TOP residual was lost at irmin/lib_irmin/tree.ml:1920,
  Make.update_tree#1.<fun:1881:17>. Native410 probe completed410records with186
  eligible occurrences; local polymorphic annotation has rootarity3/supplied3,
  while the legacy type-arrow view sees only2 because its continuation is aliased.
- Added authentic alias_hidden native fixture; actual CHECK1 exit1 specifically
  rejects that removed legacy residual. Product correction preserves the legacy
  predicate OR actual recursive overapplication, with one shared residual emission.
  That correction is written but not built/tested at this update.

Still3/5 delivered.179 additional relations are unretained candidate data only.

Residual correction validation:
- Build exit0 and CHECK1 exit0 including the new alias_hidden regression and
  paired rich/flat preservation. No assertion weakened.
- Second fixed410 candidate attempt4-candidate-V7jzC4:45052rows on both sides,
  181removed callback heads/181added bounded heads,179new relations
  (+68Irmin/+111protocol),0lost resolved relations,0new MUST,0removed TOP residual.
  Digest082bdce92c6cab7b654f87a90db59ca9979d7004f45a42997a33718f6cd7c67a.
  Still REFUSE until native witness approval; not KEEP or completed guards.
- Mechanical draft-witness generator under review; initial static interface
  mismatches are being fixed before execution. Pristine calibration diagnostic
  runner is being prepared without altering any reference, branch or user dirt.
