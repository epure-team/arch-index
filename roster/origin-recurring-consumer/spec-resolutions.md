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
