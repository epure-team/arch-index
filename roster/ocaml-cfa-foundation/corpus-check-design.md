# CHECK-3 implementation boundary

Read-only Terra design reviewed by root, 2026-09-16. This is a handoff,
not a completed checker, Roster verdict, or semantic soundness proof.

Implement a stage2-specific checker; do not weaken the existing frozen
comparators. Reuse canonical snapshot/selection helpers only after checking
their pins and assumptions. In particular the residual-targets source-state
helper is not a stage2 freshness gate.

## Inputs and accounting

- Frozen stage1 snapshot: 45052 canonical rows, SHA256
  `1799c07fd3eb87d4bca433b15b7daeb47f466f90cb098541372e1dd9dd7bac7a`;
  existing slice relation definitions yield Irmin4849/protocol12171.
- Pinned410 manifest SHA256:
  `9e38880a52f855c58081b1a171af5879058cbaa2697aaa5694827cbd16f8ecd1`.
- Verify every selected CMT hash, producer/schema identity, and source state
  before and after the run. Record Tezos revision/status without modifying it.
- Create only an owned temporary selection/database; remove these in finally.
- Emit exact canonical row multiset additions/removals including multiplicity.
  Separately report relation-set gains/losses using the existing documented
  relation definition. If also reporting relation multiplicities, label them
  distinctly: extra rows are not necessarily new relations.
- Record every changed row, totals, digests, slice metrics, and new MUST rows.
  Do not turn the preliminary 8 removed/10 added/3 gained into a fixed oracle.

The frozen baseline must remain byte-identical. A successful measurement is
not approval of every semantic delta: the plan additionally requires each
delta to be explained and reviewed. File/line correspondence is not physical
application identity, and does not prove a one-to-many refinement sound.
Keep `semantic_status: "not_proven"` explicit in machine-readable output.

## Resources and exit contract

Measure producer wall time with a monotonic clock. If Linux /proc sampling is
used, identify RSS as a sampled observation, not an exact portable peak; report
null and the reason when unavailable. Never report the Node runner's own
resourceUsage as producer memory. No new resource threshold is specified.

Exit0 means the measurement and its declared checks completed; exit1 is an
explicit assertion mismatch; >=2 means missing corpus, malformed input/output,
build/load/production failure, timeout, or other unavailable environment.
Provenance drift must not silently produce an accepted report. Corpus absence
must not fail the self-contained native CI suite or be represented as green.

The proposed no-new-MUST/no-relation-loss diagnostics are useful regression
guards, but the governing FR043 requires exact gains/losses to be reported.
Do not invent a semantic proof gate or erase losses to satisfy a counter.
Review unexpected deltas before shipping.
