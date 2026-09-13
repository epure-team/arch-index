# QA Scope — functor-instance-resolution

**Date:** 2026-09-13
**Status: VALIDATED**

Worktree: /home/mathias/dev/arch-index-worktrees/functor-instance-resolution.
All shell commands start with rtk; use explicit existing opam switch above for
compiler/build work. apply_patch owns edits. One shared worktree; do not create
another or run Dune concurrently. Preserve unrelated files and never stage cost.jsonl.
No third-party scans, issue publication, graph precision/Tezos gain or formal proof.

## Deterministic gates

```bash
rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune build --root .
rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune test --root .
rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- node scripts/check-functor-catalogue.js inventory
rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- node scripts/check-functor-catalogue.js lifecycle
rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- node scripts/check-functor-catalogue.js query
rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- node scripts/check-functor-catalogue.js compatibility
rtk proxy node scripts/review-bundle-verify.js
rtk proxy git diff --check
```

No formatter/linter configured; git diff --check is hygiene only. Bundle integrity
is not product test coverage. Full build precedes tests. Record actual Tezt/Alcotest
counts and skips, not cached collection counts. CI self-index/golden/recalibration,
architecture rules, origin-consumer/artifacts and change impact remain required at
shipping; absent MCP credentials are a recorded skip, not a pass.

## Behavioral coverage

Read full spec and map every AC1–16 to real checks. Inventory covers native
ordinary/unit/nested/local/anonymous/opaque cases, ghost/Papply probes with explicit
premises and unchanged definitions. Lifecycle covers every failed outcome, atomic
input rows, marker earning/clearing, interrupted and repeated index, duplicate
path/module cases. Query uses independent crafted DBs, all schema/data/refusal
branches, invalid data beyond limit0, exact two-table output across formats,
strict decimal/overflow/extra args, valid empty and byte-unchanged read-only DB.
Compatibility compares fixed graph/effect/query fixtures, not only counts that
could stay equal while identities drift. No TUI/web/MCP/third-party tests in scope.
