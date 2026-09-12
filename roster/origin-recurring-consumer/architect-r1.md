# Architect R1 — origin-recurring-consumer

## Verdict

No critical architecture or acceptance-contract violation found. Overall architecture risk is
**medium** because the fail-closed behavior is implemented coherently but its lifecycle and
rollback invariants are concentrated in one oversized mutable orchestration function.

This is not a fresh independent planning voice: this specialist previously supplied the second
architectural decomposition for the same feature. The implementation review itself covered the
completed diff and was verified independently in the granted build slot.

## Critical findings

None.

## Important warning

### MEDIUM — monolithic consumer lifecycle increases invariant-coupling risk

- Location: `scripts/origin-consumer.js:147`
- Category: architecture
- Confidence: 5/5
- Fingerprint: `origin-consumer-monolithic-lifecycle-orchestrator`

`runConsumer` spans lines 147-277, about 131 lines versus the architect role's configured
50-line function threshold. It combines output admission, configuration, Git and input
provenance, indexing, measurement, gate/report execution, evidence parity, publication,
rollback, transient cleanup, diagnostics and terminal-result emission through shared mutable
state. This matters especially because AC-10, AC-14 and AC-16 impose ordering-sensitive
precedence and publication guarantees across `try`/`catch`/`finally`.

The current behavior is exercised and passing; this is not a reproduced correctness defect.
The structural risk is that a later change to cleanup or evidence publication can silently alter
a distant status/retention invariant. The adverse checker repeats the concentration in
`checks/origin-recurring-consumer.js:94-236`, where one roughly 143-line function contains nearly
all failure scenarios.

Fix direction: preserve `runConsumer` as the sole public runner seam, while extracting private
phase functions for admission/configuration, immutable input snapshot, indexing/measurement,
policy/report evaluation, publication validation, and finalization/rollback. Pass a small
explicit terminal-outcome object into finalization instead of mutating `exit`, `status`, and
`complete` across all three control-flow regions. Split adverse controls along those phases
without changing the three contractual checker modes.

## Optional improvements

None beyond the warning's phase-oriented refactor. No subjective formatting or naming nits are
raised.

## Executed verification

- `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune build --root . @install`
  — chunk `0a0dfe`, exit 0.
- `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune test --root . --force`
  — session `16449`, terminal chunk `23d2a3`, exit 0; 245/245 Tezt tests succeeded,
  together with the emitted Alcotest suites.
- `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- node checks/origin-recurring-consumer.js authentic`
  — session `11556`, terminal exit 0.
- `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- node checks/origin-recurring-consumer.js failures`
  — session `60628`, terminal exit 0; expected injected cleanup/final-record diagnostics were
  observed.
- `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- node checks/origin-recurring-consumer.js package`
  — chunk `c4a3cd`, exit 0.
- `rtk proxy git diff --check` — chunk `fd524d`, exit 0.

The checker and runner exit contracts remain distinct: authentic policy-failure scenarios return
runner exit 1 but are correctly observed by a checker that returns 0; deliberate checker
assertion and execution controls remain checker exits 1 and 2, as confirmed by the full suite.

## Review coverage and residual risk

Reviewed the complete `main...HEAD` product diff, role briefs, all specification acceptance
criteria and entities, and the modified runner, validator, checks, fixtures, Tezt registration,
CI and documentation. No coupling to the existing evaluator implementation, public report schema,
production library, or four reachability rules was introduced. The fixture-only configuration
and fault seams remain behind the exported test runner while the production CLI exposes only
`--out`, consistent with AC-1 and AC-8.

Hosted artifact delivery was not executed locally; the package checker and workflow structure
cover its repository-side contract. This is a verification limitation, not an architecture
finding.
