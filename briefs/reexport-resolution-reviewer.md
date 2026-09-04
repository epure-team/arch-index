# Reviewer sub-brief — reexport-resolution

**Status: VALIDATED**

## What was implemented

A fallback tier in the call resolver: when qualified-name resolution fails, the per-file
module aliases already in `all_pending_deps` (`dep_kind = "alias"`) are consulted and the
resolution retried once. Sets `callee_id` only; `kind` / `top_reason` / `top_anchor` are
untouched.

## Check the entry gate first

This work was **gated on `feat/qualified-unit-resolution` being merged**. If the diff was
produced against a base that predates that merge, stop — it splices into a region that
branch rewrites wholesale, and S2 depends on `paths_of_unit`, which only exists after it.

## Files to audit, in order

1. `lib/arch_index/arch_index.ml` — the alias index construction (near where `fn_lookup` /
   `mod_name_to_path` are built) and the splice into the `Head_qualified` failure path.
2. The new/changed tezt fixtures.
3. `tezt/tests/must_null_ceiling.ml` — the ratchet.

## Risks to verify, not to take on trust

- **The splice sits after the `dropped_qualified` check.** If it runs before, an edge whose
  target was dropped gets a clean `callee_id` instead of `MAY_TOP` / `dropped_node` — a
  ⊤-frontier edge silently reclassified as a resolved external leaf. Read the order; do not
  infer it from a passing test.
- **`kind` is genuinely untouched.** Confirm by reading the assignment, not by observing that
  a count did not move.
- **Ambiguity is scoped to the chase's own final lookup.** If it was wired into the shared
  `resolve_qualified`, resolution changed for calls outside this feature's scope and the
  retarget audit is not attributable.
- **The four decline outcomes come from one classifier**, so CHECK-5's sum invariant holds by
  construction. Four independent increments make it hold by accident — reject that shape.
- **Every new CHECK was red-verified.** Ask for the red run. A check whose counters can only
  ever read zero is not a check (§10.6); this spec previously carried exactly that defect in
  its 4-hop depth machinery, which is why the plan cut it to 1 hop.
- **A=A was established before A=B.** `mod_name_to_path` is last-writer-wins over an
  unordered `SELECT`, so the baseline itself can vary between runs. If the implementer
  reported a 2×2 without first running the same binary twice, the comparison is unsound in
  both directions.

## Expected behaviours to confirm

- Two files aliasing the same name to different targets each resolve to their own target.
- Reversing file processing order changes nothing.
- An alias used from inside a nested submodule resolves.
- A basename collision at the alias target leaves `callee_id IS NULL` and increments the
  ambiguity counter — it does **not** pick a candidate.
- Resolved + the four decline outcomes sums to the total fallback attempts, on both corpora.
