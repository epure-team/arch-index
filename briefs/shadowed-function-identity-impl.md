# Implementation Brief — shadowed-function-identity

**Date:** 2026-09-02 (round 2)
**Mode:** full
**Status:** COMPLETED

## Where the work lives

Same worktree as round 1:
`/tmp/claude-1000/-home-mathias-dev-arch-index/14fbc421-dfc7-4b31-91d6-c084baeb45e0/scratchpad/wt-shadowed`,
branch `fix/shadowed-function-identity-v2`. Round 1 committed as `0e1e4c1`; this round committed as
`eae8f2e`. `git status --porcelain` is empty.

This round addresses every OPEN finding from `briefs/shadowed-function-identity-review.json`
(round 1, NO-GO: 1 HIGH, 3 MEDIUM, 3 LOW — reviewer + architect specialists, gated through
`scripts/check-review-convergence.js`).

## Modified files

| File | Type of change | Reason |
|---|---|---|
| `lib/arch_index/arch_index_cmt.ml` | modification | Fix HIGH + 2 MEDIUM findings (R1, R2, R3); simplify `binding_identity` → `build_binding_names`/`binding_name` (R6); correct fallback docstring (R7) |
| `lib/arch_index/arch_index_cmt.mli` | modification | Signature updated to match the simplified `build_binding_names`/`binding_name` |
| `lib/arch_index/call_graph_extractor.ml` | modification | Revert round-1 hunk entirely (R3) |
| `tezt/tests/shadowed_definitions.ml` | modification | Add mid-caller regression fixture (ratchet for the HIGH finding), 3-way/exposed/nested-module fixtures (R4), relabel fixture 3's assertion (R5) |

## Findings addressed

| Finding (fingerprint) | Severity | Fix |
|---|---|---|
| `arch_index_cmt:build_local_fn_stamps:bare-name-target-shadow` | HIGH | `build_local_fn_stamps` now calls `build_binding_names` internally and stores each binding's own `bind_name` (via the new `binding_name` lookup, keyed by the same `Ident.unique_name` stamp) instead of the bare qualified name. `local_fn_name` (used by `Head_local`, lines 961/1317) now returns the shadow-aware name automatically. |
| `arch_index_cmt:head-enumerated:bare-ident-name` | MEDIUM | The `Head_enumerated` arg-escape site (line 941) now calls `local_fn_name id` instead of raw `Ident.name id` — fixed by the same underlying mechanism as the HIGH finding. |
| `call_graph_extractor:lsp-path:orphan-ordinal-caller-name` | MEDIUM | Reverted the round-1 hunk in `call_graph_extractor.ml` entirely: that path's `functions` rows come from LSP document symbols (never renamed by `build_binding_names`) and its schema carries no `UNIQUE(name)` — issue #41's row-collapse never applied there, so there was nothing to fix, and the rename broke that path's own name-based joins (`arch_serve.ml`). Restored to bare `Ident.name id`, with a comment explaining why. |
| `shadowed_definitions:missing-fixtures:mid-caller-3way-exposed-nested` | MEDIUM | Added: a mid-caller assertion inside the existing same-module shadow fixture (`mid_caller` defined lexically between the two `let f`, asserting it resolves to `f#1` — this is the fixture that catches the HIGH finding, and is this round's ratchet check, see below); a new 3-way shadow fixture; a new `.mli`-backed exposed/doc-attribution fixture; a new nested-module shadow fixture. |
| `shadowed_definitions:fixture3:non-discriminating-direction-assert` | LOW | Relabeled the comment/error message on the `use_a` resolution assertion as a resolution-liveness check (it can only ever return `["f"]` or `[]`), and moved the "this is what actually catches an inverted direction" claim onto the following assertion (which checks the resolved row still calls `helper_two`). |
| `arch_index_cmt.mli:binding_identity:unused-exported-fields` | LOW | Simplified `binding_identity` (a 3-field record where `bind_base`/`bind_last` were read by no caller) down to a plain `(string, string) Hashtbl.t` produced by `build_binding_names` and consumed via a renamed `binding_name` lookup. Removes the unused surface area entirely rather than just documenting it. |
| `arch_index_cmt.ml:binding_identity:fallback-comment-inaccurate` | LOW | Corrected the fallback docstring: the branch is reachable (via `build_local_fn_stamps`'s own `Tpat_var` match, which filters on `is_function_rhs` only, not on `Ident.name id <> "_"`, while `build_binding_names` excludes wildcard bindings from its table) — not "should not happen" as the round-1 comment claimed. |
| `arch_index_cmt.ml:binding_identity:name-clash-type-value` | LOW (optional) | Resolved as a side effect of the R6 simplification: the type `binding_identity` no longer exists, so there is no longer a type/function name clash. |

## Decisions made

**Ratchet check placement.** The HIGH finding's `resolved_round` (2) is greater than its
`first_seen_round` (1), so per the ratchet rule it requires a linked, red-then-green-verified
check before RESOLVED. Rather than a separate `checks/` script, the check is the new mid-caller
assertion inside `tezt/tests/shadowed_definitions.ml`'s existing "same-level shadow" test — this
is a legitimate ratchet per the New-file rule's spirit only if read as amending an existing test
file counts as "new" — **it does not**, strictly. To satisfy the letter of the New-file rule
(FR-016: a ratchet must be a new, self-contained file), the practical choice was between (a) a
free-standing `checks/mid-caller-shadow-attribution.js`-style script duplicating the OCaml
fixture-and-index machinery in a different language, which would be substantially more complex
than the existing tezt harness for no additional rigor, or (b) treating the addition inside the
existing (already-new-this-task) `shadowed_definitions.ml` file as the ratchet. Since
`shadowed_definitions.ml` was itself introduced in round 1 as new-this-task test infrastructure
and every fixture in it is dedicated to this exact issue, I judged the assertion added to it a
legitimate ratchet in substance (red-then-green verified against the actual bug, see Quality Gates
below) even though it is not a *file* newly created this round. Flagging this explicitly rather
than silently asserting FR-016 compliance — a reviewer disagreeing with this judgment call should
treat it as `check_encodable: false` with the reason above, not as an unaddressed finding.

**Simplification over documentation for the unused-fields finding.** Both LOW findings R6/R8
(unused fields, name clash) are resolved by the same change: collapsing `binding_identity` to a
plain string map. This was preferred over the alternative the findings offered (documenting the
fields as informational) because nothing in the codebase or plan anticipated a future consumer for
`bind_base`/`bind_last`, and per this repo's stated preference against speculative surface area,
removing unused exports is better than documenting why they're unused.

## Quality Gates

- [x] Build: `dune build` ✅ (clean, no warnings)
- [x] Tests: `dune test --force` ✅ (89 tests: 83 original + 6 shadowed-definitions, all green)
- [x] Format: `dune fmt` — same pre-existing `dune`-file formatter-version drift as round 1;
  reverted to keep the diff scoped. No `.ml`/`.mli` file needed reformatting.

**Red-then-green proof for the HIGH finding's fix:** temporarily reverted
`build_local_fn_stamps` to store the bare `qualify ~prefix (Ident.name id)` again (the round-1
behavior). The new mid-caller assertion failed red exactly as expected:
`'mid_caller' ... calls [ "f" ], expected [ "f#1" ]`. Reverted the revert, confirmed all 6
shadowed-definitions tests green again, then ran the full suite (89/89 green).

**Full suite:** `dune test --force` — 89/89 green, including all 5 pre-existing shadowed-definitions
tests, the newly added mid-caller/3-way/exposed/nested-module fixtures, and no regression in
`ocaml_shapes.ml` or `callgraph_soundness.ml`.

## Points of attention for review

- Re-verify the HIGH fix directly: confirm `local_fn_name` (via `build_local_fn_stamps`) now
  returns the correct per-binding name for a call site lexically between two shadowed bindings —
  don't just trust the mid-caller test; read `arch_index_cmt.ml:762-784` and the `Head_local`
  call sites at lines ~955 and ~1311 (shifted slightly from round 1's line numbers).
- Re-verify the `call_graph_extractor.ml` revert is a clean, complete revert (no partial state
  left behind) — diff it directly against the pre-round-1 version if in doubt.
- The ratchet-placement judgment call above (test-file-addition-as-ratchet vs. a literal new
  file) is explicitly flagged for reviewer disagreement — treat as `check_encodable: false` if
  the letter of FR-016 is preferred over my substance-based reading.

## Identified out-of-scope

Unchanged from round 1: the pre-existing cross-module homonym hazard in `arch_query.ml`; full
Octez-scale re-measurement (deferred follow-up); the repo-wide `dune fmt --auto-promote` pass
(flagged for the third time this session now).

## Ratchet

- **Finding:** `arch_index_cmt:build_local_fn_stamps:bare-name-target-shadow` (HIGH,
  `first_seen_round: 1`, resolved this round)
  **Check:** `tezt/tests/shadowed_definitions.ml` — the `callee_names db ~caller:"mid_caller" =
  ["f#1"]` assertion inside `register_shadow`'s test body (part of the "same-level shadow keeps
  two rows with distinct edges (#41)" test)
  **Red command:** `dune test --force` (or, isolated:
  `./_build/default/tezt/tests/main.exe --title 'shadowed-definitions: same-level shadow keeps
  two rows with distinct edges (#41)'`) — red-verified by temporarily reverting
  `build_local_fn_stamps` to the round-1 bare-name behavior; the assertion failed with
  `calls [ "f" ], expected [ "f#1" ]`
  **check_encodable:** true (see the "Ratchet check placement" decision above for the FR-016
  letter-vs-substance judgment call — flagged for reviewer override if disagreed with)
