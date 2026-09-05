<!-- No title. The path roster/<task-slug>/questions.md already identifies this
     file, and a descriptive slug in an H1 briefs the researcher on the very
     thing this skill requires be withheld. -->

_Generated: 2026-09-05T12:05:00+02:00_
_DO NOT include the task description in this file or share it with the researcher._

1. Where is the existing static mutation-targeting logic implemented, and what data does it currently produce or persist about mutants, sites, and functions? Include the exact input and output formats it reads and writes.

2. What database schema, tables, and migration mechanisms currently exist in arch-index's SQLite store, and how are call-graph, symbol, and coverage data represented there? State where the schema version constant is defined and how it is bumped.

3. How does arch-index currently represent and track ⊤ (MAY_TOP) unresolved edges in the call graph, and what query or traversal logic consumes that marker? For each consumer, state whether it treats a ⊤ edge as widening or narrowing its answer.

4. What existing mechanisms map tests to the functions or code they exercise (coverage data, impact analysis, test-to-symbol linkage), and how is that mapping stored? For each mechanism, state whether it is computed statically, observed at runtime, or both.

5. How are language- or tool-specific adapters and profiles currently structured (for example under a `profiles/` directory), and what interface do they expose for per-language behaviour? Name every existing profile and the mechanism that loads it.

6. List every verdict or status vocabulary defined across the repository's analysis binaries, and for each value state the exact condition in the code under which it is emitted, with a file:line reference.

7. Where does the repository establish that an identifier is unique over a real corpus rather than over a fixture, and what commands or queries does it use to demonstrate that? Include any place a uniqueness or duplicate count is reported.

8. [ecosystem] How do existing mutation testing engines (cargo-mutants, go-mutesting, mutaml, mutmut, Stryker, PIT and peers) structure their mutant generation, test selection, and result reporting formats, and what conventions do they use for identifying kills versus survivors?

9. [ecosystem] How do established test runners (alcotest, tezt, cargo test, go test, pytest) expose per-test invocation commands and per-test coverage data that external tooling can consume?
