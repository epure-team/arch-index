# Clean-build ratchet: scope decision required

2026-09-13. Product checkpoint: 68e77df61c68f811331180abfc25293911b2f955.

The earlier 255/255 Tezt +64 Alcotest result is real but used the corpus produced
by @install and the test executable build. It is **not** a clean/full-build CI GO.
The full build adds artifacts to the whole-repository population measured by the
existing MUST-with-NULL-callee ratchet. No assertion was weakened or pin modified.

Fresh `scripts/recalibrate.sh --check` under the project switch, DUNE_CACHE enabled,
session2307, terminal exit1:

| Metric | Pinned | A base/base | B new/base | C base/new | D new/new |
| --- | --- | --- | --- | --- | --- |
| modules/functions/calls | 23/828/5223 | 23/828/5223 | 23/828/5223 | 23/828/5223 | 23/828/5223 |
| MUST-with-NULL, Stdlib excluded | 383 | 396 | 396 | 430 | 430 |

Base is merge-base with origin/main77c7691436a7. B=A: observed movement is due to
the corpus change, not a different extractor on the same corpus. Existing pin383
plus headroom25 gives ceiling408;430 exceeds it by22. Delta from measured base is34.
This does not prove every unresolved reference is harmless.

Confirmed without changing source: `dune build --root .` exit0, then direct Tezt
`--file must_null_ceiling.ml --keep-going` exit1. Actual census19791calls,
430MUST-with-NULL (289root-outside-index,141root-indexed), resolver-miss query0
with positive control4883. That query is a narrow diagnostic, not a safety proof.

The frozen implementation manifest expressly excludes
tezt/tests/must_null_ceiling.ml and forbids pin/reference changes. Silently raising
the pin, excluding new files from measurement, or manipulating source to evade the
metric would bypass the agreed scope/gate. Request permission for a narrowly
scoped recalibration, retaining headroom25 and the unchanged query, with independent
review of attribution and a fresh full-build suite. No PR, review GO, QA GO, or merge.

Cleanup check: no /tmp/recalibrate worktrees remain registered; the script removed
its two owned temporary builds. The active guard worktree remains necessary.
