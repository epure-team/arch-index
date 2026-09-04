# Plan — reexport-resolution

**Date:** 2026-09-04
**Status: VALIDATED**
**Gate: LIFTED 2026-09-04.** #67 (roadmap 1.6) merged; `main` is at `bfbabf5`, rebase-merge,
30 commits, linear. The gate below stood for roughly one hour. It is kept, not deleted,
because the reasoning is what carries forward — see §"The sequencing decision" and the
two corrections it since received.

**Two corrections from the 1.6 author, both accepted:**

1. **`mod_name_to_path` is no longer fed at `:722-729`.** That fill is dead since 1.6 —
   the resolver reads `paths_of_unit`, and the one remaining consumer (the module-dependency
   site) repopulates the table itself immediately before reading it. So the feasibility
   argument below is stale *for the resolver* and **exact for the site this task actually
   uses**: `module_deps` keeps the basename erasure. That is residual 4 of
   `docs/adr/003-qualified-unit-resolution-accepted-residuals.md`, and it is now a named
   accepted property rather than an incidental defect. It does not weaken the gate's
   conclusion; it relocates it, and makes it permanent rather than transitional.
2. **Consuming `paths_of_unit` has a rule attached, learned the hard way on 1.6's round 6:**
   *a unit key mapping to several paths is not a choice to make, it is an absence of proof.*
   The 1.6 resolver initially found a function row in exactly one candidate path and called
   that a resolution — emitting a MUST into a library the caller does not even link, where
   `main` had emitted an honest unresolved leaf. It was closed at zero corpus cost by
   treating the case as ⊤ (`ambiguous_unit`). **D3 adopts this verbatim.**

## The sequencing decision

The spec's C-16 recorded the sibling branch as a *semantic* non-conflict — this task is a
fallback tier that only runs after the existing resolver fails, so it cannot contradict a
better resolver. That reasoning is correct and it is not sufficient. Two independent
analyses in this phase converged on the same conclusion from opposite ends:

- **Voice 2 (merge order).** `git diff origin/main...origin/feat/qualified-unit-resolution`
  on `lib/arch_index/arch_index.ml` is 596 insertions / 40 deletions, with a hunk at
  `@@ -773,23 +886,439 @@` that **replaces the whole `resolve_qualified` / `Head_qualified`
  region** — precisely where this task's fallback splices in. C-16 treated a merge-order
  collision as a documentation problem.
- **Voice 1 (feasibility).** D3 ("two or more distinct resolved ids ⇒ decline") cannot be
  built on `mod_name_to_path`, which is a `Hashtbl.replace` over an unordered `SELECT`
  (`lib/arch_index/arch_index.ml:722-729`): **one path per basename, last-writer-wins, by
  construction.** It has already discarded every candidate but one before any chase code
  runs. D3 needs a *set*; this table structurally cannot produce one.

The two findings resolve each other. The sibling branch's `unit_paths` registry is
`(string, string list) Hashtbl.t` keyed on `cmt_modname` — a **multimap**, exposed as
`paths_of_unit`. That is exactly the structure D3 requires. So:

- Starting before the merge means building a second, throwaway multi-valued registry —
  which is the one thing the spec's own residual C-14 says not to do.
- Starting after the merge means D3 is a consumer of an existing, reviewed API.

**Decision: wait.** The cost of waiting is delay. The cost of not waiting is a rewritten
merge base plus a duplicate registry we have already decided not to build.

*Outcome: the wait cost about an hour and the merge landed with a clean base, 143/143
tezt, a byte-identical self-index golden, and five explicitly-accepted residuals
documented in an ADR — including the one this task inherits.*

**The ahead-count is moving, not merely stale.** The research brief said 15; this phase
measured 29, then 30 twenty minutes later. Re-measure before acting on any figure here.

## Sequential steps

Numbering starts at S1; there is no "S0 spike" because the sibling's registry answers the
question a spike would have asked.

1. **S1 — one-hop alias chase, wired end to end.**
   Build a per-file alias index at the point `fn_lookup` / `mod_name_to_path` are built
   (`arch_index.ml:~715`): `Hashtbl` keyed `(source_module, alias_name)`, populated from
   `all_pending_deps` filtered to `dep_kind = "alias"`, first-insert-wins (US-3 scenario 1).
   Splice one lookup into the post-merge `Head_qualified` failure path, strictly after the
   existing `dropped_qualified` check (D2/C-15). Sets `callee_id` only; `kind`, `top_reason`,
   `top_anchor` untouched. **Completion criterion:** two fixture files each declaring
   `module S = <different target>` and calling `S.f` each resolve to their own target
   (CHECK-1), and a third fixture proves file-processing order does not change the result.
   Red-verified by disabling the chase.

2. **S2 — ambiguity decline at the chase's final leaf.**
   Consume the sibling's `paths_of_unit` multimap at the chase's own final lookup **only** —
   not inside the shared `resolve_qualified`, so resolution of non-aliased qualified calls is
   untouched and S4's retarget diff stays free of unrelated noise. **Completion criterion:**
   CHECK-2 — two modules sharing a basename, an alias onto that basename, `callee_id IS NULL`
   and the ambiguity counter incremented; red-verified by making the chase pick the first
   candidate greedily. That greedy behaviour is the exact defect the sibling's own review
   caught in production (`script_interpreter.ml:842` resolving to a same-basename test
   helper, stamped MUST), so the red run reproduces a real bug, not a hypothetical.

3. **S3 — dropped-target interaction.**
   A fixture where the chase's final hop lands on a unit that was walked but whose cmt
   processing failed (`record_dropped_unit` / `is_dropped_node`). **Completion criterion:**
   the edge is `MAY_TOP` / `dropped_node`, not a clean no-candidate decline. Getting this
   precedence backwards silently reclassifies a ⊤-frontier edge as a resolved external
   leaf — the soundness bug class this file already carries three comments about.
   Independent of S2; depends only on S1.

4. **S4 — decline counters, then the ship gate.**
   Counters threaded through the chase and written to `comment_db_meta` **after** the
   producing transaction commits, never before (the lesson `error_contract` cost us at
   `arch_index.ml:1010-1020`). Then the retarget audit and the full 2×2 golden
   re-measurement on both corpora, and the `must_null_ceiling` / `clean_measured` ratchet
   update, written only when A=B and C=D.

## Dependencies

- **Everything depends on `feat/qualified-unit-resolution` being merged.** S1's splice point
  and S2's multimap both live in the region that branch rewrites.
- S2 and S3 both depend on S1. They are independent of each other.
- S4 depends on S1–S3, because the counter partition is only complete once every decline
  path exists.

## Decisions made

| Point | Decision | Reason |
|---|---|---|
| Merge order vs. the sibling branch | **Wait for 1.6 to merge.** Recorded as a gate on this plan, not a note. | The sibling replaces the 439-line region this task splices into, and supplies the multimap D3 needs. Both reasons point the same way. |
| D4 chase depth | **Reduce 4 hops → 1 hop (S1).** Add depth only if the residual justifies it. | Measured: of 2811 alias rows on the whole `src` tree, **6** have a target that is itself a file declaring aliases. A 4-hop machine with cycle detection and a depth counter is built for 6 potential cases and is untestable on the corpus — its counters would report zero on both corpora forever. That is this repo's own §10.6, "a check that looks like a check", which we wrote today and which the spec then violated. |
| D3 ambiguity registry | **Consume the sibling's `paths_of_unit`. Do not build a second registry.** | `mod_name_to_path` is last-writer-wins by construction and cannot express a candidate set; C-14 already decided against a duplicate. |
| Decline counters (D6) | **One priority-ordered classifier returning exactly one bucket**, not four independent increments. | CHECK-5's sum invariant is only meaningful if the buckets partition. Four independent counters make the invariant hold by accident or not at all. |
| Alias lookup structure | **`Hashtbl` on `(source_module, alias_name)`, mandatory, in S1.** | 615 118 unresolved qualified calls × 2811 aliases = 1.7 × 10⁹ comparisons for a naive scan. Not an optimisation; a feasibility condition. |
| Ambiguity scope | Chase's final lookup only, never shared `resolve_qualified`. | Keeps S4's retarget diff attributable to this feature. |

## Identified risks

| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| The sibling branch keeps moving; this plan's line numbers rot | **Certain** (15→29→30 observed) | Medium | Every line reference here is a landmark, not an address. Re-locate by symbol after the merge; do not trust a number in this file. |
| `mod_name_to_path`'s last-writer-wins makes the **baseline** non-deterministic, so a flaky A≠B in S4's 2×2 is misread as a regression this feature caused | Medium | High — a false NO-GO, or worse a false GO | Establish A=A (same binary, twice) before comparing A=B. Voice 1 raised this; it is not addressed anywhere in the spec. |
| Counter precedence is decided by `match`-arm order rather than a stated rule (only 2 of 6 pairwise orderings are pinned) | High | Medium | The single-classifier decision above makes precedence explicit by construction; S4 must state the total order in a comment. |
| The intra-file chase model is inferred, not stated | Medium | High — S1's fixtures would be wrong | D4's key shape `(source_module, target_path)` with `source_module` constant only makes sense intra-file. S1 must assert this with a fixture rather than inherit the inference. |
| `all_pending_deps` double-reversal breaks first-wins ordering | Medium | Medium | `List.rev_append` appears at both the per-file accumulation and the merge (`arch_index.ml:594`). S1 asserts the order with a fixture; do not trust the trace. |

## Assumptions

- The chase is **intra-file**: every hop re-looks-up aliases in the referencing file's own
  table. Inferred from D4's key shape and D1's "declared in the referencing file"; the spec
  never states it. S1 pins it with a fixture.
- `caller_module` for a nested submodule's functions equals the enclosing file's `rel_path`,
  same as `pending_dep.source_module`, so no separate handling is needed for US-3 scenario 2.
  Confirmed at one call site (`arch_index_cmt.ml:2773`), not exhaustively.
- The sibling's `paths_of_unit` survives its review with a multi-valued signature. If review
  collapses it to a single path, S2 is blocked again and the D3/C-14 tension returns.

## Spec amendments this plan requires

These are corrections to `specs/reexport-resolution.md`, recorded here rather than silently
implemented differently:

- **D4** — "bounded depth 4, inclusive" → **1 hop**, with the residual measured before any
  depth is added. Cycle detection becomes unreachable and is therefore not built.
- **D6** — four counters → one priority-ordered classifier with four outcomes.
- **CHECK-5** — restated so its sum invariant is structural (guaranteed by the classifier)
  rather than an accidental property of four independent increments.
- **C-16** — amended: the collision with the sibling branch is a *merge-order* decision, now
  taken (wait), not a documentation note.

## Consensus Table

| Point | Voice 1 (architect) | Voice 2 (skeptic) | Status |
|---|---|---|---|
| Merge-order collision with the sibling branch | not raised | ⚠️ decisive — 439-line hunk replaces the splice region | **AGREE after verification** — I checked it; confirmed, and it drives the gate |
| D3 buildable on current machinery | ⚠️ decisive — `mod_name_to_path` is last-writer-wins, cannot express a set | not raised | **AGREE after verification** — confirmed at `arch_index.ml:722-729` |
| D4's 4-hop depth | risk: untested recursion | ⚠️ dead code, counters report zero forever | **AGREE** → reduced to 1 hop |
| Per-file alias lookup structure unspecified | assumption 2 flags the ordering | ⚠️ `all_pending_deps` has no index | **AGREE** → mandatory `Hashtbl` in S1 |
| Decline counters partition | ⚠️ 4 of 6 precedences unspecified | ⚠️ not a partition, sum invariant accidental | **AGREE** → single classifier |
| Baseline non-determinism poisoning the 2×2 | ⚠️ raised | not raised | **AGREE** — added to risks; unaddressed in the spec |
| Whether to start now | Step 0 spike, then decide | block on the sibling | **AGREE** → wait; the spike's question is already answered by `paths_of_unit` |

No DISAGREE items. No USER-CHALLENGE: both voices object to *how* the spec sequences and
sizes the work, neither objects to the goal, so nothing here overrides the human's direction.
