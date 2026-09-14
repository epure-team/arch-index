# QA scope — tezos-local-recursion

**Status: VALIDATED**

Native OCaml producer behavior, no TUI/UI scope. Validate the final reviewed head,
not a prior candidate. Serialize all builds/snapshots against writes.

Exact commands:
- `opam exec -- dune build`
- `opam exec -- dune exec tezt/tests/main.exe -- --no-color`
- `node scripts/review-bundle-verify.js`
- `git diff --check`
- `node roster/tezos-local-recursion/check-native.js`
- `node roster/tezos-local-recursion/check-witness-inputs.js`
- `node roster/tezos-local-recursion/check-baseline.js`
- `node roster/tezos-local-recursion/check-comparison.js`
- `node roster/tezos-local-recursion/check-compatibility.js`
- `node roster/tezos-local-recursion/check-residual-capacity.js`

Task scripts are deliverables and must exist by QA.0pass/1assertion/2+error.
No configured formatter/coverage; do not fabricate PASS. Verify every AC in
specs/tezos-local-recursion.md, including positive gain vs frozen PR10745052rows,
4781/12046,digest9ab4e0b1…,zero loss/unexplained/new MUST, exact native identity and
single-use capacities, actual storage refusals, nonempty rich/channel controls and
unchanged public flat multisets. Review/QA convergence and actual exact-head CI
are additional delivery gates; no script can claim future merge completion.
