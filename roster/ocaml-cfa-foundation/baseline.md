# Implementation baseline — 2026-09-16

HEAD c397efd1b2248564c05c74fdab795213dea593db, before product changes.
Manifest captured base and seven foreign untracked paths before gates; ACTIVE_TASK
selects ocaml-cfa-foundation. No new worktree.

- Build: opam exec -- dune build, exit0.
- Preflight test collection: main.exe --list, exit0 (348 table lines, not test count).
- Full baseline: opam exec -- dune runtest --force, exit0; Tezt344/344.
  Seven Alcotest runners also succeeded (3+17+13+10+7+5+14 tests).
- Review bundle:22 hashes matched, exit0.
- Source:261 tracked files under lib/bin/test/tezt/dune/schema;
  SHA256 eb072a76f8a4bd66db9534540596a375fe02f94e319cf8b1e3907728bd5e07ae.
- Pre/post hashes identical for that source selection and index CLI, query CLI,
  Tezt runner. Details/logs: improvement/2026-09-16-cfa/baseline-{pre,post}.json
  and baseline-runtest.log (ignored local evidence).

The first capture guessed a nonexistent index binary; corrected to
bin/arch_index_cli/arch_index_cli.exe before the full baseline began. This is not
a claim to have captured every producer binary. Final Tezos qualification must
also capture arch_callgraph_ocaml explicitly. Negative-test diagnostic errors in
the successful suite log are not ignored test failures; process exit and all
success rows establish the recorded result.

READY preflight renewed. No formatter/linter/coverage configured; none claimed.
Old Tezt temporary-directory warnings are preserved because ownership is unknown.
Sol cfa_ocaml_slice1 receives exclusive OCaml edit/build token after this baseline.
