1. Where does the existing code derive and store OCaml call-head identity, and which source locations participate in normalization or disambiguation?
2. How does the current resolver represent module paths, aliases, nested modules, includes, and functor applications in the Tezos Irmin and protocol inputs?
3. Which compiler-produced artifacts are consumed, how is OCaml 5.3 artifact compatibility checked, and which fields carry symbol and module identity?
4. Which database tables, keys, and joins connect call sites, definitions, compilation units, module paths, and candidate targets?
5. Which safeguards and assertions govern preservation of existing call sites and target edges, and under which conditions are they tested?
6. Which native regression fixtures and expected outputs cover resolved call targets, including aliases and functors?
7. Which reproducible benchmark commands, datasets, environment requirements, and baseline counts exist for call-target resolution, and which checks do they actually perform?
8. [ecosystem] How do OCaml 5.3 compiler-libs APIs and artifact formats specify identifier identity, module aliases, functor paths, and typed calls?
