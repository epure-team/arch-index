# OCaml TDD evidence

- Inventory RED: `dune build --root . tezt/tests/main.exe` exit 0, then the scoped Tezt run exit 1 with `expected one authentic division site, got 0`; fixture compilation and `arch_guard` execution both succeeded.
- Inventory GREEN: scoped Tezt under the explicit opam switch exit 0 (1/1).
- Post-inventory full suite: `dune test --root . --force` under the explicit switch exit 0 (246/246 Tezt; 64 Alcotest).
- Domain setup correction: the first probe attempt contained a literal `\\n` and exited as a JSON setup error; this was not counted as behavioral RED.
- Domain RED: runnable probe exit 0, scoped Tezt exit 1 with `expected exact Const 5, got ... top`.
- Domain GREEN: scoped Tezt exit 0 (2/2).
- Post-domain full suite: `dune test --root . --force` under the explicit switch exit 0 (247/247 Tezt; 64 Alcotest).
- Restriction RED: runnable probe exit 0, scoped Tezt exit 1 with `restriction must be reductive and preserve Const 2`, observing `nonzero`.
- Restriction GREEN: scoped Tezt plus `git diff --check` exit 0; `Const 2` is preserved.
- Unsupported-first RED: authentic fixture and CLI ran successfully; scoped Tezt exit 1 because loop, try, and `%perform` ancestry were reported `MAY_ZERO` (only the partial and int64 sites were fenced).
- Unsupported-first GREEN: scoped Tezt exit 0 (2/2); partial sites accumulate missing/arity reasons and loop, try, effect ancestry are sticky `UNSUPPORTED`.
- Interpreter RED: authentic compiled semantic fixture and CLI exited successfully, but scoped Tezt exited 1 with `nonzero: expected 3, got 1`; actual census was `1/1/5/0/5` for nonzero/zero/may-zero/unreachable/unsupported.
- Interpreter GREEN: after independent raw-inventory/interpreter reconciliation, scoped Tezt exit 0 (2/2), with expected semantic census `3/1/2/1/5`.
- Post-integration full suite: `dune test --root . --force` under the explicit switch exit 0 (247/247 Tezt; 64 Alcotest). A second final run after aggregate-preflight, metadata, sorting, interface, and output-bound work also exited 0 with the same counts.

All direct test commands use `opam exec --switch=/home/mathias/dev/arch-index --`; a direct run outside the switch found the system compiler and correctly rejected its incompatible CMT, recorded as setup friction rather than RED.
