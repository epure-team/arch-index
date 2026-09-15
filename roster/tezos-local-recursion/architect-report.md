# Architecture review — tezos-local-recursion

Final read-only architect assessment found no open product-architecture findings.
The private recursive descriptor remains constrained to singleton direct RHS
self-heads; source identity, observed physical root/storage, supplied-argument
arity, MAY-only resolution, and flat preservation were reviewed against the
task specification. The final coverage commit is confined to native preservation
test/probe evidence and does not alter the product algorithm or calibration
references.

## Independent final execution

Evidence directory: `improvement/2026-09-14-tezos-resolution/attempt4-review-architect-WDHeqv/`

| Command | Exit | Duration |
| --- | ---: | ---: |
| `opam exec --switch=/home/mathias/dev/arch-index -- dune build` | 0 | 365 ms |
| `opam exec --switch=/home/mathias/dev/arch-index -- dune exec tezt/tests/main.exe -- --no-color --keep-going` | 0 (340/340) | 269428 ms |
| `node scripts/review-bundle-verify.js` | 0 | 33 ms |
| `git diff --check` | 0 | 3 ms |
| `node roster/tezos-local-recursion/check-native.js` | 0 | 28475 ms |
| `node roster/tezos-local-recursion/check-witness-inputs.js` | 0 | 3834 ms |
| `node roster/tezos-local-recursion/check-baseline.js` | 0 | 3977 ms |
| `node roster/tezos-local-recursion/check-comparison.js` | 0 | 52542 ms |
| `node roster/tezos-local-recursion/check-compatibility.js` | 0 | 28912 ms |
| `node roster/tezos-local-recursion/check-residual-capacity.js` | 0 | 3862 ms |

Executed on `ae50e6d3309d57d1596de9cc3f088afe42287cad`. HEAD and the
pre-existing user-dirty files were unchanged by the gate sequence.

## Scope and residual risk

Risk is low within the specified scope. Mutual groups, non-direct wrappers,
alias/value-flow discovery, computed heads, and general 0CFA remain deliberately
excluded and therefore retain conservative behavior.

## Independence limitation

I authored task-local recursive witness/checker portions earlier in the task.
I did not self-certify their design correctness; independent reviewers covered
that authored surface. The final commands listed above were personally executed
in a serialized slot and are independent execution evidence only.
