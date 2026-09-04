# Arbitration — D1 unfreezes to binder identity, and it is the same item as the functor work

2026-09-05. Decision record for `reexport-resolution`, taken after the spec phase bounced
with a soundness attack the implementation could not close. Written down because it
reverses a frozen decision and because the gate that should have caught it was mine, and
was mis-specified.

## The gate I wrote could not observe the risk it guarded

I arbitrated: *"do not take MUST on my agreement — take it on this number: of the 3203,
how many resolve to exactly one target once the producer's mark is applied?"*

The peer measured exactly that: **0 ambiguous out of 8318 chases**. The number is real.
It is also **taken downstream of `first-insert-wins`**, which had already collapsed the
alias side to a single candidate. It measures the *target* side and is structurally blind
to the side where the choice is made.

That is the same defect the same session had found three hours earlier — a graft point
unable to observe its own cases — committed by me, in the gate written to prevent it.
See [[a-tier-reporting-zero-proves-nothing]].

## The attack that decides it

A perfectly stamp-precise mark cannot rescue a name-keyed join, because the precision is
lost *downstream* of the mark:

- **SA-1**: a nested `module S = Test_stub` inside a file whose toplevel declares
  `module S = Saturation_repr`. The nested binder **is** an alias, so the mark answers
  true honestly; the name key then finds the only row — the toplevel's. A production call
  to a test stub, recorded as a **proven** call into protocol code. It cannot be closed by
  rejecting nesting: US-3 scenario 2 requires a toplevel alias used from a submodule to
  resolve.
- **SA-2**: toplevel rebinding of the same name. `first-insert-wins` is pinned as a known
  limitation — defensible while `kind` never moved, lethal once it rises.

**One sentence**: D1's key is a **name**, the shadowing mark is a **stamp**, and the join
discards exactly the precision the mark establishes.

`docs/edge-kind-contract.md` guarantees at contract level that OCaml resolution is
stamp-based *so that shadowing can never forge a MUST*. This would be the first producer
path to break it, from a fallback tier.

## Decision

**D1 unfreezes to a binder-identity key.** There is no third option: keeping the name key
without raising `kind` leaves nothing, because 100 % of the measurable effect is the
removal of ~5847 ⊤ frontiers, and without the `kind` rise there is no removal. So it is
"unfreeze D1" or "no tier" — not a compromise to negotiate.

**And it is the same work item as the functor tier.** Binder identity carried in the
producer data flow is what both need — there "record the argument, not only the head",
here "record the binder's identity, not only its name". Two consumers of one producer
change; specifying them apart will make them diverge. The three gates already placed on
the functor item become the gates of the merged item:

1. are functor arguments recoverable at the same 100 % rate heads were?
2. how long are the chains, and are they bounded? (measured: ≥ 2 hops, one contributing
   zero rows)
3. when one body is reachable through several instantiations and the call site's qualified
   name pins none — ⊤, never a pick. This caps the achievable share and must be measured
   before the work is sold on a number.

**No code before those gates are measured**, since they decide the shape of the producer
data both consumers share.

## This is a re-spec, not an amendment

The amendment would contradict three FRs at once: FR-004/CHECK-3/US-1-2 require `kind`,
`top_reason` and `top_anchor` unchanged while it alters all three on ~5847 edges; US-4's
ratchet arithmetic assumed `MUST+NULL → MUST+id` where the real transition is
`MAY_TOP+NULL → resolved`; FR-007/D4 still mandate 4 hops against a design frozen at 1.

The spec must also state which of two properties it guarantees, because they cannot both
hold: the change is a **monotone shrink of an over-approximation** (removing ⊤ frontiers
drops raise-set members and promotes functions from `candidate` to `pure`), against a
feature that validates on **zero removals**.

## What survives, and must not be re-litigated

Per-file **scoping** is correct and now measured: **527 wrong resolutions avoided** across
both corpora. The defect is the key's granularity, not the scoping. The per-file alias
index read from `all_pending_deps` — never from `module_deps`, whose FK carries the
erasure ADR 003 accepts as permanent — also stands.

## A correction the peer made to their own published figure

D4's justification cited "6 aliases out of 2811", from a query comparing whole
`target_path` against `alias_name` — `Commitment.Hash` never equals `Commitment`. The real
figure is **116**, which also falsifies the §10.6 argument built on it ("the counters
would read zero forever" — at 116 cases they fire). D4 holds anyway, on the quantity that
decides: a second hop reaches **50 edges out of 8318**. Right conclusion, both stated
reasons wrong — kept by replacing the reasons rather than by defending them.

---

## CORRECTION, one hour later — gate 1 splits the item this brief merged

The merge above ("two consumers of one producer change") is **wrong**, and the peer's
gate-1 measurement is what falsifies it. They share the *principle* — the producer must
carry identity, not a name — but **not the data**:

- the **alias** consumer needs a module binder's identity: one field, already in the
  walker's hand at the moment it is discarded;
- the **functor** consumer needs the **argument**, and 34 % of arguments are inline
  anonymous structures. Closing that means indexing those structures, which is not
  "carry one more field".

I generalised from *"both want more than a name"* to *"both want the same thing"*. The
first is true; the second was asserted with no measurement behind it.

**Gate 1, measured on proto_alpha** (3310 argument occurrences, 1450 applications):

| | share |
|---|---|
| arguments that are inline anonymous structures | 1125 (34 %) |
| arguments that are themselves applications | 555 (17 %) |
| arguments that are a nameable path | ~1630 (49 %) |
| **applications where ALL arguments are nameable** | **315 / 1450 = 21 %** |

Heads were 1450/1450 recoverable; arguments come nowhere near it. And the split follows
**functor families** rather than scattering, which is the useful part — it can be written
as a scope decision that stays true, instead of a percentage to re-measure per corpus:

| always fully nameable | never fully nameable |
|---|---|
| `Map.Make`, `Set.Make`, `Path_encoding.Make_hex`, `TzPervasives.Map.Make`, `Skip_list.Make` | every `Indexed_context.Make_*`, `Bond_id_index.Make_carbonated_map` |

**The storage functors are entirely in the right-hand column**, because each takes an
inline `struct let name = [...] end` as its naming argument. So head+args covers 21 % of
applications and **none** of the ones blocking the crash question — `storage_functors.ml`'s
7 `assert false` stay unreachable by this route.

### Revised decision

- **D1 proceeds alone, for the alias consumer only.** SA-1 closes with binder identity,
  independently of anything about functor applications. Merging held the cheap item
  hostage to the expensive one — the opposite of the intent.
- **The functor tier is a separate item, repriced**: head-only 5.2 %; head+args 21 % of
  applications and 0 % of the named targets. Scope it by family ("container functors yes,
  storage functors no"), not by percentage.
- **Gates 2 and 3 are deferred** — they gate an item that just moved down the queue.
- **Gate 3 is answered as a rule, not a measurement**: when one body is reachable from
  several instantiations and the call site's qualified name pins none, the answer is **⊤,
  never a pick**. That is [[ambiguity-is-absence-of-proof]] and it is not arbitrable; the
  measurement only prices it — how much of the 21 % survives.

### A third instance of the same family, from the same probe

The peer's first gate-1 build **failed** while their command printed `BUILD=0`, because
`head` in the pipeline masked the exit status — the `pipefail` defect they themselves
reported on PR #61, turned on their own probe. Fixed with `PIPESTATUS`.

That completes the family observed in this session: a **mutant that fails to build reports
green**; a **tier never reached reports zero**; a **probe whose status is masked reports
success**. All three are the same shape — *the output does not distinguish "it worked"
from "it never ran"* — and all three close by counting what was **reached**, not what was
found.
