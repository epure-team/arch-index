# Reviewer Brief — arch-metrics-gate

**Status:** VALIDATED
**Contract:** specs/arch-metrics-gate.md (FR-001..020, AC-1..7, EC-1..7) — verdicts must cite FR/AC IDs.

## What was implemented (expected)

1. `lib/arch_compare/` + `bin/arch_compare_cli/` + top-level `arch-compare` wrapper — compare engine ported from octez-manager with spec deltas.
2. `metrics` subcommand branch in bash `arch-query` (+ header doc).
3. `metrics-baseline.json`, `.metrics-accept`, CI gate step, `docs/adr/002-metrics-gate.md`, README section.

## Audit first

- `lib/arch_compare/arch_compare.ml` — accept-file parser: reason priority (inline > trailing > preceding block; blank clears), duplicate ⇒ invalid, wrong-operator ⇒ invalid, untracked ⇒ invalid; evaluate: accepted iff within bound (inclusive — EC-4); has_failures: blocking ∨ missing ∨ invalid.
- Exit codes: arch-compare {0,1,2} (FR-007/009); arch-query metrics {0,2,3} (FR-004). Confirm exit 2 vs 1 is not conflated.
- `arch-query` metrics branch: feature-detect combinatorics — no metric emitted as 0 when its source is absent (FR-003, the highest-risk silent failure); exposed/exported dualism (FR-005); EC-1 division-by-zero guard for doc_coverage_pct; sorted keys (FR-001); `set -euo pipefail` safety of new code paths.
- CI step: baseline compared is the committed one; step reuses /tmp/self.db; failure actually fails the job.
- `.metrics-accept` committed file: must be empty policy (comments only) — any real waiver at birth is a red flag.
- Tests: octez suite ported + new cases (duplicate, EC-4, EC-5, missing, malformed→2). Check tests assert exit codes, not just output text.

## Risks to verify (from plan)

- Flat-schema column names verified in code (arch_load.ml / schema), not assumed from research.
- json_object runtime probe + printf fallback both produce byte-identical-parsing JSON (jq-validated in a selftest).
- Untracked metrics never affect exit code (FR-008) — check direction table membership is the only gate.

## Expected behaviors to confirm (spot-run)

- CHECK-2: `{"large_functions":10}` vs `{"large_functions":12}` no waiver → exit 1.
- CHECK-3: waiver `large_functions <= 12 # reason` → exit 0, reason rendered.
- CHECK-6: baseline `{"large_files":3}` vs `{}` → exit 1 "missing".
- CHECK-1/7: metrics on self-index (CMT) and on a flat NDJSON DB.
