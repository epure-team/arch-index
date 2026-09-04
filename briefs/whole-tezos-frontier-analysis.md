# Where the ⊤ frontier actually is — measured, 2026-09-04

Motivating question: *what can crash the Tezos protocol, how and why?*

## Headline

The 76% ⊤ is **unresolved re-exports**, not higher-order code. A closure analysis is
worth 3.5 percentage points; following re-exports is worth an order of magnitude more.

## Ceiling experiment

Upper bound per class — edges of the class are *deleted* rather than resolved, so the
result is unsound and valid only as a maximum.

| resolve perfectly | bounded |
|---|---|
| baseline (proto_alpha, 14452 nodes) | 3436 — 23.8% |
| all `module_param` (defunctorisation) | 3676 — 25.4% (**+1.6 pt**) |
| all `callback_param` (0-CFA) | 3939 — 27.3% (**+3.5 pt**) |
| all ⊤ | 4249 — 29.4% (**+5.6 pt**) |
| + externals assumed pure | 13069 — **90.4% (+61 pt)** |

## Why `external` dominates, and why it is not fundamental

The chain *X raises → Y calls X uncaught → Y raises* already works; it is the fixpoint.
It stops at two places, neither of them a limit of the analysis:

**1. The index boundary — which is a choice, not a constraint.** The opam switch holds
**1751 `.cmt` against 1783 `.cmi`**: 98% of installed packages ship typed trees,
stdlib included. In OCaml with opam and dune, the world is closed.

**2. Re-export hubs — the real blocker.** `src/lib_base/tzPervasives.ml` carries
**6 `include` and 33 module aliases**, and **108766 unresolved edges** hang off it.
Indexing more corpus buys nothing until aliases are followed, because the extra corpus
is reached *through* the hub.

## The three re-export forms

| form | weight | status |
|---|---|---|
| `include M` | **7653 occurrences across 2126 files** | **unmeasured until now, nobody working on it** |
| `module N = P` | 202 in proto_alpha | roadmap 1.6 (peer, in review) |
| `let f = M.g` | 390 arrow-typed in proto_alpha | `specs/point-free-aliases.md`, plan done, S0 delivered |

## Irreducible floor

| | |
|---|---|
| C stubs (`external "caml_…"`) | 4784 declarations |
| `Unix.fork` / `Lwt_process.*` | ~24 sites |
| `*TOP*` computed heads | 40353 edges |
| **total** | **≈3.8% of 1190765 edges** |

Against 74.6% ⊤ today: a factor of **20** between the tool and its honest floor.

## Scaling is not the obstacle

Whole `src` tree: **8615 modules, 304323 functions, 1190765 calls**; fixpoint **6.2 s**
(21× the corpus, 14× the time — linear). The walker and name resolution are what do not
scale; the analysis does.

## A trap worth stating

**Reducing ⊤ is not bounding nodes.** An SQL stand-in resolving 3165 statically-known
edges cut ⊤ by 28% and bounded **nine** more nodes out of 14452 — ⊤ is absorbing, so a
single residual ⊤ edge in a node's forward closure keeps its verdict. Judge this work by
bounded-node count, never by ⊤ rate.

## Consequent order of work

1. **The three re-export forms.** `include` first by weight (and unowned); value aliases
   are specced and planned; module aliases are the peer's in-flight 1.6.
2. **Index the dependency closure.** Only pays off after (1).
3. Everything else — origin-class precision, 0-CFA, GPU — far behind.
