<!-- No title. The path roster/<task-slug>/questions.md already identifies this
     file, and a descriptive slug in an H1 briefs the researcher on the very
     thing this skill requires be withheld. -->

_Generated: 2026-09-04_
_DO NOT include the task description in this file or share it with the researcher._

1. In the OCaml call-graph walker, where exactly are `functions` rows and outgoing call edges recorded — which typedtree constructs are visited, what triggers an edge insertion, and how are value bindings whose right-hand side is a bare path (qualified or local) currently traversed?

2. What is the complete schema of the call-graph database (tables, columns, edge kinds, and any non-call relation tables already present), and which schema-version/migration mechanism governs changes to it?

3. Enumerate every consumer that reads call edges or `functions` rows — the CLI commands (`may-fail`, `raises`, `reachable-from`, `reaches`, `fan-in`/`fan-out`, `arch-rules`, `arch-impact`, `arch-coverage`, `arch-mutants`), the MCP surface, and the rules engine — and for each, state the exact query or traversal it performs and whether it distinguishes edge kinds.

4. How does the walker resolve a qualified path (`M.g`) to a target node today, and what name/homonym disambiguation logic exists when multiple `functions` rows share a name across files or modules?

5. Where do the CLI and MCP verdict formatters decide what to emit when a query name matches multiple nodes — what ordering, grouping, deduplication, or per-node annotation exists in the output path?

6. In the branch `feat/qualified-unit-resolution` (@8c1cad0), what does the S4 disambiguation step do concretely — which tables and predicates does it consult, and where in the code is the "touches the functions table" test performed?

7. [ecosystem] How do established call-graph and code-intelligence systems (SCIP/LSIF, CodeQL, Glean, rust-analyzer, OCaml's merlin/odoc) represent aliasing, re-export, and forwarding definitions — what relation kinds do their schemas define alongside call edges, and how do their query surfaces expose them?
