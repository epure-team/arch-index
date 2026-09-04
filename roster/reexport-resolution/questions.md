<!-- No title. The path roster/<task-slug>/questions.md already identifies this
     file, and a descriptive slug in an H1 briefs the researcher on the very
     thing this skill requires be withheld. -->

_Generated: 2026-09-04_
_DO NOT include the task description in this file or share it with the researcher._

1. What schema does the dependency table use for module-level relations, and how does the `kind` column's constraint set (`open`/`include`/`alias`/`local_open`) map to the language constructs the analyser observes?

2. How does the current name-resolution pass build and query its module-name-to-path (or module-name-to-unit) map, and what happens when a lookup fails?

3. How is an "unresolved external leaf" represented in the schema, and what fields distinguish it from a resolved call edge with a proof-carrying target?

4. What logic, if any, currently consults the dependency-relations table (`open`/`include`/`alias`/`local_open`) when resolving a qualified callee name, and which components are the sole readers and writers of that table today?

5. How does the codebase currently disambiguate a single-letter or short module alias that refers to different target modules in different files, and is any per-file or per-scope aliasing context tracked elsewhere in the analysis?

6. How does the in-review sibling change re-keying the module-name-to-path map by compilation-unit name affect basename-based lookups, and what data structures or tests does that change touch?

7. [ecosystem] How do existing OCaml tooling projects (merlin, ocaml-lsp, odoc, dune's cross-module resolution, ppx-based analysers) resolve qualified module references, module aliases and includes to their originating definitions, and what precision/soundness tradeoffs do they document for ambiguous or re-exported names?

8. [ecosystem] How do other static call-graph or dependency-analysis tools — for OCaml or other languages with structural module/namespace aliasing — handle the tradeoff between leaving a call target unresolved versus risking a mis-resolution, and what conventions exist for representing "unknown/unresolved" targets in their output schemas?
