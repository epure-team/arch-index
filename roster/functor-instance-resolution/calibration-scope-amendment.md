# Quality-gate collateral scope clarification

The first full implementation run exposed an omitted collateral input to the
already-mandatory authentic origin-consumer gate. Its production observation
tracks `lib/arch_index`, which this task necessarily changes. The plan already
requires independently attributed source-growth calibration without weakening
semantic gates; it listed only the self-index golden and MUST-null observation.

Under the user's standing authorization for implementation, full gates, CI fixes
and autonomous review, root added exactly these conditional collateral paths to
the plan, implementer brief and manifest before any edits to those paths:

- `test/fixtures/origin-consumer/reference.json`: measured module/totals/groups
  observation, with explicit revision and review rationale.
- `checks/origin-recurring-consumer.js`: update only the corresponding exact
  expected observation, retaining all assertions and failure semantics.
- `docs/origin-consumer.md`: document the independently reviewed attribution.

No calibration has yet been applied. This does not add `self.allow`, evaluator
changes, calibration-tool changes, new exemptions or relaxed test assertions.
If the failure is policy rather than observational drift, do not relabel it;
fix the in-scope source or surface a genuinely new decision separately.

The base SHA and empty pre-task dirty set are preserved. This is a narrow
quality-gate collateral correction, not a new capability, scope-finding waiver
or permission to accept an unexplained delta. `calibration-audit.md` records
the required evidence. Its first draft overstated a human-only documentation
hold; root checked the cited text and the agent corrected that inference.
