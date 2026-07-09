# Research Questions — cfg-postdom-dominance

_Generated: 2026-07-09_
_DO NOT include the task description in this file or share it with the researcher._

1. How does `collect_calls_from_expr` in lib/arch_index/arch_index_cmt.ml currently classify call edges (e.g. the `nested` counter and any MUST/MAY distinctions), and which Typedtree expression constructs (if/match/try/loops/&&/||/lazy/object/functor/letop) does it treat specially during traversal?

2. Which components share the Typedtree walker used by lib/arch_index/arch_index_cmt.ml — in particular call_graph_extractor.ml (LSP path) and the effects extractor — and through what interfaces or shared functions do they consume its output?

3. How does the Go backend (callgraph-go) compute its `alwaysExec` / edge-kind classification, and what algorithm and data structures does it use to decide whether a call always executes?

4. How are anonymous functions and nested lambdas currently represented in the extracted call graph and function rows — do they get their own nodes, and how are calls inside lambda bodies attributed and classified?

5. What does selftest-callgraph-soundness.sh currently test — what fixtures, assertions, and edge-kind expectations does it encode, and how is it wired into the repo's test/CI flow?

6. Where and how are edge kinds (MUST/MAY_TOP/MAY_ENUMERATED) defined across the schema, storage layer, and arch-query queries; how are functions named and keyed (qualified names, file/line identity) in the index; and where does the self-index golden file record function and call counts?

7. What expression-termination or noreturn handling (raise/failwith/exit) exists in the OCaml or Go extractors today, and how do current traversals treat code following such expressions? Externally: how do mature analyzers (Soot, WALA, LLVM, Frama-C) name and link synthetic closure/lambda/anonymous-function nodes in their call graphs, and how do OCaml tools (merlin, odoc, ppx tooling) identify anonymous functions in source?
