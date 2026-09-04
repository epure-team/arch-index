# Task — reexport-resolution

Consult `module_deps` when a qualified name does not resolve.

## The defect — a disconnected wire, not a missing capability

`module_deps` is written by the producer (`lib/arch_index/arch_index.ml:504`) with
`dep_kind IN ('open','include','alias','local_open')`; the schema has carried that
vocabulary from the start. On the whole Tezos `src` tree it holds **open 8776,
alias 2811, include 840**.

The qualified-name resolver **never reads it**. `grep module_deps lib/arch_index/*.ml`
returns the INSERT and the drop-list entry, nothing else. Its sole consumer anywhere
is `arch-rules` (`bin/arch_rules/arch_rules.ml:337-350`), for declared-dependency
rules. The table recording *"TzPervasives includes TzLwtreslib"* and *"S is an alias
of Saturation_repr"* is populated, and ignored by the one pass that needs it.

Third instance of the same shape found in one session — a capability written and never
read. `top_reason`/`top_anchor` are written by every producer and read by no consumer;
`builtin_stdlib_summaries` is off by default **and** keyed on `Stdlib.*` while the
corpus spells `Tezos_base.TzPervasives.*`.

## Measured impact

Whole `src` tree: 8615 modules, 304 323 functions, 1 190 765 calls. Attribution of the
ten heaviest unresolved callee names:

| blocking form | edges |
|---|---|
| **`include`** — `Lwt_result_syntax.let*`/`let*!`/`return` (25273+8318+7951), `Lwt_syntax.let*` (3780) via `include Tezos_error_monad.TzLwtreslib` (`tzPervasives.ml:31`); `ret_succ_adding` (3642) via `include Cache_memory_helpers` | **~49 000** |
| module **`alias`** — `S.safe_int` (15249), `S.Syntax.+` (5532) | ~20 800 |
| index boundary — `Stdlib.Format.fprintf` (9090), `Stdlib.=` (5734) | ~14 800 |
| genuine callback — `f` | 5 832 |

`module S = Saturation_repr` appears in 21 files, `= Dal_slot_repr` in 2,
`= Set.Make (String)` in 2 — **the alias is per-file, never global**.
`Tezos_base` is the largest external root: 108 766 edges over 991 names.
`Lwt_result_syntax` is itself defined **inside a functor**
(`src/lib_error_monad/monad_maker.ml:182`) reached through that include — so include
and functor compose.

## Why this rather than a closure analysis

Ceiling experiment on proto_alpha (deleting a class of edges = the upper bound on
resolving it perfectly): all `callback_param` is worth **+3.5 points** of bounded
nodes, all `module_param` **+1.6**, every ⊤ together **+5.6** — while assuming
externals pure is worth **+61**. And the index boundary is not fundamental: the opam
switch holds **1751 `.cmt` against 1783 `.cmi`**, so 98 % of installed packages ship
typed trees, stdlib included. **OCaml has no open world.**

## The lesson that must not be softened

**Reducing ⊤ is not bounding nodes.** An SQL stand-in resolving 3165 statically-known
edges cut ⊤ by 28 % and bounded **nine** more nodes out of 14 452 — ⊤ is absorbing, so
one residual ⊤ edge anywhere in a node's forward closure keeps its verdict. Every
acceptance criterion states bounded-node counts, never ⊤ rate.

## Soundness surface — the real risk

Resolving an edge changes its `kind`: an unresolved external leaf becomes MUST or
MAY_ENUMERATED with a `callee_id`. **A mis-resolution is worse than no resolution** —
it points a proof-carrying edge at the wrong function. The peer's roadmap-1.6 review
caught exactly this on their own branch: `script_interpreter.ml:842` resolving to a
**test helper** of the same basename, stamped MUST. Any `module_deps` lookup must be
scoped to the referencing unit, never a global name match.

## Scope

**In:** consult `module_deps` (`include` and `alias` at minimum) when qualified
resolution fails, scoped to the referencing module; kind assignment for the
newly-resolved edge; the consequence for every consumer of `may-fail`, `raises`,
`fails-with`, `error-stats`, `reaches`, `arch-rules`.

**Out:** extending the corpus to the opam dependency closure — a separate task, and it
only pays off after this one. **Out:** `open` rows unless the research says otherwise
(8776 of them, and an `open` does not name a target the way `include`/`alias` do).

## Coordination

A peer session owns roadmap 1.6 (`feat/qualified-unit-resolution`, in review, 15
commits ahead of main), which re-keys `mod_name_to_path` by compilation unit. This task
is adjacent and must not duplicate it — the research must establish what 1.6 already
resolves before anything is proposed.
