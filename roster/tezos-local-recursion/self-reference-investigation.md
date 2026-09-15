# Exact source-only reference refresh

The first full340 run returned338PASS/2FAIL: self golden and authentic origin
consumer. All four new native tests passed. The raw log is
improvement/2026-09-14-tezos-resolution/attempt4-full-green1.log.

After the legacy-residual correction, pristine crossed measurements used an
unreferenced git snapshot a951936d93227415c8e016493e63701e850e65d4. The root
branch/index and seven unrelated dirty files were preserved. Both diagnostic
runners checked cleanup of their exclusively owned worktrees and build artifacts.
No failing implementation commit was added to branch history for calibration.

Unchanged scripts/recalibrate.sh --explain against PR107 returned0:

- Golden A=B25/998/6335; C=D25/1004/6389.
- Ceiling A=B541; C=D544, within the unchanged524±25 band.
- Evidence: attempt4-self-reference-N1yBlb, complete log/provenance retained.

Independent pristine origin2x2 also returned0:

- A=B570 origins; C=D580 origins, with complete module/group/sole-assert equality
  within each same-source pair, not merely matching aggregate totals.
- Source-only group changes: exception/compare50→52 and option/raise320→328.
- The sole assertion remains multiplicity1 and identical split_last source;
  its location moves1609→1631 and owner positions1595/1606→1617/1628.
- Evidence: attempt4-origin-attribution-wSBKDP, four DBs, logs, inventories,
  observations and provenance retained. Builds/worktrees removed.
- An earlier diagnostic rejected an unrelated Dune public_cmi .cmi symlink.
  This was setup2, not failed origin semantics. Measured-source/CMT links remain
  forbidden; irrelevant non-directory .cmi aliases are ignored. The failed run
  cleaned up and was not used as attribution evidence.

The exact four-path manifest amendment and reference-refresh-authorization.json
were written BEFORE modifying references. Old/current hashes, source snapshot and
all raw evidence hashes are bound there. All four resulting files match their
preauthorized SHA256. No policy, threshold, extra allowance, or historical checker
was relaxed. Only duplicated expected constants in origin-recurring-consumer.js
accompany the three reference-file changes.

This refresh is not a full-suite/QA/retention claim. All current gates must now
run on the resulting source; implementation remains in progress.
