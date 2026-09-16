# Approved delivery sequence — OCaml data,0CFA and functors

Authorized 2026-09-15: "ok go en roster autonome pour chaque étape".

1. **SHIPPED — ocaml-data-preservation**: PR110 merged2026-09-15, main7cd4ccb; #26 closed, #68 partial. Full Roster review/QA GO; required exact-head CI build35017888487 passed12m30s before guarded rebase merge. User approved independently compiled variants in stage4.
2. **SHIPPED — ocaml-cfa-foundation**: PR111 merged2026-09-16T11:57:56Z, main53907c5. Finite function-value/reason worklist, literals/aliases/joins end-to-end; opaque-root-alias unknown loss corrected with RED/GREEN. Roster review round2 GO, QA345/345 and CHECK1/2/3 GO, exact-head CI35091891816 build12m56s before guarded merge. Pinned410: +1Irmin/+2protocol,0loss/newMUST. Not full interprocedural0CFA. Optional MCP unverified (missing private token).
3. **NEXT — ocaml-cfa-propagation**: arguments, returns, captures, recursion and partial applications within specified subset. Before adding transfers, resolve or explicitly design around foundation advisories: complete finalized-session guards, exhaustive semantic reason type/mapping, shared root/local transfer grammar. Branch feat/ocaml-cfa-propagation contains delivery receipt only; product not started.
4. **PENDING — ocaml-functor-targets**: concrete actual member correspondence using functor-bindings, explicit supported application identities, and independently compiled same-source variant handling deferred from stage 1 by explicit user approval.
5. **PENDING — ocaml-cfa-qualification**: query integration/limits, useful-query benchmark, Irmin/protocol precision and resource costs.

Each step has independent Roster review and deterministic QA, a PR, required CI green on exact final head and guarded rebase merge before its successor. No product acceptance based on model consensus. Known target sets never erase independent unknown contributions. This delivers an explicit supported subset, not full OCaml completeness. Expansion beyond these contracts requires user direction.

Initial state: origin/main a8114dc; local c10d1a4 adds only prior delivery documentation. Seven existing untracked files preserved. Root checkout used without a new worktree. Stage1 branch fix/ocaml-data-preservation.
