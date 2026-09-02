# Reviewer Brief — shadowed-function-identity

**Date:** 2026-09-02
**Status: VALIDATED**

## What was implemented

A fix for GitHub issue #41 / roadmap item 0.6: same-level shadowing (two top-level bindings of the
same name in one `.ml` compilation unit) previously produced only one `functions` row
(`INSERT OR REPLACE` on `UNIQUE(module_id, name)` silently dropped the earlier definition and its
call edges got misattributed onto the survivor). The fix assigns each same-level binding a
distinct row identity via a `#N` ordinal suffix, with the **last** (source-order-final) binding
keeping the bare name and every earlier (shadowed) binding taking the suffix — mirroring
`lambda_name`'s existing ordinal precedent.

## Critical thing to verify first — ordinal direction

This is the single highest-risk aspect of this change. Confirm explicitly, by reading the code
(not by trusting the PR description):

1. In `lib/arch_index/arch_index_cmt.ml`, find where a binding's row name is chosen
   (`bid.bind_name` or equivalent). Confirm the **last** binding at a colliding position gets the
   bare name, and earlier ones get `#N`. If it's inverted, this is a **blocking** finding — an
   inverted direction reproduces issue #41's bug on the cross-module axis (a caller in another
   module referencing `M.f` by its only possible spelling — the bare name — would resolve onto the
   dead/shadowed definition instead of the live one).
2. Confirm this by cross-referencing `lib/arch_index/arch_index.ml:355-372` (`resolve_qualified`)
   — it resolves cross-module calls by exact `(mod_path, name)` match with no ordinal awareness.
   The bare name in `fn_lookup` MUST correspond to the definition external callers can actually
   reach.
3. Confirm the new cross-module test fixture (see below) actually asserts this — not just that
   two rows exist, but that a qualified call from another module lands on the *live* definition's
   edges.

## Files to audit first

- `lib/arch_index/arch_index_cmt.ml` — `binding_identity`/`build_binding_names`, the row-write
  site, and the interaction with `2a0a771` (wildcard-binding fix) and the `insert_function`
  return-value fix — confirm these weren't silently reverted or bypassed by the rebase.
- `lib/arch_index/arch_index_cmt.mli` — signature matches what `call_graph_extractor.ml` expects.
- `lib/arch_index/call_graph_extractor.ml` — confirm it also calls `build_binding_names` and
  produces identity-consistent naming with the main indexer for the same shadowed-binding case.
- `lib/arch_index/arch_index.ml` — confirm `fn_lookup`/`resolve_local`/`resolve_qualified` were
  NOT modified to add ordinal-awareness (they shouldn't need to be — the ordinal is baked into the
  row's `name` column itself, and lookups are still plain string matches). If they were modified,
  understand why and verify it's not compensating for a direction error elsewhere.
- `tezt/tests/shadowed_definitions.ml` — three fixtures expected: same-module "shadow" (asserts
  both rows exist, each keeps its own outbound edges, live one has the bare name), "clean"
  (no-collision case, byte-identical-to-before behavior), and cross-module (asserts an external
  qualified caller resolves to the live definition, not the shadowed one).

## Risks to verify

- **Ratchet strength**: the test must prove "two rows exist AND each keeps its own edges," not
  merely "no statement failures" — the latter is already covered by the unrelated, already-merged
  `statement_failures` gate from #37. Read the actual assertions in the new test file; don't take
  "tests pass" as sufficient.
- **`exposed`/doc-comment attribution**: confirm it's still gated on "last binding" (the live one),
  matching the corrected name-direction — a mismatch here (e.g. `exposed` computed from `bind_last`
  but name computed from `bind_last`'s old inverted sense) would silently break doc-comment
  attribution for shadowed functions even if the row-identity fix itself is correct.
- **`Tstr_include` handling**: confirm no special-case code was added for this — it should already
  work for free via `iter_structure_items`'s existing descent into `Tstr_include`. Extra code here
  would be unnecessary complexity, not a bug per se, but flag it if present.
- **No test added for `let rec f = e1 and f = e2`** — this is expected and correct (rejected by
  the type-checker, cannot occur in valid `.cmt` input). Do not flag its absence as a gap.
- **Scope creep check**: confirm the cross-module homonym hazard in `bin/arch_query/arch_query.ml`
  was NOT touched — that's explicitly out of scope and any change there is a scope violation.
- **`INSERT OR REPLACE` semantics**: confirm `functions` still uses `INSERT OR REPLACE` — this fix
  works by making colliding names non-colliding via the ordinal, not by changing the insert
  strategy. A change to the insert strategy itself would be a scope violation.

## Expected behaviors to confirm

- Two same-level same-name top-level bindings in one unit now produce two `functions` rows.
- Each row's outbound calls resolve to that specific binding's own callees, not the other's.
- The last-bound definition's row has the bare name; the earlier one(s) have `#N` suffixes.
- A qualified call from another module (`B` calling `A.f`) resolves onto the last-bound
  definition's edges.
- `dune build`, `dune test --force`, `dune fmt` all pass clean.
- No regression in the existing `ocaml_shapes.ml` (toplevel-vs-nested-module homonym) or
  `callgraph_soundness.ml` (stamp-level shadowing) tests — these are adjacent but distinct cases
  and must remain green.
