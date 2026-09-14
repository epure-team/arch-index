# Review round 1 — in-scope checker correction

The owner, spec and architecture reviewers independently identified residual
native-head reuse in witness admission. Preserve the original owner findings
and report; their successful old checks do not negate this new counterexample.
No product graph bug or false fixed410 gain was demonstrated: the316 admitted
corpus transitions contain no residual additions.

The main agent preserved the authentic compiler reproduction as self-contained
`check-residual-witness.js`. Positioned rows are synthesized native admission
controls, explicitly not producer/database measurements. Both positive controls
ran before the negative assertion: a [1,2] supplied-argument group accepts its
one overapplied head, and a [2,2] group accepts two different native heads.

Actual main RED on the old admission code: exit1,
`ASSERTION: Missing expected exception: one overapplied native occurrence cannot spend another identical head capacity`.
The minimal correction adds a Set of consumed residual head indices, refusing
reuse before consuming a positioned residual row. Main reran the same test:
exit0, both positive controls and two reuse refusals passed. The spec reviewer
independently confirmed the fix by reading; its personal final gates are pending.
An unchanged compatible residual needs no new delta witness; no blanket
residual-per-transition requirement was added.

This is a same-round fix under the user's standing authorization to correct
in-scope gate failures, not acceptance/waiver of the finding. No contract, guard,
product behavior or scope expansion is approved by this note. Mechanical
convergence-gate red_verified is not claimed from this working-tree RED.

The owner's separate MEDIUM finding about non-vacuous paired rich/effectful-open
coverage is being corrected in task-local checkers. All final personal reviewer
gates, normalization, convergence, review verdict and QA remain pending.
External runtime attempt actually timed out120s and is degraded, not a PASS.

Cleanup: the owner's disposable `/tmp/arch-index-owner-residual-5bLLl3`
compiler fixture and build artifacts were removed after its source and behavior
were preserved in the permanent regression and raw review report. That original
temporary path is historical, not a remaining runnable artifact.

## Storage interruption

During the preservation-check enhancement, `/home` reached zero available
bytes and apply_patch partially wrote the checker. The agent stopped and
reported it; no subsequent gate was treated as valid. Main moved the existing
772MiB root `_build` intact to
`/mnt/ssd-external-2to/arch-index-open-bodies-build-cKA9pZ/_build` and installed
a symlink at the original `_build` path, recovering771MiB without deleting
source, baselines, evidence or foreign worktrees. This is the sole current
build, not an unused additional worktree. Producer SHA992f4b252fb14d62cc64616bc88292883b7706a87e39ca9927bd498d0f1c5391
and CMT SHA8002f946ded9f8fa818baf4df8a05103cc13dc245887713f77a598f229ee79df
were unchanged across the move. Restoration from the committed checker tail
and syntax/control-preservation checks are required before resuming gates.

Recovery completed: syntax, probe-only and full CHECK-1 passed after exact tail
restoration; the mutation control still produced an assertion exit1. The disk
later had12GiB free independently of our771MiB recovery. Main moved the sole
build back to the original `_build` directory, verified both hashes again,
and removed the empty owned SSD temporary directory. No build symlink or
duplicate build remains.

## Preservation repair

The dedicated Sol implementer changed only CHECK-1. Its new assertion first
failed on missing paired preservation evidence; this is a checker coverage RED,
not proof of a product defect. Two separately compiled old/current collectors
then run actual process_cmt into SQLite on one compiled fixture with configured
value channels. The comparison includes all pending-call fields, stable stored
function fields, scope parents/catches, origins/operand metadata and carriers.
Only exact site-pinned admitted heads are normalized; exactly three separately
counted current-only residuals are removed (old0/current1 each). No caller-wide
exemption or duplicate-eliminating comparison is used.

Actual module-expression calls in structure/application/unpack opens, genuine
optional/default/refutable partial/full applications, homonym flat calls and
conditional/live/dead CFG facts are non-vacuous controls. Complete six-field
flat multisets retain duplicate counts. The spec reviewer independently read
the final repair and confirmed coverage closure; personal final gates remain
required. Product and Tezt source files did not change, so pristine source
attribution remains bound to the same calibrated source tree.
