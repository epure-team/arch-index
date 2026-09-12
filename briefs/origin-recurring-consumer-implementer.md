# Implementer Brief — origin-recurring-consumer

**Date:** 2026-09-12
**Status: VALIDATED**
**Mode:** full

## Assignment

Implement all three vertical increments below via roster-implement and tdd-workflow. Preserve
existing production libraries/evaluator/schema/verdict/allow identities and every old CI gate.
Root owns manifest/ACTIVE_TASK before baseline. Single shared worktree; never create another.
No global tool changes, no vendor edits, no unrelated files. All local edits apply_patch.

## Files to modify or create

- scripts/origin-consumer.js (create): narrow --out consumer/exported owned-fixture seam.
- scripts/origin-consumer-artifacts.js (create): read-only package integrity validator.
- checks/origin-recurring-consumer.js (create): authentic/failures/package standalone checks.
- test/fixtures/origin-consumer/ (create): self.rules/self.allow/reference.json and native fixture inputs.
- tezt/tests/origin_recurring_consumer.ml (create): three modes and checker-exit controls.
- tezt/tests/main.ml and tezt/tests/dune (modify only registration/dependencies as needed).
- .github/workflows/ci.yml (modify only dedicated consumer/validator/14-day known-file retention).
- docs/origin-consumer.md (create), README.md and CHANGELOG.md (document/link feature).
- briefs/, roster/origin-recurring-consumer/, specs/origin-recurring-consumer.md,
  skills-meta/friction.jsonl (pipeline evidence only).

## Sequential steps

1. **Native complete success package (test-first).** Add a failing native clean fixture check,
   then the shared runner's complete discovery/index/evaluate/report/provenance/publication path
   and read-only artifact validator. One coherent package is independently demonstrable outside
   production CI. No synthetic DB substitutes for this authentic path.
2. **Adverse outcomes (test-first).** Add native new/count controls and labelled injected fault,
   population-drift, mutation, output-ownership, parity, timeout/overflow and publication tests;
   extend the same runner and validator. Correctly observed expected runner exit1 makes checker
   pass0; deliberate checker assertion1 and execution2 controls stay distinct. Complete tests
   before declaring this capability done.
3. **Production adoption (test-first).** Pin reviewed self.rules/self.allow/reference and assertion
   rationale, register controls in Tezt, exercise actual fixed production CLI, integrate consumer,
   separate retention validation and known-file upload into existing build job, document operations.
   All existing gates plus authentic/failures/package modes and exact-head CI must pass before merge.

## Quality Gates

- Build: `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune build --root . @install`
- Full suite: `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune test --root . --force` (baseline and green verification, terminal exit required).
- Whitespace: `rtk proxy git diff --check` (no separate formatter configured).
- `rtk proxy node checks/origin-recurring-consumer.js authentic`
- `rtk proxy node checks/origin-recurring-consumer.js failures`
- `rtk proxy node checks/origin-recurring-consumer.js package`
- Fresh production `rtk proxy node scripts/origin-consumer.js --out <new-owned-leaf>` then
  `rtk proxy node scripts/origin-consumer-artifacts.js <same-leaf>`; create parent with mktemp -d,
  no literal-placeholder execution. Record real measured corpus/status/package evidence.
- Existing self golden/recalibration/reach rules/impact smoke: current CI commands unchanged.
  Root QA executes them and exact-head remote CI checks all before ship.

## Risks and assumptions

| Risk | Mitigation |
|---|---|
| Compiler fixture identities | Pin native line/function/count details; investigate differences, no auto-regeneration. |
| Reporter field compatibility | Use current existing reporter contract; shared-field validation, not guessed extra schema or changed evaluator. |
| Output/cleanup or mutation | Exclusive leaf ownership, same-run hashes, final marker last, errors visible; no atomic-filesystem claim. |
| CI loses evidence/masks failure | Independent status-aware validator then upload after actual consumer start, known files only, no continue-on-error. |
| Tests look green after execution failure | Checker0 means expected results verified,1 assertion,>=2 execution; deliberate controls. |
| Fixed counters drift on legitimate change | Manual reviewed reference edits; separate allow-list; no completeness claim. |

No extra formatter/coverage framework installed; report coverage limitations honestly.
Native fixture build and temporary DB cleanup are owned, terminal command results mandatory.

## Complete bounded contract (intake, normative)

# Intake Brief — origin-recurring-consumer

**Date:** 2026-09-12
**Status: VALIDATED**
**Type:** feature
**Trust boundary:** yes

## Goal

Make arch-index itself a recurring, non-vacuous consumer of its shipped `forbid origin`
capability: review new escaping assertion/division sites in the existing bounded OCaml library
corpus on every CI run, retain gate/report/coverage evidence, and distinguish a policy gate
holding from a completeness proof. The reference is the owned `lib/arch_index` corpus at main
`d7112964df679fb44bc033e878059537208f58da`; current checkouts remain the live subject of the gate.
Pin reference revision, module inventory and observed coverage in versioned review data rather
than pretending future source revisions remain byte-identical to the reference.

Two independent values: (1) a real CI regression consumer on production library code; (2) a
bounded authentic-control harness demonstrating that it detects a new/increased origin and
rejects incomplete measurement. Synthetic controls validate the consumer, not its deployment
adoption. Reports expose concrete sites, coverage and limits; no reviewer-time saving is claimed
without measurement. This precedes the separate arch-guard value-analysis experiment.

## Scope Boundary

Included: dedicated self-origin rules/allow-list/reference metadata, a small repository-local
runner, authentic controls and Tezt registration, CI execution/artifact persistence, usage and
reference-update documentation. Reuse Arch_rule_eval through existing arch-rules/arch-report
CLIs. Preserve the existing four reachability rules and all existing CI gates unchanged.

Out of scope:

- Third-party targets, vulnerability hunting, exploitation or campaign automation.
- New abstract-value engine, division suppression, interprocedural summaries, array analysis.
- Changes to origin extraction, verdict policy, counted allow identity or public report schema.
- Automatic allow-list regeneration, automatically accepting a coverage drift, formal proof.
- Generic corpus discovery/download, new external corpus checkout or extra durable worktree.
- MCP, release/deploy, global tooling changes or vendor roster bundle changes.

## Relevant Files

| File | Role | Key snippet |
|---|---|---|
| `lib/arch_tools/arch_rule_eval.ml` | Reuse existing origin evaluation, no change planned | `Origin (s, forms, channel, allow)` |
| `bin/arch_rules/arch_rules.ml` | Gate JSON and exit policy | `computed`, `failing`, `results` |
| `bin/arch_report/arch_report.ml` | Publish evidence, not policy gate | optional `--rules` |
| `docs/fitness-functions.md` | Existing counted-exemption contract | no automatic `--regenerate` |
| `arch-rules.txt` | Existing reachability consumer, preserved | four `forbid reach` rules |
| `.github/workflows/ci.yml` | Add separate origin consumer and retained report artifacts | self-index at line 128, existing rules at 292 |
| `lib/arch_index/dune` | Existing production corpus build, no change planned | library with inline tests |
| `lib/arch_index/arch_index_cmt.ml:1374` | Review existing assertion allowance | nonempty `segs`, `split_last [] segs` |
| `tezt/tests/actionable_review_reports.ml` | Standalone checker/Tezt pattern | exact exit mapping controls |
| `tezt/tests/rules_origin.ml` | Existing authentic CMT and counted-origin tests | multiple sites and 201 caps |
| `tezt/tests/dune`, `tezt/tests/main.ml` | Wire new registered controls | CLI dependencies and registration |
| `docs/adr/001-self-index-golden.md` | Existing pinned measurement workflow, preserved | committed self-index counts |

New paths to freeze in plan: `scripts/origin-consumer.js`,
`checks/origin-recurring-consumer.js`, `tezt/tests/origin_recurring_consumer.ml`,
`test/fixtures/origin-consumer/` reference/rules/allow data, and `docs/origin-consumer.md`.
README/CHANGELOG may link and describe the consumer. Task briefs/spec/roster/friction artifacts
are in scope. No production library modification is needed by this brief.

## Architecture Notes

### Measured intake probe (not feature acceptance)

Fresh built CMT self-index from the current checkout: 23 modules, 828 functions, 5223 calls.
SQLite enumeration observed 491 origin rows across channels; exception assert=1, division=0.
Rule `file:lib/arch_index/** form:assert,division channel:exception` with an empty allow-list
returned VIOLATION, exit 1, exactly the existing assertion at arch_index_cmt.ml:1388.
With one manually authored x1 entry, the SAME indexed corpus returned UNKNOWN, gate exit 0:
coverage 1045 graph nodes (including external nodes), one selected origin/site, one matching
allow entry, 138 top-bearing nodes reported by the existing note. This is not 1045 source
functions or a proof that no fatal origin exists. Neither probe changed source or evaluator.

Existing assertion identity:
`collect_calls_from_expr.<fun:1374:21>.<fun:1385:36> | lib/arch_index/arch_index_cmt.ml:1388 | assert | Assert_failure | x1`.
Source review: split_last is called only with a nonempty segment list; its recursive multi-item
case reaches a singleton before the empty case. This justifies one explicit initial allowance
under delegated review, not a machine-checked invariant or an automatic exemption generator.
The spec/review must challenge it; source/identity changes require a deliberate reviewed edit.
Zero current division sites is a baseline observation, not proof that division detection works;
the authentic injected-division control must supply that separate evidence.

### Runner and reference contract

- Repository-local invocation: `node scripts/origin-consumer.js --out <new-output-directory>`
  after the documented build. It creates a fresh index from the bounded built library itself;
  no arbitrary preexisting DB input, no source mutation or internal Dune rebuild. Reindexing is
  cheap and avoids claiming an externally supplied DB belongs to the current corpus.
- Reference module paths and a reference observation are pinned to d711296. Each run records
  current revision, rule/allow/reference identity, schema/error configuration and actual input
  inventory/digests. This is provenance under a trusted local build assumption, not a source
  freshness certificate; CMT bytes can vary with compiler/build path and are not global pins.
- Missing/extra module population relative to the reviewed scope or an incomplete/empty index
  is an explicit coverage failure, never a clean result. Reference source revisions and counts
  are observations, not an excuse to suppress new sites. Existing golden/recalibration gates
  remain independent. Changes to scope require deliberate reference edits.
- Reuse arch-rules for policy and arch-report for artifacts. Unknown is permitted as UNKNOWN
  (as in the established gate policy); violation always fails, vacuity/NOT_COMPUTED/refused
  execution never pass. Report exit 0 alone is never gate evidence.
- Retain gate JSON, report JSON/SARIF/HTML and a machine-readable run/coverage record on success
  and policy failure. Record corpus-wide raw counts separately from the evaluator's opaque
  per-rule coverage note; do not parse prose into a claimed stable structured API or duplicate
  origin graph/allow evaluation. Failure artifacts must identify incomplete execution.
- Output directory must be newly created and owned; refuse preexisting output to avoid stale
  success artifacts or overwrites. Remove transient DB/build fixtures, retain only useful
  reports/diagnostics. On an I/O error, incomplete reports are not publishable as a successful run.
- Exact controls: authentic clean/allowed case, new division site, increased same-site count,
  empty/wrong/incomplete corpus, unavailable origin pass and tool/execution error. Assertions
  must inspect verdict/details and real exits; test runner errors are not expected violations.
- CI runs this consumer within the existing required build job and uploads compact reports
  even when the origin policy fails, with bounded retention. No database or build tree uploaded.

Claims reconciler, freshness authority, KB and hooks are absent. No authority projection is
claimed. Trust boundary yes reflects converting measured artifacts into a CI success signal;
Full feature route chosen under standing autonomy, not a formal-verification route.

## Binding spec refinements (planning input)

The resolved obligations below are part of this validated intake, not optional external
spec context. They refine the same approved scope; implementation planning reads this brief.

### Adversarial resolution — origin-recurring-consumer

Fresh Sol challenger raised C-1..C-20 and EC-1..EC-16. All resolved within the approved
owned-repository consumer scope, by source inspection and bounded design decisions under standing
autonomy. No new human answer, evaluator extension, or completeness proof is claimed.

| ID | Story | Challenge | Resolution |
|---|---|---|---|
| C-1 | US-1 | Counter vector ambiguous | Reference version 1 has modules/functions/calls/origins nonnegative safe-integer totals and origin_groups records keyed by the tuple channel, form, escapes (escapes integer 0 or 1). Duplicate groups invalid. Compare union of keys with absent count zero; ordering is irrelevant, display lexicographically sorted tuples and signed current-minus-reference deltas. Totals must agree with group sum. Initial totals 23/828/5223/491; groups exception/assert/1=1, exception/compare/1=34, exception/failwith/1=18, exception/index/1=106, exception/invalid_arg/1=1, exception/reraise/1=4, option/raise/1=282, result/raise/1=4, result/unknown/1=41. All other groups zero. |
| C-2 | US-1 | Exact rule population absent | Exactly one production declaration named `self escaping assertion and division origins`: `forbid origin from file:lib/arch_index/** form:assert,division channel:exception allow-file:test/fixtures/origin-consumer/self.allow`. Dedicated `self.rules`; preserve existing arch-rules.txt. Explicit gate flags --on-possible fail --on-unknown warn --on-vacuous fail --on-not-computed fail. Compare non-comment normalized declaration with this bounded contract, not a general second parser. |
| C-3 | US-1 | Substituted/truncated configuration or JSON | Hash actual rules, allow, reference, schema, tools before/after execution; changes during run are error. Validate production declaration and exactly one result with ordinal1, expected rule name and origin kind, computed=true, contract_ok=true, known verdict, internally consistent census/failed list/exit. Missing/extra result or malformed field is error. Report receives identical DB/config. This is trusted local execution, not protection against a malicious replacement tool that lies consistently. |
| C-4 | US-1 | Mixed-failure precedence | error2 outranks policy-failed1 outranks coverage-drift1 outranks held0. Keep independent policy outcome and all measured coverage deltas in run.json, including on error when already validated. A stale allowance is existing evaluator evidence only, not a new policy reimplementation; moving an identity produces an uncovered site through the evaluator. |
| C-5 | US-1 | Other verdicts | PASS/UNKNOWN with correct gate exit0 are eligible; VIOLATION/POSSIBLE with correct exit1 are policy-failed. NO_SOURCE, NO_TARGET, NOT_COMPUTED, UNKNOWN_NO_CONTRACT, false contract or inconsistent gate exit/census are error2. Never interpret ordinary UNKNOWN as proof. |
| C-6 | US-1 | Authentic controls could bypass orchestration | Clean/new/count controls all invoke the same exported runner through discovery, fresh indexing, provenance, counters, real rules, real report, validation, publication and cleanup. Only explicit owned root/build path/reference/rules/tool paths differ. Fault-injection tests are separate and labelled; production CLI cannot expose their seam. |
| C-7 | US-1 | Fixture identities/counts unspecified | Owned native fixture `consumer.ml`: line1 `let allowed d = 10 / d`; clean allow identity `allowed` at consumer.ml:1 division/Division_by_zero x1. New-site variant adds line2 `let fresh d = 20 / d`; counted variant line1 `let allowed d = (10 / d) + (20 / d)`. Assert native evaluator detail names fresh line2 x1 or allowed line1 x2 respectively and actual exit1. Compile independently with the configured OCaml compiler; compiler-induced identity differences fail the control, never regenerate expectations. No precomputed DB/JSON can satisfy authentic controls. |
| C-8 | US-1 | Assertion allowance can broaden | Initial self.allow has exactly the intake's full function/location/form/exception identity x1 and nonempty split_last rationale in comments/docs. Tests pin this initial literal allowance. Deliberate future changes must update tests and rationale in review, not a hidden regeneration command. |
| C-9 | US-1 | Reference and allowance edits independence | Separate versioned artifacts with separate rationale in docs/PR. Same PR may edit both explicitly; no gate can mechanically establish reviewer intent. Reference comparison never changes evaluator inputs/exemptions. Controls prove matching changed counts cannot excuse a new site. No claim this detects intentional coordinated weakening or every population loss. |
| C-10 | US-1 | Inventory normalization/symlinks/generated modules | Record repository-relative POSIX source paths and build-root-relative CMT paths, lexical sorted unique inventories and SHA256 per file. Require inputs under the fixed source/build roots; reject CMT symlinks/duplicate canonical CMT paths. Source .ml inventory must match the reviewed module paths, and indexed modules separately match it; no one-to-one CMT count requirement (Dune inline-test generated CMTS are recorded, not counted as extra source modules). Missing/extra modules are coverage-drift if a valid nonempty contracted evaluation remains possible, otherwise error. Reference paths reject absolute paths, traversal, duplicates. |
| C-11 | US-1, US-2 | Git/dirty provenance | Require resolvable Git HEAD and repository root; detached HEAD valid, outside Git error2. Record whole-tree porcelain dirty state and actual scoped source/CMT bytes including untracked inputs. Dirtiness alone, including unrelated files, does not fail; inventories and raw counters still gate. Hash inputs again before final publication; concurrent scoped mutation is error, not a snapshot/freshness certificate. |
| C-12 | US-2 | Cross-artifact consistency | Gate results and report JSON rule_results must agree on every shared field, normalizing only omitted exact=false and report-only evaluator. Require report verdicts_status COMPUTED and matching contract/census; SARIF top-level properties.rule_results equals report rule_results and rules-run result IDs/verdicts equal the non-PASS rule alerts. HTML must be nonempty complete document containing escaped expected rule name/verdict; pin deeper site/context fidelity in authentic package tests using existing reporter contract, not a general HTML parser. run.json includes SHA256 of final gate/report files and independent status/coverage fields. |
| C-13 | US-2 | Closed artifact contract | held/policy-failed/coverage-drift require six files: gate.json, report.json, report.sarif, report.html, diagnostics.txt (may be empty), run.json. error after output ownership requires run.json and diagnostics.txt when writable, optionally fully valid gate.json, no report trio. Early output or final record write failure may produce only stderr and exit2, never a complete marker. No DB/build/staging in upload set. |
| C-14 | US-2 | Missing-artifact upload on errors | Consumer step failure remains separately visible and cannot be overridden by upload. Retention follows when consumer step actually ran; an artifact validator first checks status-dependent required files and exits nonzero for unexpected absence. Early error with no files also makes retention fail explicitly. Upload known files with if-no-files-found error; it does not prove every required filename exists. Upload still attempts existing diagnostics after validation failure. Retention failure independently fails CI; no continue-on-error on consumer or validator. |
| C-15 | US-2 | Output ownership and races | Resolve an existing parent directory with realpath, then exclusively mkdir the absent leaf (not recursive). Existing leaf including dangling symlink rejected before writes; parent aliases are allowed and resolved to the recorded physical destination. No concurrent hostile parent renames/writers supported or implied; dedicated local/CI parent required. Only successfully created owned paths are cleaned. Enforce subprocess timeout 120 seconds and max captured output16MiB per command; abnormal exit/signal/overflow is error2. |
| C-16 | US-2 | Independent value | Reviewer package is independently useful on an owned fixture outside production CI and without a production reference deployment; test its publication/validation/error behavior with that fixture. It shares the runner foundation, not a dependency on US-1's production integration or rollout. Clarify story's independent test accordingly; no extra component required. |
| C-17 | US-1 | OPA explicit nonempty gate | Adopt explicit non-vacuity semantics using existing --on-vacuous fail/--on-not-computed fail plus one-rule structural validation and nonempty corpus/origin measurements; no extra CLI opt-out. This narrow fixed consumer has no need for OPA's general test-discovery option. |
| C-18 | US-1 | OPA structured coverage vs opaque note | Existing evaluator does not expose a structured origin-cone coverage API; scope prohibits changing it. Preserve exact note plus separate measured corpus counts and explicit contracted rule execution. Claim only nonempty measured run and no reference drift, not equivalent policy-execution coverage or completeness. |
| C-19 | US-1 | Semgrep Git differential baseline | Intentionally full current bounded corpus on both PR/main, reviewed raw-population reference only. Counted allow-list evaluates all visible origins independently of Git changed lines. No differential finding classification claimed; full-library scan is cheap and scope-limited. |
| C-20 | US-2 | SARIF baseline/run separation | Preserve existing arch-report SARIF unchanged; its findings and rule census are evaluator evidence. Consumer execution/coverage/current-reference outcomes live explicitly in run.json with artifact digests, never fabricated baselineState or SARIF invocation success. Documentation requires both records. Empty SARIF findings is legal only if consistent with report's non-PASS alerts; UNKNOWN must remain represented by current reporter. |

### Edge-case outcomes

- EC-1/2: absent groups zero, directional deltas; redistribution with equal total is drift.
- EC-3/9: changed assertion identity/line is evaluated against old allowance; uncovered site fails.
- EC-4: violation plus drift => policy-failed with both retained.
- EC-5: malformed extra/missing rule => error even with a valid violation; keep validated evidence.
- EC-6: no selected origins but nonempty origin pass and valid source selection can evaluate;
  reference selected-form group decrease causes coverage-drift, not an invented NOT_COMPUTED.
- EC-7: duplicate/symlinked CMT inventory => error before indexing.
- EC-8: changed compiler identity breaks fixture expectation, not automatic allow update.
- EC-10: unrelated dirtiness recorded, not itself a failure.
- EC-11: existing symlinked parent resolved; existing leaf always refused, including symlink.
- EC-12: divergent gate/JSON/SARIF shared evidence => error, no published report trio.
- EC-13: final record write failure => error; remove owned promoted report trio if possible,
  report cleanup failure to stderr; never leave a complete=true record for failed publication.
- EC-14: no output => consumer and retention visibly fail; no invented diagnostic artifact.
- EC-15: HTML disappears after completion => retention validation fails independently.
- EC-16: UNKNOWN with zero SARIF alerts contradicts existing reporter contract => error.

Error cleanup itself failing is error2 with stderr; no claim of guaranteed cleanup under broken
filesystem permissions. No source/CMT revision matching is certified by these observations.

## Quality Gates

Standalone contract checker: `node checks/origin-recurring-consumer.js authentic` for native
success/new/count controls; `node checks/origin-recurring-consumer.js failures` for refusal,
drift, malformed execution and publication failures; `node checks/origin-recurring-consumer.js
package` for artifact/provenance/retention contract. All check modes obey 0=pass, 1=assertion,
>=2=execution error. Their deliberate checker controls must demonstrate assertion1 and error2.
Production command after build: `node scripts/origin-consumer.js --out <new-directory>`.
Retention validator: `node scripts/origin-consumer-artifacts.js <owned-directory>`
is a separate repository-local script so the consumer CLI stays --out only.
That validator is read-only, validates required names/digests and status-dependent package
completeness, and must be exercised by the package checker. This small second script is in
scope solely for the CI artifact integrity gate, not a second analyzer.

Existing runnable gates:

```bash
rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune build --root . @install
rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune test --root . --force
rtk proxy git diff --check
```

No separate formatter/full-linter configured; known opam metadata lint debt is not passing.
Existing CI golden, attributed recalibration, four architecture rules and impact smoke remain
mandatory. New consumer/control commands will be frozen as runnable CHECK-N contracts in spec;
the paths above do not yet exist and are not represented as passing. Local and remote CI gates
must both complete with real exits before the exact-head PR merge.

## Open Questions

None delegated to implementation as TBD. Corpus, reference/current distinction, initial
allowance, scope refusal, artifact retention and authentic controls are pinned here and subject
to adversarial specification. Any material direction change must be surfaced to the user.
Validation uses explicit standing autonomous authorization; no new human quiz is claimed.
