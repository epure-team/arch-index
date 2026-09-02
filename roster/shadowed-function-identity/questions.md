<!-- No title. The path roster/shadowed-function-identity/questions.md already identifies this
     file, and a descriptive slug in an H1 briefs the researcher on the very
     thing this skill requires be withheld. The mandated title contradicted the
     skill's own zero-disclosure rule. -->

_Generated: 2026-09-02_
_DO NOT include the task description in this file or share it with the researcher._

1. Where in lib/arch_index/arch_index_cmt.ml is the `functions` table populated during compilation-unit traversal, and what SQL statement and UNIQUE constraint govern how a binding is inserted when its (module_id, name) key already exists?

2. Where and how does `lambda_name` construct ordinal-based synthetic identities for anonymous/lambda nodes, and what naming pattern (e.g. `#N` suffix) does it produce?

3. How does `fn_lookup` in lib/arch_index/arch_index.ml resolve call edges to function rows post-hoc, what key(s) does it use to perform this lookup, and at what point in the pipeline does this resolution occur relative to the `functions` table being populated?

4. What other modules or files (e.g. call_graph_extractor.ml, LSP/flat-schema consumers) read from or depend on the `functions` table's (module_id, name) uniqueness assumption, and how do they consume function identity/names?

5. What existing tests (e.g. under tezt/tests/) exercise same-name bindings, shadowing, or duplicate-name scenarios in a single module, and what do they currently assert about the resulting row count or call-edge attribution?

6. What downstream consumers (arch-query or other tooling) query the `functions` table by bare name, and what documented or implicit contract exists today regarding uniqueness/meaning of a function's `name` column?

7. [ecosystem] How do other static-analysis or call-graph tools (e.g. for OCaml, or general compiler IR-based indexers) represent multiple same-named bindings/shadowed definitions within the same scope in their symbol/call-graph data model, and what identifier scheme (ordinals, unique IDs, scoped paths) do they use to keep such bindings and their edges distinct?
