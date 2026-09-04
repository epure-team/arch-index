# S1 finding — the splice point sees zero of the cases it was written for

**Date:** 2026-09-05
**Status:** blocks S1 as specified; requires a spec amendment before implementation.

## What was specified

D2/C-15 put the alias fallback in the `Not_found` arm of `Head_qualified`,
strictly after the `dropped_qualified` check, and required that it **set
`callee_id` only and never change `kind`**.

## What the corpus says

Implemented as specified, instrumented, and run on proto_alpha:

```
Alias fallback: 0 resolved, 0 declined ambiguous, 0 no candidate
AIPROBE index_size=133          (the alias index is populated and correctly keyed)
chases attempted: 35705         (the tier runs)
```

35 705 chases ran and **not one** came from a file that declares an alias. Every
`mod_name` reaching that arm is a library-level name — `Tezos_protocol_environment_alpha`
(12 450), `Tezos_base` (7 732), `Stdlib` (2 994). Never a local alias binder.

The reason, measured rather than inferred:

```sql
-- unresolved calls whose head IS an alias declared in the SAME file
kind      | top_reason   | n
MAY_TOP   | module_param | 3203      -- all of them
```

**All 3 203 are `Head_unknown (_, Module_param)`.** A path rooted at a local
module binder is classified dynamic by `qualified_is_dynamic` and sent straight
to ⊤; it never reaches `Head_qualified` at all. So the specified splice point is
**structurally unable to observe the case the task exists for** — the same shape
as the `traversed` guard that could not fire on `<path>:*`, one day later, in a
different file.

Concretely: `script_repr_costs_generated.ml` declares
`module S = Tezos_raw_protocol_alpha.Saturation_repr`, has 45 unresolved `S.*`
calls, and produced zero chases.

## What this changes, and why it is not a one-line move

Moving the splice to the `Module_param` arm makes the tier see the cases — but it
breaks D2, and not on a technicality:

- **D2 says do not change `kind`.** These edges are `MAY_TOP`. Resolving one
  necessarily leaves ⊤, because ⊤ was recorded for "I cannot tell what this
  module is" and the alias table answers exactly that. So D2 as written forbids
  the only useful outcome. It has to be re-decided, not worked around.
- **`qualified_is_dynamic` conflates two things.** It returns true for a module
  alias AND for a functor parameter. Today that conflation is *sound* — both are
  unknowable to the walker. Resolving on an alias-name match alone would resolve
  a functor parameter that happens to share a binder name with an alias, turning
  an honest ⊤ into a wrong `callee_id`. **42 alias rows already carry a name that
  maps to more than one target across the corpus**, so the collision is real, not
  hypothetical.
- The safe form is therefore **not** "match the name" but "the head is a binder
  this file aliases AND is not shadowed at the call site" — which is walker-side
  evidence the resolver does not have today.

## Recommendation

Bounce to spec. Three decisions need re-taking with this measurement in hand:

1. **Splice point** — `Module_param`, not `Head_qualified`/`Not_found`.
2. **D2** — an alias-resolved edge leaves ⊤; state what kind it lands on.
   `MAY_ENUMERATED` is the candidate, by the same argument used for point-free
   value aliases: the target set is a singleton but no call is proven.
3. **Shadowing evidence** — decide whether the producer must distinguish an
   alias-rooted path from a parameter-rooted one, or whether the resolver
   declines whenever the binder name is not unambiguously an alias in that file.

Until (3) is decided, implementing (1) alone would trade a sound ⊤ for a
possibly-wrong MUST — the exact defect roadmap 1.6 spent six review rounds
closing, and the one ADR 003 named as its accepted residual.

## What is already built and stands

`briefs/…` `wip` commit: the per-file alias index, keyed `(source_module,
alias_name)`, first-insert-wins, read from the in-memory `all_pending_deps` and
never from `module_deps` (whose `target_module` FK carries the basename erasure
ADR 003 accepted as permanent). 133 entries on proto_alpha, keys verified
correct against `caller_module`. It is the right structure; only its consumer is
in the wrong place.

---

## The measurement that unblocks D2 (2026-09-05)

Taken with the REAL resolver, by temporarily running the chase from the
`Module_param` arm and recording `resolve_qualified_unit`'s verdict on the
rewritten name. Both corpora, because they have inverted on every previous
split.

| corpus | chases | resolved to ONE target | not found | **ambiguous** |
|---|---|---|---|---|
| proto_alpha | 3 203 | 2 838 (88.6 %) | 365 (11.4 %) | **0** |
| octez-manager | 5 115 | 3 009 (58.8 %) | 2 106 (41.2 %) | **0** |
| **combined** | **8 318** | **5 847 (70.3 %)** | 2 471 | **0** |

**Zero ambiguity across 8 318 chases.** The unit registry never reported more
than one candidate for a rewritten alias target on either corpus.

### What this decides, and what it does not

- **Ambiguity is not the risk here.** The 1.6 decline rule costs nothing to
  apply on these corpora. It should still be applied — a decline rule that never
  fires is a *guarantee*, not a measurement, and is a different thing from a
  CHECK that cannot fire (§10.6). But it is not what makes this task hard.
- **The whole risk is decision (3).** Every resolution is single-target, so if
  the producer's alias-vs-parameter mark is CERTAIN, each resolved edge is as
  proven as any qualified resolution. If the mark stays probabilistic, the ratio
  above is irrelevant — a wrong resolution at 88 % is still a wrong resolution.
- **Therefore D2's landing kind follows (3), not this table.** MUST is
  defensible only on the certainty of the producer mark. This measurement
  removes ambiguity as an objection; it does not by itself license MUST.

### A design detail the spec must also settle

`Head_unknown` carries a single display string (`"S.safe_int"`), not the
`(module, name)` pair `Head_qualified` preserves. Any consumer at that arm has
to re-split on the last dot, which is a parse of a rendered string rather than a
read of preserved structure. If the fallback lives there, the producer should
carry the split — recovering structure by parsing your own output is how the
`top_reason` string/constructor divergence happened.

### Correction to my own earlier argument

I proposed MAY_ENUMERATED "by the same argument as point-free value aliases".
That argument does not transport, and the reviewer is right to reject it: for a
point-free alias the reason was that **no call happens at the site** — the edge
is not an application at all. Here there is a real `Texp_apply`. The conclusion
may still be MAY_ENUMERATED, but it needs a different reason, and the only one
available is the certainty of (3).

---

## Further measurements taken during the spec amendment (2026-09-05)

### The per-file key is now justified empirically, not just argued

| | proto_alpha | octez-manager |
|---|---|---|
| `module_param` ⊤ edges, total | 5 381 | 5 303 |
| of which head is an alias in the SAME file | 3 203 (59.5 %) | 5 115 (96.5 %) |
| stay ⊤ under the per-file filter | 2 178 | 188 |
| **of those, head IS an alias in a DIFFERENT file** | **460** | **67** |

A global name match would have resolved those **527 edges — wrongly**. D1's per-file
scoping was previously argued from "`module S` appears in 21 files"; this is the
consequence measured directly.

### The alias/parameter collision is real ACROSS files and absent WITHIN one

8 binder names on proto_alpha are both an alias name and a functor-parameter name —
including `S` itself, plus `Context`, `Parameters`, `G`, `H`, `P`, `R`, `T`.

But **no single file in either corpus declares an alias `X` and also takes a functor
parameter `X`.** `sc_rollup_stake_storage.ml` takes `(S : ...)` and calls `S.*` five
times, and declares four aliases — none of them named `S`.

So the collision the (3) decision exists to prevent is **real in principle and has zero
measured instances**, because the per-file key already separates every case found. That
does not make (3) unnecessary — absence on two corpora is not a guarantee, and a
name-match-only design would be one shadowing binder away from a wrong `callee_id`. It
does mean (3) buys a **guarantee**, not a measured correction, and the spec must say so
rather than claim a defect it cannot exhibit.

### D4's justification was wrong; D4 survives on a different quantity

I justified "1 hop" with "of 2811 alias rows, SIX have a target that itself declares
aliases", and used it as an example of machinery whose counters would read zero forever.

**That number came from comparing the whole `target_path` against `alias_name`.**
`Commitment.Hash` never equals `Commitment`, so every genuine two-hop alias was missed.
Comparing the target's HEAD segment instead:

| | count |
|---|---|
| alias rows, whole tree | 2 811 |
| **two-hop (target head is an alias in the same file)** | **116** |
| the wrong query's answer | 23 |

Concretely: `module Commitment_hash = Commitment.Hash` beside
`module Commitment = Sc_rollup_commitment_repr`, in four different files.

**So both of my arguments for D4 were wrong.** The population is 19× what I published,
and at 116 cases a depth counter would NOT read zero — the §10.6 objection does not
apply.

**D4 still stands, on the quantity that actually decides it:**

| edges a second hop would reach | proto_alpha | octez-manager |
|---|---|---|
| | 21 | 29 |

50 edges against 8 318 chases — 0.6 %. The decision is right; I had justified it by
counting ALIASES when the decision-relevant quantity is EDGES. Counting the right thing
gives a better justification than a wrong count of the wrong thing, and this is the
second time today a correct decision rested on a number that did not support it.
