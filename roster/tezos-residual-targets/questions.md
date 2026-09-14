_Generated: 2026-09-14_
_Do not share task text with the researcher._

1. How do arch_index_cmt.ml and call_graph_extractor.ml currently derive, represent, and classify module and value identities from CMT Typedtree, Path, Ident, and Uid data?
2. Which existing code paths handle qualified persistent modules, module aliases, functor applications, and functor parameters, and where do they deliberately refuse or leave call targets unresolved?
3. How do the Tezt tests, retained corpus artifacts, and verifier harness under roster/tezos-call-resolution and roster/functor-instance-resolution currently measure resolution outcomes and preserve existing graph relations?
4. [ecosystem] What identity, path, alias, and functor-application information do the supported OCaml compiler-libs APIs officially expose through CMT files, Typedtree, Path, Ident, and Uid?
