# Implementation checkpoint — fifth/final attempt

2026-09-15. Implementation complete, not a retained iteration. Six-check sweep
passes; no review/QA/ship success event yet. See the canonical implementation brief.
Product source now admits the specified single named-path open. Active task manifest is installed on branch
feat/tezos-recursive-open-bodies at 0017a48f47e6cac1035cfdd19f2b97106a7e9113.
Manual apply_patch control-file edits follow the host's higher-priority editing
rule; no harness freeze hook is installed. Only seven unrelated user files are
dirty exclusions; this task's already-created files remain reviewable scope.
Original pre-product full340 guard remains recorded separately. No owned
worktrees or persistent witness build artifacts were created.

## Actual checks

- New sealed-v2 baseline loader/control: exit0, 43 malformed-record refusals,
  both creation routes refuse overwrite, CWD independence, writable-read stability
  on copies and neutral full410 replay. 45052 rows, digest082bdce9…;
  Irmin4849/protocol12157. Three semantic-replay failure controls also pass.
- Fresh Sol static helper review found semantic replay errors incorrectly grouped
  with setup errors. Fixed by assertions after successful production, not blanket
  conversion of input errors. Provenance/input failures still exit2. This was a
  bounded static review, not the pipeline's final roster GO.
- Compiler-only open witness compiled and ran on all410 immutable CMTs: exactly
  14 eligible protocol heads, no eligible Irmin head. Original root/caller/arity
  observations saved in ignored attempt5-open-native-observation.json (164MiB).
  Separate native build directory cleaned automatically. Fresh Terra static
  review found no concrete defect; this is not storage confirmation or a gain.
- Build after dedicated native Tezt registration: exit0.
- Full Tezt first run: exit1, 340 existing SUCCESS, two new fixture compilation
  failures, 274890ms. Unused-open warning33 was fatal. This is setup failure, NOT
  authentic RED. Evidence: attempt5-native-red-1.json/.log in the ignored loop.
- Corrected only the fixture warning mask (-33), preserving exact AST intent.
  Focused two-test run: exit1, ten authentic RECURSIVE_OPEN_ASSERTION failures,
  no fixture/indexing setup failure. Parent/continuation/exclusion controls pass.
- CHECK2 check-witness-inputs.js: exit0 on genuine compiled open-recursive CMT;
  binder/root/ordinal/caller/range/shape/arity/tamper/head-residual reuse refusals.
- CHECK1 check-native.js: after fixture corrections below, authentic exit1 at
  missing independently observed target basic.<fun:17:43>. Before reaching that
  assertion it passed complete rich pending/non-call and public flat multiset
  preservation, actual selected exception/channel scope coverage, physical
  collision ordinal, and selected parent-context effect coverage.

## Fixture corrections, not product changes

Initial channel fixture merely propagated Error and supplied no handler scope;
replaced it with a real inner handler around the selected recursive call. Initial
effect assertion incorrectly required counters on the synthetic function. Actual
diagnostic shows effects parent mutation1/deref2, promoted root counters null.
The corrected assertion requires the selected root's compiler-observed structural
parent, matching its range, with both nonzero counters. This does not use an
unrelated nonempty effect row or change the product's storage policy. Diagnostic
print removed. Both earlier assertion failures are retained here, not hidden.

## Product and post-edit verification

Corrected full RED run: 340 existing tests pass, two new tests fail on ten intended
assertions. The minimal private admission was then implemented. Build and CHECK1
pass; the complete suite passes 342/342 (attempt5-native-green-1.json/.log).
Raw fixed410 candidate adds 14 protocol relations, no Irmin relations, no losses,
and preserves 45,052 rows. Its unwitnessed verifier correctly refused acceptance.
Independent Sol CLI review approved all 14 native-to-row pairs; the separate
reviewed witness is prepared. This is not the final Roster review verdict.
Six-check witnessed sweep now passes, including +14 protocol, zero losses and
unchanged self policy. Remaining: full roster review/QA/exact-head CI/merge.
No fifth PR/KEEP yet; no sixth iteration authorized.
