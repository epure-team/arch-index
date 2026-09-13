# Reviewer Brief — functor-instance-resolution

**Date:** 2026-09-13
**Status: VALIDATED**

Worktree: /home/mathias/dev/arch-index-worktrees/functor-instance-resolution.
All shell commands start with rtk; use explicit existing opam switch above for
compiler/build work. apply_patch owns edits. One shared worktree; do not create
another or run Dune concurrently. Preserve unrelated files and never stage cost.jsonl.
No third-party scans, issue publication, graph precision/Tezos gain or formal proof.

## Review target (expected, not yet implemented)

Audit the catalogue slice against the complete spec and implementation brief.
Read collector/native probes, process_cmt integration, run lifecycle/drop/markers,
query validator/formatter and independent check script first. Check everyFR/AC.

## Risks to verify

- All reachable immediate module applications, no Env/Types/Shape expansion.
- One definition/body unchanged; catalogue failures cannot promote/remove graph facts.
- Identity exact selected path/preorder; locations/shadowed names cannot collapse sites.
- Per-input atomic publication, selected/expected counts and real provenance.
- Stale marker absent after reindex failures; only complete nonempty selection earns v1.
- Query uses one read-only snapshot, validates ALL data before applying limit/output.
- Stable schema/marker/consistency refusal precedence and empty stdout on refusal.
- Native/probe premise checks, closed descriptors/locations/codes and Papply non-occurrence.
- No silently skipped gates, self-confirming oracles, or test-runner exit remapping.
- Main additive version checked at ship; flat schema and unrelated contracts unchanged.
- Any new self-index pin change backed by measured source attribution, not weakening.

## Scope

Authorized product files and pipeline exceptions are in plan/manifest. The four
standalone checks and native fixtures must be wired into tests. No cost telemetry
or private issue publication. Claims metadata remains draft without installed tool.

## Quality gates

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

