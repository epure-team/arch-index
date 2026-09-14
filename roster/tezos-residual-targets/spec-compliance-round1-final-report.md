---
auditor: spec-compliance-auditor
date: 2026-09-14
status: 0 open critical, 0 open warnings, 0 open info
coverage: 35/35 claims reviewed; 33 locally complete; 2 retain downstream delivery obligations
---

# Round 1 final specification review

Reviewed product HEAD `436cbfc667a5f01880fd9c11f53242c8fffb6ed3` against `fb9c8f3f685d751ee07a81c17fb1ca61860a7365`. The product HEAD was verified again after all commands. Review-time pending changes were task documentation/evidence plus preserved unrelated user paths; no product changes occurred during this specialist's exclusive run slot.

The complete source contract is `specs/tezos-residual-targets.md`, including `spec-input.md` and `spec-resolutions.md`. Reviewed all17 FR,13 AC and5 CHECK claims, changed product/test/helper files, imported historical comparison code, current reviewer scope, self-attribution and pristine calibration evidence. The initial complete source review and subsequent exact repair review form one continuous specialist review; historical OPEN findings were not silently replaced. The report location adapts embedded mode to this task because KB is absent; no KB was created. IDs below are the local identifiers of this explicit feature contract, not a projected KB. Claims metadata remains draft.

There are no open specification findings on the reviewed implementation. This is a specialist result only, not an aggregate roster verdict or retention authorization. FR-017/AC-12 retain downstream delivery obligations; QA, exact-head hosted CI and rebase merge are not reported as completed.

## Prior CRITICAL disposition

Fingerprint: `spec:flat-alias-ownership-leaks-legacy-occurrences`, FR-007 / AC-5. **FIXED and independently verified**, not waived.

The initial native reproduction compiled both old and current extractors and actually exited1: new alias-owned target-name membership changed three legacy b.ml call facts. A separate pending probe established that direct calls, parameter calls and bare callbacks retained their original heads. This showed why merely testing Head_enumerated would not isolate qualified aliases.

The repair carries default-false `pending_call.local_module_invocation`, sets it at successful qualified application/callback/invoked-letop lookup, and consults that occurrence fact in flat attribution. Point-free and residual emissions leave it false. The independently repeated old/current native comparison then exited0: six legacy ordinary rows exactly equal, four qualified positive/refusal rows correct, two point-free rows equal. See `spec-repair-confirmation.md` and historical `spec-compliance-round1-report.md`; those artifacts remain unchanged.

On the committed repaired HEAD, CHECK-1 again executes the permanent forced-flat regression, pending provenance assertions, body-only/arity tests, storage rejection and all five new Tezt cases. The complete332-test suite also passes. This final evidence closes the original implementation divergence without weakening its acceptance criterion.

## Personally executed commands

Commands ran sequentially with `rtk proxy`, the task's local opam switch and an exclusive root build/test/producer slot. No report/source write overlapped CHECK-3 or CHECK-4.

| Gate | Exact command | Exit | Observed result |
|---|---|---:|---|
| Build | `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune build --root .` |0|Full build completed.|
| Full suite | `rtk proxy sh -c 'opam exec --switch=/home/mathias/dev/arch-index -- dune runtest --root . --force > improvement/2026-09-14-tezos-resolution/attempt2-spec-final-full-guard.log 2>&1'` |0|332 SUCCESS,0 FAILURE.|
| Bundle | `rtk proxy node scripts/review-bundle-verify.js` |0|22 files present and SHA-matched, bundle1.6.0.|
| Whitespace | `rtk proxy git diff --check` |0|No whitespace errors; repeated after checks.|
| CHECK-1 | `rtk proxy node roster/tezos-residual-targets/check-native.js` |0|Native both-context metadata and all5 Tezt cases passed.|
| CHECK-2 | `rtk proxy node roster/tezos-residual-targets/check-comparison.js` |0|38 assertions; native3 positive consumers/12 refusal controls; paired positive/10 refusals.|
| CHECK-3 | `rtk proxy node roster/tezos-residual-targets/prepare-baseline.js --check` |0|Fresh frozen neutral replay:45052 rows, Irmin4772/protocol11615.|
| CHECK-4 | `rtk proxy node roster/tezos-residual-targets/verify.js --witness improvement/2026-09-14-tezos-resolution/attempt2-reviewed-witness.json` |0|124 paired transitions; zero losses/errors;9Irmin/115protocol gains; retention_authorized=false.|
| CHECK-5 | `rtk proxy node roster/tezos-call-resolution/check-self-index-smoke.js` |0|Exact golden modules25/functions989/calls6275.|

Full-suite log SHA-256: `c6ca9ed2a6e143fd7e4f3297e4ef92f97fa0481faaae55a752aebdd1bb29652a`. The full-suite command's actual completion was session23910/chunk289506. CHECK-1 completed in session13843/chunk309223; CHECK-2 in20799/630547; CHECK-3 in94210/d76ce8; CHECK-4 in6177/a4ef22; CHECK-5 chunk6a9268.

Actual CHECK-4 output directory:
`improvement/2026-09-14-tezos-resolution/attempt2-2026-09-14T17-17-01-900Z-864282`.
It records45052 rows on each side,124 removed/124 added,0 relation losses,0 other-slice gains, baseline digest
`90e76d6b40b2d7f108fcc25523f85de1cb533a98565a8a7d6d284c1654939d4b`
and candidate digest
`00f1769d6db7f6ee91ee51becabccd7b4ce13975acb6610c95ace69a7f620e9b`.
The unchanged candidate digest demonstrates that the bounded flat repair did not alter the admitted rich-corpus movement. Its positive comparison is not permission to retain or begin attempt3.

## Compliance matrix

PASS means matching implementation with relevant tests and the actual local checks above. DELIVERY PENDING explicitly does not mean PASS for unperformed merge/CI/QA actions.

| Claim | Status | Implementation / evidence | Test | Assessment |
|---|---|---|---|---|
| FR-001 | PASS | arch_index_cmt.ml:1600,1637,2286 | CHECK-1; local_value_targets.ml | Applied, callback and letop qualified aliases select existing bodies. |
| FR-002 | PASS | arch_index_cmt.ml:1014,1054 | CHECK-1; local_module_targets.ml; CHECK-2 | Plain variable/bare arrow Pident/body eligibility; unsupported forms and opaque owners refuse. |
| FR-003 | PASS | arch_index_cmt.ml:1067,1129; check-witness.js:131 | CHECK-1/2/4 | Per-CMT compiler identity and complete owner chain; independent alias/body disagreement controls. |
| FR-004 | PASS | arch_index_cmt.ml:974,1054 | local_value_targets.ml:124; CHECK-1 | Original Shadow.base#1 retained; source-order replacement mask selects only current export. |
| FR-005 | PASS | arch_index_cmt.ml:2286; local_value_targets.ml:135 | CHECK-1 | One ordinary enumerated body head, null TOP/form; rejected body remains dropped_node. |
| FR-006 | PASS | arch_index_cmt.ml:2206,2244,2330 | CHECK-1 pending probe | Some supplied count, hidden syntactic arity, partial status and exactly one allowed return residual. |
| FR-007 | PASS — repaired | arch_index_cmt.ml:1384,1600,1637,2286; call_graph_extractor.ml:350 | Independent RED→GREEN; CHECK-1/full suite | Occurrence ownership restricts new flat attribution. Existing point-free, ordinary, CFG/channel/config consumers preserved. |
| FR-008 | PASS | call_graph_extractor.ml:350; check-flat.js:78 | CHECK-1 forced flat | Actual body display retained; absent same-file symbol yields NULL with foreign-homonym positive/refusal controls. |
| FR-009 | PASS | baseline.js:24,121 | CHECK-3 | Distinct frozen PR105 predecessor, exact45052/digest/4772+11615 pins; historical baseline unchanged. |
| FR-010 | PASS | prepare-baseline.js:19,79; baseline.js:101,185 | CHECK-3; preparation evidence | Fresh neutral frozen replay; producer/schema/input/source pins and canonical identity. Pre-product self run is historical, not re-claimed as newly executed. |
| FR-011 | PASS | witness.js:23; comparison.js:6 | CHECK-2/4 | Only ordinary paired same-site module_param TOP→same-file body transitions admitted. |
| FR-012 | PASS | witness.js:52,83; check-witness.js:131 | CHECK-2/4 | Replayed native evidence, exact positioned membership and one-time locator use; duplicate multiplicity/refusal controls. |
| FR-013 | PASS | witness.js:100; comparison.js:9 | CHECK-2/4 | Separate overapplication premise for residuals; point-free rows immutable; actual candidate adds zero residuals. |
| FR-014 | PASS | roster/tezos-call-resolution/comparison.js:151 | CHECK-2/4 | Zero relation loss/new MUST/unconsumed movement; distinct gains9Irmin/115protocol. |
| FR-015 | PASS | check-native.js:120; verify.js:125 | CHECK-1/2; native RED1 | Assertion and forbidden-movement paths deny keep; malformed setup/input/witness paths use>=2. |
| FR-016 | PASS | arch_index_cmt.ml:974 | CHECK-1 body table; local_value_targets.ml | Alias declarations remain absent from body table; unqualified alias calls retain prior behavior. |
| FR-017 | DELIVERY PENDING; guard verified | verify.js:107; reviewer brief | CHECK-4/5; downstream delivery | Positive candidate and local guards verified; retention_authorized=false. QA, hosted exact-head CI and rebase merge are not asserted complete. |

| Acceptance criterion | Status | Check | Assessment |
|---|---|---|---|
| AC-1 | PASS | CHECK-1 | Exact same-file MAY_ENUMERATED body heads. |
| AC-2 | PASS | CHECK-1/2 | Eligibility and compiler-identity/refusal controls; actual native evidence replay. |
| AC-3 | PASS | CHECK-1 | Original ordinal body and later masking; no retargeting. |
| AC-4 | PASS | CHECK-1 | Required/optional holes, compiler Some defaults, hidden-arrow partial and exact residual counts. |
| AC-5 | PASS — repaired | Independent RED→GREEN; CHECK-1/full suite | Six legacy direct/parameter/bare-callback rows preserved; qualified invocation gain retained; point-free unchanged. |
| AC-6 | PASS | CHECK-1 | Dropped actual body and missing-local-flat-symbol controls. |
| AC-7 | PASS | CHECK-3 | Fresh frozen neutral replay;45052 canonical rows and4772/11615 relations. |
| AC-8 | PASS | CHECK-2/4 | 124 exact witnessed pairs, multiplicity controls, separate+9/+115 gains. |
| AC-9 | PASS | CHECK-2/3/4 | Wrong provenance/input/run/witness controls and native-replayed positive. |
| AC-10 | PASS | CHECK-2/4 | New MUST, loss, point-free movement and duplicate deletion refused. |
| AC-11 | PASS | CHECK-1 | Body-only table and unqualified alias-call behavior unchanged. |
| AC-12 | DELIVERY PENDING; guard verified | CHECK-4 plus delivery | No neutral/unreviewed/unguarded keep; current candidate does not authorize retention. |
| AC-13 | PASS | CHECK-5 | Exact current self golden25/989/6275; no threshold or automatic refresh. |

All five CHECK claims are individually accounted for in the command table, not inferred from a different agent's run.

## Evidence interpretation and scope

The native one-hop witness is independent of product lookup. The constrained-signature UID case is admitted only with one same-CMT arrow-typed Value declaration and one plain Resolved implementation alias; it is not a fallback from competing concrete bodies to names. CHECK-2 exercises disagreement, missing declaration, malformed position, wrong snapshot/probe/evidence hashes, reused native locator and forged-rehashed evidence refusal. CHECK-4 actually recompiles/replays the probe before admitting the124 exact pairs.

Point-free lookup remains direct-only and immediate-predecessor alias facts stay unchanged. Applied alias arity uses actual syntactic body arity and supplied Some arguments; no stored arity/partial column is invented. Configuration-head classification and CFG/channel mechanics are unchanged; existing full-suite channel/scope tests run alongside the focused alias tests. Flat output gains no kind/TOP columns or nested caller coverage.

Current exact self-reference movement was not accepted as an unexplained refresh. Read `self-attribution-review-fix.md` and `pristine-repair-calibration.md`: the latter reports fresh four-cell SOURCE_ONLY calibration on the exact repaired commit, A=B25/980/6245 and C=D25/989/6275; unchanged ceiling537→538 within524±25. This specialist personally reproduced the exact current golden through CHECK-5 and the full authentic-consumer suite. It did not independently rerun the separate pristine four-cell experiment, and does not represent the coordinating agent's experiment as its own. The sole existing assertion allowance moves only to the same assertion's1559/lambda coordinates; no rule/cardinality/threshold relaxation is present.

No additional unspecified public feature was found. The new pending provenance field is internal consumer plumbing for FR-007/FR-008. No formatter/coverage or deterministic claims projection is configured, so none is labelled PASS. The coordinating agent reports a fresh cross-runtime120-second timeout/degraded run; that is neither independent approval nor a test pass and is not substituted for evidence here. Existing unrelated Tezt temporary-file warnings are historical and were not removed. No product/spec/reference file, PR, commit or worktree was changed by this specialist. Only final task report/findings are written after hash-sensitive gates.
