# Approved reference migration — 2026-09-16

The user's explicit "oui!" approves only the four previously requested files.
Manifest and implementer scope were extended before editing. Sol independently
checked complete A=B and C=D canonical arrays and applied exact D module,
origin-group and total observations. Root reviewed the diff and replaced the
stale descriptive reference revision with the measured c397efd source-overlay
identifier. The single assertion exemption moved coordinates; its explanation,
policy and multiplicity are unchanged. No new exemption was introduced.

Root build/full suite passed:345/345 Tezt and6/6 native CFA groups. Log:
`improvement/2026-09-16-cfa/approved-reference-runtest.log`, SHA256
`4ae1fdca9c2362dc7cb96eda59616a5b9366c06a439e3d2dab2cb2cf9555efee`.
The descriptive revision changed during this first run; no production source
changed. This is not the final frozen-source attestation.

Independent preparatory review then identified missing AC-13 nonpositive-arity
coverage, contradicting an earlier checkpoint's claim of a synthetic control.
That historical claim was corrected. Sol added real-CMT sessions with arity
callbacks returning0/-1. Root rejected an initially vacuous test using a caller
with an existing opaque frontier. The corrected known-only scoped caller
requires exactly two candidates plus exactly one new unknown and exact metadata
copying. CHECK2 passes; this is post-implementation coverage, not claimed TDD.

Root reran CHECK1 (517 oracle cases), CHECK2 (authentic1/1) and CHECK3: all exit0.
Fresh CHECK3 report:
`improvement/2026-09-15-ocaml-cfa/check3-1789554436047-3697806.json`.
Its410 inputs and frozen baseline are stable, output digest remains
`a4fbf0841ed4897f5321c315b12dcbff974537518d78a0177b1b6f5885718193`,
Irmin+1/protocol+2 relations, no relation loss. Producer wall2945.974341ms,
Linux sampled RSS144936KiB. This is measurement, not a semantic proof.

Bundle22 hashes, scope-diff and whitespace gates pass. Domain checker injection,
Tezos pure accounting and self-calibration pure controls pass. Final full suite
including the new arity coverage passes345/345 plus6/6 kernel groups, exit0.
The313-file inventory and five binary hashes match before/after; exact evidence
is in final-implementation-run.json. Independent formal Roster review,
QA and exact-head PR CI remain pending. No stage2 PR/merge or new worktree.

Staging exposed four extra blank EOF lines in new files; the earlier unstaged
diff check had not examined untracked files. Root removed only those blank
lines (kernel ml/mli, literal fixture, fixture dune-project) and the staged
whitespace check now passes. The frozen full-run evidence above predates this
whitespace-only cleanup; build/CHECK1/CHECK2 are rerun afterward, and formal QA
must qualify the committed head. Do not relabel the prior hashes as current.
