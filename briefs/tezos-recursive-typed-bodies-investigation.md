# Investigation — tezos-recursive-typed-bodies baseline

**Date:** 2026-09-15
**Symptom:** frozen SQLite main-file hash changed after an ordinary SELECT.
**Status:** ROOT CAUSE IDENTIFIED

## Root Cause

The new baseline preparation recorded only the main database hash while SQLite
WAL state remained present. Its canonical snapshot reader uses readOnly:true,
so it can read WAL contents without checkpointing the main file. A later normal
sqlite3 open is allowed to checkpoint on close, even for SELECT-only SQL. This
is a baseline-packaging defect, not a callgraph product regression or SQLite bug.

Evidence: `roster/tezos-recursive-typed-bodies/prepare-baseline.js` records db_sha256
immediately after produce, before sealing any WAL; the imported snapshot reader
uses DatabaseSync(readOnly:true) in `roster/tezos-call-resolution/comparison.js:76`.
Fresh researcher reported seeing baseline.db-wal/-shm before executing a plain
`rtk sqlite3 ...baseline.db "SELECT ..."` without readonly options. The main file
changed9d1711e0...→ddb9e316..., WAL files disappeared, while canonical rows/digest
and relation counts remained exactly45052/082bdce9.../4849/12157.

The exact header transition of the historical main file was not captured before
that read. A fresh controlled reproducer confirms the mechanism: create a WAL DB
in an owned temporary directory and exit without close; readonly SELECT preserves
the main hash and WAL; writable sqlite3 SELECT preserves the value42 but changes
the main hash and removes WAL. Actual exit0, recorded in ignored
attempt5-wal-diagnosis.json. Its temporary files were removed.

## Tested hypotheses

| Hypothesis | Result | Evidence |
|---|---|---|
| Product changed target data | Not supported | Product hash unchanged; exact canonical digest and4849/12157 preserved. |
| Normal SELECT checkpoints existing WAL | Mechanism reproduced | Fresh child/readonly/writable experiment, before/after hashes and WAL existence. |
| Frozen DB packaging was self-contained | Refuted | WAL/-shm existed after initial freeze; main-file-only hash was insufficient. |

## Fix plan

Keep the original attempt5-baseline and provenance for audit; do not overwrite
or accept its new hash. Prepare a distinct v2 baseline from the same unchanged,
pinned PR108 producer/schema/CMTs. While staging, checkpoint WAL and switch to
DELETE journal mode before hashing, verify complete SQL data equality across
sealing, then replay and compare. Require no WAL/-shm sidecars in the committed
baseline package. Add a writable-SELECT stability test on a disposable copy, not
the immutable original. Only after that may specification/implementation consume
the replacement reference.

## Impact scope

Fifth-attempt setup only; no product code edited and no new gain claimed. The
initial source guard340/340 remains valid. Earlier immutable baselines/checkers
are read-only and outside this repair. This is not a sixth product iteration.
Routine in-scope setup repair is covered by standing user autonomy. No fabricated
approval or historical hash rewrite. Future forensic reads enforce readonly mode.

## Verified setup repair

Created separate attempt5-baseline-v2 from the unchanged pinned producer. Staging
checkpoint/DELETE mode preserved the digest of every SQL table row and schema
definition. Create and independent check/replay exit0 reproduce45052rows and
4849/12157 with exact canonical digest. Ordinary writable SELECT on disposable
copy preserves bytes and leaves no WAL/SHM. V2 DB SHA is c45f4d08cafaaa764b32fc092609ad7d44b52edd2bc7bc17fae1e27fd4754198;
provenance SHA is d05dc367bd0ad8db2c1f63939cb85431a19830caa6cf04caa332a6e1b2f97182.
No old baseline overwritten; no product change. Repair remains subject to the
fifth attempt's full reviewer/QA pipeline rather than self-certified delivery.
