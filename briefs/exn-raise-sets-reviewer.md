# Reviewer sub-brief — exn-raise-sets

**Status: VALIDATED**
**Normative sources:** `specs/exn-raise-sets.md` (FR/AC), `briefs/exn-raise-sets-plan.md`.
**Gate:** soundness (roadmap): a may-raise set that omits something the code can raise, or an
edge closed by a handler that does not actually catch it, is a CRITICAL.

## What was implemented (expected)

Producer: `lib/arch_index/arch_index_exn.ml/.mli` + hooks in `arch_index_cmt.ml` (pending_call
field, `lctx.lexn`, `Texp_try`/`Texp_match`/`Texp_assert`/`Texp_apply`/`walk_function_root`,
`process_cmt` inserts, structure-walk registration), `arch_index.ml` (statements, call→scope link,
`exn_contract`), `arch_index_db.ml` (`insert_call_rowid`), schema tables. Query:
`lib/arch_tools/arch_exn.ml`, `arch_query.ml` (`raises`, `raisers-of`, `exn-stats`,
`--assume-externals-pure`). Tests: `tezt/tests/exn_raise_sets.ml`. Docs + golden.

## Audit first (in this order)

1. `arch_index_exn.ml` `arm_is_closing` and `classify_arms` — the soundness core. Verify: guarded
   arms never close; any raise of a non-literal anywhere in the arm RHS makes the arm non-closing
   (including inside nested `match`/`let`/lambda in the RHS); `Tpat_or` unions; `Tpat_alias`
   recurses; `Tpat_var`/`Tpat_any` = catch-all only when closing.
2. Hook placement in `arch_index_cmt.ml`: the `try` scope must wrap exactly `body` (not the
   handlers); the `match_exception` scope exactly the scrutinee; scopes must be per-context
   (`lctx`), so a lambda literal inside a try body gets a fresh empty stack while its occurrence
   edge (emitted in the parent context) carries the parent scope. Check balanced enter/leave on
   every exit path (exceptions in the walk).
3. Id mapping in `process_cmt`: scopes inserted parent-before-child; origins reference mapped ids;
   pending calls' `exn_scope` rewritten for lambda nodes too (keyed by node name); a rejected
   function/lambda row (`None` from `insert_function`) must drop its exn rows — not attach them to
   another id.
4. `arch_index.ml` link insertion: `insert_call_rowid` result `None` ⇒ no link row; the link uses
   the rowid of *that* call (no intervening insert).
5. `Arch_exn.close`: catch-all ⇒ ∅ including ⊤; constructor set never closes ⊤; chain walks
   `parent_id` to the root; `--assume-externals-pure` clears only `External` reasons.
6. Fixpoint: monotone join; predecessors re-queued on change; deterministic output order; no
   quadratic re-scan.
7. `NOT_ANALYSED` refusal precedes any query on Flat/pre-feature DBs; `need_contract`/`need_known`
   semantics identical to `unreachable`.
8. Schema diff: only additive `IF NOT EXISTS`; `schema_version` write sites and
   `lib/arch_index/runner.ml` untouched (CHECK-4).
9. Existing ratchets unchanged: `tezt/tests/callgraph_soundness.ml`, `must_null_ceiling.ml`,
   `nested_module_qualification.ml`; golden regenerated with a commit message stating the reason.

## Risks to verify

- Canonical path agreement across units (US-1.9): inspect the two rows in the fixture DB by hand.
- `%raise` primitive keying (US-1.10) and that a non-Stdlib `failwith` is *not* an origin.
- Root `function` partial-match origin attributed to the top-level node, not a lambda (US-1.7).
- `match … with exception` scope does not cover value-arm RHS (US-1.6 / US-2.8).
- Reraise origins forward the scope's caught set and do not double-count.
- Lambda inside try: US-1.3 / US-2.6 both outcomes (⊤ external without flag; closed with flag).

## Expected behaviours to confirm

All spec scenarios US-1.1–1.10, US-2.1–2.10, US-3.1–3.4 via the tezt; CHECK-2 green; the
implementer's ship-gate draft lists the proto_alpha step as pending QA (not claimed done).
