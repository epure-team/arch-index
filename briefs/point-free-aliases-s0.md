# S0 — the typedtree-path split, measured

**Date:** 2026-09-04
**Method:** throwaway instrumentation at the drop site (`walk_function_root`'s
peeled root being a bare `Texp_ident`), classifying by `Path.t` constructor crossed
with arrow-typedness. The walker was restored immediately after; nothing here is
committed to the producer.

**Why this exists:** the intake brief proposed a 248-qualified / 87-local work
breakdown derived from SOURCE SYNTAX. The spec retracted it (`open M` makes a bare
identifier syntactically local and semantically qualified). This is the split by the
thing that actually decides the resolution mechanism.

## Result

| typedtree path | proto_alpha | octez-manager | resolution mechanism |
|---|---|---|---|
| `Pdot`, arrow-typed | **285** | 214 | `resolve_qualified` — **blocked on roadmap 1.6** |
| `Pident` in `local_fn_stamps`, arrow | **67** | **326** | `resolve_local` — **no dependency** |
| `Pident` not in stamps, arrow | 38 | 10 | neither — see below |
| non-arrow (all paths) | 390 | 376 | excluded by FR-003 |
| **arrow-typed total** | **390** | **550** | |

## What this changes in the plan

1. **The source-syntax split was wrong in composition, not only in principle.** On
   proto_alpha the local-resolvable set is **67**, not the 87 the brief implied — and
   38 more *look* local while resolving through neither mechanism.

2. **The two corpora invert.** octez-manager is 59% locally resolvable; proto_alpha is
   73% qualified. So the "local slice ships first" strategy delivers 326 aliases on
   octez-manager and only **67 on the corpus that drives the question**. The strategy
   is still right — 393 aliases with no external dependency — but its value on Tezos
   is 17%, not a majority. Sequencing must say this rather than imply the local slice
   is most of the work.

3. **`Pident_other` is a third class the plan did not name.** 38 on proto_alpha, 10 on
   octez-manager: a bare identifier that is not a same-module top-level function.

   **CORRECTED IN REVIEW — this enumeration was incomplete, and the missing member was
   the feature's own construct.** The class has *three* members, not two:

   - an **alias binder** (`let t2 = t1`, where `t1` is itself `let t1 = target`). `t1`
     has no function *body*, so it is not in `local_fn_stamps` and `t2` fell into this
     class and was dropped. That is the original defect one hop along: `t1` reads
     `BOUNDED: {Boom}` and `t2` reads `BOUNDED: {}`. **Now handled** — see FR-005c.
   - a **parameter** or local closure (not an alias at all — correctly excluded, and
     there is no top-level row to point an edge at even if one wanted to).
   - an **`open`-mediated reference** — **not actually a member.** Settled empirically:
     typedtree paths are post-resolution, so `open M` followed by a bare `g` yields
     `Path.Pdot (M, g)`, never a `Pident`. The qualified slice covers it by construction.

   US-3's second acceptance scenario covers the `open` case; nothing covered the
   parameter case, and nothing named the alias-binder case at all.

4. **The non-arrow population is large and real** — 390 on proto_alpha, 376 on
   octez-manager. FR-003's exclusion is not a corner case; it is roughly half of all
   point-free bindings.

## Cost note, recorded for a queued research item

Of a 3969 ms proto_alpha index, the fixpoint is **434 ms** — so roughly **89% is
`.cmt` reading, walking and SQLite writing**, and the analysis proper is a tenth of it.

A future research item (queued, deliberately after the current 0-CFA design work)
should ask whether incremental re-indexing is possible. Framing to carry into it: the
obstacle is unlikely to be write cost. The fixpoint is **whole-program**, so a change
in one module can move any other node's verdict. Re-walking three changed modules is
easy; knowing which verdicts to invalidate is the hard half, and it is a
compositionality question, not an I/O one.
