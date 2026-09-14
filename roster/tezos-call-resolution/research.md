# Research — tezos-call-resolution

Mode: full, degraded staffing. Online research: enabled.
Input: validated neutral questions.manifest.json. Fresh Sol analyzer received no task description and never read task.md. The runtime refused additional agent threads; that same blind agent performed pattern and external roles sequentially. Root performed path-only locator work. This is not four independent research passes.

## Question 1 — Call-head identity

Typed applications are classified into Head_local, Head_qualified, Head_enumerated or Head_unknown, retaining source location, conditionality, partiality and edge form until global insertion. Local body and alias identities use Ident.unique_name. Module aliases only normalize when their target root is persistent; suffixes are preserved, applied/extra-type paths declined.

References: lib/arch_index/arch_index_cmt.ml:601, :617, :1021, :1044, :1365, :2012, :2065, :2091; lib/arch_index/arch_index.ml:1459.

## Question 2 — Module representation

Nested definitions use qualified definition paths. A functor body is indexed once; applying it creates no instance definitions. Nonpersistent module roots remain dynamic unless an existing alias rewrite handles them. Dependency extraction records only top-level opens, includes and aliases, independently of call resolution.

The strong qualified tier enumerates __-joined prefixes with residual function paths. Only when it has no candidate does the weaker facade tier inspect later bare segments below the deepest indexed prefix. Source comments explicitly disclose homonym/linkage residuals; it is incorrect to describe the entire resolver as excluding arbitrary later segments.

References: lib/arch_index/arch_index_cmt.ml:721, :1333, :2948, :2955; lib/arch_index/arch_index.ml:973, :1300, :1368, :1373, :1384.

## Question 3 — Artifacts and compatibility

The scanner consumes CMT/CMti. Implementation bodies are read from Implementation annotations; interface annotations supply exposure/docs. Unit identity comes from cmt_modname, source mapping from cmt_sourcefile, and local symbol identities from typed binders/paths. Compatibility is acceptance by the linked Cmt_format.read, not a separately implemented exact 5.3-version predicate. The call resolver does not use CMT imports/UIDs/shapes as linkage evidence.

References: lib/arch_index/arch_index_cmt.ml:307, :346, :442, :2761, :2775; lib/arch_index/arch_index.ml:475.

## Question 4 — Database and resolution joins

modules.path is unique; functions are unique by (module_id,name). calls has a required caller_id, nullable callee_id, display name, file:line call_site, kind and metadata. fn_lookup joins stored functions/modules and keys by (source path,qualified function name). Qualified unit registry paths feed this lookup. Ambiguity and known dropped bodies produce TOP. module_deps does not participate in call-target resolution.

References: architecture-schema.sql:131, :151, :287, :363; lib/arch_index/arch_index.ml:820, :959, :1391, :1477, :1523, :1689.

## Question 5 — Safeguards and assertions

calls.kind is nullable TEXT without a SQL vocabulary CHECK; the test in callgraph_soundness queries invalid/null kinds and requires zero. top_reason and edge_form have SQL CHECKs. Point-free tests assert no value_alias MUST and test SQLite rejection of unknown edge forms. Existing no-drop tooling compares populations, but its kind-movement self-join explicitly documents false movements when several calls share a line. These are tests and comparison safeguards, not a proof of arbitrary target correctness.

References: architecture-schema.sql:293, :307, :345; tezt/tests/callgraph_soundness.ml:300; tezt/tests/point_free_aliases.ml:232, :556, :583; scripts/callgraph-diff.sh:1, :240.

Example existing assertion: `kind IS NULL OR kind NOT IN ('MUST','MAY_ENUMERATED','MAY_TOP')` must match zero rows.

## Question 6 — Native fixture patterns

Nested qualification tests expect exact linked definitions or ambiguity, not a homonym guess. Library scoping tests cover wrapped units and facade residuals. Module-alias tests cover applied heads, escaped callbacks and let operators, persistent roots and parameter refusal. Point-free tests cover local/chained/cross-module aliases and exclusions. Functor tests assert definition-only indexing and parameter TOP.

References: tezt/tests/nested_module_qualification.ml:112, :169; tezt/tests/qualified_library_scoping.ml:328, :551; tezt/tests/module_alias_heads.ml:12, :315, :326; tezt/tests/point_free_aliases.ml:183, :333, :617; tezt/tests/callgraph_nested.ml:160, :202, :235.

Example existing pattern: module-alias uses are checked with `edge_form='module_alias' AND callee_id IS NOT NULL`; aliases to unit-local modules are currently declined.

## Question 7 — Existing corpus controls

The fixed manifest contains 410 CMTs: 66 Irmin core, 17 pack, 52 pack Unix and 275 protocol. Earlier measurements collected all 410 and reported 1,275 functor applications, 12,373 functions and 45,018 call rows. Three generated aliases and one unresolved generated wrapper were excluded from the initial 414-artifact inventory. The old scripts temporarily select symlinks under Tezos/_build and remove their DBs. measure-bindings.js checks hashes before/after, unchanged git status and binary provenance; its 202 matches are explicitly parameter provenance, not call targets. No retained per-call before/after target comparison is provided by these scripts.

References: roster/functor-instance-resolution/tezos-irmin-candidate/manifest-410.tsv:1; report.md in the same directory:27, :38, :62, :82; reproduce.sh:13, :18, :25, :34; roster/functor-binding-resolution/measure-bindings.js:5, :18, :35, :46, :50; tezos-irmin-bindings/report.json in the same directory:8, :13, :24, :77, :135.

Existing producer command shape: `arch_callgraph_ocaml.exe --build-dir=<selection> --db-path=<fresh-db> --schema-path=architecture-schema.sql`. scripts/callgraph-diff.sh instead compares a freshly built self-index corpus, with magnitude floors; its documented kind-movement report is not a reliable changed-site oracle.

## Question 8 — External interfaces

OCaml 5.3 Typedtree distinguishes identifier expressions, applications and the different module-expression constructors. Path carries structural Pident/Pdot/Papply/Pextra_ty forms; Ident.same is binding identity, whereas name rendering is not a cross-artifact identity. CMT interfaces document typed trees, magic, imports, source/build information, UIDs and shapes. Compiler-libs offers no stable cross-version API promise.

Primary sources accessed by the blind external role:

- [OCaml 5.3 Typedtree](https://ocaml.org/p/ocaml-compiler/5.3.0/compiler-libs.common/Typedtree/index.html)
- [OCaml 5.3 Path](https://ocaml.org/p/ocaml-compiler/5.3.0/compiler-libs.common/Path/index.html)
- [OCaml 5.3 Ident](https://ocaml.org/p/ocaml-compiler/5.3.0/compiler-libs.common/Ident/index.html)
- [OCaml 5.3 Cmt_format](https://ocaml.org/p/ocaml-compiler/5.3.0/compiler-libs.common/Cmt_format/index.html)
- [Compiler manual](https://ocaml.org/manual/5.3/comp.html)
- [Compiler front end](https://ocaml.org/manual/5.3/parsing.html)

## Coverage gaps and corrections

- GitHub tagged implementation sources were blocked by robots.txt; ecosystem findings concern published interfaces/manual, not verified internal version-check implementation.
- Initial research incorrectly claimed a SQL kind CHECK and generalized the prefix-tier restriction to the facade tier; both were corrected against source before synthesis.
- Initial benchmark search missed the roster measurement artifacts; the follow-up inspected them before this report.
- No ground-truth oracle for arbitrary real-corpus target correctness exists in the inspected measurements. File:line is not a unique syntactic-call identity.
- No installed claims reconciler or acknowledged code-intel orientation resolver; local manifest validation and blind source flow used.
