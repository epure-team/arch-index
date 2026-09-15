# Stage 1 implementation checkpoint — 2026-09-15

Not a review/QA GO or delivery claim. No PR or merge yet.

## Implemented and measured

- Effects source-aware main/alternative/flat association, stale-ID repair,
  complete payload identity, transactional persistence, producer source paths
  and top-level shadow names. Initial implementation delegated to Sol; root
  added regressions/fixes for multiple leading parents and relative explicit
  roots with absolute CMT source metadata.
- Exact-copy graph reuse in one run/root/source/unit. Full-byte comparison plus
  stored representative SHA-256; cache stores only paths/digests/module IDs.
  Per-artifact catalogue/binding collection stays independent. Partial graph
  extraction, changed/unreadable bytes and nonidentical variants cannot borrow
  success. Existing lifecycle tests amended with a retained conflict control.
- CHECK1 and CHECK2 pass. Native `data_preservation.ml`:2/2 pass.
- CHECK3 fixed410 passes:45052 rows, canonical SHA256
  `1799c07fd3eb87d4bca433b15b7daeb47f466f90cb098541372e1dd9dd7bac7a`,
  Irmin4849/protocol12171. Effects360 emitted,139 distinct payloads stored,
  63 bound/76 unbound. No completeness or measured effect-gain claim.

## Genuine RED and harness corrections

- CHECK2 initially exit1 on the native producer's rejected identical copy:
  UNIQUE modules.path, dropped compilation unit. After implementation exit0.
- Producer leading `../../` regression initially exit1 and corrected.
  The first loader companion fixture also lacked an explicit migration path:
  that part was a setup mistake, not genuine semantic RED; corrected before
  accepting GREEN. Do not present it as independent writer RED evidence.
- Relative-root/absolute-metadata CHECK1 regression exit1, then exit0 after fix.
- Existing lifecycle variant probe requires the original module basename;
  initial `altered.cmt` setup exit2 corrected to `variant/catalogue.cmt`.
- The Tezos comparison helper enforces410 by default; unsuitable for local
  whole-build attribution. The local diagnostic now compares actual complete
  grouped calls directly instead of weakening the Tezos helper.

## Gate requiring an explicit scope decision

Initial effects-slice full forced suite:341/342 Tezt pass; MUST-null ceiling
measured551 against549. This was not automatically recalibrated.

Fresh two-worktree 2x2 after integration (both worktrees/builds removed):

| Corpus | old engine | new engine |
|---|---:|---:|
| Pristine base whole-build |545|545|
| Pristine candidate whole-build |554|554|
| Base producer-only calls |6389|6389|
| Candidate producer-only calls |6425|6425|

Each same-corpus pair also agrees on complete grouped-call SHA256, module paths,
origin groups and counts. Snapshot
`fcd229ef7cbeb165e9178c204c19eb76155c692109eb0e540c7e1b6739c69ec6`;
raw evidence under ignored `improvement/2026-09-15-ocaml-cfa/calibration/`.
The reference524 already lagged base545 by21; candidate adds9 source-only rows.
This is not a nine-row resolution regression. User subsequently approved adding
`tezt/tests/must_null_ceiling.ml` to the declared scope and set the measured
reference to554, preserving query/floor/headroom25. Edit applied after manifest
extension. Full integrated attempt1 then exposed two already-authorized golden
reference updates; pristine evidence supports25/1013/6425/583 and option/raise331.
After those updates full forced suite passes344/344 (272109ms), CHECK1–3 and
bundle/diff hygiene also pass. See calibration-attribution.md and impl brief.

Remaining: Roster independent review and QA, exact-head green PR and guarded merge.
Only then stage2/0CFA. Independently compiled CMT variants remain stage4;
issue #68 is partial throughout this stage.
