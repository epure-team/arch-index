# Implementation baseline and TDD start

Manifest captured from clean89a15afb51fa89eb0da209a3f611b08b2df31ff3 before
baseline commands. No pre-task dirty entries. Shared worktree only.

Root ran, in order:

1. `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune build --root .` =>0.
2. `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune test --root .`
   =>0, session92240 terminal. Tezt256/256 successful (last at09:54:02UTC);
   Alcotest64 across8+3+17+10+7+5+14. Controlled assertion/execution and FK
   failure outputs are deliberate negative tests, not failures of the suite.
   Readiness quiescence fallback warning was visible. Output was truncated in
   display, so no claim of exhaustive warning census; terminal suite exit is real.
3. `rtk proxy node scripts/review-bundle-verify.js` =>0,22SHA-matched files1.6.0.

Dedicated ocaml-dune-specialist agent file and language patterns are absent;
installed implementer role was read fully and a user-approved fresh Sol executes
the OCaml specialty in the shared worktree. ACTIVE_TASK requires shared worktree;
no additional checkout is created. Higher-priority developer file-edit rules use
apply_patch for manifest/ACTIVE_TASK instead of the skill's shell-write recipe.

Sol first performed read-only prep while root baseline ran. After terminal0 root
authorized TDD implementation and transferred exclusive Dune ownership to Sol.
Agent reported genuine red: native fixture compiled and existing producer indexed
it; assertion `functor_applications table count is 0, expected 1` failed1/1 after
successful test binary build. Root has not yet independently rerun that new test;
agent's evidence will be inspected at handoff. Product GREEN is not yet claimed.

No active root Dune/session remains. Root handles independent checker/docs after
OCaml handoff, calibration, final full gates and phase completion.

## Preserved baseline executables

Before product rebuild, Sol copied the baseline producer and query to the owned
scratch directory `/tmp/functor-baseline.wVd0Kv`. Root verified their actual
`.exe` filenames and SHA256 values:

- `arch_callgraph_ocaml.exe`: `3c8cb74d672b5c5e0225009ab69036ca494e294b584336d853b979c90cf74e21`
- `arch_query.exe`: `ddea3d3b6366a67e9384f99edaf81700f31ad5a0d638d5e8443ad3e5c84e0e81`

An initial root hash command guessed names without `.exe` and failed with missing
files; listing and hashing the actual files corrected that assumption. These
binaries support an old/new owned-fixture comparison only. The shipped checker
must remain self-contained and may not depend on this scratch directory. Remove
the two verified owned copies and their directory after evidence is captured.

During integration root detected an out-of-manifest helper addition to
`lib/arch_tools/arch_db.ml`. Sol removed its own addition and localized the typed
row shape in the authorized new query module instead; no scope expansion.

## Integration observations before completion

Sol reports the first post-change full run:258Tezt,256passed,2failed. Ordinary
catalogue producer/query tests pass. The failures are the authentic origin
consumer and MUST-null ceiling (462 versus455). Attribution remains pending;
neither is waived, and no calibration has been applied.

Root's read-only collector inspection found the explicit `Tmod_constraint`
module-type child omitted. The installed compiler package lacks tast_iterator.ml;
the [OCaml5.3 upstream implementation](https://raw.githubusercontent.com/ocaml/ocaml/5.3/typing/tast_iterator.ml)
(lines469–472) confirms traversal of the inner expression followed by the explicit
module type. This can reach additional `module type of` applications. Sol was
asked to add a premise-verified native red test and fix within existing scope.
This is an in-progress integration finding, not a completed roster review.

Root's later independent probe run compiled the full tree successfully and
confirmed lifecycle/storage/selection probes exit0. It exposed a further setup
gap: a synthetic `ghost-valid` CMT had lost its source mapping when serialized.
The new source-mapping check correctly returned2. Earlier mutation-probe exits0
proved only that the AST could be reread, not that the producer could resolve its
source. The probe author is fixing serialization while keeping the stricter
premise check. This does not count as a product assertion failure or inventory
CHECK-1 success.
