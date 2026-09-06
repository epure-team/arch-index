# Formal Verify — mutation-campaign-313

**Date:** 2026-09-06T00:20:00+02:00
**Backend:** quint (human decision at triage, `briefs/mutation-campaign-313-formal-triage.md`)
**Evidence tier:** **E0m-abstract**

## Checker result

Every command below was run by this phase, not reported by a delegate. The tier rests on exit
codes observed here.

| # | Tool | Command | Exit | Outcome |
|---|---|---|---|---|
| 1 | quint 0.32.0 | `quint typecheck specs/mutation-campaign-313.qnt` | **0** | PASS |
| 2 | quint simulator | `quint run specs/mutation-campaign-313.qnt --invariant=allInvariants --max-samples=20000 --max-steps=12` | **0** | PASS — "No violation found" |
| 3 | Apalache 0.56.1 | `quint verify specs/mutation-campaign-313.qnt --temporal=p2ExecutedIsMonotoneOverTime --max-steps=6` | **0** | PASS — "The outcome is: NoError" |
| 4 | red harness | `scripts/check-quint-red.sh` | **0** | PASS — 6/6 injected defects each turned a **named** invariant red |
| 5 | replay driver | — | — | **ABSENT** — no driver in this repository consumes the committed ITF trace |

Row 4 is why rows 2 and 3 mean anything. A green model check with no red harness proves only that
the checker ran; it does not prove the invariants can fail. On its first execution this harness
found one invariant **tautological** — it related the published verdict to a derived value the
publication function ties together by construction — and that invariant was rewritten over the
primitive state before it could ship green and empty.

## Why E0m-abstract and not E0m

**E0m requires a connect-bridge replay to pass against the implementation.** There is no such
replay here. `~/dev/ocaml-quint-connect` exists and provides the machinery, but **nothing in this
repository is wired to it**: no module imports it, and the committed trace
`specs/itf/mutation-campaign-313.itf.json` is generated and stored, never consumed.

So the claim is exactly this, and no more: **the model's invariants are verified; the correspondence
between that model and the OCaml implementation is a manual argument, not a machine-checked one.**
Anyone reading this as "the implementation is verified" would be reading something that was not
established. Follow-up: write a connect driver for the selection function and the verdict
derivation, and replay the trace against them.

**Two limits on row 3 that the tier does not carry on its own.** Apalache documents its temporal
support as experimental, and TLC — the backend its own warning recommends for temporal properties —
**rejects this shape**, because a box over an action requires the subscripted `[A]_v` form that
Quint does not emit here. The temporal result is therefore bounded at 6 steps and caveated at the
tool level, not a general proof.

## Tool resolution — a gap in this gate's own table

Stage 6's deterministic grep found **no skill carrying `capability: formal-quint`**, in
`skills/pipeline/` or in the installed commands. The resolution table's only row for that case
sends the phase to a scaffold offer whose outcomes are "build a skill" or "downgrade to E1".

**Neither describes what happened**, and reporting E1 would be false. E1 means formal verification
was *proposed and declined*; here it was proposed, accepted, and performed — with real tooling, real
executions and observed exit codes. The missing capability tag affects **delegation**, which this
gate's own rule makes redundant anyway: roster re-runs the checker and never trusts a delegate's
self-report. So the substance of the gate ran in full; only the delegation step had no delegate.

Recorded as a finding rather than resolved by picking whichever tier the table permits: **the table
has no row for "no tagged skill, but the tooling is present and the checker ran"**, and that state
is neither a downgrade nor a scaffold.

## Proposition-to-story trace

| Proposition | Parent story | ELI5 |
|---|---|---|
| `p1SurvivorNeedsProvedSuperset` | US-3 | When we only run the tests we *know* touch a piece of code, and the analysis admits it may have missed callers, a mutant nobody killed must be reported as "we don't know", never as "no test catches this". |
| `p1KillIsNeverWeakened` | US-3 | Killing a mutant proves the tests notice the change, whatever the selection was. |
| `p1UnknownsStayDistinct` | US-3 | An escaped analysis and an analysis that never established soundness are different facts and must not collapse into one. |
| `p2ExecutedNeverShrinks`, `p2ExecutedIsMonotoneOverTime` | US-6 | Evidence that a test *did* run through some code may only add that test to the list we run, never remove one. |
| `p2ExecutedIsSupersetOfIntended` | US-1 | The driver never runs fewer tests than the plan says reach the mutant. |
| `p3AttributionNeverInvented`, `p3AttributionOnlyForKills` | US-2 | We never claim to know which test killed a mutant unless we actually do. |
| `p3PendingIsNeverStored`, `p3UnattemptedIsPendingNotSurvived` | US-2 | A mutant nobody has tried yet is "not tried", never "survived". |

**P4 (site-key uniqueness) is deliberately absent from the model.** It is a fact about real corpora,
not a theorem, and no model check substitutes for a probe over the largest available population. It
is carried by CHECK-9 as an empirical gate.

The E0m-abstract claim is conditioned on the accuracy of this proposition-to-story mapping, which
was validated at the spec-formal quiz.

## Not to be confused with this result

The branch's tezt suite is **red on one test** — the whole-repo MUST-with-NULL-callee ceiling, at
373 against a pin of 347 plus 25. That red is main's undeclared drift, not this branch's rows, and
the recalibration was deliberately reverted so a shared gate is recalibrated by one branch at a
time. It is independent of everything above: the Quint verification touches no OCaml code.

## Next step

`/roster-review`. On the E0 path formal verification replaces the QA gate, so there is no separate
`/roster-qa`. Review waits for the rebase after #83 lands, because a complete pipeline cannot close
over a red suite.
