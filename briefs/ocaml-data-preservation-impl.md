# Implementation Brief — ocaml-data-preservation

**Date:** 2026-09-15
**Mode:** full
**Status:** COMPLETED

## Modified files

- `lib/arch_effects/effects_db.ml`/`.mli`, `effects_load.ml`,
  `ocaml_effects_extractor.ml`, `effects-schema-migration.sql`: source association,
  payload preservation, transaction errors, producer paths and shadow identity.
- `lib/arch_index/arch_index_cmt.ml`/`.mli`, `arch_index.ml`: run-local exact-copy
  graph evidence, successful-extraction eligibility and independent callbacks.
- `test/test_effects.ml`, `tezt/tests/data_preservation.ml`, `main.ml`, `dune`,
  catalogue lifecycle checker: native coverage and retained rejection controls.
- `roster/ocaml-data-preservation/`: standalone acceptance checks, provenance and
  bounded calibration diagnostics; task briefs/spec and preservation docs.
- External roadmap note updated; unrelated dirty files preserved.

## Decisions and evidence

Detailed checkpoint: `roster/ocaml-data-preservation/implementation-progress.md`.
Sol effects implementation followed by root integration; native thread quota
exhaustion required an ephemeral CLI fallback initially. A completed native Sol
agent was reused for a final read-only advisory audit; no formal review claimed.
Its payload-normalization finding was rejected against the frozen distinction
between normalized association and raw payload retention; documentation and a
counterexample test now make that distinction explicit. Its checker gaps and
assertion/setup exit-code issue were addressed.

No new0CFA engine yet. Independently compiled CMT variants remain stage4;
issue #68 remains partial. Implementation is ready for its round commit and
independent review; no PR or merge is claimed.

## Quality gates actually run

- Build: `rtk proxy opam exec -- dune build` exit0.
- Effects native unit suite:13 tests pass at delegated handoff.
- CHECK1: real loader/producer, exit0 after integration and added negative cases.
- CHECK2: real CMT producer, exit0 (genuine RED on exact-copy rejection first).
- Native integration: `opam exec -- _build/default/tezt/tests/main.exe --file data_preservation.ml --keep-going` exit0,2/2.
- Catalogue lifecycle check: exit0 after intentional exact-copy amendment.
- CHECK3 pinned410: exit0;45052 unchanged canonical rows,4849/12171 relations;
  effects360 emitted,139 distinct stored,63 bound/76 unbound.
- Full forced suite at effects-slice boundary: exit1,341/342 Tezt pass,
  MUST-null551 >549. Historical failure retained, not reclassified as green.
- Fresh pristine calibration: A=B545, C=D554; full grouped calls and origin
  groups agree within each corpus. Source-growth only; both temporary worktrees
  and build artifacts removed. User subsequently approved reference524 ->554.
- Full integrated attempt1: exit1,342/344, duration273528ms;
  failures were self-index golden and origin reference drift, not the ceiling.
- Full integrated attempt2 after measured reference updates: exit0,344/344,
  272109ms. Logs/receipts: `improvement/2026-09-15-ocaml-cfa/stage1-integrated-guard-2.{log,json}`.
- Final CHECK1/CHECK2/CHECK3 rerun after full suite: all exit0, same Tezos figures.
- Bundle verification: exit0,22 files SHA-matched, version1.6.0.
- `git diff --check` exit0; no separately configured formatter/linter.

## Approved scope extension and continuation

The user approved adding `tezt/tests/must_null_ceiling.ml` to the manifest before
editing it: reference524 ->554, retaining headroom25/query/floors. The original
PARTIAL event remains in the append-only history. Source-growth evidence is in
`roster/ocaml-data-preservation/calibration-attribution.md`. Existing manifest
permission also covers measured self-index and origin reference changes:
25 modules,1013 functions,6425 calls,583 origins; option/raise328 ->331 only.
The assertion allowlist is unchanged. Two stale migration comments were corrected.

Next: commit this round and run actual Roster review/QA/ship gates.
The seven pre-task unrelated untracked files remain untouched and excluded from
the commit: a documented dirty-tree exception, not a claim of globally clean git.
Final-head required CI must be green before merge.
No later stage starts before stage1 merge.

## Same-round review correction

Root reproduced a schema-valid NULL-path homonym aborting exact-path lookup.
CHECK1 was extended for both main and alternative source columns, proven RED
exit1, then fixed by two SQL `IS NOT NULL` candidate filters. It also verifies
that removing the exact candidate clears the old association and retains payload,
without name fallback. Build/CHECK1–3/hygiene pass; the architect independently
ran the full forced suite on corrected source,344/344 exit0, and all other gates.
Fresh same-corpus old/new-engine comparison remains23329 rows and MUST-null554.
See `roster/ocaml-data-preservation/review-fixes.md`. Final reviewer/spec addenda
are still required before the review verdict; no new upstream phase is claimed.

## Remaining limitations

No formal proof, complete-effects guarantee, effect-resolution gain, CI corpus
availability, coverage percentage, installed formatter or full lint. No silent
golden refresh; no worktree remains from this stage's calibration.
