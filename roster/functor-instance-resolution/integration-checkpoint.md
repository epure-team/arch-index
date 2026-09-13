# Root integration checkpoint — 2026-09-13

Implementation remains in progress; this is not a roster review/QA verdict or
implementation-completion artifact. The durable ledger remains at plan.

## Verified corrections and tests

- Full build passed after native lifecycle finalizer corrections. A real test-first
  probe with input/app run2 and header/producer run1 exited1: `input run differs
  from header run unexpectedly finalized`. Finalization now joins input provenance
  to both the run header and matching module source path. The same probe exits0
  and includes wrong-input-run and wrong-source among six negative variants.
- CMT read exceptions report unreadable at their actual read boundary. The outer
  missing-outcome fallback now uses collection_failed, not an unsupported inference
  of unreadability after arbitrary processing exceptions. No existing graph tuple
  or edge classification was changed.
- Removed the out-of-manifest public selection helper addition from arch_index.mli;
  the same helper lives in the authorized new catalogue module and is used by the
  producer and probe. No retrospective widening of the file manifest.
- Main checker now invokes all helper groups; all four groups are registered in
  Tezt with script/helper/oracle dependencies in Dune. The first integrated full
  suite played266 tests:262 passed,4 failed (inventory/lifecycle source-relative
  probe setup under Dune cwd, origin reference drift, MUST-null ceiling).
- Default subprocess cwd is now the source root (runtime compilation explicitly
  overrides it). Re-running all ten catalogue Tezt cases from the Dune test cwd
  passed10/10. This was followed by additional finalizer/byte-oracle checks, not
  represented as a final whole-suite pass.
- Current independent inventory: native18apply+1apply_unit, five descendant
  context premises, exact source-authored preorder/operand oracle; an excluded
  external CMT genuinely contains an application but is not expanded, while three
  selected external/shadowed-head applications remain distinct.
- Lifecycle uses real copied/symlink selections, real mid-input storage failure
  followed by persisted collection_failed on the same connection, reindex clearing,
  and zero-selection/valid-zero-app distinctions. Probe boundaries are not a
  process-kill experiment and are not described as such.
- Compatibility compares all16 versioned semantic tables/old markers, three old
  query byte oracles, two indexing passes, and DB byte immutability. Baseline
  query outputs were independently rerun with the preserved pre-feature binary.
- Query byte checks cover all six formats,0/2/default limits and valid empty data;
  default50 has a60-row premise. Installed SQLite3.53.3 renders rounded boxes and
  right-aligned numbers, unlike the established square/left-aligned renderer.
  The failed moving-shell oracle was replaced with a self-contained frozen-format
  oracle; product formatting was not changed to match a newer SQLite shell.
  An agent initially reversed actual/expected in its explanation; root inspected
  the diff and corrected the account before accepting the replacement oracle.
- Bundle22 files SHA-matched1.6.0; git diff --check passed at the checkpoint.

## Calibration boundary

No pins, reference, or allowance changed. A detached unpublished measurement
snapshot was created in a separate temporary clone because the unchanged
calibration tool measures committed HEAD and refuses dirty sources. This is a
measurement fixture, not a feature-branch commit, implementation GO, PR or bypass
of delivery gates. Base89a15af and temporary snapshot8656e4a include the same source
population as the current implementation at snapshot time; later documentation
updates do not change that population. Temporary clone/builds must be removed
after evidence collection. Any required ceiling increase needs explicit acceptance
of its measured delta; source-only attribution alone does not authorize loosening.
