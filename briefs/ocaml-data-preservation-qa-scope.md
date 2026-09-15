# QA scope — ocaml-data-preservation

**Status: VALIDATED**

Run serialized: `rtk proxy opam exec -- dune build`; `rtk proxy opam exec -- dune runtest --force`; `rtk proxy node scripts/review-bundle-verify.js`; `rtk proxy git diff --check`; `rtk proxy node roster/ocaml-data-preservation/check-effects.js`; `rtk proxy node roster/ocaml-data-preservation/check-cmt-copies.js`; `rtk proxy node roster/ocaml-data-preservation/check-tezos.js`.

Cover all twelve ACs in `specs/ocaml-data-preservation.md`, truthful failures, retained rows/IDs, exact paths, shadowing, per-artifact catalogue/binding outcomes, nonidentical conflicts, stale reuse, immutable pinned410 neutrality and effect observations. Capture exact pre/post source status and binary identity; no writes during gate execution. No TUI, no separately configured lint/coverage. Existing unrelated files remain untouched; no claim global worktree clean. Required CI must pass exact PR head before merge, not inferred from local results.
