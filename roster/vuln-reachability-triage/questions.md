<!-- No title. The path roster/<task-slug>/questions.md already identifies this
     file, and a descriptive slug in an H1 briefs the researcher on the very
     thing this skill requires be withheld. -->

_Generated: 2026-09-06_
_DO NOT include the task description in this file or share it with the researcher._

1. Where in the codebase are unresolved/⊤ call edges represented and queried — which schema columns, SQL helpers, and OCaml modules produce and consume the `calls.kind` values (MUST / MAY_ENUMERATED / MAY_TOP), and how does existing code compute a forward transitive closure over the call graph?

2. How does the rule language implement `forbid reach`, and what selector syntax, root-selection options (including `--roots exported`), and result/verdict data types does it currently define? Point to the parser, evaluator, and the type declaring possible outcomes.

3. What flags or columns mark a function as exposed/exported in the schema and extractors, how are they populated for OCaml, and where can an explicit list of entry symbols be supplied today?

4. How are fully-qualified OCaml value paths stored as identifiers in the index — what is the exact string form for values inside modules, inside functor applications, and for external/C primitives, and where is any name normalization (case, module aliasing, path splicing) performed?

5. Does any OCaml **type** in this repository represent a qualified value path as a parsed structure rather than as a flat string — for example a record or variant carrying module path segments and a value name separately? For every place a qualified name is compared, matched, or joined, state whether the comparison operates on a string or on such a structure, and cite the declaration.

6. What durable/record-keeping structures already exist in this repo — their file formats, schemas, required fields (corpus, tool version, commit, provenance, status enums), and the code or tests that read and validate them?

7. What are the existing output and integration paths for findings: the SARIF emitter, the coverage report that counts unresolved edges, and the ADR governing external-tool integration — including where a finding's severity/confidence class such as `heuristic` is assigned?

8. How does the codebase currently handle a query or join that returns zero rows — where does it distinguish "no data / not measured" from "measured empty", and what error or exit-code taxonomy exists for failing loudly?

9. [ecosystem] What public APIs and downloadable per-ecosystem archives distribute security advisories for the OCaml/opam package ecosystem, and what is the schema of the fields that name affected symbols or functions (OSV format and the opam security advisory database)?

10. [ecosystem] How do existing reachability-based vulnerability scanners for other language ecosystems (for example Java, JavaScript, Python, Go) define and report their result lattices — what statuses do they emit, how do they root the analysis at an API surface, and how do they represent analysis incompleteness?
