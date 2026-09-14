# Self-index golden ratchet evidence

The checker runs the built OCaml producer against
`_build/default/lib/arch_index` in an owned temporary database, executes the
same three SQLite statements as CI, and byte-compares their output with
`test/fixtures/self-index-stats.txt`. It never writes the fixture and removes
its temporary directory in `finally`.

## RED

Before refreshing the fixture, the producer and SQLite query both succeeded.
The checker exited 1 with an assertion mismatch:

```text
expected: modules 25, functions 956, calls 6145
actual:   modules 25, functions 980, calls 6245
```

This was an assertion RED, not a missing-tool or producer setup failure.

## GREEN

After refreshing only the measured fixture, the same checker exited 0 with
25 modules, 980 functions, and 6245 calls.

The final portability correction follows the existing native-check convention:
an in-repository `_opam` uses its explicit switch, while CI runs the producer
directly under its inherited opam environment. Root integration independently
exercised that inherited-environment branch and observed exit 0 with the same
25/980/6245 result. Its missing-producer control exited 2 as SETUP before
temporary database creation.

Final local verification passed: `dune build`, the standalone smoke, all seven
native-wrapper titles, the wrapper's five classification assertions, and the
forced full suite (327/327 Tezt cases, including the new ratchet). No coverage
percentage is claimed because no coverage tool is configured.
