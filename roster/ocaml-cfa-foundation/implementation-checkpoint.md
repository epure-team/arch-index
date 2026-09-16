# Stage2 implementation checkpoint — 2026-09-16

Nonterminal progress record, not an implementation/review/QA verdict.
The append-only phase ledger remains at validated plan while work continues.

## Baseline and first vertical slice

- Committed plan/base: c397efd1b2248564c05c74fdab795213dea593db.
- Fresh pre-product full baseline:344/344 Tezt, exit0; see baseline.md.
- Authentic OCaml5.3 alias-chain fixture compiled/indexed before product edits;
  main and flat target assertions both failed (exit1, not a setup error).
- Initial private finite target/reason worklist and alias session made that
  targeted fixture pass, including no duplicate ordinary TOP and no new MUST.
- Implementer-reported first full run:345 played,340 passed,5 failed, exit1.
  Not a green slice. Exact failure attribution remains in progress.

## Required corrections / extensions

Root read-only examination identified nested-module alias transfer beyond
FR016, solving before authoritative collector notification, missing faithful
flat caller/target mapping, and incomplete Some-slot/unknown-arity/residual
handling. The implementer accepted these points and retains the sole source/build
token while correcting them. A separate read-only Terra examination supplied
target-shadowing, ambiguous-caller, capture and foreign-homonym controls.

Historical point-free underapplication/query assertions must be compared with
the new contract before deciding whether they are regressions or newly-supported
expectations. No out-of-manifest test edit, frozen-corpus change, allowlist
weakening or blind golden refresh is authorized by this checkpoint.

Full literals/joins/same-callable lets, independent solver oracle, authentic
adversarial identity/metadata coverage and candidate pinned410 replay remain.
Existing frozen45052 rows /4849 Irmin /12171 protocol are unchanged baseline
figures, not measurements of this candidate. No PR or merge for stage2 yet.

No new worktree. Foreign files and Tezos checkout remain untouched.

## Post-run attribution and deferred-expansion review

After restricting transfer to root structure items, the implementer reported a
focused15-test run with4 failures: two point-free assertions, the supported
`unqualified` alias expectation, and the authentic self-origin reference check.
This focused run does not establish a fresh full-suite result. Root examined
point_free_aliases.ml: its old `arity_partial -> arity_alias MAY_TOP` assertion
must become a real-target/partial/no-MUST assertion under FR031/032; its module
fan-in expectation must account for the newly resolved ordinary application
while still excluding all seven value_alias edges. Exact-file scope approval
has been requested asynchronously; no edits to that test have been made.

The first deferred-expansion refactor built and passed the alias fixture, but
root code review rejected its completeness claim: main still expanded per
binding, the walk still inspected solved target sets, and partiality was joined
across candidates rather than computed per candidate. This is NOT accepted
FR012/032 evidence. A fresh Terra subagent has the exclusive source/build token
to repair whole-CMT finalization and occurrence descriptors, with explicit tests.
No Roster phase PARTIAL event is emitted for this internal handoff.

## Self-reference attribution plan (not executed)

Root read `checks/origin-recurring-consumer.js` and the stage1 calibration
script. The authentic check pins modules25/functions1013/calls6425/origins583
and one precise assertion allowlist entry. These are source-dependent guards,
not Tezos baseline metrics. Neither file is currently in implementation scope.

Do not run or repurpose stage1 `calibrate.js` unchanged: it reads the stage1
manifest and asserts engine equality on both source corpora. Stage2 deliberately
changes engine resolution, so equality cannot be presumed. A later stable-source
2x2 qualification must separately attribute source changes and actual engine
changes, preserving exact call-row multiplicities and origin groups, before any
specific reference update is proposed. Capture both producer binaries and
pre/post source state, and clean only exact temporary trees created by that run.
No extra worktrees or builds have been started for this preparation.

## Whole-CMT repair checkpoint

Terra completed the bounded lifecycle correction. Root inspected the resulting
source: main finalizes after `iter_structure_items`, flat after its whole walk;
registered occurrence tokens retain binder/head, supplied-expression and omitted
slot counts, and existing-residual status. Root stored/rejected notifications
check exact physical body and canonical binder name; absent notification seeds
dropped_node at finalization. Per-candidate expansion keeps arity separate and
adds an overapplication residual only when one was not already emitted.

Reported commands passed:

```sh
rtk proxy opam exec -- dune build lib/arch_index/arch_index.cma tezt/tests/main.exe
rtk proxy opam exec -- dune runtest lib/arch_index --force
rtk proxy opam exec -- dune exec tezt/tests/main.exe -- --file tezt/tests/ocaml_cfa_foundation.ml
rtk git diff --check
```

The authentic alias test passed1/1. Two direct private expansion checks cover
mixed arity and omitted-slot/opaque/residual behavior. These additional checks
were added after the refactor, not demonstrated as a new pre-implementation RED.
They use boolean inline tests, not new assertion-policy exceptions. Root's
inspection is not independent Roster review or a full-suite pass.

Flat still only has an availability notification, not faithful unique mapping.
Its bounded caller/target identity guard is the next assigned subtask, beginning
with an authentic duplicated-caller RED. Literal reconciliation, local lets,
joins, broader metadata coverage and the independent oracle remain open.

## Flat identity guard — authentic RED/GREEN, review follow-up

The duplicate-caller fixture first failed with zero TOP rows instead of two,
and two bounded f rows instead of zero. The guard then passed the authentic
main/flat fixture, including a shadowed target and inter-file homonym; targeted
build, private inline checks and diff hygiene also passed. CFA provenance is an
ephemeral marker removed before flat serialization, not a persisted vocabulary
addition. Safe new candidates force the same file, unknown candidates force NULL.

Root review requested two further controls before accepting this subtask:
restore a nonambiguous flat alias-chain positive (duplicate callers had replaced
that exact earlier positive), and count actual CMT root declarations as well as
LSP rows. A collapsed/missing LSP duplicate must not make two actual callers
appear unique. These follow-up checks are in progress; no full-suite GO or
independent Roster review verdict is implied by the targeted pass.

## Root full-suite checkpoint — 338/345, exit1

After the flat follow-up, root ran a complete build (exit0) and forced full
suite with output retained in `improvement/2026-09-16-cfa/slice1-runtest.log`.
All345 Tezt tests ran:338 passed,7 failed. Source inventory273 files and all
four captured executables were unchanged before/after. Source digest
6165a3a0c63fd165762ac92b85a1ceee6df9abc9ba64f533e745ea3bd39c1fd3;
log digest3aaf0324aa0ea40238c1265486a9f5a3ad8a6f39385c0670ac502b01bb27ae5d.
The ignored slice1-pre.json/post.json retain exact binary digests and inventory.

Exact failures:

1. Point-free underapplication: obsolete alias-name/MAY_TOP assertion.
2. Point-free god-modules: old1 count vs newly resolved ordinary call count2.
3. Self-index golden:27 modules/1056 functions/6643 calls vs25/1013/6425.
4. Open-body flat compatibility: source binder spelling0 vs2 expected.
5. Local-value unqualified alias: old TOP assertion.
6. Forced-flat native probe: new inline extension in copied plain
   call_graph_extractor.ml fails to compile (`Uninterpreted extension 'test'`).
7. Authentic origin recurring consumer: nonzero result; requires measured
   source/reference/policy attribution, not a presumed source-only waiver.

Failures4 and6 are new concrete compatibility regressions, not obsolete
expectations. They are assigned back to implementation without changing the
historical tests. The full run also establishes the previously unlocated fifth
failure was not shown eliminated by the earlier focused run. No references,
ratchets or allowlists have been changed. No review/QA/ship phase completed.

### Targeted repairs after the full run

The implementer repaired both compatibility regressions without modifying the
old tests: unsupported root RHSs are no longer enrolled merely because a cell
exists, and the uniqueness helper/inline control moved into the preprocessed
CFA module. Exact open-body flat and forced-flat native titles both passed,
as did the CFA fixture, inline tests and targeted build.

Root updated the already-in-scope local_value_targets expectation for the one
newly supported root alias: actual local_base target, MAY/null ordinary edge,
no MUST or stale TOP, and preserved immediate predecessor. All nested-module
refusals remain. Its exact Tezt title passed1/1. This is documented semantic
expectation migration under the validated spec, not a golden/count waiver.

The last FULL result remains338/345. These three subsequent targeted repairs
do not establish a new full-suite total. Point-free exact-file scope approval
remains pending; self-index/origin references await measured attribution.
The next assigned subtask is same-callable local alias flow with physical-owner
capture refusal, tested before product changes. No joins/literals claimed yet.

### Same-callable alias checkpoint

An authentic local-alias fixture produced three failing assertions before the
change, including absent main and flat targets. A preceding fixture warning
configuration failure was setup, not counted as RED. After implementation,
local_run reaches local_root in both producers, a captured local alias remains
callback_param, and a unit alias remains visible in a genuinely nested lambda.
Targeted CFA, private inline checks and both flat compatibility titles passed.

Root requested stricter negative assertions (not merely presence of TOP but
absence of a captured bounded target), a local-in-initializer capture control,
and an opaque owner type rather than exposing owner integers through the private
interface. Those follow-ups are in progress. No branch/literal result flow or
new full-suite total is claimed at this checkpoint.

### Resume checkpoint — 2026-09-16

Root revalidated the full ledger schema, all three context input digests,
`opam exec -- dune build` (exit0), nonexecuting Tezt collection (exit0), and
review bundle22 hashes (exit0). No new full-suite result is implied.

The subsequent local-alias controls include an absent-bounded-target assertion
for captures, initializer capture, and session-local opaque owner tokens. Named
if-joins have targeted evidence. A previous handoff added match/sequence code
without the required prior fixtures; these forms require honest post-change
coverage, not a fabricated TDD claim. Sol now owns source/build for the bounded
named-value join tranche, including genuinely test-first root branch bindings.
Root prepares literal reconciliation read-only and updates these artifacts.

The installed OCaml5.3 Typedtree confirms that match computation cases (field2)
contain ordinary and exception cases, and field3 contains effect cases. The
previous expression builder traversed only field3, so ordinary match result
flow was not actually implemented. Explicit fixtures must cover this loss.

### Named-join full-suite checkpoint — 341/345

Sol's real root-branch fixture first failed `branch_run` with0 targets instead
of2. The implemented root/local/direct named joins then passed the targeted
CFA fixture. It now checks known plus callback together, match ordinary and
exception RHSs, pattern-bound unknown plus known, and guard/scrutinee/sequence
prefix call preservation. No literal or application-return transfer is claimed.

The complete forced suite finished at06:44:44 with345 played and4 failures
(341 passes), exit1. Root inspected the complete failure entries. Log:
`improvement/2026-09-16-cfa/named-joins-runtest.log`, SHA256
`b3f9bb1a3d63b3dd93e27e823e204b654b1aa6cade92b6918f4e29d29b9ed2c0`.
Remaining failures are the two point-free expectations, self-index golden
(actual27 modules/1078 functions/6813 calls versus25/1013/6425), and the authentic
origin consumer. No reference or policy waiver was applied. This run predates
removal of the two now-unused specialized join helpers; the cleanup passed
the targeted build/CFA/diff checks, not a second full suite.

The next literal tranche is delegated to Sol. Root concurrently adds the
standalone native kernel oracle in disjoint files, with no concurrent builds.
Stage2 remains in implementation; no review/QA/ship event is appended.

### Literal and physical-identity checkpoint

Sol added literal descriptors keyed by physical expression, collector-observed
names/owner/arity, and actual main storage acknowledgement. Targets are seeded
only at finalization, with final name uniqueness and conflict refusal. Root
review caught missing-observation reason handling, a spurious root-literal
callback, and late name/owner conflict hazards; targeted fixes were applied.
Real fixtures cover two selected stored lambdas, known-plus-callback, a local
literal alias, root literal joins, no spurious closed-flow TOP/MUST, and exact
flat TOP tuples for unrepresentable synthetic targets.

Sol's literal full run finished345 played/4 failures, exit1, before those last
corrections. Its log is `improvement/2026-09-16-cfa/literals-runtest.log`; it is
not final-head qualification. The same four expectation/reference failures
remain; no baseline was relaxed.

Root then added actual-CMT physical identity controls to the existing Tezt
fixture. Two distinct native literal records share one ghost position; the
real collector assigns two distinct names including collision ordinal#2, and
the application retains exactly those two targets. Fresh-session controls cover
missing observation, missing storage, wrong physical body, wrong owner, late
duplicate name and late conflicting owner/name. Two same-position application
records receive distinct tokens, with exact value and metadata checks.

Private CMT interfaces are deliberately hidden from public consumers. Initial
test compilation failed on that setup boundary, not a behavioral assertion.
Tezt now has a test-only include of Dune's already-hidden private CMI directory;
the library's private_modules and installed API are unchanged. A discarded
lib-private directory dependency and discarded preprocess dependency attempt
were setup failures, not RED evidence. Final scoped build, targeted CFA Tezt
and diff-check passed. These controls are post-implementation coverage.

Root launched a fresh full forced suite with402 code/build inputs and five
executables captured before execution. `identity-runtest.log` is its ignored
log. Source digest before execution:
`5124d541ed163f49fe4d95021ea0f10f8e4f2756d21e3af5e06b09eb1f3cc561`.
The402-file inventory also includes JS/SQL/shell gates and is not directly
comparable to the earlier ML/build-only273-file count. No result yet claimed
for this run until completion and post-run identity verification.

The root run completed at07:12:47:345 played,341 passes,4 failures, exit1.
All402 code/build-input hashes and all five executable hashes are identical
before/after. The standalone kernel suite passed6/6. Exact identity and log
digest are persisted in `identity-full-run.json`. The four failures are the
same point-free x2/self-index/origin controls; nothing was waived.

Preliminary independent test review found a raw-lambda count hidden behind
`sort_uniq`, and omitted explicit Dune dependencies for five fixture files.
Root added the raw-count assertion and complete dependency list after the full
run. The reviewer's initial late-conflict objection was based on the old source
and was withdrawn after rereading: current storage acknowledgement never seeds;
finalization authenticates each descriptor before seeding. No monotone target
was removed. This preliminary audit is not the formal Roster review gate.

The post-review-strengthening targeted CFA test completed at07:14:18, exit0.
No source/build subprocess remains active and no new worktree was created.
Implementation remains open. Next: occurrence metadata/arity/channel controls,
permanent CHECK1–3 and Tezos replay, and measured expectation/reference repairs.
The exact-file point-free expectation scope question is still unanswered; do
not silently add it to the manifest or change the self-index/origin references.

### Occurrence metadata checkpoint

Sol completed authentic metadata fixtures and root examined the pending-call
assertions. Coverage now includes two same-line applications expanding to four
rows, actual match `c_guard` calls, conditional/dead occurrences, tuple/curried/
function-cases/labeled arities, an omitted labeled slot, and two known
overapplication candidates with an independent opaque frontier and one residual.
Database links check exception and result scopes. Raw real-CMT collector tests
check partiality and copy of site/conditional/dead/scope metadata; cardinalities
guard against vacuous `List.for_all`. Correction2026-09-16: this checkpoint
originally claimed a synthetic unknown-arity expansion control. Independent
preparatory review and root inspection found no such assertion in the actual
CHECK2 test. That coverage was missing, not qualified; a real-CMT session with
an injected nonpositive arity callback is now assigned as a test-only addition.

The full metadata run finished at08:09:14:345 executed,341 passed,4 failed,
exit1 (`improvement/2026-09-16-cfa/metadata-runtest.log`). The same two point-free
expectations and self-index/origin reference checks remain. These are failures
on this branch, not an assertion that the pre-edit baseline was broken.
Root verified all four failure events and the log SHA256:
`e776a74825e4fb1ab679ac7ecb96d1b7775a7fcfe91e50eae60753c298494c26`.
Subsequent assertion strengthening received a successful targeted rerun, not a
second full qualification. No production change was needed for this tranche.

The next non-OCaml tranche is the permanent CHECK1 independent oracle and CHECK2
native/consumer wrapper. CHECK3's exact-accounting boundary is recorded in
`corpus-check-design.md`; the earlier preliminary Tezos measurement remains
descriptive only. No phase-completion, review, QA, or ship verdict is implied.

### Standalone CHECK1/CHECK2 and scope stop

Terra implemented CHECK1 and its explicit injection self-test; Sol implemented
CHECK2 and authentic main-query assertions. Root reviewed both scripts and
required fresh builds (no stale executable acceptance), nonvacuous case lists,
and setup/assertion classification controls. Both agents completed their bounded
handoffs and released the build token.

Root reran normal CHECK1:517 cases pass, exit0. Root reran its checker self-test:
exit0, including real subprocess0/1/2 controls. Root reran normal CHECK2 after
explicit fresh executable builds:1/1 native test, exit0, completed08:19:42.
Main queries assert no MUST path for the CFA candidate, positive may-reach,
UNKNOWN through an opaque frontier, and caller exclusion for point-free aliases.
Delegated CHECK2 controls cover assertion1, setup2, compiler-source assertion
text2, empty false-success2 and invalid option2. These are control tests, not
substitute native evidence. No new full-suite pass is implied.

The implementation now pauses on the explicit point-free exact-file scope
question. CHECK3 and self-reference attribution are also still unfinished.
The impl brief records PARTIAL for this scope blocker, not simply because tests
are red. No commit/review/QA/ship is claimed; task slot stays active for resume.
Old Tezt temp-directory warnings are not ownership proof and do not authorize
deleting those directories. No unrelated worktree or artifact was removed.

### Approved point-free migration and qualification

The user approved the exact point-free file on resume. Root extended the
manifest without changing its base/dirty exclusions; Sol migrated only the
supported call expectations and retained the seven alias exclusions. Targeted
point-free5/5 passed. Root forced full suite then ended09:52:01 at343/345,
exit1, with only self-index/origin failures remaining. Log SHA256
`46723b9e30593ca8e28be9f8352b13c3be5ec7e7ffb50670541ca72a4def7bd3`,
`improvement/2026-09-16-cfa/point-free-runtest.log`. This is not final-head CI.

CHECK3 now exists and passes on the authentic410 CMT corpus after fresh build:
same digest a4fbf084… as the preliminary observation, exact8 removed/10 added,
three relation gains/no losses/no newMUST. Producer/schema copies and selected
hashes are checked; old frozen artifacts are unchanged. Success publication
follows temporary cleanup. Its initial shadowed-variable report-publication
failure was corrected and followed by a fresh successful replay, not called GO.
Root verified its generated report and pure tests; see tezos-delta-explanation.md.

Root executed and examined the self-index2x2 diagnostic. Full call/origin arrays
and populations are equal on each fixed corpus (A=B,C=D); source growth explains
25/1013/6425/583→27/1082/6804/603. Source-block equality plus actual origin rows
ground a coordinate-only relocation of the sole existing assertion exemption.
All owned archive/build trees are removed. See self-reference-evidence.md for
exact pins, matrix, setup failures and limitations.

Implementation pauses only on the new four-file reference/coordinate approval
question. No references, policy, ceiling, rules or baseline have been modified.
Next is approved reference migration, full gates, committed task-owned diff and
independent Roster review/QA/ship. The three CHECK scripts passing does not
override the still-red full suite or grant a merge.
