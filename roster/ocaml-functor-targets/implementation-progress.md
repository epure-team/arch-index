# Implementation checkpoint — 2026-09-16

Implementation is complete and ready for independent Roster review. This is
not yet a review/QA GO, PR, CI, merge, or Stage-4 delivery claim.

## Product

- Matched same-artifact local functor actuals now supply additive concrete
  member targets for formal calls. The original `MAY_TOP/module_param` row is
  retained and every concrete target is `MAY_ENUMERATED`.
- Direct bodies, nested owners/includes, and invocation-safe one-hop value
  aliases are supported. Persistent roots, `Path.Papply`, module aliases,
  anonymous structures, unpack, opaque/missing members and unsupported alias
  chains remain conservative.
- Physical calls keep their original occurrence ordinal, sink/handler metadata
  and caller. No functor body, caller, function, or runtime instance is cloned.
- Exact copies share only the representative graph while retaining independent
  catalogue, binding and target provenance. Nonidentical same-source variants
  reconcile only when their normalized catalogue and target-relevant call
  signature matches; altered variants fail closed.

## Persistence and lifecycle

- Main schema 1.16 adds `functor_target_inputs`,
  `functor_target_witnesses`, supporting indexes, and
  `functor_target_contract=v1`.
- Witnesses link application, declaration/formal slot, actual/member paths,
  physical occurrence, candidate call and target function. The finalizer
  validates expected cardinalities, binding/formal/actual equality, caller and
  target source/run identity, candidate kind/callee, JSON shape and all joins.
- A rejected positive candidate or any storage/collection failure prevents the
  marker. Reindex drops both tables and clears the marker. Flat output remains
  unchanged and has an explicit non-inference test.

## Verification

- CHECK-1: pass, including six authentic target fixtures, exact copies,
  separately compiled variants, reversed discovery order and altered-variant
  refusal.
- CHECK-2: full 351/351 Tezt suite plus inventory/lifecycle/query/compatibility
  independent binding modes pass.
- CHECK-3: frozen Stage-3 replay is neutral at 45,290 rows and digest
  `e1eca575...`; candidate adds seven exactly witnessed Irmin relations, zero
  protocol relations, zero global loss and zero new/upgraded `MUST`.
- Checker controls classify pass/assertion/setup as 0/1/2 for all three gates.
- Fresh self-index 2x2 calibration: A=B576, C=D587 `MUST`/NULL rows. The engine
  is neutral on each corpus; the net 11-row increase is source-only. Owned
  temporary worktrees/builds were removed.

## Limits

No whole-program, closed-world, completeness, runtime-instance, cross-unit,
Shapes/UID, or performance claim is made. The safe supported subset improves
Irmin in the pinned corpus but does not add a protocol relation in this stage.
