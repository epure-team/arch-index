# Measurement — `val_loc` is sound, small, and does NOT close the functor case

2026-09-04. Probe at the existing `Tstr_include` site, real producer, real `.cmt`, SQL
against the resulting database. Three corpora: a four-file fixture, octez-manager
(480 `.cmt`), and octez at `tzx-anchor-16ca2d33` (6 735 `.cmt`, 4 954 indexed modules,
188 082 function rows).

**Read the last section first if you are short of time: the fixture-scale conclusion in
the first version of this brief was wrong, and PR #69's "not deliverable" is
substantially right.**

## The question

`incl.incl_type` carries a `Sig_value` per re-exported value, and each carries a
`val_description.val_loc`. Can `val_loc` be used as a resolution key, and does it reach
through a functor application — the shape PR #69 measured as blocking, and the one that
carries `Lwt_result_syntax.let*` (25 273 unresolved edges, the heaviest name in the
corpus)?

## What holds at every scale — zero ambiguity

The lookup is: `val_loc`'s file, mapped `.mli -> .ml`, plus the value's own name, against
`(module path, function name)`.

**Across all 79 123 `Sig_value` entries in octez, that key hit more than one function
row exactly 0 times.** Not once, in any include shape. This is the property that
matters for [[ambiguity-is-absence-of-proof]]: the mechanism never has to choose among
candidates, so it can never upgrade an honest leaf into a false `MUST`. Ghost locations
are 342/79 123 = 0.43 %.

## What does not hold — the hit rate, and the functor case in particular

octez, 4 834 includes, 79 123 re-exported values:

| shape | total | UNIQUE | name absent | module not indexed | ghost | AMBIGUOUS |
|---|---|---|---|---|---|---|
| CONSTRAINT | 30 702 | 14 661 | 7 971 | 7 964 | 106 | **0** |
| IDENT | 25 470 | 543 | 6 110 | 18 810 | 7 | **0** |
| APPLY | 21 423 | **178** | 6 487 | 14 758 | 0 | **0** |
| STRUCTURE | 1 526 | 162 | 1 135 | 0 | 229 | **0** |
| APPLY_UNIT | 2 | 0 | 0 | 2 | 0 | **0** |
| **ALL** | **79 123** | **15 544 (19.6 %)** | 21 703 | 41 534 | 342 | **0** |

**The functor-application case resolves 178 of 21 423 = 0.8 %.** The first version of
this brief claimed "the functor case is not the hard one; it is the same one". That is
false at scale, and it was false for a reason I could have anticipated.

## Why — verified, not inferred

The dominant `module not indexed` targets are not externals alone:

```
  3822  stdlib.ml                                  <- genuine external
  2142  src/lib_crypto/s.ml                        <- signature-only file
  1820  src/lib_lwt_result_stdlib/lwtreslib.ml
  1811  irmin/lib_irmin/store_intf.ml              <- signature-only file
  1432  v0/s.ml                                    <- signature-only file
```

`src/lib_crypto/s.ml` contains **16 `module type` declarations and zero top-level
`let`**. It is a pure signature file. So when a functor's result is constrained by a
`module type S` — which is the normal way this corpus is written — `val_loc` for each
re-exported value points at the **`val` declaration inside that `module type`**, not at
the functor body. A declaration is not a definition: there is no function row there, and
there never will be. The same class explains most of `name absent` (the `.ml` is indexed,
but the name is declared in a `module type` inside it rather than defined).

## The fixture was the artifact — section 10.2 in a new dress

My fixture's functor result had **no `.mli` and no `module type` constraint**, so
`val_loc` pointed straight at the body (`lib/monad_maker.ml:6`, non-ghost) and every
value resolved. That shape barely exists in real OCaml. octez-manager, which has `.mli`
files but almost no functor includes (28 CONSTRAINT / 5 IDENT, **zero APPLY**), gave
302/312 = 96.8 % and reinforced the error — it measured the easy shape at a scale large
enough to feel like proof.

`specs/qualified-unit-resolution.md` §10.2 is "the measured artifact is not the artifact
under test". This is that, one level up: the measured *corpus* was not the corpus under
test. Two corpora agreeing did not help, because both lacked the structure that
dominates the third.

## Where this leaves the item

**PR #69's scope-out is substantially correct, and my correction to it was overconfident.**
Their diagnosis also names the right route: `module_path_of_expr`
(`arch_index_cmt.ml:631-635`) handles only `Tmod_ident`/`Tmod_constraint`, and for
`Tmod_apply` the functor's own path is what is needed. The functor body's functions *are*
indexed — the fixture showed `lib/monad_maker.ml | Make.bind | 6` — so a fix that
recovers `Monad_maker.Make` from the application and looks for `Make.<value>` there is
the tractable one. That is a **producer** change, exactly as #69 says, not a resolver
change.

What `val_loc` is still worth, on its own terms:

- 15 544 values (19.6 %), **never ambiguous**, at the cost of one more arm on a site the
  walker already visits.
- It is a strictly additive fallback tier: 0 candidates or >1 declines, so it cannot
  regress an existing edge.
- It does **not** need `module_deps`, `module_path_of_expr`, or the `prefix = ""` guard,
  so it does not collide with #69's slice.

Whether 19.6 % of re-exported *values* is worth shipping depends on how many *edges* it
moves, which is unmeasured. It should not be scoped until that number exists — the
mistake this brief already made once was letting a mechanism's elegance stand in for its
measured impact.

## Corrections to my own prior work

1. [[include-reexport-resolution-research]]'s "33/33 `Tmod_ident`" for octez-manager is
   wrong: the shapes are 28 `Tmod_constraint` / 5 `Tmod_ident`. On octez the split is
   1 471 CONSTRAINT / 1 344 APPLY / 1 015 STRUCTURE / 1 003 IDENT / 1 APPLY_UNIT.
2. That brief's design — record the source module path from `incl_mod` and re-resolve it
   through 1.6's `unit_readings`/`paths_of_unit` — is not superseded by `val_loc` after
   all. For the CONSTRAINT and IDENT shapes the two are alternatives; for APPLY neither
   works, and the producer fix #69 names is the only route.
3. My statement to the #69 reviewer that their conclusion was "too pessimistic" was
   itself based on the fixture. Retracted and corrected in writing to that reviewer.
