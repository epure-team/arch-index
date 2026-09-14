# Architect round 3 checks

Architecture risk: **low**. The round-2 CI golden finding is resolved by an exact, permanent smoke ratchet. The checker uses the current built producer, the same corpus/schema and SQL count query as CI, byte-compares the committed oracle, never refreshes it, has bounded subprocesses, maps setup failures to exit 2, and removes only its owned temporary directory. No semantic product path changed.

| Command | Exit | Result |
| --- | ---: | --- |
| `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune build --root .` | 0 | PASS |
| `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune runtest --root . --force` | 0 | PASS; full forced 327 Tezt gate |
| `rtk proxy node roster/tezos-call-resolution/check-native.js` | 0 | PASS; 7/7 native titles |
| `rtk proxy node roster/tezos-call-resolution/check-native.js --self-test` | 0 | PASS; 5 assertions |
| `rtk proxy node roster/tezos-call-resolution/check-comparison.js` | 0 | PASS; 28 assertions |
| `rtk proxy node roster/tezos-call-resolution/check-labeled-arity.js` | 0 | PASS |
| `rtk proxy node roster/tezos-call-resolution/check-verifier-inputs.js` | 0 | PASS; 39 assertions |
| `rtk proxy node roster/tezos-call-resolution/check-self-index-smoke.js` | 0 | PASS; exact `25/980/6245` golden |
| `rtk proxy node roster/tezos-call-resolution/verify.js --baseline /tmp/arch-index-resolution-baseline-OmhcEs/baseline.db --witness improvement/2026-09-14-tezos-resolution/attempt1-reviewed-witness.json` | 0 | PASS; 795 gains (+400 Irmin/+395 protocol), zero losses, canonical `90e76d6b40b2d7f108fcc25523f85de1cb533a98565a8a7d6d284c1654939d4b` |
| `rtk proxy node roster/tezos-call-resolution/verify.js --baseline /tmp/arch-index-resolution-baseline-OmhcEs/baseline.db --self` | 0 | PASS; 45,018 unchanged rows |
| `rtk proxy node scripts/review-bundle-verify.js` | 0 | PASS; bundle 1.6.0, 22 hashes |
| `rtk proxy git diff --check main...HEAD` | 0 | PASS |

Candidate/self reports retain `retention_authorized=false`; no hosted CI, keep, or merge claim is made.
