# Pristine committed-tree calibration

Historical975c73b calibration. Occurrence-provenance repair requires a fresh
committed-tree run; the counts below are not claimed for those later bytes.

2026-09-14, actual command exit0. Candidate
975c73b49def2813517b00c296006417d062d8b2, predecessor
fb9c8f3f685d751ee07a81c17fb1ca61860a7365.

Root ran the unchanged scripts/recalibrate.sh from a clean, detached candidate
checkout to preserve unrelated dirt in the main checkout. Its own two detached
worktrees were built from these exact commits. Raw log:
improvement/2026-09-14-tezos-resolution/attempt2-pristine-calibration.log.

```
rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- env TMPDIR=/tmp/arch-index-attempt2-pristine.oMg09d DUNE_CACHE=enabled DUNE_CACHE_STORAGE_MODE=copy bash scripts/recalibrate.sh --check --base fb9c8f3f685d751ee07a81c17fb1ca61860a7365
```

| Metric | A old/old | B new/old | C old/new | D new/new |
| --- | --- | --- | --- | --- |
| lib/arch_index modules/functions/calls | 25/980/6245 | 25/980/6245 | 25/989/6276 | 25/989/6276 |
| whole-tree non-Stdlib MUST without target | 537 | 537 | 538 | 538 |

Both metrics are SOURCE_ONLY. Golden bytes are current; ceiling538 is inside
the unchanged524±25 band. No automatic write, threshold change or exception
relaxation occurred. This confirms the earlier incremental self calibration on
clean committed corpora; aggregate equality does not establish semantic soundness
on arbitrary programs. Reviewed fixed410 evidence remains a separate gate.

The script's two build worktrees were removed by its normal exit cleanup.
Root verified the outer checkout clean, removed that exact worktree with
git worktree remove (without force), listed its now-empty parent, then removed
the empty parent with rmdir. All three owned worktrees/builds are gone; small
logs remain. No foreign worktree or frozen comparison baseline was touched.
