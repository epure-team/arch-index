# Self-reference investigation

Main ran the full336 suite with `--keep-going`, using the built executable under
the root opam switch. Actual exit1:334 passed, two failed. Raw output is
`improvement/2026-09-14-tezos-resolution/attempt3-guard-precalibration.log`.
The point-free flat LSP test and all four new Tezt tests passed in this run.

The failures are the exact self golden and the authentic origin-consumer check.
Main then ran the real origin consumer into the new owned output directory
`attempt3-origin-before-refresh`; it correctly returned `policy-failed`, exit1.
Measurements are25 modules,999 functions,6332 calls,566 origins. Relative to the
retained reference: functions+10, calls+57, origins+2 (exception/compare+1 and
option/raise+1); assertion origins remain exactly1.

The existing sole allowed assertion moved from
`collect_calls_from_expr.<fun:1545:21>.<fun:1556:36>` at line1559 to
`collect_calls_from_expr_with_open_bodies.<fun:1593:21>.<fun:1604:36>` at line1607.
Its `split_last` assertion source is unchanged. This is a relocation of the same
source assertion, including its private implementation owner name, not a second
allowance. A refresh still requires source-only attribution and leaves x1 and
the rule policy unchanged.

The authentic check duplicates both exact reference totals and the sole allowed
identity in `checks/origin-recurring-consumer.js`. Under the intake's conditional
exact-reference authority, this single collateral path was added to the manifest
before edits. Only those two expected constants may change after attribution;
no test deletion, dynamic self-derived expectation, extra allowance, threshold,
or policy/fixture change is authorized. The original manifest base and dirty
header are preserved. No reference has been refreshed at this stage.

Pristine crossed measurements are in progress separately; an incremental
self-corpus measurement alone is not accepted as source-only attribution.

## Pristine attribution and authorized refresh (2026-09-14)

The first root measurement (`25/999/6332/566`) came from an intermediate CMT,
not from the final clean root build. After `dune build`, the only changed CMT
was `arch_index_cmt`, whose SHA-256 moved from
`d0d55636aba165f095df249c1510cbce8e662a2e73e6fc3b96ea92c42efe41b0` to
`8002f946ded9f8fa818baf4df8a05103cc13dc245887713f77a598f229ee79df`.
The exact clean-root measurement is therefore `25/998/6335/570`.

The pristine crossed calibration establishes source-only attribution: golden
cells A=B=`25/989/6275` and C=D=`25/998/6335`; the ceiling moves from 538 to
541 while the pinned `524 +/- 25` band remains unchanged. The origin 2x2 is
A=B=564 and C=D=570, with `exception/compare` 49 -> 50 and `option/raise`
315 -> 320. Evidence is retained in
`improvement/2026-09-14-tezos-resolution/attempt3-pristine-explain.log` and
`attempt3-pristine-origin-2x2.json`.

The pre-refresh authorization JSON was recorded at 21:05 UTC before the four
references were changed; it is retained as
`attempt3-reference-refresh-authorization.json`. Those four exact references
are now refreshed. The sole assertion identity is
`collect_calls_from_expr_with_open_bodies.<fun:1595:21>.<fun:1606:36> | lib/arch_index/arch_index_cmt.ml:1609 | assert | Assert_failure | x1`.
It remains the same source assertion, with no extra allowance or policy change.

The main full guard is still running, so this note does not claim that it
passes. Delivery status remains 2/5 shipped. Attempt 3 has CHECK-4 PASS:
316 additional protocol relations, zero additional Irmin relations and zero
lost relations, but has not passed KEEP, review, QA or ship.
