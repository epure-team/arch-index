# FR014 negative checks — round1 repair

CHECK-5 calls actual manifest/provenance/witness validators using isolated fixture
files and actual SQLite snapshots. Its synthetic .cmt bytes exercise hashing and
selection only, not compiler decoding; authentic decoding is CHECK-4/fixed410.
Minimal exported expected/file parameters keep CLI defaults pinned. No Tezos file
or retained baseline is modified. Owned temporary fixtures are removed in finally.

After root requested additional branches beyond the initial18 checks, Sol expanded
to38 and root added the combined undeclared-run control:39 assertions now PASS.
Coverage includes missing/changed/malformed/short/duplicate manifest and artifact,
provenance JSON/path/pins/integrity flags, catalogue and binding collection counts
and outcomes, declared run/cardinality/columns, positioned transition/residual
witness digests/fields/review metadata, valid controls and cleanup.

The two direct child controls establish this checker's assertion1/setup2 mapping;
they do not run every invalid fixture through the complete fixed410 CLI. Actual
validator errors are checked as ComparisonInputError except the missing manifest
file, which preserves its existing raw filesystem error. No CLI-wide fault
injection or compiler-input corruption coverage is claimed.

Comparison run-set validation is a genuine strengthening, not only test coverage:
all410 input rows must belong to the declared producer run, with distinct artifact
keys. The agent implemented this before demonstrating RED; this TDD sequencing
gap is explicitly recorded, not relabeled as test-first. Root retrospectively
loaded exact12ab1fc comparison.js through a Node module-loader substitution while
running the current unchanged CHECK-5. A first run exposed only a different error
message for a single-side run mismatch, not a missed refusal. Adding the combined
case (both410-row input tables use run2, declared run1) then produced genuine
exit1: `both inputs use undeclared run: expected refusal`. The current comparator
passes all39. No source mutation, temporary worktree or historical build was used
for that replay. This independently confirms the old behavior accepted the
inconsistent joined run set; do not claim the replay preceded implementation.
