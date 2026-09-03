# Plan — exn-raise-sets

**Date:** 2026-09-03
**Status: VALIDATED**
_(autonomous mode: quiz and final gate recorded as pre-approved per the user's instruction; every
DISAGREE below was resolved by a reachability check, none by guessing.)_

## Sequential steps (vertical slices over fixture complexity)

1. **Slice A — literal raise + single `try` + schema + `raises` end to end.** Files:
   `architecture-schema.sql` (5 additive tables + no version change), new
   `lib/arch_index/arch_index_exn.ml/.mli` (scope stack, origin/arm classification, canonical path
   for predef/persistent roots), hooks in `lib/arch_index/arch_index_cmt.ml` (`pending_call.exn_scope`,
   `Texp_try` enter/leave, `Texp_apply` origin, return value), `lib/arch_index/arch_index_cmt.mli`,
   `lib/arch_index/arch_index.ml` (prepared statements, `insert_call` rowid + `call_exn_scopes`,
   `exn_contract` meta), `lib/arch_index/arch_index_db.ml` (`insert_call_rowid`; do NOT touch the
   `.mli`'s schema-version area — add the new val only), `lib/arch_index/call_graph_extractor.ml`
   (ignore the field), new `lib/arch_tools/arch_exn.ml`, `bin/arch_query/arch_query.ml` (`raises`),
   new `tezt/tests/exn_raise_sets.ml` + `tezt/tests/main.ml`. Completion: US-1.1, 1.2, US-2.1
   green in tezt; `dune build` green; `must_null_ceiling`/`callgraph_soundness` unchanged.
2. **Slice B — closure edge cases.** Non-closing arms (any non-literal raise in RHS), catch-all,
   guards, `Tpat_or`/`Tpat_alias`, nested scopes (`parent_id`), `match … with exception`
   scrutinee-only, reraise origins forwarding. Completion: US-1.4, 1.5, 1.6, US-2.7, 2.8 green.
3. **Slice C — ⊤ propagation.** `MAY_TOP` edges, `ext:` leaves, fixed table,
   `--assume-externals-pure`, verdict vocabulary, `need_contract`/`need_known`/`NOT_ANALYSED`.
   Completion: US-2.2, 2.4, 2.5, 2.9, 2.10 green; AC-7 under `timeout`.
4. **Slice D — lambda attribution, assert, partial match.** Origins/scopes inside literals go to the
   lambda node; occurrence edge carries the parent scope; `Texp_assert`, `Partial` on `Texp_match`,
   `Tfunction_cases`, `fp_partial`; root `function` owner. Completion: US-1.3, 1.7, US-2.6 green.
5. **Slice E — canonical paths across units + rebinds + shadowed `%raise`.** Register
   `Tstr_exception`/`Tstr_typext`/`Tstr_module` idents during the structure walk; `local:` rule;
   `exn_rebinds` + query canonicalisation; two-library fixture. Completion: US-1.8, 1.9, 1.10 green.
6. **Slice F — `raisers-of`, `exn-stats`, Flat/pre-feature refusal.** Completion: US-3.1–3.4 green.
7. **Slice G — self-index golden + `arch-rules` + docs.** Regenerate
   `test/fixtures/self-index-stats.txt`; `docs/exception-raise-sets.md`; `docs/edge-kind-contract.md`
   pointer; roadmap 3.4 notes. Completion: CHECK-2 and CHECK-4 green.
8. **Slice H — proto_alpha measurement (QA/ship-gate).** Index `lib_protocol` to
   `/mnt/ssd-external-2to/arch-index-runs/proto-alpha-exn.db`; `exn-stats` ×2; 3 spot checks +
   `Main` entry points; transcript in the ship gate. Completion: CHECK-3 recorded; no contradiction.

## Dependencies

A precedes everything (schema + hook skeleton). B, C, D, E are independent of each other but all
need A; do them in B→C→D→E order so each red test is small. F needs C. G needs A–F (golden counts
depend on the final module). H needs G (measurement on the final binary).

## Consensus Table

| Point | Voice 1 | Voice 2 | Status |
|---|---|---|---|
| Vertical slices over fixture complexity, tests built incrementally | ✅ | (implicit) | AGREE |
| Dual bookkeeping between CFG `lhandlers` and the new scope stack drifts | ⚠️ (risk) | ⚠️ (#1) | AGREE — mitigation: single hook per site inside the same match arm; a unit test asserts scope depth = `lhandlers` depth at every `Texp_try` |
| Three id spaces (function/lambda/scope) across two passes | ⚠️ | ⚠️ (#2) | AGREE — fixed insertion order (below) |
| `last_insert_rowid` for call→scope links | ⚠️ | ⚠️ (#3) | AGREE — link inserted immediately after its call, same statement pair, inside the existing transaction; `exec_stmt_rowid` already guards a rejected step |
| Fixpoint cost at corpus scale | — | ⚠️ (#4) | AGREE — SCC-free worklist with per-node dirty flags; `exn-stats` prints wall-clock; H records it |
| Cross-unit canonical path is the riskiest rule | ⚠️ (MED/HIGH) | ⚠️ (#5, #6) | AGREE — Slice E has its own two-library fixture; proto_alpha spot check includes one cross-unit handler |
| Primitive-keyed raise on proto_alpha is hypothesis | ❓ | ⚠️ (#5) | RESOLVED — verified: `sigs/v15/pervasives.mli:30,33` declare `external raise/raise_notrace = "%raise"/"%raise_notrace"`; the environment's `failwith`/`invalid_arg` are plain vals → external ⊤ (sound) |
| Rowid-returning `insert_call` affects the Flat/LSP path | ⚠️ | — | RESOLVED — `call_graph_extractor.ml` does not call `insert_call`; the LSP path writes through `arch_load` |
| Corpus run as a separate checkpoint before docs are finalised | ❓ | — | ACCEPTED — Slice H is the QA step; docs in G may be amended by H's findings |

No DISAGREE, no USER-CHALLENGE.

## Identified risks

| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| Scope stack drifts from CFG try handling | M | H | one hook per site, depth assertion in a `let%test`, tezt over nested try |
| Canonical path mismatch across units (silent non-unification) | M | H | Slice E fixture with two libraries; proto_alpha cross-unit spot check |
| Wrong `function_id` for lambda-attributed rows | M | H | insertion order: parent row → walk → lambda rows → scope rows (by node) → origin rows → calls (later, with links) |
| Fixpoint slow on proto_alpha | M | M | worklist + dirty flags; time printed; if > 60 s record as residual, not a gate |
| Golden/ratchet regressions from hooks | L | H | run `callgraph_soundness`, `must_null_ceiling`, golden after Slice A before continuing |
| `Partial` origins flood `Match_failure` on idiomatic code | M | L | it is the truth; documented; `exn-stats` reports the count separately |
| Reraise detection misses indirect forwarding | L | H | non-closing rule is conservative (any non-literal raise in arm RHS) — errs toward not subtracting |

## Decisions made

| Point | Decision | Reason |
|---|---|---|
| Scope/origin ids | minted by `Arch_index_exn` per node as local ints; mapped to DB ids in `process_cmt` | keeps the walker's CFG ids untouched |
| `call_exn_scopes` link | inserted right after each `calls` insert via new `Arch_index_db.insert_call_rowid` | pairs rowid with its statement |
| Fixpoint | OCaml worklist in `Arch_tools.Arch_exn` loading `functions`, `calls`+links, scopes, origins, rebinds | set subtraction + ⊤ reasons don't fit SQL CTEs |
| Verdicts | `BOUNDED` / `UNBOUNDED (⊤)` / `BOUNDED_UNDER_HYP(externals_pure)` | spec C-17 |
| Environment `failwith` | not an origin; external ⊤ | non-Stdlib path; sound direction |

## Assumptions

- `Ident.persistent` is true for dune-mangled unit roots referenced across units (as it is for
  `Stdlib`) — the spec's canonical rule relies on it; Slice E's fixture is the check.
- The tezt harness can build a fixture with two dune libraries in one project (`with_fixture`
  takes arbitrary files; `multilang.ml` precedent) — verified reachable by reading `arch_tezt.ml`.
- The proto_alpha `.cmt` build at `1727d7e192f` stays available; the DB path on the SSD is writable
  (checked 2026-09-03).
