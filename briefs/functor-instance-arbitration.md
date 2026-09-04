# Arbitration — `functor_instance` is worth 5.2 %, not 35 %, and the 35 % needs a design decision

2026-09-04. Two sessions measured this from opposite ends and converged. Written down
because it is a roadmap ranking, it changed twice in one evening on unmeasured framing,
and the peer is right that it deserves a spec rather than a decision in messaging.

## How the ranking moved, and why it kept being wrong

1. Peer: "functor-instance indexing is the next big lever, ahead of the opam closure" —
   from a targeted, true observation (storage's `assert false` are behind functors).
2. Peer, retracting: proto_alpha's 47 024 unresolved edges are 41.4 % external, **30.7 %
   monadic-syntax-via-`include`**, only **4.2 %** functor-instance. "False by volume."
3. Me, refusing that retraction: the two buckets are not independent — my own measurement
   says the heavy `include` names arrive *through* functor-application includes, so the
   4.2 % bucket may be the 30.7 % bucket's lock.
4. Both, measuring: **I was right about the structure and wrong about the consequence.**

Each wrong step was the same shape: a true local observation extended, for free, into a
global ranking. See [[ceiling-experiments-measure-what-you-left-open]].

## The chain, measured

```
TzPervasives.ml:31   include Tezos_error_monad.TzLwtreslib              [IDENT]
TzLwtreslib.ml:26    include …Lwtreslib.Traced (TzTrace)                [APPLY]
lwtreslib.ml:46      module Traced (Trace) = Traced_structs.Structs.Make (Trace)
monad_maker.ml:182   module Lwt_result_syntax = struct
                       include Monad.Lwt_result_syntax   ← let* / return come from HERE
                       let tzfail = Monad.Lwt_traced_result_syntax.fail
                     end
```

Indexed-function counts by functor name, whole octez (`tzx-anchor-16ca2d33`, 188 082
functions):

| functor name | indexed functions |
|---|---|
| `Traced.*` | **0** |
| `Structs.*` | **0** |
| `Make.*` | 16 579 |

`Traced` indexes **nothing** because its body is *itself a functor application*, not a
struct — a third case neither of us had: an intermediate functor-alias hop that
contributes no rows and must still be traversed. Bodies index under the functor's own
name (`Make.Lwt_result_syntax.tzfail`), which is why `Make.*` is populated.

And `Monad` at `monad_maker.ml:182` is a **functor parameter**. So head recovery reaches
the body, and the body forwards to a parameter whose value is known only at application.

## The split (peer's measurement, proto_alpha's 14 439 monadic edges)

| | edges | share |
|---|---|---|
| comes from an `include` **of the parameter** → needs the ARGUMENT | **13 999** | **97.0 %** |
| defined **in** the body → head suffices | 440 | 3.0 % |

## Decision

**1. The head-only `functor_instance` row is worth 5.2 % (1 997 + 440 = 2 437 edges), and
that is what it may be scoped as.** Not 35 %. It is cheap, its heads are 100 %
recoverable (1 450/1 450, peer's probe), and the peer's design — a `module_deps` row of
kind `functor_instance` resolving to the already-indexed body — preserves
`arch_index_cmt.ml:196`'s deliberate rejection of per-instance indexing ("one row set per
instance instead of one per definition"). Take it on those terms or not at all.

**2. Resolving to the body MERGES all instantiations**, so `Total_frozen_bonds.update` and
`Total_supply.update` would name one `Make_single_data_storage.update`. Over-approximating,
therefore right for a may-raise and **forbidden for `MUST`**: the edge must be
`MAY_ENUMERATED`. This goes in the spec before the first line of code, not after.

**3. The 97 % is NOT unlocked by the cheap mechanism, and the mechanism that unlocks it is
the one the design rejected on purpose.** That is a real tension, not an easy call, and it
does not get settled in a message thread.

**4. Gate before anyone specs the argument-following route** — three measurements, none
of which exist yet:
   - Are functor **arguments** recoverable at the same rate heads were (100 %)? Unmeasured.
     The peer's intermediate idea — record head *and* args in the `module_deps` row and
     substitute the parameter at RESOLUTION time rather than at indexing — is the right
     shape precisely because it keeps "one definition, N bindings" and moves the cost to
     the query. It is worthless if the args are not recoverable.
   - **How long are the chains, and are they bounded?** The measured one is ≥ 2 functor
     hops with a zero-row functor-alias in between. A substitution that must thread a
     parameter through N hops is a different mechanism from one that threads it through 1.
   - **What happens when one body is reachable through several instantiations and the call
     site's qualified name does not pin one?** The answer must be ⊤, never a pick — that is
     [[ambiguity-is-absence-of-proof]], and it is the rule working rather than a flaw. But
     it caps the achievable share, and the cap should be measured before the work is sold
     on 35 %.

**5. Neither route goes ahead of `reexport-resolution` on this evidence.** 5.2 % does not
displace it, and 35 % is not yet a deliverable — it is a hypothesis with three open
measurements.

## The convergence worth keeping

`let tzfail = Monad.Lwt_traced_result_syntax.fail` is a **point-free alias** (PR #69) whose
qualifier is a **functor parameter** (this item), inside a **`include` of a parameter**
(the re-export tier) — three re-export forms in one 15-line `struct`, and they are the 83
`MAY_TOP`/`module_param` alias edges already measured. The forms are not three independent
work items; they meet at the same site.
