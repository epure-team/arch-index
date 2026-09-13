## Summary

- Persist artifact-local formal-to-actual provenance for named OCaml functors, local identity aliases and literal curried applications; account for every catalogue occurrence with a match or explicit refusal.
- Add read-only `arch-query DB functor-bindings [limit]`, six renderers, full-snapshot validation and an independent completion marker (main schema1.15; flat unchanged).
- Isolate binding storage from graph/catalogue transactions. A real SQLite global-rollback regression proves earlier facts survive and later inputs still run.

## Scope and evidence

This follows catalogue PR #102. It is **not** general0CFA, actual-module substitution, cross-unit resolution, graph closure or new call-target resolution. Prior digest-verified410-CMT Tezos/Irmin observation:1275 applications,202 matched formals (120protocol/82Irmin),1073 explicit unresolved results. These are provenance counts, not target-precision gains; the saved report identifies its measurement binary.

Reference updates are backed by two fresh symmetric engine/corpus comparisons per checkpoint. The rollback correction is SOURCE_ONLY on both corpora: no same-corpus grouped-call/origin delta. Headroom remains25, with no rules/allowlist relaxation.

## Test plan

- [x] Full local build and QA:320/320Tezt+64Alcotest.
- [x] Four independent acceptance families: inventory, lifecycle, query, compatibility (36 renderer oracles;57 limit-zero corruptions).
- [x] Standalone real-producer two-input global rollback and separate three-input continuation; exact-checkout build, full old/binding row comparisons.
- [x] Official convergence helper verified new checker RED against5338a81 and GREEN after correction.
- [x] Roster review round2 GO,39/39 FR+AC claims verified; QA round1 GO. OpenCode skipped by recorded degraded-runtime breaker, not counted as approval.
- [x] Scope, bundle hashes, whitespace and schema-slot checks.
- [ ] Hosted CI on this exact PR head (required before rebase merge).

CHECK5 runs explicitly in local review/QA outside Dune to avoid nested builds; do not infer that hosted Dune independently runs it. Held PR #93 and private issue remain untouched.
