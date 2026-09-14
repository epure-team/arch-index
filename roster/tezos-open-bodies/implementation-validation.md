# Implementation validation — attempt 3

2026-09-14, main-agent executions after the exact attributed reference refresh.

- `opam exec -- dune build`: exit 0.
- `opam exec -- _build/default/tezt/tests/main.exe --no-color --keep-going`:
  exit 0, 336 successes, zero failures, 21:09:51–21:13:54 UTC.
  Raw log: `improvement/2026-09-14-tezos-resolution/attempt3-guard-refreshed.log`.
  Both formerly stale self-reference tests and all four new native tests pass.
- CHECK-1 `node roster/tezos-open-bodies/check-native.js`: exit 0, including
  actual stored-body mismatch/duplicate-observation finalizer controls and all
  four Tezt controls, exact duplicate-sensitive flat rows and rich facts.
- CHECK-2 `node roster/tezos-open-bodies/check-witness-inputs.js`: exit 0,
  316 actual positioned pairs, genuine duplicate fixture, 13 negative controls.
- CHECK-3 `node roster/tezos-open-bodies/check-baseline.js --replay`: exit 0,
  neutral frozen replay, 17 malformed-record controls and overwrite refusal.
- CHECK-4 `node roster/tezos-open-bodies/verify.js --witness improvement/2026-09-14-tezos-resolution/attempt3-reviewed-witness.json`:
  exit 0; output `attempt3-candidate-s0F4So`, 45,052 rows each side,
  +316 protocol relations, +0 Irmin, zero relation losses/unexplained changes.
  Candidate digest `9ab4e0b13457247fb93dc83bf80323fcc5cec67866a18f56995ac0ec4a20867e`.
- CHECK-5 parser controls: exit 0. The complete CHECK-5 subsequently passed
  after the calibrated source tree was committed as `a5ae981`.
- Review bundle: exit 0, 22 SHA-matched files, version 1.6.0.
- Whitespace: `git diff --check` exit 0. No formatter or coverage configured;
  neither is claimed to have passed.

Pristine unchanged-policy calibration and exact pre-refresh hashes are retained
in `attempt3-pristine-attribution.json` and its authorization/raw-log references
under the same improvement evidence directory. Source-only cells are A=B
25/989/6275 and C=D25/998/6335, ceiling538→541 within the unchanged524±25 band.
The sole allowed assertion remains identical source with multiplicity one.

After source commit `a5ae981`, CHECK-5 also exited0: exact self smoke, frozen
policy and pristine attribution boundary all passed. Implementation is now
COMPLETED; this is not KEEP, review GO, QA GO or delivery.
Two of five attempts are delivered. Seven unrelated untracked paths
remain deliberately untouched; no global clean-tree claim is made.
