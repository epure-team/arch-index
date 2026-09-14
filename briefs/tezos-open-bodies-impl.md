# Implementation Brief — tezos-open-bodies

**Date:** 2026-09-14
**Mode:** full
**Status:** COMPLETED

## Modified files

Product commit `a5ae981` adds private invocation-only descriptors and post-insert
availability checks in `lib/arch_index/arch_index_cmt.ml`. The public collector
interface, flat consumer, schema, CFG ownership and global function recognition
are unchanged. Four tests in `tezt/tests/open_body_targets.ml` are registered
through `tezt/tests/main.ml`.

Task-local native probe, witness admission, counted comparison, frozen replay
and self-attribution checks are under `roster/tezos-open-bodies/`. Briefs/spec and
phase evidence document the contract. Four exact self-reference literals/files
were refreshed only after pristine source-only attribution, including the two
duplicated expected constants in `checks/origin-recurring-consumer.js`.

## Decisions made

Only direct same-CMT Pident calls to a structural binding whose RHS is exactly
one path-only open around a function are admitted. They reach the already
stored synthetic body as MAY_ENUMERATED, never a new MUST. Physical expression
identity, exact compiler binding identity, unique correspondence and successful
insertion are required. Known rejected parents/bodies remain dropped_node TOP;
unknown/mismatched availability remains callback_param TOP.

Independent native occurrence evidence binds all 316 candidate transitions on
the fixed 410-CMT corpus. Actual application locations, caller ownership,
shadowing, body identity and complete printed-head group capacity are checked.
No new Irmin relations, no lost relations, no unexplained row movement.

The first self measurement used an intermediate CMT. Fresh root and pristine
builds agree at25/998/6335/570. Crossed old/new producers establish source-only
movement, not a reason to relax a guard. The sole source assertion remains
identical and allowed exactly once. Full attribution and chronological failed
measurements remain available; no failed setup is represented as a TDD RED.

## Quality Gates

- Build: `opam exec -- dune build` exit0.
- Full guard: `opam exec -- _build/default/tezt/tests/main.exe --no-color --keep-going`
  exit0,336/336,21:09:51–21:13:54UTC, four new tests.
- CHECK1 native/Tezt/flat/rich/identity/availability: exit0.
- CHECK2 actual316pairs, native duplicate fixture and13refusals: exit0.
- CHECK3 frozen replay and17recordrefusals: exit0.
- CHECK4 witnessed fixed410 comparison: exit0, `attempt3-candidate-s0F4So`,
  +316protocol/+0Irmin/0loss,45052rows,
  digest9ab4e0b13457247fb93dc83bf80323fcc5cec67866a18f56995ac0ec4a20867e.
- CHECK5 exact self and pristine attribution: exit0 on committed `a5ae981`.
- CHECK5 parser negative controls, bundle22SHA and whitespace: exit0.
- Format/coverage: not configured; skipped, no invented PASS.

Exact commands and evidence paths: `roster/tezos-open-bodies/implementation-validation.md`.
Checks were serialized against source/artifact writes. Product source matches
the calibrated snapshot. Seven unrelated untracked paths are deliberately
preserved; task-owned work is committed before review, not globally clean.

## Points of attention for review

Review private marker finalization, root-name collisions, exact AST identity,
optional argument holes and returned-call residual multiplicity. Check that
flat/point-free/callback paths do not acquire invocation-only ownership. Audit
independent witness reconstruction and capacity refusal rather than relying on
the positive corpus count alone. Fixed-corpus checks depend on local pinned
Tezos inputs and ignored frozen evidence; native Tezt tests are portable CI gates.

## Identified out-of-scope

No 0CFA, general defunctorization, instance substitution, cross-module include
resolution or alias/escape expansion. No held PR93 changes or Tezos writes.
Owned calibration worktrees/builds were removed; foreign worktrees untouched.
Hooks/CWR/claims reconciler/OCaml specialist were unavailable: documented manual
pipeline and Sol/Terra delegation used, not fabricated tooling runs.

Next: full independent roster review, QA, then exact-head green CI and rebase
merge. Still2/5 delivered; this completion does not authorize retention alone.
