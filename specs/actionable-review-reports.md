---
name: roster-spec
type: spec
status: live
feature: actionable architecture review reports
brief: briefs/actionable-review-reports-intake.md
date: 2026-09-12
version: 1.0.0
---

# Spec — actionable architecture review reports

## Clarifications

| Q | A |
|---|---|
| Report failure or rule-gate failure? | Successfully written reports exit 0 for every rule verdict; arch-rules retains its policy-driven exits. |
| No rules vs invalid rules? | No option retains NOT_COMPUTED placeholders; empty/malformed/unreadable file rejects with exit 2 before writes. |
| Which ordering? | Artifact alert order is VIOLATION, POSSIBLE, uncertainty, vacuity, then declaration ordinal within each tier; not viewer-order/confidence promises. |
| Shared evaluation? | One extracted parser/evaluator, invoked once using the same read-only DB handle; exit policy stays at CLI boundary. |
| Origin identity and caps? | Existing site identity/count/allow matching and 200-site cap unchanged; contexts are separate supporting data with explicit omitted totals. |
| Syntax or value? | CMT typed-AST slot 2, literal kind/identifier/other/missing; no source reread, folding, range or nonzero inference. |
| Which producers? | Native division/remainder exception origins only; older/flat indexes and unsupported forms/channels explicitly unavailable. |
| Entity naming? | RuleReportEntry and DivisorOperandContext; no redefinition of raise-set verdict. |

## User Stories

### US-1: Follow evaluated architecture rules in one report (Priority: P0)

As a repository maintainer, I want a unified report with the same evaluated rules and witnesses
as arch-rules, so I can inspect violations and uncertainty without manually combining outputs.
**Why this priority:** the existing witness computation is shipped but absent from report artifacts.
**Scope:** does not change reachability semantics, rule gate policy, imported-finding rigor,
concurrent DB-writer support or source freshness guarantees.
**Independent Test:** run real arch-report and arch-rules CLIs against a bounded fixture DB/rules
and compare verdicts/evidence plus three report renderings, without operand producer changes.
**Acceptance Scenarios:**
1. **Given** a quiescent fixture index with MUST path entry → middle → sink and one forbidden
   reach rule, **When** the maintainer runs `arch-report fixture.db --out report --rules rules.txt`,
   **Then** exit is 0, the VIOLATION census is 1, and JSON/HTML/SARIF retain the same ordered
   three-step witness as arch-rules; the report is not a policy gate.
2. **Given** that same DB, **When** the option is omitted, **Then** all eight compatibility counts
   remain explicitly NOT_COMPUTED placeholders; **When** an empty, malformed or unreadable rules
   file is supplied, **Then** exit 2 and a diagnostic occur before writes, not no-rules success.
3. **Given** rules deliberately declared vacuous, UNKNOWN, VIOLATION, POSSIBLE and PASS in that
   order, with a second UNKNOWN after the first, **When** reports are rendered, **Then** alert
   entries use the documented tier order, both UNKNOWN entries retain declaration order, PASS
   is counted but not an alert, and all individual rule results remain inspectable in JSON.
4. **Given** one escaping MAY_TOP witness and a separate no-contract index, **When** corresponding
   reports are produced, **Then** UNKNOWN versus UNKNOWN_NO_CONTRACT and their explanations
   remain distinct, and no frontier witness is presented as a path to the target.
5. **Given** an evaluated origin/effect rule whose source table is absent, **When** the report
   completes, **Then** census availability is COMPUTED but that rule remains NOT_COMPUTED;
   native coverage and imported producer metadata do not become proofs by association.
6. **Given** rule names and detail strings containing HTML metacharacters and duplicate rule
   display names, **When** rendered, **Then** output is escaped, entries remain individually
   identifiable by declaration ordinal, and repeated runs produce the same artifact order.

### US-2: Inspect divisor syntax without changing the origin gate (Priority: P1)

As a maintainer reviewing `forbid origin`, I want bounded divisor context beside a reported
division/remainder site, so I can read the relevant operand while retaining the current gate.
**Why this priority:** this removes source-navigation work and provides data for the separately
planned value-analysis experiment without pretending that experiment already exists.
**Scope:** integer primitive division/remainder exception origins only; not arrays, general
expressions, value channels, semantic symbol identities or value analysis.
**Independent Test:** compile a tiny owned OCaml fixture, index it, inspect origin metadata and
run the existing arch-rules CLI; this story is useful without the optional unified report path.
**Acceptance Scenarios:**
1. **Given** typed fixture bodies `x / 0`, `x / 2`, `x / y`, `x / (y + 1)` and typed int32/int64/
   nativeint remainders, **When** indexed, **Then** second-slot syntax categories, primitive and
   integer kinds are recorded without evaluating expressions; every preexisting division origin
   and its escape state remains, including the nonzero literal case.
2. **Given** two division sites on one source line with different divisors and an allow count of
   one for their aggregate identity, **When** arch-rules runs, **Then** it still reports the same
   increased-count offender; operand context remains supporting data, not a new identity/exemption.
3. **Given** an old index with no operand metadata, a missing second argument slot, and an
   unsupported origin form/value channel, **When** queried/reported, **Then** metadata absence,
   missing operand and unsupported context are explicit; no later present argument is substituted.
4. **Given** a fixture whose source file was changed or removed after CMT generation, **When**
   the existing CMT is indexed, **Then** operand context still comes from that typed AST; it is
   not represented as exact text from the current source tree.
5. **Given** more origin contexts than the displayed evidence budget and an oversized identifier,
   **When** results are rendered, **Then** representation and context lists are bounded, omitted
   counts/reasons are visible, existing aggregate counts remain exact, and HTML is escaped.
6. **Given** a unified report of a division-origin rule after US-1 is available, **When** generated,
   **Then** the same structured operand context and unavailability states reach all three
   artifacts without changing the rule verdict or suppressing an origin.

## Challenges

| ID | Story | Challenge | Resolution |
|---|---|---|---|
| C-1 | US-1 | Same evaluator but different CLI success? | Equality covers parser/evaluator result fields, not CLI policy. Report exit 0 means written; no fabricated passed gate. |
| C-2 | US-1 | Same handle is not a snapshot across CLIs. | Compare on a quiescent fixture; same-handle invocation is not source freshness or concurrency support. Document that limit. |
| C-3 | US-1 | Ordinals/duplicate names ambiguous. | Ordinal is one-based position in successfully parsed rule list; comments/blank lines consume none. It identifies entries within this invocation, not across edits. Expose ordinal in all artifacts. |
| C-4 | US-1 | Ordering within uncertainty/vacuity groups? | Each group is one tier. No sub-verdict sort; declaration ordinal is the only tie-breaker. Preserve original declaration order separately in full rule results. |
| C-5 | US-1 | SARIF has no natural result-array order and distinguishes execution completion. | Use producer-defined artifact order as a property, not a standard confidence/rank claim. COMPUTED describes census evaluation only; individual NOT_COMPUTED and explanations survive. No changes to coverage from census status. |
| C-6 | US-1 | GitHub imposes its own precision/severity ordering. | Assert serialized order only; explicitly document viewer freedom. Do not invent precision/security-severity/rank to force viewer order. |
| C-7 | US-1 | GitLab offers scan provenance/status/partial state. | Reuse available index producer/coverage metadata and separate current rule-evaluation status/path; do not invent GitLab metadata, snapshots or unknown tool versions. No new input format is needed. |
| C-8 | US-1 | Code Climate distinguishes trace order and process fatal errors. | Existing rule witnesses are ordered by construction; operand contexts are not traces. Evaluation/serialization/write errors cause nonzero, while completed violation reports remain successful artifacts. |
| C-9 | US-1/2 | Sonar secondary locations are not execution paths; what are operands? | Witnesses alone use codeFlows. Operand contexts are supporting structured properties, rendered visibly in HTML, never fabricated flow edges or file locations. |
| C-10 | US-1/2 | Checkstyle flat findings vs rich report semantics. | Keep existing JSON/SARIF/HTML outputs because flattening would lose required uncertainty/witness data. No Checkstyle exporter or flat identity rewrite. |
| C-11 | US-2 | 200 sites does not bound contexts within one site. | Preserve existing 200 offender-site limit. Independently cap emitted operand contexts to 200 per rule result, only from displayed offender sites. Carry exact context_total and context_omitted (total matching offender-origin rows minus emitted contexts), separate from detail_total. Deterministic site-identity then source line/column/row-id order; context multiplicity retained. |
| C-12 | US-2 | Syntax distinguishes occurrences but gate identity aggregates. | Each context names existing site identity and occurrence position; repeat contexts when rows repeat, without adding context fields to allow identity/counts. Context totals do not become exemption counts. |
| C-13 | US-1 | Latest producer_runs may be a foreign importer, not the rule evaluator (root challenge). | New rule findings identify evaluator as arch-rules, with no invented version or inherited latest-run soundness class. Preserve result exact/contract_ok/verdict/top reasons; index producers stay a separate list. Ambiguous origin rigor stays unattributed. Existing imported findings retain their own attribution. Do not change legacy arch-rules SARIF attribution in this slice. |

External challenges C-5 through C-10 refer to the corresponding direct primary URLs in
research.md's External prior art table; every table entry with a differing model is addressed.

## Functional Requirements

- **FR-001** [US-1]: When --rules is supplied, arch-report MUST parse/evaluate once using its already-open read-only DB and the same evaluator semantics/result fields as arch-rules. Documentation MUST limit cross-CLI equality to a quiescent index, not promise a snapshot, source freshness or concurrent-writer support. [S1; AC-1, AC-8]
- **FR-002** [US-1]: A successfully written report MUST exit 0 regardless of individual rule verdicts and MUST NOT claim a policy gate passed. Existing arch-rules policy exits and allow behavior MUST remain unchanged. [S1; C-1; AC-1]
- **FR-003** [US-1]: Without --rules, all three artifacts MUST retain eight zero-valued compatibility verdict placeholders with NOT_COMPUTED availability and its explanation, never measured zero counts. [S2; AC-2]
- **FR-004** [US-1]: Empty, malformed or unreadable supplied rules MUST cause exit 2 and a diagnostic before any artifact write, preserving preexisting outputs and forbidding fallback to no-rules success. [S2; AC-3]
- **FR-005** [US-1]: Parsed rules MUST receive one-based declaration ordinals excluding comments and blank lines. Every rule alert MUST expose its ordinal in JSON, SARIF and HTML, distinguishing duplicate display names within this invocation without promising identity across edits. [S3; C-3; AC-4]
- **FR-006** [US-1]: Full JSON rule results MUST retain declaration order. Rule alerts MUST sort by VIOLATION, POSSIBLE, uncertainty (UNKNOWN/UNKNOWN_NO_CONTRACT/NOT_COMPUTED), vacuity (NO_SOURCE/NO_TARGET), with ordinal as the sole in-tier tie-breaker. PASS MUST remain counted and inspectable but not an alert. All formats MUST explain this artifact-order policy without confidence/rank/severity-conversion or viewer-order claims. [S3; C-4/5/6; AC-4]
- **FR-007** [US-1]: RuleReportEntry MUST retain verdict, exactness, applicable selector sizes, detail/detail_total, note, top reasons and ordered witness. Witnesses MUST preserve repeated/logical-only labels and sequence across formats, using SARIF codeFlows without invented physical locations or reconstructed paths. [S1/S4; C-8/9; EC-2; AC-1, AC-5]
- **FR-008** [US-1]: UNKNOWN, UNKNOWN_NO_CONTRACT and NOT_COMPUTED MUST retain distinct individual verdicts and existing explanations. UNKNOWN frontier witnesses MUST NOT be presented as reaching the forbidden target. [S4; AC-5]
- **FR-009** [US-1]: Completed supplied-rule evaluation MUST mark the census COMPUTED and count every rule exactly once across the eight buckets, including individual NOT_COMPUTED entries. Census status MUST NOT alter coverage, producer soundness or individual verdicts. [S5; C-5/7; AC-6]
- **FR-010** [US-1]: New rule findings MUST identify their evaluator as arch-rules and MUST NOT inherit an arbitrary latest/index/imported producer version or soundness class. Index metadata, exact/contract_ok facts and imported-finding attribution MUST remain separate; unknown rigor MUST stay unattributed. [S5; C-13; AC-6]
- **FR-011** [US-1]: HTML MUST escape every rendered string. Render/write failures MUST diagnose nonzero and omit the success summary; write errors MUST exit 2. Documentation MUST state that publication is not an atomic three-file transaction and partial I/O output is unusable. [S6; EC-1/2; AC-7]
- **FR-012** [US-2]: Native CMT indexing MUST record divisor context for recognized integer division/remainder origins from original typed-AST slot 2, preserving primitive, slot, category (integer_literal/identifier/other/missing) and applicable integer kind. It MUST NOT reread current source, evaluate/fold expressions, infer ranges/values or suppress nonzero-literal origins. [S1/S4; AC-9, AC-12]
- **FR-013** [US-2]: Supported integer_literal and identifier contexts within the representation limit MUST carry typed-AST-derived display text. Other/missing MUST carry no fabricated text. Negative typed constants MUST preserve compiler-recorded kind/text; unary-application ASTs MUST remain other. Identifier labels MUST NOT claim stable binding identity or exact current-source spelling. [S1/S3; EC-4; AC-9, AC-11]
- **FR-014** [US-2]: Old/flat indexes lacking metadata, SQL NULL and unsupported forms/value channels MUST expose context as unavailable without DB mutation. Absent original slot 2 MUST remain missing, never replaced by a later present argument. Malformed non-NULL metadata, unknown category or invalid type MUST be refused diagnostically (report 3, arch-rules 2), not normalized into fabricated unavailable syntax. [S3; EC-3; AC-11]
- **FR-015** [US-2]: Contexts MUST associate with the existing aggregate site identity and occurrence position, preserving row multiplicity. They MUST NOT change origin identity, allow matching/counts, gate verdicts, escapes or the existing 200-offender-site cap. [S1/S2; C-12; AC-10]
- **FR-016** [US-2]: Each rule result MUST emit at most 200 contexts, only from displayed offender sites, ordered by site identity then source line/column then row id. context_total MUST count all matching offender-origin rows; context_omitted MUST equal that total minus emitted contexts, independently of detail_total. [S5; C-11; AC-13]
- **FR-017** [US-2]: Representation MUST be at most 256 UTF-8 bytes. Over-limit text MUST be omitted whole with an explicit limit reason while category/primitive/slot remain; invalid UTF-8 truncation MUST NOT be emitted. [S5; EC-4; AC-13]
- **FR-018** [US-2]: Structured context and unavailable/omitted states MUST reach arch-rules JSON and all unified report formats as supporting properties/visible HTML data, never flow edges, fake locations or new flat gate identities. [S6; C-9/10; AC-14]

## Acceptance Criteria

- **AC-1** [US-1 happy path; C-1/C-8]: MUST-path fixture → report exit 0, VIOLATION count 1 and equal three-step witnesses across CLIs/artifacts.
- **AC-2** [US-1; no-rules compatibility]: No --rules → eight unavailable placeholders in every format.
- **AC-3** [US-1; EC-1]: Empty/malformed/unreadable rules → exit 2 before writes, preserving preexisting outputs.
- **AC-4** [US-1; C-3/C-4/C-5/C-6]: Mixed verdicts, comments and duplicate display names → tier/ordinal ordering, explicit explanation, declaration-order full results and non-alert PASS.
- **AC-5** [US-1; EC-2]: Top-escaping vs no-contract indexes → distinct explanations and exact witness sequences, with logical-only/repeated labels retained and no claimed frontier-to-target path.
- **AC-6** [US-1; C-5/C-7/C-13]: Absent origin/effect data and native+imported producer fixture → COMPUTED census sums correctly, individual NOT_COMPUTED preserved, evaluator arch-rules and foreign attribution unchanged.
- **AC-7** [US-1; EC-1/EC-2]: HTML metacharacters → escaped data; repeated runs → stable order; write failure → nonzero without success summary and documented unusable partial outputs.
- **AC-8** [US-1; C-2]: Report documentation → explicit quiescent-index/no-snapshot/no-current-source-freshness constraint.
- **AC-9** [US-2 happy path; EC-4]: Authentic integer primitive fixture → original slot-2 category/text/primitive/integer kind, including negative typed literal vs unary AST; nonzero literal origins unchanged.
- **AC-10** [US-2; C-12]: Two divisions on one line with allowance count one → unchanged increased-count offender with supporting contexts, not new identities.
- **AC-11** [US-2; EC-3/EC-4]: Old/NULL/missing-slot/unsupported contexts → explicit states; malformed/unknown metadata → specified diagnostic refusal, never DB writes or later-argument substitution.
- **AC-12** [US-2]: Change/remove source after compilation → unchanged CMT-derived syntax context.
- **AC-13** [US-2; C-11/EC-4]: More than 200 contexts/sites and oversized UTF-8 identifier → exact totals/omissions, bounded lists/text, preserved multiplicity and deterministic order.
- **AC-14** [US-2; C-9/C-10]: Division-origin report → same structured context and unavailable/omitted states in JSON/SARIF/HTML, never flow edges or changed verdicts.
- **AC-15** [US-1/US-2; verification boundary]: All four self-contained cases run in normal Tezt; controls distinguish pass0/assertion1/execution-error>=2; missing tools never pass or masquerade as feature assertions.

## Edge Cases

- EC-1 [US-1]: render/write failure → nonzero diagnostic (write failure exit 2), no success
  summary. Preexisting files remain on pre-write input rejection. Successful writes are not an
  atomic three-file transaction; partial output on I/O failure is documented as unusable.
- EC-2 [US-1]: repeated/logical-only witness labels → preserve JSON strings and sequence exactly;
  HTML escapes them; use existing SARIF location conversion, retaining logical steps without
  inventing physical locations. No path reconstruction or feasibility assertion.
- EC-3 [US-2]: missing column or SQL NULL → explicit metadata unavailable. Malformed non-NULL
  metadata/unknown category/invalid field type → diagnostic refusal, not fabricated unavailable
  syntax (report exit 3, arch-rules existing refusal exit 2). No DB writes on read.
- EC-4 [US-2]: typed negative constant → integer_literal with its compiler-recorded kind/text;
  unary application AST → other, no folding. Identifier display text is not a binding identity
  or current-source excerpt. At most 256 UTF-8 bytes of representation; over-limit text is
  omitted whole with an explicit limit reason, not split into invalid UTF-8. Preserve category
  and primitive/slot even when text is omitted. Other/missing has no fabricated text.

## Runnable Checks

Build prerequisites with the intake's explicit project-switch build command. Each check creates
bounded owned fixtures, invokes the actual built CLIs, cleans its temporary outputs, and honors
0=pass, 1=assertion failure, >=2=execution/fixture/parse/environment error. No wrapper may translate
a test runner's generic failure exit into proof of a feature assertion. Register all cases in
Tezt and validate SARIF against the existing vendored schema using the installed validator.

- **CHECK-1** [AC-1, AC-5, AC-15]: `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- node checks/actionable-review-reports.js rules` → expected exit 0, non-vacuous authentic CLI assertions and tested failure mapping.
- **CHECK-2** [AC-4, AC-7, AC-15]: `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- node checks/actionable-review-reports.js ordering` → expected exit 0, non-vacuous authentic CLI assertions and tested failure mapping.
- **CHECK-3** [AC-9, AC-10, AC-12, AC-13, AC-14, AC-15]: `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- node checks/actionable-review-reports.js operands` → expected exit 0, non-vacuous authentic CLI assertions and tested failure mapping.
- **CHECK-4** [AC-2, AC-3, AC-6, AC-8, AC-11, AC-15]: `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- node checks/actionable-review-reports.js compatibility` → expected exit 0, non-vacuous authentic CLI assertions and tested failure mapping.

## Claims Metadata

Metadata stays draft because no claims reconciler/authority projection is installed. This does
not claim a deterministic validation/project pass. Normative prose is above, not duplicated here.

```claims
{"record":"claims-header","schema_version":1,"namespace":"actionable-review-reports","spec_lifecycle":"draft"}
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
{"record":"acceptance-criterion","id":"AC-1","for":["FR-001","FR-002","FR-007"]}
{"record":"acceptance-criterion","id":"AC-2","for":["FR-003"]}
{"record":"acceptance-criterion","id":"AC-3","for":["FR-004"]}
{"record":"acceptance-criterion","id":"AC-4","for":["FR-005","FR-006"]}
{"record":"acceptance-criterion","id":"AC-5","for":["FR-007","FR-008"]}
{"record":"acceptance-criterion","id":"AC-6","for":["FR-009","FR-010"]}
{"record":"acceptance-criterion","id":"AC-7","for":["FR-011"]}
{"record":"acceptance-criterion","id":"AC-8","for":["FR-001"]}
{"record":"acceptance-criterion","id":"AC-9","for":["FR-012","FR-013"]}
{"record":"acceptance-criterion","id":"AC-10","for":["FR-015"]}
{"record":"acceptance-criterion","id":"AC-11","for":["FR-013","FR-014"]}
{"record":"acceptance-criterion","id":"AC-12","for":["FR-012"]}
{"record":"acceptance-criterion","id":"AC-13","for":["FR-016","FR-017"]}
{"record":"acceptance-criterion","id":"AC-14","for":["FR-018"]}
{"record":"acceptance-criterion","id":"AC-15","for":["FR-001","FR-004","FR-012","FR-014"]}
{"record":"check","id":"CHECK-1","for":["AC-1","AC-5","AC-15"]}
{"record":"check","id":"CHECK-2","for":["AC-4","AC-7","AC-15"]}
{"record":"check","id":"CHECK-3","for":["AC-9","AC-10","AC-12","AC-13","AC-14","AC-15"]}
{"record":"check","id":"CHECK-4","for":["AC-2","AC-3","AC-6","AC-8","AC-11","AC-15"]}
```

## Entities

- `RuleReportEntry`: one parsed rule's evaluated result with a one-based invocation-local ordinal, distinct from gate-policy success or census availability.
- `DivisorOperandContext`: bounded CMT-derived syntax metadata associated with an existing division/remainder origin, never a value-analysis result or exemption identity.
- Existing exception origin, raise-set verdict, reach verdict and coverage definitions remain unchanged.

## Validation and consistency record

Two stories, eight clarifications, thirteen resolved challenges including all six prior-art
approaches, eighteen requirements, fifteen acceptance criteria and four executable-check
contracts. Fresh Terra research, fresh Sol clarifier/challenger; Terra researcher reused as
formalizer after runtime rejected new agent creation. Root strengthened literal/identifier
representation from optional to required within bounds, preserving the intake obligation.
User's standing autonomous authorization replaces a new interactive quiz; no fresh human
approval is claimed. No unresolved direction change or authentic-path exclusion is accepted.

Existing reporting FR-021 must be amended to scope placeholder counts to absence of --rules.
Its no-rules regression stays intact. Cross-spec entity search found no competing definitions
for the two new names; existing raise-set and reach verdict names were checked explicitly.
