# Roster intake — recurring analysis report runner

## Objective

Make the report profiles usable in recurring local or CI runs, with an explicit
baseline comparison.  The runner consumes already-produced report JSON files;
it must not rebuild an index, replace a baseline, derive findings from Git
text, or turn a partial report into a clean change verdict.

## Contract

`node scripts/analysis-report-consumer.js --report CURRENT.json --scope SCOPE.json
--out NEW_DIR` creates a self-contained first-run package.  With
`--baseline PREVIOUS_RUN.json`, it creates the same package plus a semantic
delta.  Stage7 reports do not carry a corpus fingerprint, so the versioned
scope manifest is mandatory: it is an explicitly supplied, hashable description
of corpus/configuration ownership and must match the baseline byte-for-byte.
The two report inputs must also be complete report-v1 JSON values whose schema,
profile, producer identities and contract availability agree.

The semantic identity of an API inventory row is its published
`file:function` identity.  The comparison classifies identities as `new`,
`unchanged`, or `absent`; it never uses SQLite row IDs or the JSON array order.
The report does not claim an `absent` API is a correction.  It reports a scope
or corpus change separately and refuses comparison if the published scopes do
not match.

## Non-goals

- No producer, call-graph, rules, MCP, SARIF, database or automatic index-build
  change.
- No gate policy: a successful consumer validates and describes a comparison;
  it does not say that a code change is safe.
- No baseline promotion/replacement, fallback from missing profile data, or
  approximate matching.

## Acceptance evidence

1. First run is complete and deterministic from one `api-review` report.
2. Comparison is stable under reordered arrays and uses only the declared API
   identity.
3. New/unchanged/absent counters and rows reconcile exactly in `delta.json`.
4. Changed profile/schema/producer/scope, incomplete report, duplicate identity,
   missing `api_surface`, malformed JSON, existing output and bad options exit
   2 and never publish a successful completion record.
5. `run.json`, `delta.json` and `diagnostics.txt` form a closed final package;
   `run.json` is written last and hashes the other artifacts.
6. Documentation gives one local command, explains the limits, and shows that
   baseline promotion is an explicit human review action.
