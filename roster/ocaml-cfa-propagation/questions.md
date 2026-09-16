<!-- The path identifies the task; this view intentionally withholds intent. -->

_Generated: 2026-09-16_
_DO NOT include the task description in this file or share it with the researcher._

1. How are callable identities, finite target sets, uncertainty reasons, and source metadata currently represented, joined, and propagated by the OCaml analysis worklist?
2. Which typedtree expression and binding forms currently create or connect values for function parameters, arguments, return positions, captured variables, recursive bindings, and partial applications?
3. How does the existing implementation distinguish declaration identity from individual occurrences when aliases, recursive references, or repeated applications share the same callable?
4. Which current transfer paths preserve an unknown component alongside known targets, and where do unsupported expressions or unseeded cells enter the analysis state?
5. What regression fixtures and assertions currently cover propagation fixed points, arity mismatches, duplicate occurrences, metadata retention, and mixed known/unknown target sets?
6. What pinned Tezos and Irmin inputs, baselines, comparison metrics, and reproducibility checks are already used to evaluate OCaml call-graph changes?
7. Which existing architectural review findings constrain the current analysis boundary, ownership model, convergence behavior, or evidence requirements?
8. [ecosystem] How do documented production OCaml call-graph or control-flow analyses model argument-to-parameter flow, returned functions, closures, recursion, and partial application?
9. [ecosystem] What conservative handling of unsupported typedtree constructs and unresolved callees is documented in established static-analysis frameworks for higher-order functional languages?
