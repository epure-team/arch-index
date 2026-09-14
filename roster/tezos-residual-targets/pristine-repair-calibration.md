# Pristine repair calibration

Actual exit0 on436cbfc667a5f01880fd9c11f53242c8fffb6ed3,2026-09-14.
Predecessor fb9c8f3f685d751ee07a81c17fb1ca61860a7365.
The unchanged scripts/recalibrate.sh ran in a clean detached checkout and built
its own two pristine comparison checkouts. Command after rtk proxy:

```
opam exec --switch=/home/mathias/dev/arch-index -- env TMPDIR=/tmp/arch-index-attempt2-repair-pristine.36lVy3 DUNE_CACHE=enabled DUNE_CACHE_STORAGE_MODE=copy bash scripts/recalibrate.sh --check --base fb9c8f3f685d751ee07a81c17fb1ca61860a7365
```

| Metric | A old/old | B new/old | C old/new | D new/new |
| --- | --- | --- | --- | --- |
| Self modules/functions/calls |25/980/6245|25/980/6245|25/989/6275|25/989/6275|
| Whole-tree non-Stdlib MUST without target |537|537|538|538|

Both controls are SOURCE_ONLY. The exact golden is current; ceiling538 remains
inside the unchanged524±25 band. No threshold, rule or extra allowance changed.
This completes the fresh four-cell check required after the incremental C/D
diagnostic; it does not claim arbitrary-program semantic soundness.

Raw output: improvement/2026-09-14-tezos-resolution/attempt2-pristine-repair-calibration.log.
Script-owned build checkouts were removed normally. Root verified the outer
checkout clean, removed that exact worktree with git worktree remove without
force, verified its parent empty and removed the empty parent with rmdir.
All three owned worktrees/builds are gone. Frozen history and foreign worktrees
were untouched. The current root owner review ran independently; no root source
or report writes overlapped its source-state-sensitive checks.
