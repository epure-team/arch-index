# Follow-up: linkage evidence closes the qualified-resolution residual

Opened 2026-09-04 from roadmap 1.6's disclosed residual (scenarios F, J and L,
`tezt/tests/qualified_library_scoping.ml` — narrower when first opened, when only F existed; see
below). Not part of 1.6 — recorded here with its evidence so the next slice starts from a
measurement rather than from the idea.

## Scope — THREE shapes, not one

Review found the residual is wider than this brief first described, twice over: round-2/3 review
found shape (b) alongside (a), and round-5 review found shape (c) is not even the same KIND of
hole — it never reaches the facade tier at all. All three need attention, though only (a) and (b)
need the SAME evidence (a caller's `.cmt` import list); (c) is a prefix-tier defect and linkage
evidence does not obviously apply to it (see "Shape of the slice" below).

- **(a) rooted outside the index** — `Stdlib.Buffer.add_string` in a project owning a `buffer.ml`,
  `Unix.*`, a vendored duplicate, any unlinked library. Pinned by scenario F
  (`unlmylib/buffer.ml`).
- **(b) rooted INSIDE it, and the caller LINKS the library it wrongly reaches** — an anchor exists,
  and the facade tier re-interprets a segment strictly below it. Two measured shapes: scenario J
  (`Owner.Submod.f`, an unlinked homonym) and scenario L:

      linca/api.ml = "include Base_impl"        (no Inner.run row of its own)
      Linca.Api.Inner.run  ->  lincb/inner.ml   MUST

  while the correct answer `linca/base_impl.ml:Inner.run` IS indexed. This is FR-001's defect one
  qualification level deeper than scenario A, and an earlier revision of this brief excluded it by
  scoping the residual to "a library the caller does not link". That exclusion was wrong: (b) is
  the more common shape in dune projects, and it is what scenario G's title used to claim was
  closed.
- **(c) NOT a facade-tier hole** — found by round-5 review, in the PREFIX tier, for `(wrapped
  false)` libraries. Pinned by scenario M:

      wa/api.ml (wrapped false) = "include Base_impl"   (no run row of its own)
      wb/api.ml (wrapped false) = "let run () = …"       (the truth, wrong library)
      caller links wa ONLY, writes Api.run   ->   wb/api.ml:run   MUST

  For `(wrapped false)`, `paths_of_unit "Api"` returns both `wa/api.ml` and `wb/api.ml` — the same
  unit-keying collision scenario C discloses — but the function table finds a row at only ONE path,
  so `ids_of_readings` collapses to a single id and the PREFIX tier itself answers `` `Resolved ``
  before the facade tier's anchor gate is ever consulted. Linkage evidence (§ below) constrains
  `facade_readings`; it does not touch the prefix tier at all, so closing (c) needs either
  constraining `ids_of_readings` the same way when a prefix reading names MULTIPLE paths, or
  deciding this narrow, zero-incidence case is not worth chasing. Not scoped further here —
  recorded so the next slice starts from the right question.

A gate over the data already in the index cannot separate (b) from the LEGITIMATE facade it must
serve — `Facade.Protocol.Script_int` reaching `Rawlib__Script_int` has the identical shape. That is
the whole argument for linkage evidence, for (a) and (b).

## The residual

Shape (a), the one this brief originally described alone: a qualified reference rooted entirely
outside the index still binds a local homonym, as a NULL-free `MUST`:

```
Stdlib.Buffer.add_string   ->   unlmylib/buffer.ml:add_string   MUST
```

(scenario F's actual fixture is `unlmylib/buffer.ml`; an earlier revision of this section named a
`mylib/buffer.ml` that does not exist in the suite). The same shape holds for any project owning a
`buffer.ml` / `list.ml` / `option.ml` / `result.ml`. It reproduces identically on `origin/main`, so
1.6 retains it rather than introducing it — but 1.6's facade tier is what makes it reachable
through a bare segment, so 1.6 owns the follow-up. Shapes (b) and (c) are described above; they are
not re-derived here since scenarios J, L and M already state the fixtures precisely.

## Why the cheap fixes do not work — both measured, not argued

All figures are resolved-call counts on proto_alpha/lib_protocol (468 modules / 73 588 calls,
`--errors-profile tezos`), measured by patching the gate in place and rebuilding the producer
explicitly:

| tree | resolved |
|---|---|
| `origin/main` | 26 693 |
| this branch | 26 762 |
| this branch, facade tier disabled entirely | 25 116 |
| this branch + "require SOME reading to name an indexed unit" | 25 135 |

So the facade tier is worth **1 646** resolutions, and the tempting conjunct would cost **1 627**
of them.

An earlier revision of this brief cited **−1638** and **−1616 against a 26 693 baseline**. Those
are wrong twice over: they came from a wider corpus scope (`src/proto_alpha`, 690 modules) and from
a set-diff that counts a re-target as a loss, and they do not reconcile even with each other
(26 693 − 25 116 = 1 577, not 1 616). They are the same figures `lib/arch_index/arch_index.ml`
already flags as reproducing nowhere — so this brief was, in the same commit, republishing numbers
the code called unreproducible. Found by review; recorded here rather than quietly deleted, because
the failure is the interesting part.

Both candidates fail for one reason: **a facade library is routinely not indexed at all at the
scope being analysed.** `Tezos_protocol_alpha.Protocol.Main.acceptable_pass` legitimately reaches
`lib_protocol/main.ml` while none of `Tezos_protocol_alpha`,
`Tezos_protocol_alpha__Protocol` or `Tezos_protocol_alpha__Protocol__Main` is a stored row.

## The evidence that does distinguish them, and it is already in the .cmt

`Cmt_format.cmt_infos` carries `cmt_imports : crcs` — `(unit_name * Digest.t option) list` — one
field away from `cmt_modname`, which `arch_index_cmt.ml:342` already reads.

Verified on the scenario-F fixture with `ocamlobjinfo`. The caller `unluser/u.ml`, which does
**not** link the local `unlmylib`:

```
Interfaces imported:
    bf6c18db9a96f4c2d97dddb7f07cdee4  Stdlib__Buffer
    cfc6abca663b2d71db1750a2c051cf6e  Stdlib
    ...                               (no Unlmylib__Buffer)
```

The import list names **the unit the reference actually resolves to**, and does not name the
homonym. So this is not a heuristic that merely rules the wrong answer out — it states the right
one. A facade reference's caller will likewise import the units it really reaches.

## Shape of the slice

1. Record `cmt_imports` per unit alongside the existing unit registry (`record_unit`).
2. Constrain `facade_readings`: a bare-segment candidate is admissible only if the CALLER's own
   import set contains that candidate unit. This closes (a) and (b); it does not touch (c), which
   is a prefix-tier defect (see "Scope" above).
3. Scenarios F, J and L all flip from asserting the defect to asserting the fix when this lands —
   each is written to fail when its residual closes, precisely so each is a deliberate edit. So
   does the resolver's residual paragraph (`lib/arch_index/arch_index.ml`, "WHAT THIS STILL DOES
   NOT CLOSE"): it must drop shapes (a) and (b) in the same commit, not be left describing a hole
   the code no longer has. Scenario M and shape (c) are NOT closed by this slice and must not be
   deleted alongside the others.

## Caveat to settle first, in research not in code

Finding 3 of `qualified-unit-resolution-research.md` established that a caller importing an alias
imports **all** of `Foo`, `Foo__`, `Foo__Bar`. So the import set is permissive: it will not
by itself collapse a genuine two-answer case to one. It is a filter on *admissibility*, not a
replacement for the function table's 1 / 2+ / 0 arbitration. Whether it ever removes a
LEGITIMATE candidate — a call through a functor argument, a `-open`ed module, a ppx-generated
reference — must be measured on both corpora before it gates anything.
