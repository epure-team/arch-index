# Spec research — fresh Sol, read-only

No edits/builds by researcher; this is documentary input, not review GO.

- Structural traversal visits literal/recursive modules, constraints and functor
  bodies at definition prefixes; applications/aliases/unpacks excluded:
  arch_index_cmt.ml:162–198. Whole-structure binding naming:924–996.
- Direct-body admission matches immediate Texp_function only:878–996. Local
  Texp_let lambda stamps are a separate immediate-pattern mechanism:1865–1920.
- Structural shadows retain last bare name and earlier#N:901–948. Synthetic
  names use current caller and function location, with collision suffixes:
  1424–1460; cfg-postdom-dominance.md:17–18,99,126.
- Syntactic arity:889–899; actual supplied Some argument count is currently
  limited to owned-module invocation:2202–2212. Partial and returned-call residual
  logic:2241–2244,2325–2332. Preserve rather than globally reinterpret it.
- Head_enumerated always emits MAY_ENUMERATED; known dropped target emits
  MAY_TOP/dropped_node. Missing non-dropped enum target remains a dangling leaf:
  arch_index.ml:1481–1492. New descriptor must not rely on missing target fallback.
- Rejected lambda rows tracked, facts not reassigned:arch_index_cmt.ml:3464–3501;
  existing injected rejection fixture:tezt/tests/local_module_targets.ml:202–222.
- Point-free physical-root guard:arch_index_cmt.ml:2745–2848. Exception/value
  propagation captured independently:1383–1408; CFG finalization:2876 onward.
  Lambda bodies own their CFG/effects, parent scope covers only occurrence:
  specs/exn-raise-sets.md:27,59,157; specs/error-channels.md:32.
- Flat fallback shares collector but discards lambda/effect facts and walks
  top-level callers only:call_graph_extractor.ml:248–342. Existing flat test does
  not invent nested-caller coverage:local_module_targets.ml:224–250.
- Existing entities ResolutionRelation/ResolutionRowMultiset keep definitions
  from specs/tezos-call-resolution.md:162 and tezos-residual-targets.md:197.
  LocalStructureTarget is NOT redefined as this new lambda descriptor.

No conflict requiring changed old spec semantics found. New checks still needed
for the exact admitted shape, node availability/collision and unchanged legacy
flat/effect/point-free paths. Research does not itself establish these checks.
