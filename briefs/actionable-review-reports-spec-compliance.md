---
auditor: spec-compliance-auditor
date: 2026-09-12
status: 0 critical, 0 warnings, 0 info
coverage: 18/18 requirements verified (100%)
adaptation: per-feature report lives in briefs because no canonical kb/spec.md is installed
context: reused review context; no fresh-independence claim
---

# Spec compliance — actionable review reports

## Compliance matrix

| Claim | Status | Implementation evidence | Test evidence |
|---|---|---|---|
| FR-001 shared single evaluation | PASS | `bin/arch_report/arch_report.ml:67-75`; `lib/arch_tools/arch_rule_eval.ml:1199-1204` | `checks/actionable-review-reports.js:75-101` |
| FR-002 report/gate exit separation | PASS | `bin/arch_report/arch_report.ml:81-100`; `bin/arch_rules/arch_rules.ml:468` | `checks/actionable-review-reports.js:82-91` |
| FR-003 no-rules placeholders | PASS | `lib/arch_tools/arch_report.ml:236-252,433-447` | `checks/actionable-review-reports.js:148-162`; `tezt/tests/report.ml:88-119` |
| FR-004 invalid rules before writes | PASS | `bin/arch_report/arch_report.ml:67-80,96-100` | `checks/actionable-review-reports.js:163-179` |
| FR-005 ordinals | PASS | `lib/arch_tools/arch_report.ml:236-242,479-495` | `checks/actionable-review-reports.js:126-143` |
| FR-006 declaration and alert ordering | PASS | `lib/arch_tools/arch_report.ml:497-521` | `checks/actionable-review-reports.js:104-145` |
| FR-007 complete evidence and witness order | PASS | `lib/arch_tools/arch_report.ml:479-495,616-632,719-745` | `checks/actionable-review-reports.js:75-101`; full Tezt SARIF witness tests |
| FR-008 distinct uncertainty | PASS | `lib/arch_tools/arch_rule_eval.ml:569-590,718-769` | `checks/actionable-review-reports.js:97-101,180-190` |
| FR-009 computed census separation | PASS | `lib/arch_tools/arch_report.ml:236-252,433-447` | `checks/actionable-review-reports.js:85,115-133` |
| FR-010 evaluator/import provenance | PASS | `lib/arch_tools/arch_report.ml:485,566-632,645-656` | `checks/actionable-review-reports.js:134-143`; `tezt/tests/report.ml:354-414` |
| FR-011 escaping and I/O failure | PASS | `bin/arch_report/arch_report.ml:35-45,78-95`; `lib/arch_tools/arch_report.ml:659-745` | `checks/actionable-review-reports.js:163-190`; `tezt/tests/report.ml:559-569` |
| FR-012 typed original slot 2 | PASS | `lib/arch_index/arch_index_exn.ml:395-398,471-506` | `checks/actionable-review-reports.js:192-236`; `tezt/tests/exn_raise_sets.ml` |
| FR-013 bounded syntax categories | PASS | `lib/arch_index/arch_index_exn.ml:487-506` | `checks/actionable-review-reports.js:192-236` |
| FR-014 old/NULL versus malformed | PASS | `lib/arch_tools/arch_origin_context.ml:52-165` | `checks/actionable-review-reports.js:238-295` |
| FR-015 unchanged identity/count | PASS | `lib/arch_tools/arch_rule_eval.ml:1000-1074` | `tezt/tests/rules_origin.ml:180-235`; checker operands mode |
| FR-016 independent 200-context cap | PASS | `lib/arch_tools/arch_origin_context.ml:185-199`; `lib/arch_tools/arch_rule_eval.ml:1057-1074` | `tezt/tests/rules_origin.ml:195-215`; `checks/actionable-review-reports.js:231-236` |
| FR-017 256-byte whole omission | PASS | `lib/arch_index/arch_index_exn.ml:497-502`; `lib/arch_tools/arch_origin_context.ml:159-165` | `checks/actionable-review-reports.js:192-230` |
| FR-018 contexts across report channels | PASS | `bin/arch_rules/arch_rules.ml:286-291`; `lib/arch_tools/arch_report.ml:479-495,645-656,731-742` | `checks/actionable-review-reports.js:219-236`; focused report/SARIF validation |

## Verification executed by this embedded pass

- Build `@install`: exit 0.
- Full suite: 240/240 Tezt plus Alcotest, terminal exit 0.
- Focused `report.ml`: 6/6, exit 0.
- Standalone `rules`, `ordering`, `operands`, `compatibility`: each exit 0.
- Self-index/golden and self architecture rules: exit 0.
- `recalibrate.sh --check`: exit 0 after review artifacts were committed.
- `git diff --check origin/main...HEAD`: exit 0 after mechanical EOF cleanup.

## Findings JSON

```json
[]
```

No `kb/spec.md` or `kb/properties.md` exists, so no projected KB identifiers or
code-quality-auditor result is claimed.
