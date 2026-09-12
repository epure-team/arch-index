---
name: roster-spec
type: spec
status: live
feature: Recurring owned origin consumer
brief: briefs/origin-recurring-consumer-intake.md
date: 2026-09-12
version: 1.0.0
---

# Spec — Recurring owned origin consumer

## Clarifications

# Clarifications — origin-recurring-consumer

Fresh Sol clarifier produced eight questions before story drafting. All OPEN items below were
resolved by root within the approved bounded consumer scope; no unresolved item passed to
implementation and no new interactive human approval claimed.

| Q | Resolution |
|---|---|
| Closed runner terminal vocabulary and artifacts? | held=exit0, policy-failed=exit1, coverage-drift=exit1, error=exit2. held/policy-failed/coverage-drift require complete valid gate.json + report.json/report.sarif/report.html + run.json; diagnostics.txt retained. run.json distinguishes measurement completeness, coverage comparability and policy outcome. error never claims complete successful publication; retain run.json/diagnostics and valid gate.json if available, exclude partial reports. If output cannot be created or run record cannot be written, stderr+exit2 suffice; never touch a preexisting output path. |
| Same modules but partial population loss? | Exact reviewed module-path set AND exact reference raw counters (modules/functions/calls/origins grouped by channel/form/escapes, absent groups treated as zero) are compared. Any difference blocks as coverage-drift unless a real policy violation already supplies policy-failed. Existing golden remains independent. Counts are operational drift checks, not proof of complete population. Updates require manual review, never autoaccept/regenerate. |
| Are input digests a fresh-source certificate? | No. Record current source revision/dirty state, actual source and CMT inventories/digests, tool/config/rules/allow/reference identities and trusted-build assumption. Do not compare CMT hashes across machines as source pins; do not assert source-to-CMT correspondence mechanically. |
| Output directory versus arch-report prerequisite? | Runner creates a previously absent owned output directory, then an owned report staging subdirectory for arch-report; complete validated report files are promoted only after successful publication. Exclude/remove owned partial report staging on errors. No whole-filesystem atomicity claim; final run completion marker is written last. |
| Narrow fixture seam? | Internal JavaScript module API may accept explicit owned fixture roots/reference/rules/tool paths. Production CLI exposes only --out and remains repository-anchored; no --db, arbitrary target discovery or environment-only success bypass. Every authentic control uses built CMT and real indexer/rules/report CLIs; injected failures are explicitly separate controls. |
| Zero production division and counted increases? | Keep observation zero, prove detection with native fixture division at a new identity and a second same-line occurrence over x1 allowance; assert actual verdict, identity/count and process outcome. Clean/allowed native fixture must also succeed. |
| Initial assert exemption? | Exactly the measured x1 identity permitted, with documented nonempty split_last rationale under delegated review. Not value-analysis suppression or machine proof. Source/identity/count edits force deliberate review, no regeneration path. |
| Failure artifacts and retention? | CI runs dedicated consumer with step id inside required build job; upload compact known filenames when the step ran, using success/failure condition, not continue-on-error for the consumer. Retention 14 days, no DB/build or whole workspace. No artifacts required before consumer starts. Upload missing expected files must fail rather than silently warn. Error record is diagnostic, not a valid report set. |

Status precedence: malformed input/schema/contract, subprocess error, timeout, report validation
or I/O failure => error2; otherwise actual VIOLATION => policy-failed1; otherwise any policy
failure remains nonzero and explicitly recorded; otherwise reference drift => coverage-drift1;
held0 only with valid computed contracted gate, allowed PASS/UNKNOWN result, matching reference,
complete verified artifacts. NO_SOURCE/NOT_COMPUTED/UNKNOWN_NO_CONTRACT are measurement errors,
never ordinary successful UNKNOWN. Coverage fields preserve raw counts plus reference deltas;
the original evaluator note remains verbatim and separate.

The conservative count rule can fail on legitimate source evolution: this is intentional review
work, not attribution to a code regression. Updating observation metadata cannot excuse a new
origin: the separate counted allow-list and actual evaluator still govern it.

## User Stories

# Stories — origin-recurring-consumer

Derived only after the fresh eight-item clarification ledger was resolved.

### US-1: Review the production library's origin drift (Priority: P0)
As an arch-index maintainer, I want each required CI run to execute the existing origin policy
over the bounded built library and refuse silent coverage changes, so new visible fatal-origin
sites and degraded measurements cannot pass unnoticed.
**Why this priority:** establishes the missing real recurring consumer, using already shipped tools.
**Scope:** no value inference, third-party corpus, automatic exemptions, new evaluator or completeness proof.
**Independent Test:** invoke the local runner with the reviewed reference on owned built library;
inspect exit, gate JSON and coverage status without requiring a CI artifact download or HTML review.
**Acceptance Scenarios:**
1. **Given** reference d711296, 23 module paths, counters 23/828/5223 and 491 raw origins,
   the one reviewed assertion allowance and the trusted local build, **When** the maintainer runs
   the dedicated consumer, **Then** exit0, policy held with UNKNOWN remains explicitly unproved,
   and no observed coverage drift is asserted.
2. **Given** an owned native CMT control with an additional escaping division absent from its
   allow-list, **When** the same consumer evaluation path runs, **Then** exit1 and policy-failed
   identify that division; changing reference counts cannot exempt it.
3. **Given** an owned native fixture with two division occurrences at the same counted identity
   but x1 allowed, **When** evaluated, **Then** exit1 and the increased count is observable.
4. **Given** a valid built subject whose module inventory matches but one observed raw count
   differs, **When** evaluated without a policy violation, **Then** coverage-drift/exit1,
   actual/reference/delta retained; no automatic reference update or code-regression attribution.
5. **Given** a missing/extra module, empty origin pass, wrong contract, unavailable tool or
   invalid result JSON, **When** the consumer runs, **Then** it never exits0 and distinguishes
   measured drift from execution/incomplete-analysis error. Existing CI gates remain unchanged.
6. **Given** a developer needs to review a legitimate scope or allowance change, **When**
   following the documented procedure, **Then** reference metadata and any allowance must be
   deliberately edited/reviewed separately; there is no --regenerate/autoaccept path.

### US-2: Inspect a complete and attributable review package (Priority: P1)
As a code reviewer, I want a locally reproducible compact report package with its exact input
identities and uncertainty, so I can understand the origin gate without re-reading the whole
codebase or assuming a successful report means a successful policy.
**Why this priority:** makes the recurring consumer useful and auditable in actual review.
**Scope:** no stable structured parsing of evaluator prose, no source freshness certificate,
  no database/build uploads, no fabricated reviewer-time savings.
**Independent Test:** run the shared runner on an owned native fixture outside production CI
  and without the production reference deployment; validate publication, report consistency
  and failure artifacts. Shared execution infrastructure does not require US-1's CI rollout.
**Acceptance Scenarios:**
1. **Given** a fresh output destination and valid observed policy outcome, **When** the runner
   finishes, **Then** gate.json, report.json, report.sarif, report.html and run.json are present
   and mutually consistent; diagnostics are retained, and the final record distinguishes
   policy outcome, coverage comparability and measurement completeness.
2. **Given** a genuine division policy failure, **When** the runner completes analysis,
   **Then** nonzero policy exit does not suppress the complete reviewer package; its rule
   details/contexts match actual evaluator output and no PASS is fabricated.
3. **Given** an existing output directory or symlink, **When** requested as --out,
   **Then** exit2 before overwrite; previous bytes remain unchanged.
4. **Given** a report subprocess failure or a write failure, **When** publication stops,
   **Then** exit2, no complete-success marker, partial report set excluded from publication;
   useful diagnostics/run error record survive when writable. A record write failure is
   itself failure, never silently accepted.
5. **Given** the same production paths under a different compiler/build path or changed source
   revision, **When** evidence is generated, **Then** it records actual inventories/digests and
   revision/dirty state, labels trusted-build assumptions, and never promotes hash equality or
   unchanged counts into a complete/freshness proof.
6. **Given** CI starts the consumer and receives held, policy-failed, coverage-drift or error,
   **When** retention runs, **Then** known compact report/diagnostic artifacts survive for 14 days;
   no transient DB/build tree is uploaded, no failed gate is converted to success, and absent
   expected artifacts are not silently represented as an upload success.

Authentic-control obligation applies to both stories: direct standalone checks must distinguish
check assertion1 from execution>=2, use actual built OCaml fixtures/CLIs for success/new/count
cases, and test wrong/empty/incomplete inputs separately. No real corpus is downloaded.

## Challenges

# Adversarial resolution — origin-recurring-consumer

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

## Edge-case outcomes

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

## Functional Requirements

- **FR-001** [US-1]: The production consumer MUST scan the bounded live owned library in required CI with a repository-anchored CLI exposing only --out. [AC-1, AC-8]
- **FR-002** [US-1]: Reference v1 MUST validate the nonnegative safe-integer totals and unique channel/form/escapes groups defined in C-1, including origin-total/group-sum equality. [AC-1, AC-4]
- **FR-003** [US-1]: Comparison MUST report sorted signed current-minus-reference deltas over the union of group keys with missing counts zero; any total, group or module-set difference MUST block as drift when measurement is otherwise valid. [AC-4, AC-6]
- **FR-004** [US-1]: Production policy MUST be exactly the one C-2 declaration and explicit fail/warn flags; existing arch-rules.txt MUST remain unchanged. [AC-1, AC-5]
- **FR-005** [US-1]: Initial allowance MUST be exactly the intake's assertion identity x1 with the nonempty split_last rationale; it MUST NOT broaden identity/count or exempt division. [AC-1, AC-2, AC-3, AC-9]
- **FR-006** [US-1]: Consumer MUST record pre/post actual config/schema/tool/source/CMT identities and MUST reject in-run scoped mutation as error. [AC-7]
- **FR-007** [US-1]: Gate validation MUST enforce computed/contracted exactly one expected ordinal1 origin result, consistent census, failed-list and process exit; malformed/missing/extra evidence MUST be error. [AC-5]
- **FR-008** [US-1]: PASS/ordinary UNKNOWN MAY hold only with consistent exit0; VIOLATION/POSSIBLE MUST fail policy; vacuity/NOT_COMPUTED/UNKNOWN_NO_CONTRACT/false contract MUST be error. UNKNOWN MUST NOT mean proof. [AC-1, AC-5]
- **FR-009** [US-1]: Terminal status MUST follow error2 > policy-failed1 > coverage-drift1 > held0 and retain independent validated policy and measured deltas. [AC-4, AC-10]
- **FR-010** [US-1]: Inventories MUST contain unique sorted scoped relative POSIX paths and SHA256, reject unsafe reference paths and CMT symlinks/duplicates/out-of-root inputs, and record generated CMTs without assuming one CMT per source module. [AC-6, AC-17]
- **FR-011** [US-1]: Reviewed source-module and indexed-module inventories MUST match; mismatch MUST be drift only with valid nonempty contracted measurement, otherwise error. [AC-6]
- **FR-012** [US-1]: Authentic clean/new/count controls MUST traverse the same full runner with independently compiled owned CMTs and actual index/rules/report CLIs and pinned C-7 identities/counts; precomputed DB/JSON MUST NOT satisfy these controls. [AC-2, AC-3, AC-8]
- **FR-013** [US-1]: Reference and allowance changes MUST remain separate explicit reviewed artifacts/rationales; consumer MUST NOT regenerate, autoaccept or let count updates exempt origins. [AC-2, AC-9]
- **FR-014** [US-1]: Consumer MUST preserve the opaque evaluator note separately from raw counts and MUST NOT claim completeness, freshness certification, equivalent structured cone coverage, Git-differential findings or resistance to coordinated policy weakening. [AC-1, AC-4, AC-17]
- **FR-015** [US-2]: Completed held/policy-failed/coverage-drift MUST publish the six-file C-13 package with final run record last. [AC-11, AC-12]
- **FR-016** [US-2]: Output creation MUST exclusively create an absent leaf beneath a physically resolved existing parent, reject any existing leaf before writes and clean only owned paths. [AC-13]
- **FR-017** [US-2]: Subprocesses MUST be bounded by120s/16MiB per command; timeout, signal, abnormal exit, overflow, report/validation/I/O failure MUST become error2. [AC-14]
- **FR-018** [US-2]: Gate/JSON/SARIF evidence and HTML MUST satisfy the exact C-12 parity contract before publication. [AC-15]
- **FR-019** [US-2]: run.json MUST separate policy, coverage comparability and measurement completeness and contain SHA256 of final gate/report artifacts. [AC-11]
- **FR-020** [US-2]: Policy failure MUST retain a complete faithful reviewer package without fabricating PASS or changing evaluator details/contexts. [AC-12]
- **FR-021** [US-2]: Error after output ownership MUST retain run.json/diagnostics when writable and only valid optional gate.json, exclude partial reports and complete-success markers; unwritable output/record MUST use stderr and exit2. [AC-14, AC-16]
- **FR-022** [US-2]: Provenance MUST record Git HEAD/root/detached/dirty state, actual scoped inputs including untracked bytes, physical output and tool/config/trusted-build assumptions; missing Git provenance MUST error, dirtiness alone MUST NOT fail. [AC-17]
- **FR-023** [US-2]: SARIF MUST remain existing reporter evidence unchanged; consumer execution/reference/coverage outcomes MUST live in run.json without fabricated SARIF baselineState or invocation status. [AC-20]
- **FR-024** [US-2]: After consumer actually starts, CI MUST validate status-dependent artifacts, attempt surviving known-file upload with14-day retention, fail independently on missing evidence/upload failure, exclude DB/build/staging and never mask consumer failure. [AC-18, AC-19]
- **FR-025** [US-2]: Package behavior MUST be independently demonstrable on an owned native fixture without production CI/reference deployment. [AC-11]

## Acceptance Criteria

- AC-1 [US-1 happy path; C-1,C-2,C-5,C-17,C-18]: Reviewed production23/828/5223/491 with nine C-1 groups and one assertion allowance => held0 with zero deltas, ordinary UNKNOWN explicitly unproved.
- AC-2 [US-1; C-6,C-7,C-9]: Native fresh division at consumer.ml:2, absent from allowance => actual detail fresh x1, policy-failed1 even with matching updated reference counts.
- AC-3 [US-1; C-6,C-7]: Native same-line two divisions with x1 allowance => actual allowed line1 x2, policy-failed1.
- AC-4 [US-1; C-1,C-4]: Any raw total/group change, absent group or redistribution under valid held policy => coverage-drift1 with sorted directional deltas, no auto-update or regression attribution.
- AC-5 [US-1; C-2,C-3,C-5]: Missing/extra/malformed/renamed/noncomputed/noncontracted/inconsistent result or exit => error2, including when other evidence shows violation.
- AC-6 [US-1; C-10]: Invalid reference path, duplicate/symlink CMT or unusable/empty measurement => error2; valid nonempty module mismatch => drift1; generated CMT recorded without invented source module.
- AC-7 [US-1; C-3,C-11]: Scoped pre/post identity mutation => error2; unrelated dirty state => recorded, not independently failing.
- AC-8 [US-1; C-6,C-7,C-17]: All native clean/new/count controls traverse complete actual orchestration; correctly observed expected runner failures make checker pass0. Deliberate checker assertion =>1; execution fault =>>=2. Wrong/empty/incomplete cases tested separately.
- AC-9 [US-1; C-8,C-9]: Reference/allow changes require separate visible edits/rationale; initial literal allowance changes require changed tests; no regeneration/autoaccept interface.
- AC-10 [US-1; C-4]: Violation+drift => policy-failed1 with both; later execution/validation/I/O error =>error2 retaining previously validated evidence.
- AC-11 [US-2 happy path; C-12,C-13,C-16]: Native fixture package independently outside production CI => six required consistent files, digests and separate policy/coverage/completeness; final completion record last.
- AC-12 [US-2; C-12]: Genuine division policy failure => exit1 and complete faithful six-file package, no fabricated PASS.
- AC-13 [US-2; C-15]: Existing output file/directory/dangling symlink =>error2 byte-preserved; symlinked parent resolved to physical destination before exclusive absent-leaf creation.
- AC-14 [US-2; C-15]: Timeout/signal/abnormal exit/output overflow =>error2, no complete-success marker or partial report trio.
- AC-15 [US-2; C-12]: Divergent gate/report/SARIF shared evidence or missing HTML expected identity/verdict =>error2 before report promotion.
- AC-16 [US-2; C-13]: Report/promotion/final-record write failure =>error2, no complete=true record, owned partial reports removed when possible, cleanup failure stderr and writable diagnostics retained.
- AC-17 [US-2; C-10,C-11,C-18,C-19]: Different compiler/path, revision, detached HEAD, untracked input or dirty tree => actual recorded identities and explicit trusted-build limits, no freshness/completeness/differential finding claim; outside Git =>error2.
- AC-18 [US-2; C-13,C-14]: Every actually started consumer terminal outcome => status-dependent retention validation, attempt known surviving diagnostics upload,14-day compact retention without DB/build/staging.
- AC-19 [US-2; C-14]: Early error no files or disappeared completed artifact => retention fails independently; consumer failure remains visible.
- AC-20 [US-2; C-20]: SARIF unchanged with reporter findings/census, run.json contains consumer/current-reference outcomes; UNKNOWN missing its expected reporter alert =>parity error, no fabricated baseline/invocation state.

## Runnable Checks

- CHECK-1 [AC-1, AC-2, AC-3, AC-8] (authentic-success-path, fail-closed-path): `node checks/origin-recurring-consumer.js authentic` => 0=all assertions pass, 1=assertion fired, >=2=execution error.
- CHECK-2 [AC-4, AC-5, AC-6, AC-7, AC-9, AC-10, AC-13, AC-14, AC-16] (fail-closed-path): `node checks/origin-recurring-consumer.js failures` => 0=all assertions pass, 1=assertion fired, >=2=execution error.
- CHECK-3 [AC-11, AC-12, AC-15, AC-17, AC-18, AC-19, AC-20] : `node checks/origin-recurring-consumer.js package` => 0=all assertions pass, 1=assertion fired, >=2=execution error.

Commands require the documented @install build and configured OCaml compiler. Checker contract
includes deliberate assertion/execution controls, registered in Tezt. Commands are contractual,
not yet implemented or claimed passing. CI integration assertions included in package mode;
real CI execution remains a separate premerge gate.

## Claims Metadata

```claims
{"record":"claims-header","schema_version":1,"namespace":"origin-recurring-consumer","spec_lifecycle":"draft"}
{"record":"requirement","id":"FR-001","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-002","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-003","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-004","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-005","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-006","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-007","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-008","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-009","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-010","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-011","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-012","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-013","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-014","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-015","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-016","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-017","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-018","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-019","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-020","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-021","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-022","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-023","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-024","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-025","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"acceptance-criterion","id":"AC-1","for":["FR-001","FR-002","FR-004","FR-005","FR-008","FR-014"]}
{"record":"acceptance-criterion","id":"AC-2","for":["FR-005","FR-012","FR-013"]}
{"record":"acceptance-criterion","id":"AC-3","for":["FR-005","FR-012"]}
{"record":"acceptance-criterion","id":"AC-4","for":["FR-002","FR-003","FR-009","FR-014"]}
{"record":"acceptance-criterion","id":"AC-5","for":["FR-004","FR-007","FR-008"]}
{"record":"acceptance-criterion","id":"AC-6","for":["FR-003","FR-010","FR-011"]}
{"record":"acceptance-criterion","id":"AC-7","for":["FR-006"]}
{"record":"acceptance-criterion","id":"AC-8","for":["FR-001","FR-012"]}
{"record":"acceptance-criterion","id":"AC-9","for":["FR-005","FR-013"]}
{"record":"acceptance-criterion","id":"AC-10","for":["FR-009"]}
{"record":"acceptance-criterion","id":"AC-11","for":["FR-015","FR-019","FR-025"]}
{"record":"acceptance-criterion","id":"AC-12","for":["FR-015","FR-020"]}
{"record":"acceptance-criterion","id":"AC-13","for":["FR-016"]}
{"record":"acceptance-criterion","id":"AC-14","for":["FR-017","FR-021"]}
{"record":"acceptance-criterion","id":"AC-15","for":["FR-018"]}
{"record":"acceptance-criterion","id":"AC-16","for":["FR-021"]}
{"record":"acceptance-criterion","id":"AC-17","for":["FR-010","FR-014","FR-022"]}
{"record":"acceptance-criterion","id":"AC-18","for":["FR-024"]}
{"record":"acceptance-criterion","id":"AC-19","for":["FR-024"]}
{"record":"acceptance-criterion","id":"AC-20","for":["FR-023"]}
{"record":"check","id":"CHECK-1","for":["AC-1","AC-2","AC-3","AC-8"]}
{"record":"check","id":"CHECK-2","for":["AC-4","AC-5","AC-6","AC-7","AC-9","AC-10","AC-13","AC-14","AC-16"]}
{"record":"check","id":"CHECK-3","for":["AC-11","AC-12","AC-15","AC-17","AC-18","AC-19","AC-20"]}
```

Claims reconciler/authority not installed: draft metadata retained, no deterministic authority
validation/projection claimed. Root cross-spec entity scan found no definition collision.

## Entities

- `OriginConsumerRun`: one fresh bounded local index/evaluation/publication with separately recorded policy, drift and execution outcomes.
- `OriginConsumerReference`: versioned module inventory and raw observation vector, not a finding baseline, exemption or completeness certificate.
- `OriginConsumerPackage`: status-dependent compact evidence files tied by final run-record digests.
- Existing `RuleReportEntry`, exception origin and error contract definitions remain unchanged.
