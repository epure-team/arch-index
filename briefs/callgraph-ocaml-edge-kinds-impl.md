# Implementation Brief — callgraph-ocaml-edge-kinds

**Date:** 2026-07-09
**Mode:** fast → escalated to phased (option 2: execution-sound redesign, test-first)
**Status:** PHASE 1 COMPLETE (baseline + regression suite); PHASE 2 pending (walker redesign)

## Goal

Make `arch-callgraph-ocaml` emit sound edge kinds + the ⊤-contract flag, and make
`arch-query`'s `reaches`/`unreachable`/`escapes` work on the main schema — with
**execution-sound MUST** semantics (a MUST edge means the call runs when the caller runs;
calls inside un-invoked nested bodies are not MUST).

## Target semantics (agreed)

A call site is a MUST edge of `F` only if it sits directly in `F`'s body, not inside a nested
function literal `F` does not invoke. Nested-closure calls count only when the closure is
invoked; passed/stored/returned closures link via MAY_ENUMERATED/MAY_TOP. Branches count both arms.

## Phase 1 (this commit) — landed

Edge-kind emission + the tractable soundness fixes + the regression suite that pins Phase 2:

| Area | Change |
|---|---|
| `architecture-schema.sql` | add `comment_db_meta` table |
| `arch_index_cmt.ml`/`.mli` | `call_kind_hint` variant; stamp-based local-fn resolution (`is_function_rhs` + `Ident.unique_name` set); MAY_TOP for params/closures/computed heads; callback-escape (MAY_ENUMERATED for named local callbacks, MAY_TOP for param/external) |
| `arch_index.ml` | INSERT `kind`; classify MUST/MAY_TOP/MAY_ENUMERATED; stamp `callgraph_contract=v1` only when >0 functions |
| `arch_index_db.ml`/`.mli` | `insert_call ~kind` |
| `call_graph_extractor.ml` | build the stamp set for the LSP path too |
| `arch-query` | id-based main-schema CTEs for `reaches`/`unreachable`/`escapes`; `unreachable` REFUSES unknown roots |
| `selftest-callgraph-ocaml.sh` | unqualified name fix + switch-pin + PART 2 assertions |
| `selftest-callgraph-soundness.sh` | **NEW** table-driven corpus; P1 (13, pass now) + P2 (redesign targets, xfail now) |
| `docs/edge-kind-contract.md` | Backends table (OCaml ⚠️ partial); honest in-progress note |
| CI, golden | gate both selftests; self-index 2455→2514 (MUST 2368 / MAY_ENUMERATED 2 / MAY_TOP 144 / 0 NULL) |

**Fixed & regression-locked (codex-verified across 3 rounds):** F1 param/shadow, F2 cross-module
id closure, F3 function-typed value, F4 empty/unknown-root refuse, HOF named-callback escape.

## Phase 2 (next) — the redesign

Flip the 5 `PHASE2` xfails green by modeling nested/lambda bodies as deferred and linking only
when invoked/passed:
1. Un-invoked nested body must not contribute enclosing MUST edges (`unused_closure`, `lam_map`).
2. Computed callback arg → MAY_TOP (`computed_map`).
3. First-class-module parameter call → MAY_TOP (`fcm_param`).
Blast radius: the walker is shared by the LSP path and the effects extractor — re-verify both.
On completion: run `STRICT=1 ./selftest-callgraph-soundness.sh`, regenerate golden, re-review (codex).

## Quality Gates (ENV: local `_opam` switch)

- [x] `dune build` ✅  [x] `dune test --force` ✅ (35)
- [x] 5 selftests + `selftest-callgraph-soundness.sh` (P1 green, P2 xfail) ✅
- [x] self-index golden matches ✅
