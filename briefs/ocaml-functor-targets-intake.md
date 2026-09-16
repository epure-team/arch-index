# Intake Brief — ocaml-functor-targets

**Date:** 2026-09-16
**Status: VALIDATED**
**Type:** feature
**Trust boundary:** no

## Goal

Resolve a bounded, explicit subset of calls through OCaml functor parameters. For a
locally identified functor application whose formal slot and concrete named actual
module are both proven by the existing compiler-identity binding collector, calls to
members of that formal parameter must gain the corresponding callable members of the
actual module as `MAY_ENUMERATED` targets. Multiple proven applications contribute a
union of concrete targets; no known target may erase an independent unknown
contribution, and this stage must not promote any such edge to `MUST`.

The implementation must keep correspondences scoped to their authentic compiler
artifact and formal position, handle independently compiled variants of the same
source without borrowing compiler identities between variants, and remain idempotent
for byte-identical copies. It must demonstrate deterministic synthetic behavior and a
fresh pinned-410 Tezos/Irmin comparison with zero lost resolved relations, zero new
`MUST` claims, and at least one genuine resolved-relation gain attributable to the new
functor correspondence. The external roadmap note must record the shipped contract,
measured effects, limits and next stage.

## Scope Boundary

What is explicitly OUT of scope:
- General OCaml defunctorization, context-sensitive analysis, whole-program 0CFA, or cloning a functor body per application.
- Guessing from display names, source spellings, basename equality, `Path.Papply`, anonymous structures, unpacked first-class modules, persistent/cross-unit heads, or any application lacking the existing explicit matched identity premises.
- Treating the indexed corpus as closed world, removing the original `module_param` uncertainty merely because some concrete actuals are known, or upgrading a functor-derived target to `MUST`.
- Cross-artifact joins on `Ident.unique_name`; nonidentical compiled variants must be analyzed in their own identity scopes and may only add facts to shared source-level graph rows after independent proof.
- Full generative-functor semantics, synthesized instance identities, exception/type instantiation, or module-shape/UID adoption.
- User-facing query redesign and final useful-query/resource qualification, which remain Stage 5 (`ocaml-cfa-qualification`).
- SQLite backend replacement or broader storage migration.

## Relevant Files

| File | Role | Key snippet |
|---|---|---|
| `lib/arch_index/arch_index_bindings.ml` | Existing application/formal/actual compiler-identity collector | `actual_root_key`, `declaration_key`, `formal_position`, `head_application_ordinal` |
| `lib/arch_index/arch_index_functors.ml` | Typedtree application inventory and stable artifact-local ordinals | `Tmod_apply`, `Tmod_apply_unit`, preorder `ordinal` |
| `lib/arch_index/arch_index_cmt.ml` | Module export ownership, CMT call extraction, CFA expansion and compiled-variant reuse | `build_local_module_targets`, `Head_enumerated`, `Head_unknown Module_param`, `graph_reuse` |
| `lib/arch_index/arch_index_cfa.ml` | Monotone known/unknown/residual value domain | `join_value` unions all independent contributions |
| `lib/arch_index/arch_index.ml` | Producer orchestration, final qualified resolution and call persistence | catalogue/binding callbacks and `Resolved | Ambiguous | Not_found` correspondence |
| `architecture-schema.sql` | Artifact-scoped catalogue and binding contracts plus source-level graph rows | `(producer_run_id, artifact, ordinal)` and `(producer_run_id, artifact, declaration_key)` keys |
| `tezt/tests/functor_bindings.ml` | Authentic compiler-identity, curried-slot, shadowing and refusal fixtures | direct, curried, traversal, identity-mutation and lifecycle cases |
| `tezt/tests/ocaml_cfa_foundation.ml` | Authentic CMT target/unknown and no-overclaim assertions | exact call-row and CFA metadata checks |
| `tezt/fixtures/ocaml_cfa/` | Compiled fixtures extended for formal-member/actual-member flow | current higher-order, metadata and module fixtures |
| `roster/ocaml-cfa-foundation/check-cmt.js` | Deterministic authentic producer gate | CHECK1 producer assertions |
| `roster/ocaml-cfa-foundation/check-tezos.js` | Pinned 410-input Tezos/Irmin replay | relation deltas, loss and new-MUST gates |
| `briefs/ocaml-cfa-five-stages.md` | Approved delivery sequence | Stage 4 contract and Stage 5 handoff |
| `/home/mathias/notes/2026-09-01-arch-index-roadmap.md` | External roadmap note requested by the user | current Stage 3 shipped status and Stage 4 next action |

## Architecture Notes

- The trusted premise is the existing artifact-local compiler identity chain, not a
  textual module name: matched binding → declaration/formal position → named formal
  binder key and named actual root key.
- `local_module_exports` already distinguishes callable direct bodies, invocation-safe
  one-hop aliases and opaque named members. Correspondence must reuse those ownership
  facts rather than reconstructing a parallel name-only export model.
- A functor body is currently walked as code, but its `Tmod_functor` and applications
  do not become concrete module owners. The new facts therefore belong at the boundary
  where formal-root member calls are classified, before final call-row correspondence.
- Each formal-member site may receive zero, one or several concrete actual-member
  targets. The union is monotone and remains accompanied by the independent
  `module_param` frontier in this stage.
- Curried applications must select actuals by declaration identity and
  `formal_position`; the nested application ordinal is provenance, not a substitute
  for the formal slot.
- Exact-copy graph reuse may share the source graph row but still runs per-artifact
  binding collection. Nonidentical same-source variants must not be dropped before
  their independently proven additive functor facts can be considered; their local
  compiler identifiers must never be compared across artifacts.
- The task-description keyword heuristic did not match any trust-boundary keyword;
  proposed value is therefore `no`. The feature changes analysis precision but does
  not authorize access or weaken an integrity/authentication boundary.
- No claims reconciler or managed KB is installed. Research context is recorded in
  `roster/ocaml-functor-targets/research.md`.

## Quality Gates

```bash
# Build
opam exec -- dune build --root .

# Full deterministic test suite
opam exec -- dune exec --root . tezt/tests/main.exe -- --job-count 1

# Focused authentic CMT/functor tests
opam exec -- dune exec --root . tezt/tests/main.exe -- --job-count 1 --match 'functor|CFA'

# Existing independent functor contract checks
opam exec -- node scripts/check-functor-bindings.js inventory
opam exec -- node scripts/check-functor-bindings.js lifecycle
opam exec -- node scripts/check-functor-bindings.js query
opam exec -- node scripts/check-functor-bindings.js compatibility

# Authentic producer and pinned Tezos/Irmin comparisons
opam exec -- node roster/ocaml-cfa-foundation/check-cmt.js
opam exec -- node roster/ocaml-cfa-foundation/check-tezos.js

# Lint/Format
# No standalone lint or format gate is documented; dune build/test are the documented gates.
```

## Open Questions

_(empty — the supported identity subset, soundness boundary, variant behavior, corpus acceptance and Stage 5 exclusions are fixed above)_
