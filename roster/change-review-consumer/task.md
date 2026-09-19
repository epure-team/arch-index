# Roster intake — change-review sidecar consumer

## Objective

Create the first explicit, read-only consumer for `arch-impact --format json`.
It packages a raw briefing, an explicit corpus/configuration scope manifest,
and a normalized descriptive delta. It is not a gate or risk verdict.

## Input compatibility

Before comparing, require both impact briefs to be computed and to have:

1. `impact_input.version == 1`, identical mode/range/changed-file map;
2. `index_provenance.version == 1`, identical schema version, stable producer
   identity (name/version/soundness; digest preserved but excluded) and exact
   coverage;
3. `contract_ok == true`, `sound_reachability == true`,
   `resolved_cone == possible_bounded`, exact `[MUST,MAY_ENUMERATED]` kinds;
4. equal explicit v1 scope manifests; no unmatched or file-granular inputs;
5. available decision analysis on both sides.

Any mismatch is a refusal, not an `absent` observation. A first run is an
explicit no-baseline package.

## Output

`impact.json`, canonical `scope.json`, `delta.json`, `diagnostics.txt`, and
final hash-bearing `run.json`. Normalized rows are descriptive identities only:
`touched file:function`, bounded possible exports/tests, observed TOP frontier
holders, and decision `file:line:form`. `new`, `unchanged`, and `absent` do
not carry a correctness/security/risk meaning.

## Non-goals

No index build, Git parsing, baseline promotion, policy exit based on delta,
severity, source digest, hidden TOP target enumeration or MAY→MUST upgrade.
