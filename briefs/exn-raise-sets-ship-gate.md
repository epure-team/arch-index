# Ship Gate — exn-raise-sets

**Date:** 2026-09-03
**Status: VALIDATED** — human approved push + PR (merge left to the human), PR opened:
https://github.com/epure-team/arch-index/pull/54
**Review:** GO (round 1 / cycle 1,
`briefs/exn-raise-sets-review.json`), QA GO (round 1, `briefs/exn-raise-sets-qa.md`). The
push and the PR are outward-facing and wait for the human; the merge is the human's.
**Branch:** `feat/exn-raise-sets` → `main` (base `origin/main` `69e5c3d`, up to date — no rebase
needed at gate time). **Open PR next door:** #53 `fix/schema-versioning` (roadmap-handler session;
no file overlap, see follow-up 1).

## What this ships

Roadmap item 3.4 in its exception-**identity** form — a computed Java-`throws` for OCaml:

- Producer (`arch-callgraph-ocaml`): per function node (lambda nodes included) raise origins
  with the resolved constructor path, handler scopes with their caught sets from *closing* arms,
  the scope enclosing **each call site**, rebinds; `comment_db_meta.exn_contract = v1`.
- Query: `arch-query raises <fn>` — worklist fixpoint over MUST ∪ MAY_ENUMERATED with
  subtraction of what the handlers around each call catch (the user's hard requirement), ⊤
  with reasons, `BOUNDED` / `UNBOUNDED (⊤): {…}` / `BOUNDED_UNDER_HYP(externals_pure)`;
  `raisers-of`, `exn-stats`; `NOT_ANALYSED` refusal on Flat/pre-feature DBs.
- Spec `specs/exn-raise-sets.md` (20 FR, 14 AC, 4 CHECK), doc `docs/exception-raise-sets.md`,
  tezt `tezt/tests/exn_raise_sets.ml` (two-unit fixture, 55 assertions), golden regenerated,
  `must_null_ceiling` recalibrated (260 → 289, new module's compiler-libs leaves), CHANGELOG.

## Evidence (soundness gate)

- `dune build --root .` ✅ · `dune test --root . --force` 91/91 ✅ (85 s) · `arch-rules … --on-vacuous
  fail` exit 0 — **1 proved / 0 violations / 3 UNKNOWN** (recorded here as `4/0` ✅; that was the
  tool's own summary collapsing a three-state verdict into one number — corrected in PR #70. Three
  of the four rules proved nothing, so the gate is unchanged, not passed; see
  specs/qualified-unit-resolution.md §10.5) · golden `20 / 532 / 3804` ✅ · CHECK-4 (additive
  schema, `runner.ml` untouched) ✅.
- Review round 1: 20 findings, 3 HIGH + 5 correctness MEDIUM fixed in-round — including a real
  soundness hole the spec had not covered (a raise inside `lazy`/object/functor bodies under a
  `try` was stored as closed; fixed by clearing the scope stack around deferred walks, pinned as
  US-1.11). Gate exit 0, no strike. Codex cross-runtime pass degraded (non-conforming output).
- **CHECK-3, Tezos `proto_alpha`** (`briefs/exn-raise-sets-qa-proto-alpha.log`): 468 modules,
  14 452 functions, 73 588 calls, 0 rejected rows, 3 s index, 0.38 s fixpoint.
  `bounded 23.8 %` raw / `46.4 %` under `externals_pure`; ⊤ dominated by `may_top_edge` (7 743 —
  functor/module parameters, roadmap 3.7's class). Origins 1 219: `assert` 585, `compare` 262,
  `division` 150, `index` 124, `failwith` 58, `raise` 20, `unknown` 5. Six spot checks read
  against source, all consistent; the protocol's entry points `begin_application` /
  `apply_operation` / `finalize_block` are reported as escaping `{Assert_failure,
  Division_by_zero(, Invalid_argument)}` via `apply_liquidity_baking_subsidy` plus ⊤ through
  `alpha_context` — a finding for a human, named with witnesses.
- Self-index: 532 nodes, 20.7 % bounded / 68.7 % under the hypothesis (Sqlite3/compiler-libs
  externals dominate).

## Follow-ups (recorded, not blocking)

1. **`schema_version` → "1.3"** + `docs/schema-versions.md` entry — after PR #53
   (`fix/schema-versioning`) merges; the five tables here are additive, minor bump per that PR's
   convention. Rebase this branch on it if #53 lands first.
2. `Arch_exn.load` / `Arch_graph.load` share one node/edge loader (review MEDIUM, architecture).
3. Extract `bin/arch_query/arch_exn_queries.ml` on the `arch_effects_queries.ml` pattern (MEDIUM).
4. `known_leaf` fixed table: a shared constant or a sync test with the producer's recognisers (LOW).
5. Module-alias paths: `Tezos_protocol_alpha.Environment.Z.Overflow` vs
   `Tezos_protocol_environment_alpha.Z.Overflow` never unify (over-approximating) — a `Path`
   alias normalisation would close it (LOW, QA observation).
6. `raises` on a name shared by two modules prints two verdicts labelled by name only — add the
   file (LOW, UX).
7. Roadmap item 3.4 notes and the in-flight claim live in `~/notes/2026-09-01-arch-index-roadmap.md`
   (out of repo, by that file's own design) — FR-020's roadmap clause is satisfied there.
8. Item 4.2 (`divergence-reachability`) now has its "handler half"; its redo can build on
   `exn_scopes` rather than re-walking `Texp_try`.
9. ⊤ reasons accumulate transitively to the roots: `raises <entry point>` can list hundreds of
   witnesses. Group by reason kind with a count and the first N witnesses (LOW, UX).
10. Error-monad counterpart (`tzresult`): the protocol signals errors as `Error trace` values,
    not exceptions. A "may-return-error" analysis of the same lattice shape (origins =
    `error`/`fail`/`tzfail` on literal constructors, handlers = `catch`/`trace` combinators,
    propagation along `let*` binds) would answer the `throws` question in the protocol's own
    idiom — a roadmap item, not a follow-up of this PR.

## Commits (5 on the branch + this gate)

- `8e3a599` feat(exn): exception-identity may-raise sets with handler subtraction at call sites
- `8abb95d` chore(ledger): implement COMPLETED
- `17bc764` fix(exn): review round 1 — deferred bodies escape their enclosing try; shared raise recogniser; ⊤ keeps its known part
- `88a5542` chore(ledger): review round 1 GO
- `17ab207` chore(ledger): QA GO — proto_alpha measurement recorded
