# Intake Brief — ocaml-cfa-propagation

**Date:** 2026-09-16
**Status: VALIDATED**
**Type:** feature
**Trust boundary:** no

## Goal

Extend the shipped finite OCaml callable-value worklist into a conservative,
context-insensitive interprocedural propagation layer for a precisely declared
same-CMT subset. Function-valued actual arguments must reach supported formal
parameters; function-valued normal results must reach application results;
lexically captured values and supported recursive groups must participate in the
same fixed point; and supported partial applications must remain callable values
that can later resolve their underlying target without erasing independent
unknown frontiers.

The change must first close the three recorded foundation architecture findings:
all mutation APIs reject finalized sessions, uncertainty reasons use an exhaustive
semantic type and persistence mapping, and root/local expression transfer share
one grammar with explicit ownership policy. The delivered value is measured by
authentic CMT regressions and the frozen 410-input Tezos replay, reporting Irmin
and protocol relation gains/losses separately.

## Scope Boundary

What is explicitly OUT of scope:
- Functor actual-to-formal member correspondence, generative/applicative functor
  semantics, and reuse of independently compiled functor variants (stage 4).
- Cross-CMT callable-value propagation, whole-program linking, polymorphic
  specialization, object/method dispatch, first-class module unpacking, effects,
  continuations, mutable-field points-to analysis, and claims of full OCaml
  completeness.
- Destructured formal/binding patterns unless the specified subset can preserve
  every function-valued component; unsupported patterns remain explicit unknown.
- Turning corpus row deltas into a semantic soundness/completeness claim.
- Broad query UX, useful-query benchmarking, storage migration, or resource
  qualification beyond recording the existing CHECK-3 observations (stage 5).
- Changing existing static direct-call resolution or promoting new CFA-derived
  facts to `MUST`.

## Relevant Files

| File | Role | Key snippet |
|---|---|---|
| `lib/arch_index/arch_index_cfa.ml` | Finite inclusion kernel | `type value = {targets; reasons}` and `copy`/`solve` fixed point |
| `lib/arch_index/arch_index_cfa.mli` | Kernel contract | fresh cells, seeds, copies, solve and query |
| `lib/arch_index/arch_index_cfa_cmt.ml` | Typedtree/CMT session | binder cells, literal authentication, expression transfer, call occurrences and finalization |
| `lib/arch_index/arch_index_cfa_cmt.mli` | Session boundary | root/literal notifications, local registrations, call tokens and final query |
| `lib/arch_index/arch_index_cmt.ml` | Main producer integration | local binding registration, `Texp_apply` classification and per-occurrence expansion |
| `lib/arch_index/call_graph_extractor.ml` | Flat producer integration | session creation, storage notification, finalization and pending-call expansion |
| `test/test_cfa.ml` | Independent domain oracle | repeated full-scan oracle and fixed-point/ordering/cycle cases |
| `tezt/tests/ocaml_cfa_foundation.ml` | Authentic CMT regression harness | physical occurrence, metadata, arity, unknown-frontier and consumer assertions |
| `tezt/fixtures/ocaml_cfa/` | Compiled OCaml fixtures | aliases, joins, literals and arity boundary inputs |
| `roster/ocaml-cfa-foundation/check-tezos.js` | Pinned corpus replay | fixed 410-input Tezos revision, exact relation deltas and no-loss/no-new-MUST gates |
| `roster/ocaml-cfa-foundation/architect-round2-findings.json` | Precondition findings | lifecycle guard, reason typing/mapping and shared transfer grammar |

## Architecture Notes

- The kernel already computes a monotone least fixed point over finite target and
  uncertainty sets. Interprocedural support should add cells and inclusion
  constraints, not a second solver.
- Binder identity is `Ident.unique_name`; literal and stored-root authentication
  additionally uses physical Typedtree identity. Source locations and display
  names are not declaration identities.
- Application occurrence identity is separate from callable identity. Each
  physical call token retains its caller/site/partial/conditional/dead/scope and
  residual metadata through one-to-many expansion.
- The supported subset is same-session/same-CMT and 0-context-sensitive: formal
  and return cells are shared across all supported call sites of one callable.
  Recursion therefore converges through ordinary cyclic inclusion constraints.
- Known targets never absorb or erase an independent uncertainty reason. Every
  unsupported actual, formal pattern, result form, capture, arity/label mapping,
  partial closure or ownership boundary must preserve a typed reason.
- Partial application is value production, not execution of the callee body.
  Already supplied function-valued arguments may flow to corresponding formals,
  while the application result represents a conservative residual callable; body
  return flow becomes applicable only when the represented call is saturated.
- Root and local expression evaluation need one shared transfer function with an
  explicit environment/owner policy; syntax recognition must not be duplicated.
- CHECK-3 is structural evidence only. It pins Tezos revision
  `1727d7e192f2374edda7ad7adceef6f4ec51f71a`, 410 inputs, Irmin/protocol
  relation sets and resource observations, and must retain zero relation losses
  and zero new `MUST` rows.
- No managed claims projection or project `AGENTS.md` exists. The user-supplied
  instruction resolves to `/home/mathias/.codex/RTK.md` and is applied to shell
  execution.
- Type `feature` and Trust boundary `no` are validated under the user's explicit
  authorization to run every stage autonomously through the full Roster pipeline.

## Quality Gates

```bash
# Build
opam exec -- dune build --root .

# Unit and integration tests (native CI command)
eval "$(opam env)"
dune test --root .

# CFA domain, authentic CMT, and pinned Tezos qualification
rtk proxy node roster/ocaml-cfa-foundation/check-domain.js
rtk proxy node roster/ocaml-cfa-foundation/check-cmt.js
rtk proxy node roster/ocaml-cfa-foundation/check-tezos.js

# Lint/Format
# No standalone lint or format gate is documented; dune build/test are the documented gates.
```

## Open Questions

_(empty; unsupported language forms are required to remain explicit unknown, and
the exact supported partial-application representation will be fixed by the
adversarial spec before implementation.)_
