# Investigation — ocaml-cfa-flat-timeout

**Date:** 2026-09-16  
**Symptom:** CHECK-2 passes alone, then the review ratchet can report eight flat
CFA assertions at zero while the rich CMT projection remains correct.  
**Status:** ROOT CAUSE IDENTIFIED

## Root Cause

The flat fixture runs the LSP pipeline under a 30-second global timeout.  Call
hierarchy preparation can spend 20 seconds retrying a method that `ocamllsp`
does not support before the CMT fallback runs.  A measured successful fixture
run took 25.327 seconds, leaving little scheduling margin.  If the budget
expires first, the runner preserves 135 function rows but no call rows, writes
the partial database and returns success.  The Tezt helper discards successful
process output, so the timeout is misreported as eight CFA assertion failures.
The outer review ratchet additionally converts a CHECK-2 setup exit 2 into an
assertion exit 1.

**Evidence:** `lib/arch_index/call_graph_extractor.ml:497` performs the bounded
retry sweeps and reaches the CMT fallback at line 509;
`lib/arch_index/runner.ml:294` applies the global timeout, line 337 only stores
call rows after extraction completes, and lines 344–350 preserve partial rows
after timeout; `tezt/lib/arch_tezt.ml:420` returns only the database path and
does not surface output on exit 0; `roster/ocaml-cfa-propagation/check-review-fixes.js:25`
maps every unexpected child status to exit 1.

The controlled command
`EPURE_ARCH_INDEX_TIMEOUT_S=1 node roster/ocaml-cfa-propagation/check-review-fixes.js`
reproduced the exact eight flat failures.  Its producer log contained
`timeout after 1s — using partial results (135 functions, 0 calls)`.  The same
fixture with the normal budget produced 135 functions and 169 calls.

**Introduced:** the partial-success contract predates Stage 3; the ratchet
classification gap was introduced with the Stage-3 review ratchet.  
**Impact scope:** LSP-backed tests that require complete call facts can
misclassify a setup timeout as a behavioral regression.  The rich CMT producer
and the CFA solve are unaffected.

## Tested hypotheses

| # | Hypothesis | Result | Evidence |
|---|---|---|---|
| H1 | Global LSP timeout leaves a functions-only database | CONFIRMED | Controlled 1-second run: 135 functions, 0 calls, exit 0 |
| H2 | A stale LSP process corrupts the second run | REFUTED | No residual LSP/Merlin process after reproduction; cleanup completed |
| H3 | The nested Node wrapper causes the loss | REFUTED | Direct Tezt execution reproduced the same eight failures |
| H4 | CMT input or CFA solving regressed | REFUTED | Rich assertions and independent CHECK-2 pass; failure is flat-only |
| H5 | The historical failure was certainly a timeout | UNPROVEN | Its transient log was not retained; only its exact signature was reproduced |

## Fix plan

1. Expose raw LSP indexer status/output to tests and make this completeness-
   requiring fixture classify lookup/start/timeout/unexpected diagnostics as
   `OCAML_CFA_SETUP`.
2. Give this fixture a 60-second default budget while preserving an explicitly
   supplied `EPURE_ARCH_INDEX_TIMEOUT_S` for controlled failure tests.
3. Preserve CHECK-2 exit 2 through the review ratchet.
4. Ratchet both paths: one-second timeout must exit 2; normal execution must
   exit 0 with all rich and flat assertions.

## Tests to add

- `EPURE_ARCH_INDEX_TIMEOUT_S=1` CHECK-2 and review-ratchet controls expecting
  setup exit 2, not assertion exit 1.
- Normal CHECK-2 and review-ratchet executions expecting exit 0.

## Impact scope

The minimal correction is test infrastructure plus the Stage-3 ratchet.  A
future product task should persist an explicit completeness status in flat DB
metadata and avoid retrying unsupported call-hierarchy preparation, but that
schema/runtime change is outside this Stage-3 correction.
