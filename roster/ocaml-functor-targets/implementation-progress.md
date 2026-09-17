# Implementation checkpoint — 2026-09-16

Review round 1 found proof-authentication and publication gaps. This loopback
implements the v2 correction and awaits independent Roster review; it is not
yet a review/QA GO, PR, CI, merge, or Stage-4 delivery claim.

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
  collect their own local occurrences/proofs before unique stable-field
  reconciliation; zero/multiple matches fail closed.

## Persistence and lifecycle

- Main schema 1.17 adds durable target occurrences/candidates and
  `functor_target_contract=v2`.
- Candidate rows bind each actual/member path to its exact call/function; the
  finalizer authenticates physical sites, member-to-candidate links, stable
  representative reconciliation, cardinalities, run/source identities and JSON.
- Candidate calls, provenance and marker are one atomic batch. A rejected
  positive candidate or any storage/collection failure records failure without
  leaving an independently consumable functor-derived call.

## Verification

- CHECK-1: pass, including durable occurrence and member/candidate corruption
  ratchets, real `arch-query` consumer coverage, exact copies and independently
  compiled variants.
- The self-index golden is recalibrated to `27/1231/7556`: the v2 collector,
  occurrence inventory and atomic-publication code are indexed source, while
  its direct target checks remain independently covered above.
- CHECK-2: full 354/354 Tezt suite plus inventory/lifecycle/query/compatibility
  independent binding modes pass.
- CHECK-3: frozen Stage-3 replay starts at 45,290 rows and digest
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
