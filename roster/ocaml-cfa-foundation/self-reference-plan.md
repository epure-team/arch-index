# Self-reference attribution before reference edits

Stage2 read-only preparation, 2026-09-16. Not executed; no reference update
authorized or applied. The pre-edit full baseline was green.

Remaining failures include source-dependent self-index and origin-consumer
references. Measure a 2x2 using pre-CFA source S0=`c397efd` and an exact stable
stage2 source snapshot S1, with tools E0/E1 and separately compiled CMT corpora
C0/C1. The four cells are A=E0(C0), B=E1(C0), C=E0(C1), D=E1(C1).
Use owned temporary source copies, not new Git worktrees; preserve foreign dirt.
Keep one build owner and remove only the directories created by the measurement.

Record source/CMT/binary/schema hashes and complete call-row multiplicities,
not just module/function/call counts. For the origin consumer also record origin
rows/groups, coordinates, rule verdicts and the tool bundle used. C-A is source
growth under E0; B-A and D-C are same-corpus engine changes; their difference is
the interaction. Stage2 deliberately changes resolution, so these engine deltas
must be explained rather than forcibly equated or called source-only growth.

Previous calibration worktrees/CMT builds are not retained. The stage1 Tezos
bundle is not a sufficient replacement for the required self-index inputs.
Its frozen executable provenance records checkout HEAD/dirty state, not a
pristine source-tree build attestation. Rebuild E0 from the exact source snapshot
for the self-index experiment instead of assuming that frozen executable is E0.

Correction to the preparatory agent's first report: the pinned410 manifest DOES
contain each CMT SHA256 and its reader verifies all entries; symlink selection
does not make that corpus unpinned. The self-index 2x2 does not require four new
Tezos replays.

Only after attribution, request exact-file authority for any necessary edits:
`test/fixtures/self-index-stats.txt`,
`test/fixtures/origin-consumer/reference.json`,
`checks/origin-recurring-consumer.js`, and possibly the single-coordinate
`test/fixtures/origin-consumer/self.allow` entry. Do not infer a policy waiver
from a count increase. A coordinate relocation requires the same semantic
origin and no added exemption. No CI/test-harness expansion is assumed needed.
The separate point-free test scope request remains unanswered.
