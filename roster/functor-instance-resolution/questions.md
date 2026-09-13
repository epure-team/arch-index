_Generated: 2026-09-13T09:08:22Z_
_DO NOT include the task description in this file or share it with the researcher._

1. How does the analyzer currently decode OCaml module expressions, module applications, functor parameters, anonymous structures, and nested application chains from compiler artifacts?

2. Where and how are module paths normalized today, including module-alias rewrites, unresolved paths, and the preservation of source-level versus canonical identities?

3. What database entities and invariants currently represent definitions, bodies, module instances, call sites, and call-graph targets, and which uniqueness constraints govern them?

4. How does the current call-resolution pipeline distinguish a uniquely resolved target, multiple possible targets, and an unresolved or uncertain target?

5. Which native fixtures and query-level tests currently exercise modules, functors, aliases, exception identities, and bounded graph-enumeration behavior?

6. [ecosystem] What identities and application structure do current OCaml compiler artifacts expose for functor applications, module arguments, aliases, anonymous structures, and generative definitions?

7. [ecosystem] What guarantees does the OCaml language and compiler documentation provide about applicative versus generative functors and the identity of exceptions defined within module or functor bodies?
