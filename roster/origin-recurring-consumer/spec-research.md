# Spec research — origin-recurring-consumer

Fresh Terra context; read-only, no build/test/write. Existing relevant paths and prior research
confirmed on this worktree. arch-rules policy JSON/exits at bin/arch_rules/arch_rules.ml:238–300,
470–491; origin evaluation at lib/arch_tools/arch_rule_eval.ml:885–1103; existing counted allows
at :119–229, opaque coverage at :1041–1053. CI self-index .github/workflows/ci.yml:128–141 and
reach rules :292–296, no origin artifact upload. Existing tests rules_origin.ml and
actionable_review_reports.ml cover authentic CMT, count/caps, unavailable inputs and checker
exit mapping. Closest spec actionable-review-reports.md preserves evaluator/report separation,
quiescent DB assumption and non-atomic publication; existing entities RuleReportEntry and
DivisorOperandContext stay unchanged. KB absent; planned consumer files absent.

Material constraints:
1. arch-report requires an existing output directory and writes three files sequentially
   (bin/arch_report/arch_report.ml:51–95); the owning runner must provide its stronger boundary.
2. Origin coverage is prose, not structured module/count provenance. Do not parse it as an API.
3. UNKNOWN can legitimately hold the gate; report exit 0 is publication, not policy success.
4. Existing golden pins only counts; no source/CMT freshness or full population certificate.
5. Checker 0/1/>=2 is not the same as every underlying tool's process vocabulary.
6. Existing assertion at arch_index_cmt.ml:1388 is in a nonempty split_last branch, with informal
   source justification only. Initial root measurement is not yet an automated consumer.
