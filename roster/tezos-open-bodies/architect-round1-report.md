# Architecture review — tezos-open-bodies

Head reviewed: `cd3cb3c7c4bcf9e87bcde69707f4db531f390286`.

Architecture risk: low. No open architecture or specification violation remains.

The product change is correctly isolated in `arch_index_cmt.ml`: only same-CMT structural `Pident` calls use the invocation-only descriptor; it does not widen the legacy local-function recognition or public collector interface. Finalization occurs after actual lambda storage, preserving the required enumerated/dropped/unknown partition. Flat extraction remains on the legacy wrapper path.

One high-confidence review finding was discovered in witness admission: duplicate canonical transition rows could allow a repeated `head_index` to authorize multiple residuals. It was repaired in `cd3cb3c` with per-native-head consumption in `witness.js` and a real compiler-native CHECK-6 control. This is a resolved checker-only defect; the fixed corpus has no residual delta.

Personal gate results:

- `opam exec -- dune build`: PASS.
- Full Tezt guard: PASS, 336/336; log: `improvement/2026-09-14-tezos-resolution/attempt3-review-arch-full.log`.
- CHECK-1 through CHECK-6: PASS.
- Fixed410 witness comparison: PASS; 316 protocol relation gains, zero relation losses, 45,052 rows unchanged in count.
- Review bundle verifier and `git diff --check`: PASS.

The full guard emitted existing constraint diagnostics after its 336 successes; no test failure was recorded.
