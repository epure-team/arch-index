# Review round1 coverage correction — root GREEN, independent verification pending

The owner reviewer independently ran build/full340, CHECK1–6, bundle and diff
on3181262: all exit0. Raw evidence is in
improvement/2026-09-14-tezos-resolution/attempt4-review-owner-sFGYKj/.
This was not a final review GO.

Owner and spec-compliance independently confirmed one MEDIUM coverage finding,
FR-009/AC-15: native-preservation-probe.ml:71 discarded dependencies/type usages;
its emitted payload omitted module/type/rebind semantic shape. Mutation/deref
columns existed but the fixture did not require nonzero activity. No product bug,
Tezos loss or incorrect candidate target was demonstrated by this finding.

Stricter assertions were added before extending the fixture/probe. Actual
coverage RED: attempt4-coverage-red-lAJ6D6/check1.log, exit1 in2025ms,
`ASSERTION: old modules preservation array present`. This proves a coverage
omission, not a new failing product behavior or a fourth discarded attempt.

The same-round correction is restricted to check-native.js and
native-preservation-probe.ml: retain every old assertion/output, add independently
compiled nonempty semantic families and exact counted before/after equality.
Product, public schema, native witness algorithm, pinned410 and all reference
authorizations remain unchanged. Verification and independent review are pending.

Root GREEN now executed: attempt4-coverage-validation-xFi95E/check1.log,
exit0 in28544ms, source_state_unchanged=true. Both predecessor/current snapshots
must now exercise nonzero mutation/deref and nonempty module/dependency/type/
field/constructor/rebind/catch families plus a module_alias edge. Every existing
assertion and output field remains. SQL read errors now fail instead of silently
ending a result set. Native target, full paired rich/flat comparison and four
actual Tezt storage/exclusion tests all pass. Independent final review remains.
