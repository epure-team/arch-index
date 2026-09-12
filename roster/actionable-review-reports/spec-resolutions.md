# Challenge resolutions — actionable-review-reports

Root resolution from intake, primary-source research and existing behavior. Two independent
stories; eight clarifications, zero OPEN. No user questions needed for these bounded details.

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

## Edge cases and resolutions

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

## Verification boundary

Four self-contained authentic-CLI cases: rules, ordering, operands, compatibility. Check script
distinguishes assertion failure (1) from execution/fixture/parse errors (>=2), and validates its
own failure mapping with controls; normal Tezt registration must invoke it. Include mixed
native/imported producer fixture, multiple verdict classes in one census, duplicate display
names and both caps, SQL NULL/old-column absence versus malformed metadata, and an unrelated
second argument control. Existing no-rules report and arch-rules regression suites remain gates.

## Cross-spec consistency

Searched specs/*.md entities. `exception origin` and existing raise-set `verdict` retain their
definitions (specs/exn-raise-sets.md:204); `reach verdict` also remains unchanged
(specs/vuln-reachability-triage.md:274). New RuleReportEntry and DivisorOperandContext names have
no existing entity definition. Reporting FR-021 needs an explicit optional-rules amendment;
its no-rules placeholder contract remains load-bearing rather than superseded wholesale.
