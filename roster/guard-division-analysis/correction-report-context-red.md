# R1 report-context RED

Production baseline remains the pre-R1 implementation; correction plan committed as
613d6e2. Full `dune build --root .` under the explicit project opam switch exited0
before adding the new regression test. No report production edits preceded RED.

Command (task worktree):

`rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- node scripts/check-guard-report-context.js`

Exit1 (assertion, not setup). Output:

```text
empty: text linked compiler version
classified: text linked compiler version

2 !== 0
```

The script compiled both owned fixtures and invoked the actual built CLI four times
(JSON/text for empty/classified). All child setup/CLI calls succeeded; assertions
detected missing text compiler context. Each assertion currently stops at its first
missing obligation; later limitations checks must also pass after the correction.
Both temporary fixture/build directories were removed by the check's finally block.

Integrated command `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune test --root . --force`
completed exit1. Tezt ran256 tests: only test147, the new report-context check,
failed with the same two assertion messages; the other255 passed. All64 Alcotest
tests passed. Run06:56:14–06:58:45 UTC. Initial non-Tezt tool output was truncated;
the final complete Tezt output was inspected, not claimed as a retained full log.

OCaml specialist released for production edits only after this integrated RED.
The specialist subsequently obtained full-build0, full-suite0 (256Tezt+64Alcotest)
after the minimal report/private-package correction. Fresh Terra helper audit
found the checker absent from Dune's test dependency list; root added the exact
dependency after the suite terminated. Root also tightened indirect/omitted scope
assertions to require the complete negative statement, not just the noun phrase.

The final checker then passed the actual shared archive-only RED/GREEN helper:
`correction-context-ratchet.json` retains command, exit0 and raw result. Its checker
blob is8108aa657905871c8693120bb3168ce40b9d6c0f. Archive cleanup is helper-owned;
no extra worktree was created. Full final suite after remaining fixture/oracle
corrections is still required. No R2 resolved finding or GO is claimed here.
