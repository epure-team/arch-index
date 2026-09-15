# Owner reviewer report — tezos-local-recursion

## Outcome

No open correctness, security, regression, or test-impact finding remains in the
reviewed core implementation surfaces at HEAD `ae50e6d`.

This conclusion is independent of the implementation handoff: the owner reviewer
personally executed the final gates below. The earlier native-pair audit was used
as supporting evidence, not as a substitute for this review or its gate run.

## Final gate evidence

Raw logs and the command ledger are under
`improvement/2026-09-14-tezos-resolution/attempt4-review-owner-final-nSXzEe/`.

| Gate | Exit | Duration |
|---|---:|---:|
| `opam exec -- dune build` | 0 | 498 ms |
| `opam exec -- dune exec tezt/tests/main.exe -- --no-color --keep-going` | 0 (340/340 success) | 270760 ms |
| `node scripts/review-bundle-verify.js` | 0 | 100 ms |
| `git diff --check` | 0 | 33 ms |
| `node roster/tezos-local-recursion/check-native.js` | 0 | 28521 ms |
| `node roster/tezos-local-recursion/check-witness-inputs.js` | 0 | 3956 ms |
| `node roster/tezos-local-recursion/check-baseline.js` | 0 | 4187 ms |
| `node roster/tezos-local-recursion/check-comparison.js` | 0 | 52724 ms |
| `node roster/tezos-local-recursion/check-compatibility.js` | 0 | 28914 ms |
| `node roster/tezos-local-recursion/check-residual-capacity.js` | 0 | 3946 ms |

The full-suite log contains exactly 340 `[SUCCESS]` records and no failure,
error, or fatal marker. CHECK1 confirms complete rich/flat preservation; CHECK3
replays the immutable 45052-row predecessor digest; CHECK4 reports 179 relation
gains and zero unaccounted loss; CHECK5 confirms the frozen public/schema/flat
compatibility boundaries.

## Same-round resolved finding

MEDIUM, confidence 5, `FR-009` / `AC-15` — the original native preservation
probe discarded dependency and type-usage outputs, omitted module/rebind/type
shape tables, and did not make mutation/dereference fields non-vacuous
(`roster/tezos-local-recursion/native-preservation-probe.ml`, formerly line 71).

Commit `60bf7ab` resolved the gap by retaining dependency and type-usage results,
serializing modules, rebinds, types, fields, and constructors, and adding authentic
alias/include/rebind/type/catch/mutation/dereference fixtures with explicit
non-vacuity and row-shape assertions. Exact predecessor/current equality remains
after those assertions. The final owner CHECK1 passed at exit 0 in 28521 ms.

Fingerprint:
`roster/tezos-local-recursion/native-preservation-probe.ml:71:spec:rich-preservation-channels-vacuous`.

## Review coverage and limits

The owner reviewer read the complete core product change, Tezt feature test,
native fixture and preservation probe, baseline/comparison/witness/compatibility
validators, reviewer and implementation briefs, targeted native evidence, and
reference-refresh authorization. No applicable `.claude/patterns` language file
was present.

The owner reviewer did not independently consume every supplemental documentary
file in the approximately 75k-token `origin/main...HEAD` diff without truncation.
Those documents were separately read by the main reviewer; this report does not
attribute that work to the owner reviewer. The cross-runtime attempt degraded on
non-conforming output after 106.379 seconds (`opencode` configuration digest
`76f897c73342fdbf`), so no cross-runtime finding was accepted.

Seven unrelated user-untracked files were intentionally preserved. This report
makes no clean-worktree claim.
