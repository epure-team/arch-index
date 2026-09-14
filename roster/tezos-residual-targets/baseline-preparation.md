# Attempt2 predecessor preparation — 2026-09-14

Completed before product edits, on fb9c8f3f685d751ee07a81c17fb1ca61860a7365.
This is preparation, not a retained improvement or an additional iteration.

Root reviewed Sol's three preparation scripts and required post-replay input
rehashing, explicit purpose/version validation and phase-state snapshots.
Root permits an absent ACTIVE_TASK for later read-only review/QA replay,
but rejects a foreign task and any phase/scope change during a run.

Actual commands, all exit0:

- `node roster/tezos-residual-targets/check-comparison.js`: initially30 preparation
  controls, then36 with invocation-only multiset/witness-capacity controls.
- `node roster/tezos-residual-targets/prepare-baseline.js --create`: exclusive
  freeze, fresh production and independent frozen-binary replay.
- `node roster/tezos-residual-targets/prepare-baseline.js --check`: another actual
  frozen-binary replay, complete410 catalogue/binding joins and input rehash.
- `node roster/tezos-residual-targets/verify.js --self`: current unchanged producer
  versus frozen predecessor; exact neutral comparison, no retained gain.

All three real productions/replays match45052 canonical rows,
SHA25690e76d6b40b2d7f108fcc25523f85de1cb533a98565a8a7d6d284c1654939d4b,
Irmin4772/protocol11615 distinct relations. Full exact source/input/producer/schema
pins are in ignored `improvement/2026-09-14-tezos-resolution/attempt2-baseline/provenance.json`.
Frozen executable/schema/database are retained for subsequent comparisons;
owned temporary selections and replay databases were removed by each runner.
No additional worktree. Historical attempt1 baseline remains untouched.

Current witness acceptance is deliberately unavailable until implemented and
tested: `verify.js` only supports the preparation `--self` path at this point.
Existing comparator machinery is imported read-only; the attempt2 wrapper
rejects every reexport-row movement even if a historical witness would permit it.
Native tests subsequently established actual assertion RED before product edits.
Full candidate verification/review/QA/ship remain pending.
