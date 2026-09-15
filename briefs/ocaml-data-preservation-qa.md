# QA Brief — ocaml-data-preservation

**Date:** 2026-09-15
**Status:** GO ✅
**Round:** 1 (qualifying 0/5)

Fresh cycle1; convergence exit0, no warnings or violations. Routine approval is
covered by the user's explicit autonomous Roster authorization; no quiz answers
were invented.

## Quality Gates

Final validation HEAD: `7febb24d1e117148092f0ec43611d90a4d3744c5`.
All commands executed serially from the root checkout, with `rtk proxy`.

| Gate | Command | Exit | Duration |
|---|---|---:|---:|
| Build | `opam exec -- dune build` | 0 | 334ms |
| Full suite | `opam exec -- dune runtest --force` | 0,344/344 | 271332ms |
| Bundle | `node scripts/review-bundle-verify.js` | 0,22 files | 28ms |
| Hygiene | `git diff --check` | 0 | 5ms |
| CHECK1 | `node roster/ocaml-data-preservation/check-effects.js` | 0 | 269ms |
| CHECK2 | `node roster/ocaml-data-preservation/check-cmt-copies.js` | 0 | 578ms |
| CHECK3 | `node roster/ocaml-data-preservation/check-tezos.js` | 0 | 4182ms |

Logs/receipts: `improvement/2026-09-15-ocaml-cfa/qa-final-*` (local generated
evidence, ignored). Full suite includes two new native integration cases versus
the342-case baseline; no failed Tezt cases. No configured separate formatter,
full linter or instrumented coverage percentage is claimed.

## Behaviors and limitations

CHECK1 exercises exact name/path binding, source normalization, shadow identities,
NULL/empty payload distinctions, all-field persistence, stale association repair,
nullable-path homonyms, and truthful atomic failures. CHECK2 exercises byte-copy
and symlink reuse, independent catalogue/binding collection, nonidentical conflict
refusal, representative failure, and fresh-run cache invalidation.

CHECK3:410 selected CMTs;45052 canonical rows;
SHA256 `1799c07fd3eb87d4bca433b15b7daeb47f466f90cb098541372e1dd9dd7bac7a`;
Irmin4849/protocol12171 relations unchanged. Effects360 emitted,139 distinct
stored,63 bound/76 unbound. Duplicate payloads221. This is fixed-corpus
non-regression, not completeness or measured resolution gain. Local corpus is
not assumed available in CI; CHECK1/2 are native CI integration tests.

All twelve ACs were considered by the spec audit. Its three MEDIUM coverage debts
remain open: missing/outside-root/underscore producer metadata, bind/commit failure
injection, and equal-location declaration ordering. Implementations are present;
these boundaries are not claimed dynamically tested. FR012's INFO wording
ambiguity is bounded by frozen C11: successful process_cmt extraction return,
not a new transaction covering deferred whole-graph persistence. See normalized
review findings and specialist report. No silent waiver or completeness claim.

## Evidence boundaries

Exact pre-build/post-CHECK3 source status and all three producer/loader binary
hashes match in `qa-final-before.json` and `qa-final-after.json`. No source edits
occurred during the final run. Existing unrelated arch-index and Tezos work was
preserved. No new worktree was created.

An initial capture setup failed before gates due to an incorrect executable path.
The first successful full QA pass344/344 captured source state throughout, but
binary hashes only mid-suite; its console's combined identity wording was too
broad. It is superseded for identity evidence by the second complete pass above,
which mechanically compared both source and binary snapshots before/after all gates.

## Code-intel and TUI

Code-intel skipped: no KB properties/code-intel declaration. TUI skipped: no TUI
scope. Hooks and managed claims reconciler unavailable in this consumer install.

## Cross-runtime QA

Shared breaker actually invoked with `--phase qa --check-availability --write`:
`skipped-degraded`, runtime degraded during review with unchanged runtime version,
source `review-go`. No second OpenCode pass is claimed.

## Verdict

GO — ready for roster-ship. Required CI must still pass on the exact final PR
head before guarded rebase merge. This report is not evidence of remote CI.
