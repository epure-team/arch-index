# Implementation checkpoint — Stage 5 OCaml CFA qualification

## Delivered bounded slice

- `arch-impact` now calls its `MUST ∪ MAY_ENUMERATED` closure
  `possible_bounded` in JSON and human output. It no longer calls a mixed MAY
  path definite or ground truth. The existing `MAY_TOP` frontier remains a
  separately reported open-world limitation.
- `docs/change-impact.md` explains the three-way distinction in operator terms:
  only `arch-query reaches` provides a MUST-only positive path; a closed
  bounded cone does not promote MAY to MUST.
- The task checker composes existing authentic evidence rather than a synthetic
  surrogate: a real CMT CFA fixture exercises MUST-only / MAY / TOP queries,
  impact tests verify output wording and machine fields, and the frozen 410-CMT
  replay verifies relation preservation, target-v2 witnesses and resource
  observations.

## Verification completed

- `opam exec -- node roster/ocaml-cfa-qualification/check-cmt.js` — pass.
  It ran 7 authentic query/impact tests and a fixed-410 replay: +7 Irmin, +0
  protocol, zero loss and zero new/upgraded MUST; wall 3521ms, RSS unavailable
  and explicitly not a bound.
- Checker controls: assertion exits 1; setup exits 2.
- `opam exec -- dune exec --root . tezt/tests/main.exe -- --job-count 1` —
  **354/354 pass**. Expected injected-failure diagnostics are emitted only by
  their owning passing tests.
- `git diff --check` — pass.

## Explicit limits

This qualifies a bounded same-CMT CFA/functor subset. It does not measure
recall, prove whole-program/cross-unit completeness, create a generic benchmark
CLI, set a performance SLA, or classify a known MAY edge as a vulnerability or
a definite execution. Public target-v2 queries, analysis profiles and recurring
comparisons remain the later approved stages 6–8.
