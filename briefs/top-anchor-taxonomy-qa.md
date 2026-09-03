# QA Report — top-anchor-taxonomy

**Date:** 2026-09-03
**Mode:** fast
**Verdict:** GO
**Round:** 1 / **Cycle:** 1

## Context read

- `briefs/top-anchor-taxonomy-review.json` — status GO, round 1, no OPEN findings (all fixed
  during review); reviewer's points of attention (Head_local/dropped_local precedence, top_anchor
  v1 scope, calls.resolution deferral) all addressed.
- `briefs/top-anchor-taxonomy-impl.md` — Fast mode, no `qa-scope.md`/`intake.md` (no plan phase);
  gate commands taken from the impl brief's own Quality Gates section.

## Deterministic quality gates

1. **Build** — `dune build --root . @all` (opam switch `arch-index`) → clean, zero warnings.
2. **Tests (full suite)** — `dune test --root . --force` → **111/111 passing**, exit 0. All 6
   `top_anchor_taxonomy.ml` tests independently re-ran and passed:
   `register_callback_param`, `register_module_param`,
   `register_resolved_edge_has_no_top_reason`, `register_global_invariant`,
   `register_kind_top_reason_pairing_constraint`, `register_check_constraint`. The 2 extended
   assertions in `dropped_node_dependents.ml` and 2 in `load.ml` also passed.
3. **Format/lint** — `dune build --root . @fmt` shows a pending formatting correction, but it is
   on `lib/arch_index/dune` (a dune-stanza wrapping style, not any file this task modified) and
   the identical drift class is independently reproducible against `origin/main` HEAD (`lib/arch_io/dune`,
   `poc/decision-lint/test/dune`, etc.) — pre-existing repo-wide drift, not introduced by this
   task. Not a QA blocker.
4. No project-specific gate beyond the above documented in the impl brief.

## Spec runnable checks

`specs/top-anchor-taxonomy.md` absent (Fast mode, no spec phase) — N/A.

## Code-intel invariant gate

No `kb/properties.md` code-intel block installed in this repo — `RESULT: skip`, no verdict impact.

## TUI check

N/A — no TUI scope in this task.

## Cross-runtime QA

`codex` breaker check (`scripts/xruntime-review.js codex --phase qa --check-availability --write`)
returned `status: "available"` (a fresh probe permitted post the review phase's `skipped-degraded`
verdict for that phase — QA tracks its own breaker state). Ran one independent QA pass via
`scripts/xruntime-exec.sh codex --write` in the `wt-topanchor` worktree at commit `617a00e`,
instructed to re-verify (not re-read) the build, full test suite, the HIGH review-finding fix
(`dropped_local` guard on `Head_local`'s unresolved branch), the new CHECK constraint's actual
presence and behavior, and the self-index golden fixture — reporting only discrepancies the
primary QA pass may have missed.

**Result:** codex independently re-ran the full suite (111/111), directly inspected the
`Head_local`/`dropped_local` fix in `arch_index_cmt.ml`/`.mli`, independently verified the
`CHECK(top_reason IS NULL OR kind = 'MAY_TOP')` constraint rejects a `MUST`-row insert via a live
in-memory SQLite probe, and independently regenerated the self-index database (fresh
`/tmp/codex-topanchor-self-617a00e.db`, cleaned up after) — confirming 21 modules / 576 functions /
3994 calls matches `test/fixtures/self-index-stats.txt` exactly. **Zero discrepancies reported.**
No block — no gate FAIL, no disputed claim.

## Verdict composition

- Causes this round: none (`causes: []`).
- `qa_no_go_round`: 0 (GO verdict resets/starts at 0).
- `rounds_audit`: one entry, round 1, verdict GO, `qualifying: false`.
- Gate (`check-qa-convergence.js`): exit 0, no violations.

## Summary

Independent fresh-fixture reverification confirms the implementation and all review-round fixes:
the ⊤-anchor taxonomy (`calls.top_reason`/`calls.top_anchor`) is correctly wired end-to-end —
`callback_param`/`module_param` decided structurally in the CMT walker, `dropped_node` correctly
overriding at classification time (including the review-round `dropped_local` guard fix),
the CHECK constraint enforcing both vocabulary and the MAY_TOP-pairing invariant, and
`bin/arch_load` accepting the full ten-value vocabulary. Self-index golden fixture regenerated and
verified twice independently (primary QA + cross-runtime codex) at 21 modules / 576 functions /
3994 calls. `must_null_ceiling` ratchet holds within its existing headroom against the new count.
No new findings. **GO — ready to ship.**
