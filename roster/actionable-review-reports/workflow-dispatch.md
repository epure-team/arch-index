# Workflow dispatch — actionable-review-reports

Plan8dce35a, schema1.0, Full. Installed roster canonical source:
/home/mathias/dev/agent-roster/workflows/templates/full.cwr.json, template version1.0.0.
Project template prerequisite was absent; supplied a temporary local copy, generated the
execution-only instance with unchanged template steps and literal TASK placeholders, then
validated JSON, exact step equality and plan/template skill IDs. Non-TTY fallback: no workflow
staging/commit. CWR executable is absent, so no CWR lint/run or hook execution is claimed.
Dispatch is manual roster-implement → roster-review → roster-qa → roster-ship.

Generated workflow, ephemeral sidecar and temporary template were removed exactly after
dispatch selection. No durable harness change or new runtime dependency. Working tree was clean
before writing this small audit note. No ledger phase invented for the phase-null skill.
