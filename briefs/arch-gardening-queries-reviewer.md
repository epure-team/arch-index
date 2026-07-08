# Reviewer Brief — arch-gardening-queries

**Status:** VALIDATED. Contract: specs/arch-gardening-queries.md FR-001..011; plan decisions binding.

Audit ranked:
1. latest-record SQL (correlated MAX subquery) — two-snapshot fixture must exclude improved fn; ties impossible via UNIQUE.
2. Loader transaction: malformed mid-stream → ROLLBACK ALL (verify with count check), exit 2, no summary; skip vs abort taxonomy exact.
3. Stamp validation strict UTC; identical-stamp rerun → ignored (changes()=0 detection).
4. Resolution exactly-one semantics (0 and >1 both skip); prepared statements only.
5. Helper hoist didn't regress health branches (selftest-health green).
6. Doc-SQL extraction actually executes the doc blocks (fail on 0 extracted).
7. Exit taxonomy across all new surfaces; deterministic ordering.
Spot-run: CHECK-1..5.
