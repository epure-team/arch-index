# Architect round 2 checks

Reviewed `d4d945543e977617352f901138aa275ea4d33f8b` against `12ab1fc..HEAD`, the updated specification and repair briefs. The local 15-line correction counts only `Some` application slots for `module_target`-proven owned heads; legacy heads and CFG/noreturn accounting retain their existing slot count. No ownership, alias/refusal, or flat-attribution boundary was widened.

| Command | Exit | Result |
| --- | ---: | --- |
| `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune build --root .` | 0 | PASS |
| `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune runtest --root . --force` | 0 | PASS; full 326 Tezt gate |
| `rtk proxy node roster/tezos-call-resolution/check-native.js` | 0 | PASS; 6/6 native cases |
| `rtk proxy node roster/tezos-call-resolution/check-native.js --self-test` | 0 | PASS; 5 assertions |
| `rtk proxy node roster/tezos-call-resolution/check-comparison.js` | 0 | PASS; 28 assertions |
| `rtk proxy node roster/tezos-call-resolution/check-labeled-arity.js` | 0 | PASS; four callers, both contexts |
| `rtk proxy node roster/tezos-call-resolution/check-verifier-inputs.js` | 0 | PASS; 39 assertions |
| `rtk proxy node roster/tezos-call-resolution/verify.js --baseline /tmp/arch-index-resolution-baseline-OmhcEs/baseline.db --witness improvement/2026-09-14-tezos-resolution/attempt1-reviewed-witness.json` | 0 | PASS; 795 gains, +400 Irmin/+395 protocol, zero losses, digest `90e76d6b40b2d7f108fcc25523f85de1cb533a98565a8a7d6d284c1654939d4b` |
| `rtk proxy node roster/tezos-call-resolution/verify.js --baseline /tmp/arch-index-resolution-baseline-OmhcEs/baseline.db --self` | 0 | PASS; 45,018 unchanged rows |
| `rtk proxy node scripts/review-bundle-verify.js` | 0 | PASS; bundle 1.6.0, 22 hashes |
| `rtk proxy git diff --check main...HEAD` | 0 | PASS |

The candidate and self reports retain `retention_authorized=false`. The owner reviewer independently established the separate HIGH CI self-index-golden mismatch; it remains unresolved and requires the normal scoped repair path before ship.
