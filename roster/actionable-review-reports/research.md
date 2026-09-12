# Research — actionable-review-reports

_Generated: 2026-09-12T17:21:58+02:00_
_Mode: full_
_Online research: enabled_

## Question 1: Where are review reports assembled and rendered, and which data structures, serializers, templates, or formatters define their current contents?

**Finding:** Two existing reporting paths carry relevant structures. The architecture-analysis report is collected once into `Arch_report.t`, whose `producer`, `coverage`, `finding`, `section`, and report record types are the shared input to JSON, SARIF, and self-contained HTML renderers. The `arch-report` CLI opens the database read-only, calls that collector once, and writes `report.json`, `report.sarif`, and `report.html`. Separately, roster review findings have a closed JSON shape and are validated, canonicalized, deduplicated, and returned in a normalization envelope containing primary findings, cross-runtime findings, duplicate candidates, rejected inputs, lifecycle dispositions, warnings, and stats.

**References:**
- `lib/arch_tools/arch_report.ml:38` — defines the report verdict vocabulary.
- `lib/arch_tools/arch_report.ml:95` — defines producer and coverage records.
- `lib/arch_tools/arch_report.ml:112` — defines the renderer-visible finding record.
- `lib/arch_tools/arch_report.ml:151` — defines sections and the complete report record.
- `lib/arch_tools/arch_report.ml:205` — `collect` performs the report query pass.
- `lib/arch_tools/arch_report.ml:456` — JSON finding and report serialization.
- `lib/arch_tools/arch_report.ml:479` — SARIF conversion.
- `lib/arch_tools/arch_report.ml:581` — self-contained HTML rendering.
- `bin/arch_report/arch_report.ml:43` — CLI orchestration and three artifact writes.
- `schema/review-finding.schema.json:5` — closed canonical review-finding object and required fields.
- `scripts/review-normalize.js:168` — candidate validation retains invalid inputs with reasons.
- `scripts/review-normalize.js:245` — normalizer assembles the review result envelope.

---

## Question 2: How are witness paths represented, produced, propagated, and displayed across the existing analysis and reporting pipeline?

**Finding:** `arch-rules` represents a witness as an ordered string list on each rule result. Reach-rule evaluation builds it from graph labels along a shortest path: `must_fwd` for `VIOLATION`, `fwd` for `POSSIBLE`, and `fwd` to the selected escaping node for `UNKNOWN`; other verdicts and rule forms shown here carry an empty witness. JSON emits the list as `results[].witness`; text and Markdown join it with arrows. SARIF maps it to `codeFlows[0].threadFlows[0].locations[]` in list order. The separate `arch-report` collector does not persist or load in-memory rule results and constructs SARIF findings with `code_flow = []`.

**References:**
- `bin/arch_rules/arch_rules.ml:741` — verdict-specific shortest-path construction.
- `bin/arch_rules/arch_rules.ml:770` — witness is retained on the rule result.
- `bin/arch_rules/arch_rules.ml:1430` — JSON result serialization includes `witness`.
- `bin/arch_rules/arch_rules.ml:1485` — SARIF finding conversion assigns `code_flow = r.witness`.
- `bin/arch_rules/arch_rules.ml:1551` — text and Markdown render witness steps in their stored order.
- `lib/arch_tools/arch_sarif.ml:203` — a witness becomes one code flow, one thread flow, and one location per step; empty input omits `codeFlows`.
- `tezt/tests/sarif_out.ml:370` — test asserts a three-node witness becomes three ordered SARIF locations.
- `lib/arch_tools/arch_report.ml:243` — report verdict evaluation is not persisted and report totals are placeholders.
- `lib/arch_tools/arch_report.ml:480` — `arch-report` SARIF findings currently set `code_flow = []`.

---

## Question 3: Where are origin operands captured or discarded, and what existing provenance metadata is retained from analysis results through report generation?

**Finding:** Error-channel configuration records origin declarations as `(callee path, 1-based literal-argument position)`. During analysis, exception/value-channel origin records retain channel, form, canonical path when known, source line/column, function and scope linkage, and escape state; the database row does not contain the configured operand position or the source operand expression. The architecture report's currently known sections are `dead_code` and `sarif_import`, so origin rows are not collected into its report record. Report provenance is retained at two levels: producer-run metadata in the header, and per-imported-finding producer plus soundness class through the finding's own `producer_run_id`. Dead-code findings have no recorded producer-run link and are rendered unattributed.

**References:**
- `lib/arch_index/arch_errors_config.mli:20` — transform modes state when inner literal origins are kept or discarded.
- `lib/arch_index/arch_errors_config.mli:27` — channel configuration includes `origins : (string * int) list` with literal-argument positions.
- `architecture-schema.sql:456` — `exn_origins` schema retains function, scope, form, canonical path, escape flag, line, column, and channel.
- `lib/arch_index/arch_index_exn.ml:79` — extraction accumulator stores form, path, scope, line, and column.
- `lib/arch_index/arch_index_exn.ml:383` — raw origin capture.
- `lib/arch_index/arch_index_cmt.ml:3326` — finalized exception origins are written to the database.
- `lib/arch_tools/arch_report.ml:190` — collector's known analysis/table pairs are dead code and SARIF import.
- `lib/arch_tools/arch_report.ml:213` — report header reads producer, version, soundness class, and invocation digest.
- `lib/arch_tools/arch_report.ml:247` — dead-code findings explicitly carry no producer or soundness attribution.
- `lib/arch_tools/arch_report.ml:326` — imported findings join their own producer run and retain producer, soundness class, level, location, rule, and message.
- `tezt/tests/report.ml:367` — test asserts an imported finding carries its own producer and soundness class.

---

## Question 4: What ordering rules currently govern findings and supporting evidence in review reports, and where are those rules implemented or documented?

**Finding:** Architecture-report inputs use explicit database orders: coverage by analysis/language, dead-code findings by call site/callee, imported findings by row id, and producers by id. Sections follow the fixed `known_analyses` list, with an unmatched-coverage section appended when present. SARIF producer groups are deduplicated and ordered by generic comparison. Coverage state selection has a distinct precedence—`failed`, `partial`, `not_analysed`, then other/covered—and chooses the highest-ranked status. In roster review normalization, exact-duplicate survivors are chosen by severity (`CRITICAL` through `INFO`) and then by longer evidence; contributing specialists remain in encounter order. The returned primary finding list is prior-ledger order followed by settled new findings; no global confidence sort is applied.

**References:**
- `lib/arch_tools/arch_report.ml:203` — fixed section order is `dead_code`, then `sarif_import`.
- `lib/arch_tools/arch_report.ml:216` — producer rows are ordered by id.
- `lib/arch_tools/arch_report.ml:225` — coverage rows are ordered by analysis and language.
- `lib/arch_tools/arch_report.ml:247` — dead-code rows are ordered by call site and callee.
- `lib/arch_tools/arch_report.ml:326` — imported findings are ordered by id.
- `lib/arch_tools/arch_report.ml:290` — status precedence and descending selection.
- `lib/arch_tools/arch_report.ml:390` — fixed sections are built before optional unmatched coverage.
- `lib/arch_tools/arch_report.ml:519` — SARIF producer options use `List.sort_uniq compare`.
- `scripts/lib/review/normalize-rules.js:12` — review severity rank.
- `scripts/lib/review/normalize-rules.js:92` — exact-duplicate survivor uses severity, then evidence length.
- `scripts/lib/review/normalize-rules.js:103` — convergence specialists retain deduplicated input order.
- `scripts/review-normalize.js:260` — prior ledger is concatenated before settled new findings.

---

## Question 5: How does the codebase represent unavailable, incomplete, uncertain, and successful analyses, and how are those distinctions exposed in reports and tests?

**Finding:** Architecture-report coverage rows admit `covered`, `not_analysed`, `failed`, and `partial`; when no matching row exists, the collector derives `not_analysed` for an absent table, `unknown` for a present empty table, and `covered` for a present non-empty table. Rule results separately distinguish `PASS`, `VIOLATION`, `POSSIBLE`, `UNKNOWN`, `UNKNOWN_NO_CONTRACT`, `NO_SOURCE`, `NO_TARGET`, and `NOT_COMPUTED`. Because rule results are not persisted, report-level verdict totals are explicitly `NOT_COMPUTED` with a reason and compatibility zero placeholders; HTML prints `unavailable`. Non-covered sections remain present in JSON/HTML and become SARIF notifications rather than an indistinguishable empty result. Roster review findings use `OPEN`, `RESOLVED`, and `ACCEPTED`; absent status becomes `OPEN`, schema-invalid candidates enter `rejected` with reasons, and unavailable check execution is represented as inconclusive with a reason. Missing loop audit evidence is a structured `process-incomplete` violation.

**References:**
- `lib/arch_tools/arch_report.ml:105` — stored coverage vocabulary.
- `lib/arch_tools/arch_report.ml:271` — derived coverage-state distinctions and precedence.
- `lib/arch_tools/arch_report.ml:417` — unavailable verdict totals and explanation.
- `lib/arch_tools/arch_report.ml:549` — non-covered SARIF sections emit notifications and `computed = false`.
- `lib/arch_tools/arch_report.ml:605` — HTML renders verdict totals as unavailable.
- `lib/arch_tools/arch_report.ml:635` — all known analysis sections render, including empty/non-covered states.
- `tezt/tests/report.ml:75` — JSON, SARIF, and HTML assertions for unavailable verdict totals.
- `tezt/tests/report.ml:315` — tests distinguish absent, empty, and populated analysis tables.
- `tezt/tests/report.ml:441` — multi-language coverage test asserts failed outranks covered across all channels.
- `schema/review-finding.schema.json:29` — review lifecycle status vocabulary.
- `scripts/review-normalize.js:168` — invalid findings are retained with validation reasons.
- `scripts/review-normalize.js:188` — missing review status defaults to `OPEN`.
- `scripts/lib/review/redgreen-scratch.js:35` — check verification uses reason-bearing inconclusive results.
- `scripts/lib/review/review-convergence-rules.js:118` — incomplete round audit becomes a structured `process-incomplete` violation.

---

## Question 6: Which existing explanation or diagnostic capabilities can report why an item has a given order, confidence, or availability state, and what interfaces expose them?

**Finding:** Architecture rule results expose verdict-specific `note`, `top_reasons`, detail rows, detail totals, source/target sizes, witness paths, and top-level census/gate counts through JSON; text/Markdown render detail, witness, and note, while SARIF maps verdict/soundness/top reasons/detail totals into properties and explanatory text. `arch-report` exposes coverage status/detail and the reason verdict totals are unavailable in JSON, SARIF, and HTML. Roster normalization exposes validation reasons, probable-duplicate line distance and identities, lifecycle dispositions, warnings, and stats; round mismatch warnings name both values. Check diagnostics return `inconclusive` plus reason and produce reason-bearing convergence violations. Confidence itself is a required integer on review findings, but the inspected schema/normalizer defines no confidence vocabulary, calculation, ordering, or explanation field.

**References:**
- `bin/arch_rules/arch_rules.ml:701` — reach verdict notes explain vacuity, unknown escape, overlap, and missing-contract states.
- `bin/arch_rules/arch_rules.ml:1406` — JSON exposes census counts and per-result evidence fields.
- `bin/arch_rules/arch_rules.ml:1468` — SARIF message construction includes notes and applicable evidence details.
- `bin/arch_rules/arch_rules.ml:1493` — SARIF properties distinguish soundness state and top reasons.
- `lib/arch_tools/arch_sarif.ml:224` — finding properties serialize verdict, soundness class/state, top reasons, and total evidence count.
- `lib/arch_tools/arch_report.ml:424` — JSON/SARIF report headers carry unavailable-verdict status and reason.
- `lib/arch_tools/arch_report.ml:616` — HTML coverage table exposes status and detail.
- `scripts/lib/review/normalize-rules.js:138` — probable-duplicate diagnostics carry line delta and both identities.
- `scripts/review-normalize.js:198` — round-consistency warning names caller and derived rounds.
- `scripts/review-normalize.js:268` — result envelope exposes rejected inputs, duplicate candidates, dispositions, warnings, and stats.
- `scripts/lib/review/redgreen-scratch.js:234` — check verification exposes check entries and inconclusive reasons.
- `schema/review-finding.schema.json:20` — confidence is required only as an integer field.

---

## Question 7: [ecosystem] How do established static-analysis and code-review reporting formats represent witness paths, source provenance, result ordering, uncertainty, and unavailable analyses?

**Finding:** SARIF 2.1.0 represents ordered execution witnesses with `codeFlows`/`threadFlows`/`locations`, distinguishes these from related locations, stacks, and graph traversals, and carries tool, invocation, version-control, conversion, analysis-target, and result provenance. Core SARIF does not prescribe natural `results[]` order or a standard confidence probability; it supplies optional rank and extension property bags. GitHub's SARIF profile adds categorical rule precision and orders alerts using level, precision, and applicable security/problem severity. GitLab SAST provides source-to-propagation-to-sink code-flow nodes, analyzer/scanner identities, scan status/messages and partial-scan metadata, and uses severity for dashboard sorting. Full Code Climate supports optional ordered/unordered traces and process-level failure; its GitLab Code Quality subset is a smaller flat finding format. SonarQube generic reports use primary plus secondary locations without execution-path semantics, while Checkstyle XML is flat. SARIF explicitly distinguishes an empty results array (analysis completed with no results) from null/omitted results or invocation errors (analysis did not begin or was non-comprehensive).

**References:**
- [OASIS SARIF 2.1.0, §§3.27.18 and 3.36–3.38](https://docs.oasis-open.org/sarif/sarif/v2.1.0/os/sarif-v2.1.0-os.html#_Toc34317838) — ordered code-flow/thread-flow witness structure.
- [OASIS SARIF 2.1.0, §§3.14, 3.18–3.23, 3.27.13, 3.27.29, 3.48](https://docs.oasis-open.org/sarif/sarif/v2.1.0/os/sarif-v2.1.0-os.html) — tool, invocation, source-control, result, and conversion provenance.
- [OASIS SARIF 2.1.0, §3.27.25 and Appendix F.3](https://docs.oasis-open.org/sarif/sarif/v2.1.0/os/sarif-v2.1.0-os.html#_Toc34317820) — rank and non-prescriptive result-array ordering.
- [OASIS SARIF 2.1.0, §3.14.23 and Appendix I](https://docs.oasis-open.org/sarif/sarif/v2.1.0/os/sarif-v2.1.0-os.html#_Toc34318249) — empty, absent, and non-comprehensive result states.
- [GitHub Docs, SARIF support for code scanning](https://docs.github.com/en/code-security/reference/code-scanning/sarif-files/sarif-support) — consumer support for code flows, first primary location, precision, and alert ordering.
- [GitLab SAST report schema v15.2.5](https://gitlab.com/gitlab-org/security-products/security-report-schemas/-/raw/v15.2.5/dist/sast-report-format.json) — code-flow nodes, scan/analyzer provenance, status, messages, and partial scan.
- [GitLab Docs, Security scanner integration](https://docs.gitlab.com/development/integrations/secure/) — severity ordering and ingestion behavior for failed jobs.
- [Code Climate Engine Specification](https://github.com/codeclimate/platform/blob/master/spec/analyzers/SPEC.md) — streamed findings, traces, engine identity, and fatal process outcome.
- [GitLab Docs, Code Quality report format](https://docs.gitlab.com/ci/testing/code_quality/#code-quality-report-format) — reduced Code Climate-derived finding subset.
- [SonarSource, Generic formatted reports](https://docs.sonarsource.com/sonarqube-server/10.3/analyzing-source-code/importing-external-issues/generic-issue-import-format) — primary/secondary location format.
- [Checkstyle, Result Reports](https://checkstyle.org/result-reports.html) — flat XML violation structure.

## Patterns found

| Pattern | File | Lines | Notes |
|---|---|---:|---|
| One collected value, three renderers | `lib/arch_tools/arch_report.ml` | 205–664 | JSON, SARIF, and HTML are total functions of one report value. |
| Deterministic query ordering | `lib/arch_tools/arch_report.ml` | 213–333 | Producer, coverage, dead-code, and imported rows have explicit SQL order. |
| Worst-state precedence | `lib/arch_tools/arch_report.ml` | 290–313 | Failed outranks partial, not analysed, and covered. |
| Ordered witness to SARIF code flow | `lib/arch_tools/arch_sarif.ml` | 203–222 | One location per witness step, order preserved. |
| Exact-duplicate survivor | `scripts/lib/review/normalize-rules.js` | 92–131 | Severity, then evidence length; encounter order otherwise persists. |
| Reason-bearing unavailable state | `scripts/lib/review/redgreen-scratch.js` | 35–110 | Unexecutable or indeterminate checks retain an explicit reason. |

## External prior art

| Tool / format | Source | Key finding |
|---|---|---|
| SARIF 2.1.0 | [OASIS specification](https://docs.oasis-open.org/sarif/sarif/v2.1.0/os/sarif-v2.1.0-os.html) | Ordered code flows, layered provenance, optional rank, and explicit analysis-completion semantics. |
| GitHub code scanning | [GitHub documentation](https://docs.github.com/en/code-security/reference/code-scanning/sarif-files/sarif-support) | Renders SARIF code flows and applies consumer-specific precision/severity ordering. |
| GitLab SAST | [Schema v15.2.5](https://gitlab.com/gitlab-org/security-products/security-report-schemas/-/raw/v15.2.5/dist/sast-report-format.json) | Code-flow nodes, scanner provenance, scan status/messages, and partial-scan state. |
| Code Climate | [Engine specification](https://github.com/codeclimate/platform/blob/master/spec/analyzers/SPEC.md) | Optional ordered/unordered traces and process-level failure semantics. |
| SonarQube generic issues | [SonarSource documentation](https://docs.sonarsource.com/sonarqube-server/10.3/analyzing-source-code/importing-external-issues/generic-issue-import-format) | Primary and secondary locations without execution-path semantics. |
| Checkstyle XML | [Checkstyle documentation](https://checkstyle.org/result-reports.html) | Flat per-file violations with source check identity. |

## Coverage gaps

- The inspected architecture-report path states that `arch-rules` verdicts are evaluated in memory and not persisted; consequently `arch-report` exposes unavailable placeholder verdict totals and does not carry the rule witness lists into its artifacts (`lib/arch_tools/arch_report.ml:243`, `lib/arch_tools/arch_report.ml:417`).
- The review-finding schema requires `confidence`, but the inspected review schema and normalization path do not define its scale, provenance, computation, sort rule, or a reason field tied specifically to it (`schema/review-finding.schema.json:20`, `scripts/review-normalize.js:168`).
- The review-finding schema has no witness-path or origin-operand field; architecture rule witnesses and exception-origin records exist in separate structures (`schema/review-finding.schema.json:18`, `bin/arch_rules/arch_rules.ml:741`, `architecture-schema.sql:461`).
- The locator found a schema description reference to `schema/review-json-schema.md`, but that referenced file is absent; the executable schema and normalizer sources above were used as the available contract.
