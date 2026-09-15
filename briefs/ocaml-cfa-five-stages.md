# Approved delivery sequence — OCaml data,0CFA and functors

Authorized 2026-09-15: "ok go en roster autonome pour chaque étape".

1. **ACTIVE — ocaml-data-preservation**: #26 effects identity/source paths and proven exact-copy CMT duplicates (#68 partial). User approved moving independently compiled variants to stage 4. Full Roster; baseline already captured.
2. **PENDING — ocaml-cfa-foundation**: function-value domain, constraints, terminating worklist, literals/aliases end-to-end and provenance.
3. **PENDING — ocaml-cfa-propagation**: arguments, returns, captures, recursion and partial applications within specified subset.
4. **PENDING — ocaml-functor-targets**: concrete actual member correspondence using functor-bindings, explicit supported application identities, and independently compiled same-source variant handling deferred from stage 1 by explicit user approval.
5. **PENDING — ocaml-cfa-qualification**: query integration/limits, useful-query benchmark, Irmin/protocol precision and resource costs.

Each step has independent Roster review and deterministic QA, a PR, required CI green on exact final head and guarded rebase merge before its successor. No product acceptance based on model consensus. Known target sets never erase independent unknown contributions. This delivers an explicit supported subset, not full OCaml completeness. Expansion beyond these contracts requires user direction.

Initial state: origin/main a8114dc; local c10d1a4 adds only prior delivery documentation. Seven existing untracked files preserved. Root checkout used without a new worktree. Stage1 branch fix/ocaml-data-preservation.
