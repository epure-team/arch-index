# Implementer sub-brief — reexport-resolution

**Status: VALIDATED**

## ⛔ Entry gate — read this first

**Do not start until `feat/qualified-unit-resolution` (roadmap 1.6) is merged into `main`.**
Verify: `git log --oneline origin/main | grep -i qualified-unit` returns the merge.

Reason: that branch rewrites the exact region you are splicing into (596 insertions / 40
deletions on `lib/arch_index/arch_index.ml`, hunk `@@ -773,23 +886,439 @@` covering
`resolve_qualified` and the `Head_qualified` match), **and** it supplies the multimap that
S2 requires (`unit_paths : (string, string list) Hashtbl.t`, exposed as `paths_of_unit`).
Starting earlier means rebasing onto a rewritten base and building a duplicate registry the
spec's C-14 already ruled out.

**Every line number below is a landmark, not an address.** Re-locate by symbol after the
merge. The sibling's ahead-count moved 15 → 29 → 30 within one afternoon.

## Goal

When qualified-name resolution fails for a call, consult the per-file module aliases already
recorded in `all_pending_deps` (`dep_kind = "alias"`) and retry the resolution once against
the alias target. Set `callee_id` only.

## Scope boundary

**IN:** `alias` rows; one hop; ambiguity decline; the dropped-target interaction; four
decline outcomes from one classifier; the retarget audit and 2×2 re-measurement.

**OUT:** `include` rows (deferred — the producer records only 840 of ~6370 recordable
because `module_path_of_expr` at `arch_index_cmt.ml:631-635` returns `None` for functor
applications; a separate task). **OUT:** `open` rows. **OUT:** `local_open`. **OUT:**
extending the corpus to the opam dependency closure. **OUT:** touching the shared
`resolve_qualified` used by non-aliased qualified calls.

## Steps

### S1 — one-hop chase (do this first, it is the whole vertical slice)

1. Build the alias index where `fn_lookup` / `mod_name_to_path` are built (`arch_index.ml`,
   near the old `:715`): `Hashtbl` keyed `(source_module, alias_name)` → `target_path`,
   from `all_pending_deps` filtered to `dep_kind = "alias"`, **first-insert-wins**.
   This index is not an optimisation. 615 118 unresolved qualified calls against 2811
   aliases is 1.7 × 10⁹ comparisons without it.
2. In the post-merge `Head_qualified` failure path, **after** the existing
   `dropped_qualified` check (D2/C-15): split the module name on `.`, look up the head
   component in the calling file's alias table, and if found retry resolution once against
   `target_path ^ rest`.
3. Set `callee_id`. Do **not** touch `kind`, `top_reason`, or `top_anchor` (D2 / FR-005).

**Fixtures (all three are required; the third is the one people skip):**
- two files, each `module S = <different target>`, each calling `S.f` → each resolves to its
  own target (CHECK-1);
- the same pair with file processing order reversed → identical result (US-3 scenario 1;
  this is what proves the `all_pending_deps` `List.rev_append` ordering actually holds
  rather than being inferred from a trace);
- one file where the alias is used from inside a nested submodule (US-3 scenario 2).

Red-verify by disabling the chase.

### S2 — ambiguity decline

Consume the sibling's `paths_of_unit` at **the chase's own final lookup only**. Do not wire
it into shared `resolve_qualified` — that would change resolution for calls this feature is
not supposed to touch and would fill S4's retarget diff with unattributable noise.

Fixture: two modules sharing a basename, an alias onto that basename → `callee_id IS NULL`
plus the ambiguity counter (CHECK-2). **Red-verify by making the chase pick the first
candidate greedily** — that reproduces the real defect the sibling's review caught
(`script_interpreter.ml:842` resolving to a same-basename test helper, stamped MUST).

### S3 — dropped-target interaction

Fixture where the final hop lands on a unit walked but whose cmt processing failed
(`record_dropped_unit` / `is_dropped_node`). Assert `MAY_TOP` / `dropped_node`, **not** a
no-candidate decline. Reversing this precedence silently turns a ⊤-frontier edge into a
clean external leaf.

### S4 — counters and ship gate

- **One priority-ordered classifier** returning exactly one of
  `Ambiguous | Dropped | No_candidate | Resolved`. Not four independent increments —
  CHECK-5's sum invariant must be structural. State the total order in a comment.
- Write counters to `comment_db_meta` **after** the producing transaction commits, never
  before (`arch_index.ml:1010-1020` is the comment that records why).
- Retarget audit: diff `calls.callee_id` before/after on both corpora, listing every changed
  target. A hard stop for human review, not an automated revert — the FK it may correct was
  already wrong under last-writer-wins.
- Full 2×2 golden re-measurement, then the `must_null_ceiling` / `clean_measured` ratchet,
  written only when A=B and C=D.

## Spec deviations you are authorised to make (decided in plan, do not re-litigate)

- **D4: 1 hop, not 4.** Only 6 of 2811 aliases have a target that itself declares aliases.
  Depth and cycle machinery would be untestable on the corpus and its counters would read
  zero on both corpora forever — this repo's own §10.6. Measure the residual after S1; add
  depth only if the residual justifies it.
- **D6: one classifier, four outcomes**, not four counters.

## Risks handed to you

- **Establish A=A before A=B.** `mod_name_to_path` is a `Hashtbl.replace` over an unordered
  `SELECT` (`arch_index.ml:722-729`), so the *baseline* may differ run to run independently
  of your change. Run the same binary twice first; a flaky A≠B is otherwise misdiagnosed as
  your regression.
- The intra-file chase model is **inferred**, not stated in the spec. S1's third fixture is
  what turns it into a pinned fact.

## Quality gates

- `eval $(opam env --switch=/home/mathias/dev/arch-index --set-switch)` then
  `dune build` and `dune runtest --force`. Never `dune exec tezt/tests/main.exe`.
- Every new CHECK red-verified before it is claimed green.
