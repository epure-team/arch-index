# Direct-binding checkpoint calibration — 2026-09-13

The user explicitly authorized source-growth-only recalibration, with headroom25
and graph semantics unchanged. This is not a closure or target-resolution gain.

`calibrate-snapshot.js` follows the existing recalibration script's matrix and
corpora, but handles this uncommitted implementation without creating a failing
product commit. Base7df5c031f809bc92c34d483a14dac3342d300ce2 was checked out twice
into fresh disposable worktrees. The candidate overlay is precisely enumerated
and SHA256-hashed in evidence.json, snapshot
3413027703081d0e4905cf0af5b4c1603ff34ed90d81be93830c2e0dcf0627de.
It is not a clean candidate commit. Both copies ran fresh dune build --root .
under the same explicit opam switch; no incremental active-worktree corpus was used.

| Corpus | A: base/base | B: new/base | C: base/new | D: new/new |
|---|---:|---:|---:|---:|
| Whole-build non-Stdlib MUST/NULL |468|468|519|519|
| Producer modules |24|24|25|25|
| Producer functions |859|859|951|951|
| Producer calls |5440|5440|6112|6112|
| Producer origins |495|495|547|547|

For both corpora, A=B and C=D also match module paths, origin groups and SHA256
of complete grouped call rows. Behavior and interaction deltas are zero on these
measurements. Source growth alone changes the measured references. Headroom stays
25, clean_measured becomes519, hence ceiling544; the query and floors are unchanged.
The self golden and recurring-origin coverage reference use producer-only totals,
not whole-build totals. The policy rule and allowlist are not changed.

All eight index commands and both builds completed successfully. Both exact
temporary worktrees and their build/DB artifacts were removed by the script's
finally block (/tmp/arch-index-binding-calibration-XLOGHR). This run's compact
logs and successful evidence remain here. The reference revision records the
base plus worktree snapshot digest instead of inventing a product commit.

An independent Sol audit agreed with the matrix and identified two reusable-tool
hazards. After this successful run, the script was hardened to invalidate old
success evidence before rerunning and detect newly dirty/untracked product paths.
Those guards were not retroactively claimed as executed in the first run. Root
made no product edits during the measurement; only excluded brief/manifest
authorization documentation changed. The recorded snapshot files were checked
for byte stability by the actual run. A subsequent full suite verifies the
reference-only edits; no scripted --write or pristine-HEAD verification is claimed.
