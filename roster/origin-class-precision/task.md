# Task — origin-class-precision

Stop recording an exception origin that the typed tree already proves impossible.

## Defect 1 — an asymmetry inside one function

`lib/arch_index/arch_index_exn.ml:408-424` classifies three primitive classes, with
the call's `args` in scope for all three:

- **`P_compare` refines.** `let unsafe = List.exists (fun (_, a) -> not
  (closure_free a.exp_type)) args in if unsafe then add acc Compare (Some
  "Invalid_argument") …` — the origin is recorded **only** when an argument's type
  could hold a closure. Comparison on a closure-free ground type cannot raise, so
  nothing is recorded. This already ships and is the correct discipline.
- **`P_division` records unconditionally**, although the divisor is right there in
  `args`.
- **`P_index` records unconditionally**, same.

## Defect 2 — information computed, then discarded

`lib/arch_index/arch_index_cmt.ml:1658-1668` matches `Texp_assert (e, _)` and then
inspects `e.exp_desc` for `Texp_construct (_, {cstr_name = "false"; _}, _)` to decide
whether the block **diverges** (`assert false` is never elided by `-noassert`). But
`Arch_index_exn.record_assert` is called on the line **before** that match, with no
discriminator — so unconditional divergence and a checked invariant are both
`form='assert'` and indistinguishable downstream.

## Measured context

proto_alpha, 14452 nodes. 190 `lib_protocol` functions carry a named exception
origin; 651 more in test code. Protocol-code forms: `assert` 137, `division` 72,
`index` 23, `compare` 3, `raise` 2.

The protocol has only **6 `try` sites** and 5 `match … with exception` in all of
`lib_protocol`, so `escaping_origins = 1219 = origins` — every origin escapes and
there is **no handler layer**. The signal-to-noise problem on the only actionable
artefact is therefore entirely the producer's own over-approximation, not handler
noise.

Sampled by hand: a substantial fraction of division sites divide by a literal
(`Int64.div amount 1000L` in `tez_repr.pp`, `v / 10`, `v / 100`). **No ratio is given
deliberately** — the ad-hoc literal/variable regex used to sample was *wrong* on the
prefix form `Int64.div (…) 10L`, which is precisely why this belongs in the producer
rather than in a human's grep.

## Soundness framing

Removing an origin **narrows** a reported set — the unsafe direction if the reasoning
is wrong. `P_compare` is the precedent that this is legitimate **when the typed tree
proves impossibility**. A non-zero literal divisor is such a proof; a variable the
analysis believes is non-zero is not.

## Scope

**In:** refine `P_division` on its divisor; discriminate the assert form; the
vocabulary/schema change that requires (`exn_origins.form` is a CHECK-constrained
enum); the consequence for every consumer of `may-fail` / `raises` / `fails-with` /
`error-stats`, since removing an origin narrows a set on every corpus.

**Out:** `P_index` — an index origin needs the container's length to be decidable,
and that a literal index is provably safe has **not** been established. Do not let
the spec quietly widen to it.

**Out:** any risk-report or ranking feature. That is a separate task.
