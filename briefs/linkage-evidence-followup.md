# Follow-up: linkage evidence closes the qualified-resolution residual

Opened 2026-09-04 from roadmap 1.6's disclosed residual (scenario F,
`tezt/tests/qualified_library_scoping.ml`). Not part of 1.6 — recorded here with its
evidence so the next slice starts from a measurement rather than from the idea.

## The residual

A qualified reference rooted entirely outside the index still binds a local homonym, as a
NULL-free `MUST`:

```
Stdlib.Buffer.add_string   ->   mylib/buffer.ml:add_string   MUST
```

in any project owning a `buffer.ml` / `list.ml` / `option.ml` / `result.ml`. It reproduces
identically on `origin/main`, so 1.6 retains it rather than introducing it — but 1.6's facade
tier is what makes it reachable through a bare segment, so 1.6 owns the follow-up.

## Why the cheap fixes do not work — both measured, not argued

| candidate gate | result |
|---|---|
| facade tier requires SOME prefix reading to name an indexed unit | **−1638** correct resolutions on proto_alpha |
| ... plus the ROOT prefix to name an indexed unit | **−1616**, and a plausible-looking 25 116 resolved against a baseline of 26 693 |

Both fail for one reason: **a facade library is routinely not indexed at all at the scope being
analysed.** `Tezos_protocol_alpha.Protocol.Main.acceptable_pass` legitimately reaches
`lib_protocol/main.ml` while none of `Tezos_protocol_alpha`, `Tezos_protocol_alpha__Protocol`,
`Tezos_protocol_alpha__Protocol__Main` is a stored row. Index membership therefore cannot
distinguish "reference into a facade we do not index" from "reference into a library we do not
link" — they are the same shape.

## The evidence that does distinguish them, and it is already in the .cmt

`Cmt_format.cmt_infos` carries `cmt_imports : crcs` — `(unit_name * Digest.t option) list` — one
field away from `cmt_modname`, which `arch_index_cmt.ml:342` already reads.

Verified on the scenario-F fixture with `ocamlobjinfo`. The caller `user/u.ml`, which does **not**
link the local `mylib`:

```
Interfaces imported:
    bf6c18db9a96f4c2d97dddb7f07cdee4  Stdlib__Buffer
    cfc6abca663b2d71db1750a2c051cf6e  Stdlib
    ...                               (no Mylib__Buffer)
```

The import list names **the unit the reference actually resolves to**, and does not name the
homonym. So this is not a heuristic that merely rules the wrong answer out — it states the right
one. A facade reference's caller will likewise import the units it really reaches.

## Shape of the slice

1. Record `cmt_imports` per unit alongside the existing unit registry (`record_unit`).
2. Constrain `facade_readings`: a bare-segment candidate is admissible only if the CALLER's own
   import set contains that candidate unit.
3. Scenario F flips from asserting the defect to asserting the fix — it is written to fail when
   the residual closes, precisely so this is a deliberate edit.

## Caveat to settle first, in research not in code

Finding 3 of `qualified-unit-resolution-research.md` established that a caller importing an alias
imports **all** of `Foo`, `Foo__`, `Foo__Bar`. So the import set is permissive: it will not
by itself collapse a genuine two-answer case to one. It is a filter on *admissibility*, not a
replacement for the function table's 1 / 2+ / 0 arbitration. Whether it ever removes a
LEGITIMATE candidate — a call through a functor argument, a `-open`ed module, a ppx-generated
reference — must be measured on both corpora before it gates anything.
