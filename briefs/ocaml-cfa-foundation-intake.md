# Intake Brief — ocaml-cfa-foundation

**Date:** 2026-09-15
**Status: VALIDATED**
**Type:** feature
**Trust boundary:** yes

Routine intake/type/trust validation is covered by explicit user authorization
for autonomous Roster on each approved stage. No quiz answers are invented.
The keyword heuristic hit authorization/provenance context; the substantive
boundary is preserving the distinction between bounded targets and unknown
contributions consumed by reachability verdicts. Standard full route, not a
machine-checked formal-verification claim.

## Goal

Deliver stage2 of the approved five-stage roadmap: a real finite function-value
domain, constraints and terminating worklist connected to OCaml CMT extraction,
persisted call targets and existing queries. Same-CMT function literals, ordinary
nonrecursive single-variable alias chains and branch joins must reach actual
stored function identities rather than merely exercise a detached solver demo.

Known targets and unknown contributions coexist. Solving a branch containing
both a known function and an unsupported/opaque value must retain the known
candidate AND an explicit unknown frontier. New value-flow candidates are
MAY_ENUMERATED, never an inferred MUST. Existing static direct calls keep their
current execution/arity rules.

## Scope Boundary

In scope: finite pure solver; per-CMT binder/expression identities; same-callable
and compilation-unit-level nonrecursive aliases; named known functions and
collector-promoted literals; if/match branch-result joins; sequence result;
ordinary applications consuming these values; main and shared flat CMT paths;
source/run/target-origin provenance; deterministic tests and pinned Tezos replay.
Same-CMT top-level aliases used inside another function are required, not deferred
as a local-only prototype. Closed source contributions may refine their own old
TOP head; independent argument/escape/overapplication residuals remain intact.

Explicitly out of this stage, retained in the full roadmap:

- Argument-to-formal, return-result, capture, recursive transfer and partial
  closure propagation: stage3. Existing support remains; unsupported new flows
  conservatively remain unknown. Per-CMT visibility must not accidentally import
  an enclosing callable's captured local values.
- Functor actual-member substitution and independently compiled variants: stage4.
- Full query-specific explanations/precision and resource qualification: stage5.
- Heap/mutation, general pattern destructuring, higher-order module evaluation,
  complete OCaml semantics, scalar numeric analysis changes and vulnerability hunting.
- New public arch-guard embedding API, changes to guard verdicts, or dependency
  on guard's private numeric implementation.
- Persisted full derivation-chain/proof graph. Stage2 provenance means actual
  target identity/source origin plus call site and producer run; not proof of
  every transfer. Internal witnesses may be finite diagnostic metadata, never
  a termination-state component or a claimed formal certificate.

## Relevant Files

| File | Role | Key interface or observed snippet |
|---|---|---|
| `lib/arch_index/arch_index_cmt.mli` | Shared private CMT interface | `pending_call`, `lambda_node`, `collect_calls_from_expr`, `process_cmt` |
| `lib/arch_index/arch_index_cmt.ml` | Existing extraction/identity and deferred edge finalization | Actual lambda naming, compiler-stamp tables, raw ord/context metadata, final pending calls |
| `lib/arch_index/call_graph_extractor.ml` | Flat CMT fallback consumer | Shared collector over implementation structure |
| `lib/arch_index/dune` | Private module wiring | Existing `private_modules` |
| `lib/arch_guard/guard_domain.ml` and `.mli` | Existing scalar prior art | `Bottom | Const | Nonzero | Top`, join/restrictions/checked arithmetic |
| `lib/arch_guard/guard_interpreter.ml` | Existing value interpreter, unchanged | `Ident.same` env, local aliases/branch joins, fresh function env, ordinary calls Top |
| `scripts/check-arch-guard.js` | Independent domain-law testing pattern | BigInt containment, join laws and monotonicity |
| `tezt/tests/local_value_targets.ml` | Adjacent alias and fallback tests | One-hop support, historical computed/unqualified TOP expectations |
| `tezt/tests/callgraph_soundness.ml` | Existing reachability contract | Mixed frontier, conditional literal/partial/overapplication cases |
| `tezt/tests/point_free_aliases.ml` | Non-call alias semantics | `edge_form='value_alias'` predecessor edges |
| `architecture-schema.sql` | Existing persistence contract, no new vocabulary assumed | Three edge kinds; edge_form only NULL/value_alias/module_alias |
| `docs/edge-kind-contract.md` | Current semantics and historical slice boundaries | MUST versus MAY_ENUMERATED/TOP |
| `test/dune`, `tezt/tests/dune`, `tezt/tests/main.ml` | Native test registration | Full runtest and independent probes |
| `roster/ocaml-data-preservation/check-tezos.js` | Latest shipped pinned410 baseline |45052 rows; Irmin4849/protocol12171; neutral stage1 check |

## Architecture Notes

Existing arch-guard is an actual abstract interpreter, not a missing component.
Its numerical Top absorbs constants; applying that representation to function
targets would lose useful known contributions. Its structural evaluator has no
worklist to reuse. Preserve its CLI/private API and scalar behavior. Reuse its
explicit-bottom/monotone-join/conservative-fallback and independent-law-test
principles, while implementing the function-value domain separately. Avoid a
generic shared library with no second real consumer; an independent read-only
architecture assessment confirms this boundary.

Use one opaque analysis session per CMT, not global state or a per-function-only
prototype. Compiler binder identities and physical expression identities are
session-local; locations are provenance, never cell identity. Keep lexical
callable ownership to distinguish a local alias from a capture. Reconcile literal
placeholders with names assigned by the existing collector; never mint duplicate
lambda names in another traversal. Noncollected or rejected bodies cannot become
silently bounded leaves.

A structure/value-only pass may collect finite constraints while the existing
collector remains authoritative for body identity/CFG. Finalize once after all
same-CMT bindings/literals are observed. Main and flat producers must share that
batch boundary. A compatibility one-expression wrapper may remain for probes.
The precise implementation belongs to the downstream plan, but location-only
placeholder strings and premature per-function solving are prohibited.

Call expansion preserves occurrence multiplicity, caller, conditionality,
partial/dead flags, handler/channel scopes and source sites. Deduplicate facts
within an occurrence, not distinct occurrences sharing a line. Keep point-free
alias edges unchanged. Ordinary CFA-derived applications retain edge_form NULL;
do not overload that closed vocabulary with analysis provenance.

Finite cells and finite target/unknown atoms, monotone union and changed-cell
rescheduling must establish termination; no unchecked cutoff masquerades as a
complete solution. Deterministic failure is required if declared limits cannot
be respected. Expected source-growth golden changes require measured attribution,
not blind regeneration or weakened allowlists/ceilings.

Earlier bounded-slice tests/spec notes saying aliases/computed values stay TOP
are refined only for the newly supported forms. Historical baselines stay frozen.
All actual losses/new relations on pinned Tezos must be accounted for separately
from source-growth changes. A zero real-corpus gain is an honest observation,
not a reason to invent results or claim the entire five-stage roadmap complete.

## Quality Gates

Run serially, using the existing OCaml5.3 opam environment:

```sh
rtk proxy opam exec -- dune build
rtk proxy opam exec -- dune runtest --force
rtk proxy node scripts/review-bundle-verify.js
rtk proxy git diff --check
```

Spec will name standalone domain/solver, authentic CMT/query and Tezos checks
with0=pass,1=assertion,>=2=setup/error. Native tests must run in CI. Separate
formatter/linter/coverage gates are not configured; no invented coverage rate.
Capture pre/post sources and binary identities; no concurrent mutation during
gates. Roster independent review/QA and required exact-final-head CI must pass
before guarded rebase merge and stage3. Preserve seven foreign untracked paths.

## Open Questions

None remaining at intake: target-origin provenance, not full derivation proofs;
numeric arch-guard behavior/private API unchanged; one session per CMT; explicit
stage3/4 boundaries. Any newly discovered material requirement conflict is
resolved during adversarial specification before implementation.
