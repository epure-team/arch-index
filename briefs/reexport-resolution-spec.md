# Spec amendment — reexport-resolution

**Date:** 2026-09-05
**Status: VALIDATED (re-opened and amended 2026-09-05)** — the bounce below is kept as the record of why D1 and D2 changed.

The amendment cannot be written as scoped. The blocker is not any of the three
decisions individually; it is that decision (2) — lifting a ⊤ edge to a resolved
kind — makes a *frozen* constraint unsafe that was harmless while D2 held the
kind constant.

## The blocking finding

**D1's index key is `(source_module, alias_name)` — a NAME. The (3) mark is a
binder identity — a STAMP.** The join between them discards exactly the
precision (3) exists to establish.

`docs/edge-kind-contract.md` states as a contract-level guarantee for the OCaml
backend: *"Resolution is `Ident`-stamp-based (shadows never forge a MUST)."*
This would be the first resolution path in the producer to break it.

Two attacks survive a **perfectly stamp-precise** (3) filter, because they
attack the join and not the classification:

**SA-1 — nested alias, correct mark, wrong target.**
```ocaml
module S = Saturation_repr                  (* toplevel: row written *)
module Internal_for_tests = struct
  module S = Test_saturation_stub           (* nested: NO row, prefix <> "" gate *)
  let cost_add x y = S.add x y              (* Head_unknown ("S.add", Module_param) *)
end
```
The inner binder **is** a `Tstr_module`/`Tmod_ident` alias, so a stamp-precise
mark answers *alias-rooted* — truthfully. The name-keyed lookup then finds the
only row under `("saturation_costs.ml", "S")`: the toplevel one. Result: a
production call to a test stub, recorded as a **proven** call into protocol
code. That is the mirror image of the defect ADR 003 documents. It cannot be
fixed by rejecting nested contexts, because **US-3 scenario 2 requires** a
toplevel alias used inside a nested submodule to resolve — the two are the same
shape from the resolver's side and are separable only by binder identity, which
the frozen key discards.

**SA-2 — toplevel rebinding turns a pinned limitation into a wrong MUST.**
```ocaml
module C = Compare.Int
let sort_ids l = List.sort C.compare l
module C = Compare.String                  (* legal shadowing *)
let sort_names l = List.sort C.compare l   (* first-insert-wins → Compare.Int *)
```
US-3 scenario 1 pins first-insert-wins as *"a known limitation with a
characterisation test, not claimed as correct"* — defensible when the outcome
was a `callee_id` on an edge whose kind was already decided. Under the
amendment the same limitation **manufactures a MUST from a sound ⊤**, on an
int-vs-string comparator, which `reaches` then treats as must-reach ground
truth. Two toplevel bindings of one alias name is a key mapping to two
candidates: an absence of proof the frozen index resolves by ordering.

## And my measurement cannot license MUST

I offered "0 ambiguous in 8 318 chases" as the evidence for a MUST landing kind.
**The measurement was taken downstream of the step that destroys ambiguity.**
The alias index is first-insert-wins, so a file with two bindings of `S`
presents **one** candidate; `resolve_qualified_unit` is asked one question and
answers `Resolved`. The figure measures the *target* side (unit name → paths)
and is structurally blind to the *alias* side, where ambiguity was already
resolved by ordering. It is a real number about the wrong side of the join.

This is the third time in two days that a correct number of mine was cited for
something it did not measure, and the first where the consequence would have
been an unsound edge kind rather than a wrong priority.

## Three further contradictions the amendment would ship

- **FR-004 / CHECK-3 / US-1 scenario 2** all require `kind`, `top_reason` and
  `top_anchor` to be unchanged, and CHECK-3 asserts a byte-identical kind
  histogram. The amendment alters all three for ~5 847 edges by definition. It
  turns three passing checks into checks that must fail, and the feature's
  entire regression evidence today is "no kind moved".
- **US-4's ratchet arithmetic assumed the opposite transition** —
  MUST+NULL → MUST+id. The real transition is MAY_TOP+NULL → resolved, so
  `must_null_ceiling` stops being a ratchet on this feature at all.
- **FR-007 and D4 still say "4 hops inclusive, with cycle detection"** while the
  frozen design is 1 hop. US-2 scenarios 2 and 3 (a 5-hop chain, an `A = B`/
  `B = A` cycle) cannot be exercised by any fixture. Spec and frozen decision
  are in direct contradiction and the amendment pass is where that must be
  resolved.

## The soundness direction, stated plainly

100 % of the amendment's measurable effect is the **deletion of ~5 847 ⊤
frontiers**. `arch_exn.ml` treats a `MAY_TOP` edge as an unknown-raise witness;
`arch_effects_queries.ml` refuses `pure` for a node with a reachable `MAY_TOP`.
Removing those edges **removes raise-set members and promotes functions from
`candidate` to `pure`** on both corpora — a monotone narrowing of an
over-approximation, in a system whose exception feature validates itself on
*"zero removals on both corpora"*. The amendment cannot meet that bar, and no
decision here sets a new one.

## What has to be decided, and by whom

The task cannot proceed without re-opening something the brief froze:

1. **Unfreeze D1's key** — index by binder identity (`Ident.unique_name`), not
   by name. That closes SA-1 and SA-2 at the root and restores the
   stamp-based guarantee. It is a producer-side data-flow change through
   `call_head`/`pending_call` (public in the `.mli`, with three consumers), not
   a resolver change.
2. **Or abandon the kind lift** — keep D2 as written. The feature then sets no
   `callee_id` on the population it was built for, because those edges are ⊤,
   and delivers nothing.

There is no third option that keeps both the frozen name key and the kind lift.
I am not taking (1) unilaterally: it re-opens a decision the brief explicitly
placed out of scope, and it is the same class of change — producer data flow
carrying binder identity — that the functor-instance arbitration deferred for
its own measurement gates.

## What survives unchanged

The per-file *scoping* is right and is now measured: 460 edges on proto_alpha
and 67 on octez-manager have a head that is an alias in a **different** file,
which a global match would have resolved wrongly — 527 wrong resolutions the
scoping prevents. The defect is the KEY's granularity (name, not stamp), not
the decision to scope per file.

D4 at 1 hop stands, on a corrected number: a second hop reaches 21 edges on
proto_alpha and 29 on octez-manager, 50 against 8 318 chases. My published
justification ("6 of 2811 aliases") was wrong — the real two-hop population is
116, measured with a corrected query — and the §10.6 argument I attached to it
was wrong too, since at 116 cases a depth counter would fire. Right decision,
both stated reasons wrong.
