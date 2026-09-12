# Research — origin-recurring-consumer

_Generated: 2026-09-12T18:00:13.972Z_
_Mode: full; online research enabled_
_Three reused Sol/Terra documentary contexts: analyzer, combined locator/pattern finder, external researcher. Not fresh-context isolation. No implementation proposals requested._
_No acknowledged graph-orientation pack; live files used. Neutral manifest closed shape/digest checked locally; claims reconciler absent._

## Question 1: Quelles interfaces existantes exécutent `forbid origin`, et quels formats de sortie, codes de retour et champs de résultat exposent-elles aujourd’hui ?

**Finding:** arch-rules reads rules, calls the shared evaluator and renders text/md/json/SARIF.
Its policy controls UNKNOWN/POSSIBLE/vacuity/NOT_COMPUTED independently of the rule verdict.
Exit 1 denotes policy failure, 0 policy success, 2 invalid input/refusal. arch-report --rules
uses the same evaluation but exit 0 denotes successful report publication, including violations.
MCP has a subprocess wrapper; it was read, not built or protocol-tested.

**References:**
- `bin/arch_rules/arch_rules.ml:127` — options; `:167` evaluation; `:470` policy exit; `:491` error handling.
- `bin/arch_rules/arch_rules.ml:253` — JSON computed/contract/policy counters; `:277` per-rule results.
- `bin/arch_report/arch_report.ml:20` — interface; `:67` rule-aware report path.
- `docs/reporting.md:16` — report success distinct from gate success.
- `bin/arch_mcp/arch_mcp.ml:444` — architecture_rules subprocess interface.

## Question 2: Comment le codebase représente-t-il actuellement la couverture, l’indisponibilité, l’incertitude, les témoins, les totaux et les omissions pour les règles d’origine ?

**Finding:** eight rule verdicts remain distinct. Missing/flat/empty origin storage gives
NOT_COMPUTED; unknown schema form/channel is refused; empty source selection gives NO_SOURCE.
Coverage for an origin rule is currently human-readable note text, not structured numeric
coverage fields. It includes cone nodes, origin occurrences, forms, channel, sites, allow entry
count and unmatched allow entries. Offender contexts are structured separately.
No offenders with an escaping cone gives UNKNOWN, not PASS; a closed contracted cone can PASS.

**References:**
- `lib/arch_tools/arch_rule_eval.ml:40` — vocabulary.
- `lib/arch_tools/arch_rule_eval.ml:890` — missing/flat origins; `:899` empty-table refusal.
- `lib/arch_tools/arch_rule_eval.ml:912` — forms must be schema-declared (not necessarily populated).
- `lib/arch_tools/arch_rule_eval.ml:927` — channel present; `:939` source vacuity.
- `lib/arch_tools/arch_rule_eval.ml:1041` — coverage string, including unmatched allow entries.
- `lib/arch_tools/arch_rule_eval.ml:1055` — 200 displayed sites and independently bounded contexts.
- `lib/arch_tools/arch_rule_eval.ml:1081` — UNKNOWN; `:1103` closed-cone verdict.
- `lib/arch_tools/arch_report.ml:226` — rule reporting, unavailable census when no rules supplied.

## Question 3: Quels invariants existants gouvernent l’identité des sites, les décomptes, les allow-lists, les verdicts et les limites d’évidence de `forbid origin` ?

**Finding:** allow identity is function/file/line/form/exception plus a positive occurrence
allowance. Duplicate allow identities are invalid. Origin query uses function IDs, selected
forms/channel and escapes=1 over the source's forward cone. Stale allow entries are reported
but do not fail, because they exempt no observed site. More occurrences than the allowance
or a new identity yields VIOLATION even if the cone also reaches top.

**References:**
- `lib/arch_tools/arch_rule_eval.ml:119` — centralized identity; `:177` positive count; `:208` duplicates.
- `lib/arch_tools/arch_rule_eval.ml:285` — only file/fn source selectors.
- `lib/arch_tools/arch_rule_eval.ml:951` — source cone; `:977` SQL selection; `:1000` counting.
- `lib/arch_tools/arch_rule_eval.ml:1016` — new/increased sites; `:1034` stale entries.
- `bin/arch_rules/arch_rules.ml:238` — seven census buckets partition rules (NO_SOURCE and
  NO_TARGET combined as vacuous), while failing is a separate policy count.

Existing query pattern:

```sql
WHERE o.escapes = 1
AND o.form IN (SELECT value FROM json_each(?))
AND o.function_id IN (SELECT value FROM json_each(?))
```

The channel predicate is added for schemas carrying the channel column.

## Question 4: Quels corpus, fixtures et scénarios positifs ou négatifs possédés par le projet exercent déjà les origines, leurs canaux, leurs formes et leurs cas d’absence ou de données malformées ?

**Finding:** owned OCaml fixtures exercise same-line multiplicity, catches, operator names,
option channel, unknown callbacks, many sites, missing origin data and invalid allow inputs.
A separate checker covers typed divisor metadata, old schemas and malformed rows. These are
test fixtures, not an observed deployment consumer.

**References:**
- `tezt/tests/rules_origin.ml:72` — fixture source: duplicate same-line divisions, caught division,
  assertions, 25 distinct sites, option channel and callback.
- `tezt/tests/rules_origin.ml:336` — refusal/accepted controls for selectors, forms/channels and allow files.
- `tezt/tests/rules_origin.ml:536` — 201-row cap tests with independent site/context totals.
- `tezt/tests/rules_origin.ml:839` — pre-channel schema behavior and unsupported channel refusal.
- `tezt/tests/report.ml:526` — authentic report --rules fixture, JSON/SARIF/HTML and schema validation.
- `checks/actionable-review-reports.js` — four authentic CLI modes plus controlled error mapping.
- `tezt/tests/schema_column_guards.ml`, `tezt/tests/sarif_out.ml` — located related schema/format patterns.

## Question 5: Quels workflows CI, scripts de contrôle et mécanismes de recalibration existants exécutent des analyses récurrentes sur des entrées bornées ou épinglées, et quelles preuves durables produisent-ils ?

**Finding:** CI builds and tests, indexes only _build/default/lib/arch_index, compares SQLite
counts against a committed three-line golden, runs attributed recalibration and evaluates
the four reachability rules in arch-rules.txt with vacuity failure. It does not contain an origin
rule or upload-artifact step for these outputs. The DB/stats are job temporaries; the golden
and rule files are versioned, while CI execution output survives as GitHub logs according to
the platform's retention, not as a versioned result artifact.

**References:**
- `.github/workflows/ci.yml:99` — build/test section; `:128` self-index; `:140` golden diff.
- `.github/workflows/ci.yml:222` — recalibration; `:292` architecture rules; `:298` impact.
- `arch-rules.txt:1` — four reachability rules over comment parser, CFG, line counter and LSP client.
- `test/fixtures/self-index-stats.txt:1` — 23 modules, 828 functions, 5223 calls.
- `docs/adr/001-self-index-golden.md:8` — committed golden and update procedure.
- `scripts/recalibrate.sh:48` — check exit 0 current, 1 stale, 2 refused/unusable measurement.
- `tezt/tests/recalibrate_self_test.ml:42` — at least 100 self-test cases; `:143` CI SQL comparison.

Existing CI consumer:
```sh
./arch-rules "$RUNNER_TEMP/self.db" arch-rules.txt --on-vacuous fail
```

## Question 6: [ecosystem] Comment les outils établis de policy gating mesurent-ils la couverture et la stabilité de règles récurrentes sur un corpus de référence versionné ?

**Finding:** OPA separates policy-test outcomes and exposes line-evaluation coverage; its
--fail-on-empty flag is opt-in (default no-test execution can succeed). Coverage measures
policy execution, not longitudinal corpus stability. Semgrep documents full scans on main
and differential scans against a Git baseline, such as SEMGREP_BASELINE_REF.

**References:**
- [OPA Policy Testing](https://www.openpolicyagent.org/docs/policy-testing), official docs, accessed 2026-09-12.
- [OPA CI/CD](https://www.openpolicyagent.org/docs/cicd), official docs, accessed 2026-09-12.
- [Semgrep CI configurations](https://docs.semgrep.dev/semgrep-ci/sample-ci-configs), official docs, accessed 2026-09-12.

## Question 7: [ecosystem] Quels formats ou pratiques existants distinguent-ils un contrôle réussi, une violation détectée, une analyse indisponible et une dérive du corpus ou de sa baseline ?

**Finding:** SARIF separates result kinds from invocation success and baseline states.
Absent/null results indicates analysis did not start; [] indicates no results detected,
not a certificate that every rule passed. Emission of pass/notApplicable results is optional.
If baselineState is emitted, the comparison requires classified results (new, unchanged,
updated, absent); without it no complete-baseline comparison is asserted. OPA separately
distinguishes PASS/FAIL/ERROR/SKIPPED. No cross-tool equality of these vocabularies is assumed.

**References:**
- [OASIS SARIF 2.1.0](https://docs.oasis-open.org/sarif/sarif/v2.1.0/os/sarif-v2.1.0-os.html),
  standard 2020-03-27, sections 3.14.23, 3.27.9, 3.27.24 and invocation executionSuccessful.
- [OPA Policy Testing](https://www.openpolicyagent.org/docs/policy-testing).

## Patterns found

| Pattern | Location | Evidence |
|---|---|---|
| Policy versus evaluation | bin/arch_rules/arch_rules.ml:238 | seven census buckets, separate failing count |
| Counted exemptions | lib/arch_tools/arch_rule_eval.ml:1016 | new or increased occurrence count violates |
| Honest incomplete cone | lib/arch_tools/arch_rule_eval.ml:1081 | UNKNOWN even when every observed site is allowed |
| Independent limits | tezt/tests/rules_origin.ml:536 | 201 occurrences, 200 emitted, one omitted |
| Attributed baseline | scripts/recalibrate.sh:48 | base/new producer × base/new source measurement |

## External prior art

| Approach | Source | Existing behavior |
|---|---|---|
| OPA explicit nonempty gate | https://www.openpolicyagent.org/docs/policy-testing | --fail-on-empty and separate error/skip outcomes |
| OPA coverage gate | https://www.openpolicyagent.org/docs/cicd | structured coverage queried by policy in CI |
| Semgrep Git baseline | https://docs.semgrep.dev/semgrep-ci/sample-ci-configs | full versus differential Git-referenced scans |
| SARIF result/invocation/baseline separation | https://docs.oasis-open.org/sarif/sarif/v2.1.0/os/sarif-v2.1.0-os.html | execution success and finding/baseline status are distinct |

## Coverage gaps and corrections

No new corpus was executed during documentary research, and no reviewer-time reduction was
measured. MCP was not built. arch-rules.txt references selftest-selfrules.sh in a comment,
but that file is absent at the worktree root; the actual CI command above was verified.
Initial pattern-finder CI offsets and conflated recalibration exit1/refusal wording were
corrected against current files. The external researcher's initial blanket claim that absence
of results cannot accompany success was corrected: OPA default no-test success and optional
SARIF pass emission are explicit counterexamples. No future-consumer intent inference retained.
