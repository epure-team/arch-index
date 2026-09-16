# QA scope — ocaml-cfa-foundation

**Date:** 2026-09-16
**Status: VALIDATED**

```sh
rtk proxy opam exec -- dune build
rtk proxy opam exec -- dune runtest --force
rtk proxy node scripts/review-bundle-verify.js
rtk proxy git diff --check
rtk proxy node roster/ocaml-cfa-foundation/check-domain.js
rtk proxy node roster/ocaml-cfa-foundation/check-cmt.js
rtk proxy node roster/ocaml-cfa-foundation/check-tezos.js
```

Run serially on frozen reviewed source and captured binary hashes. No concurrent
source/build mutation. Verify all19 ACs and44 FRs in the task spec, domain oracle
vs solver; alias/literal/join main target rows; flat unknown tuple/no homonym;
partial/cond/dead/channel/scopes and independent residual preservation.
Check literal collisions, shadow binders, unsupported captures/patterns/returns,
bottom-to-unknown and unchanged point-free/static behavior. Native coverage in CI.

CHECK3 depends on selected external pinned410 corpus. Missing corpus is >=2/
unavailable, not pass. Preserve original baseline; report gains/losses and resource
observations separately; zero gain allowed, false bounded relation forbidden.
No configured formatter/linter/coverage gate; no fabricated success or percentage.
No TUI scenarios. Roster QA convergence and exact-source evidence remain required.
