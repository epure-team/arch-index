_Generated: 2026-09-14T22:45:01Z_
_DO NOT include the task description in this file or share it with the researcher._

1. How does the current CMT ingestion pipeline represent value binders, compiler identities, function literals, and their source locations?
2. Where and how are callable bodies retained, discarded, or marked ambiguous during indexing and normalization?
3. How does the existing invocation-resolution logic associate call sites with local bindings, and which cases does it currently accept or reject?
4. Which invariants preserve effects, control-flow graphs, flat facts, and non-head facts when resolution information is attached or propagated?
5. How are MAY and MUST facts currently created, validated, and prevented from being strengthened without sufficient evidence?
6. Which fixtures and assertions cover recursive local functions, direct function literals, binder shadowing, ambiguous bodies, and large Tezos analyses?
7. [ecosystem] What identities and expression metadata do the OCaml compiler-libs Typedtree and CMT APIs expose for local recursive value bindings, identifier occurrences, and stored function bodies?
