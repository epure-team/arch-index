# Historical implementation progress

Superseded status: implementation is now COMPLETED (2026-09-13), with final
320/320Tezt+64Alcotest and all four Node families green. See the current
briefs/functor-binding-resolution-impl.md and acceptance-status.md. The sections
below preserve intermediate failures/decisions, not current outstanding work.

2026-09-13. Owned worktree:
/home/mathias/dev/arch-index-worktrees/functor-binding-resolution
Branch feat/functor-binding-resolution, base7df5c031f809bc92c34d483a14dac3342d300ce2.
Main preserves unrelated untracked user files. This is the only worktree created
this cycle; retain while active and remove its build artifacts after safe handoff.

## Actual evidence

- Manifest/base captured before baseline. Controls written with apply_patch per
  host instruction (overrides skill's Bash-only editing recommendation).
- Baseline fresh build exit0 and full dune test --force exit0, Tezt266/266.
- First new native direct test initially had a missing Lwt.Infix import; repaired
  compilation only. Running outside opam failed fixture setup (dune absent), NOT RED.
- Authentic RED under explicit opam: native CMT compiled and catalogue marker/one
  occurrence assertions passed, then binding table count0 vs expected1 failed.
- Implemented direct collector, additive schema1.15/provenance persistence,
  independent failure latch and query checkpoint. Subsequent build exit0.
- Native retest now passes binding table/matchedslot1/declarationF assertions,
  then fails expected binding marker v1 vs None. Marker intentionally NOT emitted:
  complete producer-side persisted-data validator remains unimplemented.
- Full post-edit dune suite exit1:267Tezt attempted,5 failures. A second direct
  full Tezt run reproduced exactly those5 failures (filtered output captured):
  new binding marker; two existing completion-marker controls; origin recurring
  consumer authentic; MUST/NULL self ceiling509 against493 (+16 over ceiling).
  The other262Tezt tests passed. Baseline266/266 was before product edits, not now.
- A focused catalogue/drop/marker rerun passes all10catalogue controls plus the
  drop-list guard; both old marker controls fail because the new marker isn't
  emitted. This is not evidence all compatibility gates pass.
- Origin attribution rerun is retained in origin-attribution/run.json: exit1,
  status coverage-drift; policy.failed=false, verdict UNKNOWN, gate_exit0.
  Coverage changes24/859/5440/495 to25/902/5620/524
  (modules/functions/calls/origins). New module arch_index_bindings; no missing
  module. This establishes coverage refusal, not a stronger policy verdict.
- MUST/NULL failure reports317 roots absent from index and192 present. This is
  NOT proof that these calls are resolvable. Do not raise clean_measured/ceiling
  or alter graph semantics without the contract/authorization required by intake.

## Not complete / next work

1. Establish one complete set of persisted-data validation predicates for producer
   finalization and reader. Do not add arch_index -> private arch_tools silently:
   it crosses the existing public/private library boundary. Prefer a deliberately
   scoped neutral shared validator or intentionally equivalent producer validator,
   with parity/corruption tests. Never emit v1 merely to turn the first test green.
2. Four new reader tests added by Sol, executed by root. All three corruption
   controls first proved their seeded database queried successfully at limit0,
   then failed genuinely: duplicate result replacing missing occurrence, direct
   formal position2, and missing application-head ordinal each wrongly exited0.
   Fixes now reject duplicate keys, compare exact stripped head ordinal, and force
   direct matched position1; all three subsequently passed. A fourth valid
   ghost=false declaration test failed with INCONSISTENT_BINDINGS; corrected
   boolean-type validation instead of requiring ghost=true. Fresh full gates
   pending below; these tests do not replace the four required Node families.
3. First collector supports direct heads only; alias chains and literal curried
   resolution are NOT done. Current explicit refusals are interim, not the full
   closed semantic precedence. Add each next behavior with real tests before code.
4. Implement all four plain-Node check families and their exit convention. They
   are still absent; native Tezt test is not a replacement for the frozen checks.
5. Complete lifecycle/failure injection, all9reason premises, anonymous/unit tests,
   six independent renderer oracles, compatibility/readonly checks and exact410
   benchmark. No new Tezos/Irmin precision or target-resolution result yet.
6. Full review/QA/exact-head CI/PR/merge not started; product edits uncommitted,
   no broken-test round committed. Do not append implement COMPLETED/PARTIAL merely
   to checkpoint this in-progress work; ledger's last completed phase stays plan.

## Integration corrections

Default Typedtree visitor needs separate local-module and functor-parameter hooks;
registering both module_binding and item_declaration would duplicate identities.
Existing catalogue collection stays independent/default callback-free; binding
preindex runs only after catalogue persistence and count increment.
Root corrected nonexhaustive guarded matching, ambiguous record inference and
SQL apostrophe escaping; one build also saw an agent's temporary mli-only state.
No concurrent Dune calls; wait for agent file completion before building.
Specialist profile absent, Sol OCaml-capable fallback used transparently.
One follow-up delegation was rejected with agent thread limit; no work claimed
from that failed dispatch. Root must handle remaining validation or delegate only
when a real slot is available.

## Same-corpus call attribution (2026-09-13)

Before the reader corrections were rebuilt, root compared the fresh main engine
(main7df5c03, product identical to merged catalogue) and current direct-binding
engine against the same unchanged136CMT/81CMTI build corpus. Both returned
21163 calls,9316 resolved,509 non-Stdlib MUST/NULL. Bidirectional SQL EXCEPT
of grouped caller_id/callee_id/callee_name/call_site/kind/top_reason/top_anchor/
edge_form/count found zero differences. No Dune build ran between these indexes.
The earlier21089-call snapshot likewise had509 MUST/NULL, including41 from the
three new source files: collector4, reader34, test3. This accounts arithmetically
for468+41=509; it is not a complete2x2 or an authorization to change calibration.
The two compared DBs and earlier snapshot are active diagnostic artifacts under
origin-attribution; they are not release evidence for subsequent edits.

Producer finalization still must validate old catalogue grammar, not merely trust
its marker. Read-only Sol design recommends an intentionally equivalent Sqlite3/
Yojson validator plus mutation parity tests, within existing files; no new public
dependency on private arch_tools. Do not silently strengthen old catalogue output
semantics just to reuse its current incomplete count-only finalizer.

## Latest full verification after reader corrections

Fresh build exit0; review-bundle22 hashes1.6.0 exit0; git diff --check exit0.
Full dune test --force exit1,271Tezt attempted,266 passed/5 failed.
All four new reader tests pass (positions85–88). Remaining failures are native
binding marker, two completion-marker controls, origin authentic, and MUST/NULL
ceiling. The fresh ceiling diagnostic is510 vs493 (21197 calls;318 roots outside
index,192 indexed; exact-name resolver misses0 with5300 resolved positive controls).
Earlier509 attribution is explicitly the pre-reader-correction snapshot, not
this later build. No limits or baselines changed. Implementation remains active;
no review/QA GO, round commit, PR or new product Tezos benchmark is claimed.

One fourth-test setup initially failed OCaml optional-argument erasure before
execution; trailing unit fixed setup only, then authentic ghost=false RED was
observed and corrected. New Terra architecture dispatch hit agent thread limit;
the already-existing Sol thread supplied the read-only recommendation instead.

## Producer-finalization continuation (2026-09-13)

Renewed preflight build0/collection0/bundle22 hashes0; full ledger-schema jq
predicate true. Original manifest and active worktree preserved. Native marker
RED reconfirmed before implementation. Sol implemented an intentionally equivalent
Sqlite3/Yojson validator in arch_index_bindings, without changing old catalogue
semantics or adding a private-library dependency. Root integrated the finalizer
after restore_intents, after all data transactions, as the last producer write.

31 table-driven corruption cases each verify a valid reader/finalizer control,
then producer refusal and absence of marker, followed by a forged-marker reader
refusal. Zero-application/unused-declaration and zero-declaration controls pass.
The first native direct end-to-end test now passes, including actual query output.
Root added an injected marker-write failure: authentic RED showed an active
transaction remained because the exception pattern did not cover branch-body
INSERT/COMMIT errors. Enclosing try/checked rollback fixes this; all38 focused
tests subsequently passed. Two unused declarations and one test-printer type
error were compile setup fixes, not semantic REDs.

Full suite is being rerun. Independent read-only parity audit then identified
missing producer schema-shape guards (hybrid calls.caller_name discriminator and
required columns). Two additional tests added, awaiting RED execution; do not
claim full parity until those are handled. No alias/curried collector advance,
Node check-family completion, Tezos product benchmark, review/QA or PR yet.

Schema follow-up: hybrid discriminator reproduced genuine RED (finalizer true
instead of false). Missing-column test reached the finalizer then raised
Sqlite3.prepare rather than returning false. Added the same required-column and
flat-discriminator guards before row validation; all40 focused tests now pass.
First full suite after finalizer integration:304Tezt,302pass/2fail, plus64Alcotest
pass. Native and existing marker controls now pass. Only origin authentic and
MUST/NULL self ceiling remain (518 vs493 on21749calls). A fresh full suite after
schema guards is running; previous measurements are not attributed to this build.

Final post-schema rerun: build0,40/40focused; full suite304/306Tezt pass,
64Alcotest pass. Existing marker controls now pass. Only origin authentic and
MUST/NULL519 vs493 fail (21805calls;324 roots outside,195 indexed; exact-name
misses0 against5529 positive resolved controls). No reference updated. The first
checkpoint's all-green gate now requires a coverage-reference decision; requesting
explicit authority for strictly attribution-gated recalibration, unchanged headroom.
Impl brief written PARTIAL for this scope blocker, not merely because a test failed.
Remaining feature work is enumerated there; active worktree retained, no PR/commit.

## Authorized source-only recalibration and next TDD step

User approved neutral attribution with unchanged margin. Fresh2x2 source
snapshots (not clean candidate SHAs) yielded ceiling A=B468,C=D519; producer-only
coverage A=B24/859/5440/495,C=D25/951/6112/547. All within-corpus grouped call
hashes and origin groups agree. Details and digest inventory in calibration/.
Only measured references updated: clean519/headroom25, descriptive golden,
origin coverage and authentic frozen totals. Rules/allowlist unchanged.
Both exact temporary worktrees/build artifacts removed, active worktree retained.
Full rerun then PASS:306/306Tezt and64Alcotest. This completes the direct native
checkpoint's product gates, not the whole implementation/Node families/roster.

Next native tests added by Sol, root compiled0 and ran both genuinely RED after
catalogue premises: alias chain terminal match0 vs1; literal curried match1 vs2.
Root corrected the curried fixture body before RED (removed a real arithmetic
call that contradicted its zero-call oracle); both literal formals remain.
Alias/curried collector implementation delegated, no phase completion or PR yet.

Alias and literal-curried implementation now passes both native tests and all42
focused checks. Resolution follows local Pident identity aliases with a visited
set, recursively checks/propagates inner applications, then advances the literal
formal telescope. Existing ordinal callback and finalizer unchanged.
Fresh symmetric recalibration in calibration/alias-curried/ is SOURCE_ONLY:
A=B468,C=D524 whole-corpus MUST/NULL; producer coverage25/954/6131/553.
References updated under same explicit authority, headroom25 unchanged. Both new
temporary calibration worktrees/builds removed. Full308test rerun pending.

Fresh bounded Tezos/Irmin observation succeeded on the exact410manifest:
all410 collected,1275results,202matched (82Irmin,120protocol),1073unresolved.
52 matches occupy positions2–6. Unsupported_path1050 dominates the remaining
results; other counts and limits are in tezos-irmin-bindings/README.md/report.json.
No source edits; temporary symlink corpus/DB removed. Tezos dirty47entries stable
pre/post (not the earlier46-entry research snapshot). No call-target gain claimed.

Latest verification complete: fresh build0; all308/308Tezt and64Alcotest pass
after alias/curried reference updates. Review bundle22 hashes, scope manifest gate
and git diff --check pass.42 targeted binding tests are part of this green suite.
No new terminal ledger event: the earlier PARTIAL authority blocker was resolved
by the user's explicit approval, and implementation is actively continuing.
Whole feature still needs full Node families, broader traversal/identity/refusal/
lifecycle/rendering contract tests and roster review/QA before any product PR.
No build or agent remains running at this checkpoint.

## Continuation: executable acceptance families

Fresh fetch leaves origin/main at a232eac; preflight build/bundle/collection pass.
The unchanged baseline was rerun successfully:308Tezt+64Alcotest, before the new
coverage tests were rebuilt. Native/synthetic and partial-storage tests are now
being extended; their first compile exposed a Check local-open operator-shadowing
error, not a semantic regression. Correction and a reader commit-failure RED test
are in progress. Independent inspection found the snapshot exception pattern did
not enclose commit; no product fix or passing regression test is claimed yet.

scripts/check-functor-bindings.js now implements all four command families.
Root replayed query (18 exact renderer oracles,8 limit0 mutations), native
inventory (13 occurrences), compatibility (16 historical semantic surfaces plus
read-only binding/catalogue bytes) and direct-API lifecycle successfully.
Compiler-dependent checks use ARCH_FUNCTOR_OPAM_SWITCH explicitly in this
worktree, because no default switch is set. Missing switch correctly returns
infrastructure2; no machine-specific default is embedded in the script.
Lifecycle compilation uses a fresh temporary copy of the probe and local Dune
installation staging, without adding a Dune stanza or retaining build artifacts.
Family success does NOT yet imply all frozen ACs: inventory discloses missing
synthetic-only premises and lifecycle is explicitly direct-API, not full CLI
failure orchestration. Complete acceptance coverage and full rebuilt suite remain
required before roster review/QA/PR.

Reader commit/rollback genuineRED recorded: one selected regression test exited1
with rollbackcount0vs1. Minimal `try` enclosing validation+commit fixes it. Fresh
build0 and48/48bindingTezt pass; full rebuilt suite running. Test setup corrections
(Check operator scoping, unavailable Option.exists and native constrained Alias
head) are detailed in acceptance-status.md, not counted as product regressions.
Root replayed all four Node families after the fix. Their assertion/setup exit
distinction was checked with `/bin/true` (exit1, missing expected renderer bytes)
and a nonexistent query path (exit2). Bundle/scope/diff/syntax gates pass.

Final continuation verification: full rebuilt suite314/314Tezt+64Alcotest PASS,
exit0. No additional calibration/reference/headroom changes were required.
All four Node families replayed by root; missing broader AC cases remain explicit
in acceptance-status.md. No phase completion, round commit, review/QA or PR yet.
No live agent/build remains. No new worktree was created; all checker mkdtemp
directories were cleaned (no /tmp/functor-bindings-* remains). Existing active
product worktree and unrelated user worktrees/files are retained.
