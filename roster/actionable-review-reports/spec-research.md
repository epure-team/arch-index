# Specification research — actionable-review-reports

Fresh Terra read-only research, 2026-09-12; root verified key anchors. No builds or source edits
by the researcher. Full prior-art discovery remains in research.md.

- Parser/evaluator/result are in bin/arch_rules/arch_rules.ml:238,528,665. Verdict conversion
  for exit policy is later at :1335 and consumes Arch_report. Extraction must avoid a cycle;
  policy can stay in the executable while the evaluator lives below report.
- `parse_rules` rejects empty files at :520 (`defines no rules`). Initial intake assumed an
  empty accepted scope; corrected intake to reject empty input consistently, before writes.
- Existing result fields: rule/kind/verdict/detail/detail_total/note/sizes/exact/witness/top_reasons
  at :528. JSON at :1418 projects sizes into source_size/target_size. Witness list is ordered
  and Arch_sarif at :203 preserves it in codeFlows.
- Existing no-rules report is always eight placeholders (lib/arch_tools/arch_report.ml:243,417),
  tested by tezt/tests/report.ml:75. CLI currently ignores trailing options at
  bin/arch_report/arch_report.ml:42; optional rules require real argument validation.
- Gate CLI exits 2 for parse/refusal, 1 for policy failures, 0 for passes. Report exits 0 for
  written artifacts, 2 for usage/broken input, 3 for refused DB reads; it is not a rule gate.
- Origin rows aggregate by fn/file/line/form/exception, counting multiplicities at
  bin/arch_rules/arch_rules.ml:990. Offender output cap is 200 sites at :1060. Supporting operands
  must not change identity, allow matching/counts, or this truncation total.
- Division primitive recognition in lib/arch_index/arch_index_exn.ml:416 already receives typed
  argument slots at :459, but origin record (:51) and DDL (architecture-schema.sql:461) have no
  operand metadata. Current schema version is 1.12 (arch_index_db.ml:90).
- Exception and value-channel writers share insert_exn_origin (arch_index_cmt.ml:3326,3380);
  keep value-channel operand support unavailable. Prepared statement is in arch_index.ml:564,
  parameter binding in arch_index_db.ml:507.
- Adjacent coverage: rules_origin.ml:61 has two divisions on one line, :475 empty-origin
  NOT_COMPUTED, :724 removes channel for old-schema coverage. report.ml:242,305 tests absent,
  empty and populated tables. Existing reporting FR-021's placeholder rule applies without
  --rules; amend that scope rather than erase its regression obligation.
- No KB or managed claims reconciler is installed. Do not redefine the generic `verdict`
  entity from exn-raise-sets.md (raise-set vocabulary); use RuleReportEntry and
  DivisorOperandContext for this task.
- Root inspected checks/mid-caller-shadow-attribution.js: it maps all nonzero Tezt exits to 1.
  That wrapper does not establish the required assertion/error distinction. New check commands
  need actual self-contained assertions and execution-error separation, with Tezt integration.
