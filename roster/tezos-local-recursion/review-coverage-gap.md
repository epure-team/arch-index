# Review round1 coverage correction — independently verified

Final owner, architect and spec-compliance personal gate runs on ae50e6d all
passed build/full340/bundle/diff and CHECK1–6. The MEDIUM finding is RESOLVED in
round1; the historical observations below retain their original timing. See the
three sibling reviewer/architect/spec-compliance reports for exact evidence and
independence boundaries. Overall convergence, QA and delivery are separate gates.

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

The immutable calibration commit a951936d93227415c8e016493e63701e850e65d4 is
retained by the local-only refs/roster/tezos-local-recursion/calibration reference
so Git garbage collection cannot delete CHECK5's evidence object. No worktree,
build tree, branch movement or remote publication accompanies this reference.
Cross-runtime probe actually ran106.379s: degraded/non-conforming-output,
digest opencode:76f897c73342fdbf. Its response is discarded, never counted as GO;
the authentic invocation journal is briefs/tezos-local-recursion-xruntime.jsonl.
