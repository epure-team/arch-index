# Functor-instance resolution — a separate item, priced

**Date:** 2026-09-05
**Status:** scoped and priced, NOT started. Below `reexport-resolution` in the queue.

Split out from `reexport-resolution` after gate 1. The two share a *principle* —
a binder needs more than its name — and not a *datum*: the alias consumer needs
a binder identity the walker already holds and throws away; this consumer needs
the functor **argument**, and a third of those have no name to record.

## The price, stated by functor family rather than as a percentage

Gate 1, proto_alpha, 1450 module-level functor applications:

| tier | coverage |
|---|---|
| head only (reach the functor body) | **1450 / 1450**, zero unrecoverable |
| head + args (substitute a parameter) | **315 / 1450** |

The 315 is not a scattered fifth. It follows the family, which is why this is a
scope rule and not a number to re-measure per corpus:

| substitutable — CONTAINER functors | not substitutable — STORAGE functors |
|---|---|
| `Map.Make`, `Set.Make` | `Indexed_context.Make_map` |
| `Path_encoding.Make_hex` | `Indexed_context.Make_carbonated_map` |
| `TzPervasives.Map.Make` | `Indexed_context.Make_set` |
| `Skip_list.Make` | `Bond_id_index.Make_carbonated_map` |

**Container functors take module arguments; storage functors take an inline
`struct let name = [...] end`.** That structure has no path to record, so
substitution needs the anonymous structure itself indexed — a different and
larger change than carrying one more field.

## Why that ordering matters more than the percentage

The storage functors are the ones standing between the protocol's entry points
and the seven `assert false` in `storage_functors.ml`. So the argument-carrying
design buys the container half and **none of the crash-question half**. An item
that costs anonymous-structure indexing, covers a fifth of applications, and
reaches none of the named targets does not go ahead of anything.

## Gates still open

- **Gate 2 — chain length.** Unmeasured. `lwtreslib.ml:46` shows a functor whose
  body is itself an application (`module Traced (Trace) = Traced_structs.Structs.Make (Trace)`),
  contributing zero indexed functions while still having to be traversed, so
  chains are at least 2 with a zero-row intermediate.
- **Gate 3 — a body reachable from several instantiations.** **Answered, and it
  was never a measurement question**: ⊤, never a choice. That is "ambiguity is
  the absence of proof", the rule roadmap 1.6 spent six review rounds making
  hold. The measurement would only price the rule — how much of the 21 %
  survives it — so gate 3 is a scoping gate, not a design one, and can wait
  until the item is picked up.

## What is already known and should not be re-derived

- Head recoverability is 100 % (1450/1450) and the heads are exactly the useful
  ones: `Storage_functors.Make_single_data_storage` (205),
  `Indexed_context.Make_map` (175), `Map.Make` (125).
- `arch_index_cmt.ml`'s module walk deliberately does NOT descend into
  `Tmod_apply`, and the comment says why: it would produce one row-set per
  instance instead of one per definition. Any design must preserve that —
  record a dependency edge per instance pointing at one definition, never index
  the result.
- Resolving to the functor BODY merges all instantiations, so the landing kind
  cannot be MUST for the same reason as the alias case: naming is discharged,
  uniqueness and saturation are not.
