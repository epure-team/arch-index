# Corrected spec compliance — round1

All26FR and12AC were initially reported PASS after executable checks. Architecture
review disproved FR-014/AC-8: both are DIVERGE; remaining36 claims retain PASS.
The original38/38 result is superseded, not accepted release evidence.

FR-014/AC-8: arch_index.ml616 opens a broad catalogue/graph transaction,668-670
writes catalogue,673 calls the nested binding SAVEPOINT,703 commits. A binding
RAISE(ROLLBACK) unwinds all uncommitted old facts. Actual CLI reproduction:
healthy exit0/modules1/functions3/applications2 versus fault exit1/all three0,
failure-row FK error and COMMIT with no active transaction. Both markers absent.

Native/synthetic collector, closed query grammar/precedence/renderer/read-only,
ordinary ABORT storage isolation and main/flat compatibility tests pass. They do
not prove rollback isolation in the actual broad-transaction topology.
Four independent Node families and diffcheck all exit0. Dune explicitly skipped
by specialists per root-only build ownership; root review build exit0.

The frozen spec remains the intended contract: do not weaken FR-014/AC-8.
Recommended correction: queue immutable payloads until all old transactions commit,
then per-input binding persistence and a real CLI global-rollback regression.

Schema adaptation: returned confidence HIGH/high strings were invalid for roster's
integer field; root canonicalized to5 using explicit high-confidence evidence.
Architect and spec reports describe one invariant. Preserve both raw reports but
use the spec-compliance finding once as the primary finding; do not double-count.
Default KB report destination adapted to this authorized task directory.
