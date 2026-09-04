# Research — resolving through `include M`

Roadmap follow-on to 1.6. Opened 2026-09-04, immediately after 1.6 merged as PR #67.
All findings empirical: real dune fixtures, the real producer, SQL against the resulting
database. Nothing here rests on reading code alone.

## Why this item, and why now

Own prior measurement ([[top-frontier-is-reexports]]) ranked the three re-export forms
that break the raise-set chain:

| form | weight | owner |
|---|---|---|
| `include M` | **7 653 occurrences in 2 126 files** | nobody |
| `module N = P` | 202 in proto_alpha | peer (`reexport-resolution`) |
| `let f = M.g` | 390 arrow-typed in proto_alpha | peer (`point-free-aliases`) |

`include` is the heaviest and the only unowned one. It is also exactly what ADR 003's
accepted residual for scenarios E and G defers to — "closing it requires following
`include` to find the row" — so this closes a residual the project has already
formally accepted rather than opening new ground.

## Finding 1 — the defect, reproduced

Fixture: library `inclib` with `base_impl.ml` (`run`, `helper`) and
`api.ml = "include Base_impl" + own`; a second library calling both.

```
Inclib.Api.own | MUST | -> lib/api.ml:own          resolved
Inclib.Api.run | MUST | -> NULL                    proof-shaped edge
```

and `lib/base_impl.ml:run` **is indexed**. So this is not a missing body: it is a
NULL-free `MUST` — consumed downstream as proof — into a function the graph already
holds. Same shape as scenarios E and G of `tezt/tests/qualified_library_scoping.ml`.

## Finding 2 — the walker ALREADY handles `Tstr_include`, and my own memory was wrong

`top-frontier-is-reexports` records the owner of `include` as "nobody — never measured
before this". That is wrong about the walker. `Tstr_include` is handled in three places
in `lib/arch_index/arch_index_cmt.ml`: `:184` (`module_expr ~prefix incl.incl_mod`),
`:2526`, `:2587`.

The site at `:2526` already iterates `incl.incl_type` — but matches only
`Sig_typext` and `Sig_module`, to canonicalise **exception** identities re-exported by
an include. `Sig_value`, which is what a function is, is dropped by the `| _ -> ()` arm.

So the mechanism this task needs is not new machinery. It is one more arm on a shipped,
tested pattern.

## Finding 3 — both halves of the information are present, measured

Probe inserted at that existing site, run on the fixture:

```
INCSRC IDENT Inclib.Base_impl
INCPROBE value run    (unique run_274)
INCPROBE value helper (unique helper_275)
```

- `incl.incl_type` yields `Sig_value` entries for **exactly** the re-exported values.
- `incl.incl_mod` is `Tmod_ident (path, _)`, so `Path.name path` yields the
  **fully-qualified source module** — `Inclib.Base_impl`.

Note the ident is a FRESH ident of the including unit (`run_274`), so `incl_type` says
*what* is re-exported, never *from where*. The two halves are needed together, and both
are available at the same site.

## Finding 4 — on real corpora every include is the simple shape

| corpus | includes | of which `Tmod_ident` |
|---|---|---|
| octez-manager | 33 | **33** |
| proto_alpha/lib_protocol | 253 | **202** |

No functor application (`Tmod_apply`) and no inline structure (`Tmod_structure`) among
octez-manager's. proto_alpha has 51 non-`IDENT` shapes to characterise before design —
the one open question this research leaves rather than answers.

Unresolved `MUST`-with-NULL for scale: octez-manager 15 712 (5 255 non-Stdlib),
proto_alpha 15 427 (14 233 non-Stdlib).

## Design implied by the evidence

At the existing `Tstr_include` site, record a third registry beside `unit_paths`:
`(including unit, re-exported value name) -> source module path`. Then resolution, on a
prefix-tier miss, asks: does this unit re-export a value of that name? If so, resolve
the recorded source module through the SAME `unit_readings` / `paths_of_unit` machinery
1.6 already ships, and look the residual up there.

Two properties fall out for free, and both matter:

- The re-exported name set **bounds** the follow, so it cannot over-resolve. This is not
  a guess-and-check tier like the facade tier; it is an authoritative list from the
  typedtree.
- Resolving the source module reuses 1.6's machinery, so it inherits the multi-path
  ambiguity rule — a source module name mapping to several paths degrades to ⊤ rather
  than binding whichever library owns the row. That rule was added in `6e7b429` after
  round 6 measured the branch *introducing* a wrong-library `MUST`, so inheriting it is
  the point, not an accident.

## Open questions for intake

1. **The 51 non-`IDENT` includes in proto_alpha.** Characterise them before designing:
   functor applications need the argument resolved first, and inline structures have no
   source module to record. Both may be honest residuals.
2. **Transitive includes.** `A includes B`, `B includes C`, reference to `A.f` where `f`
   is C's. Is the `incl_type` of `A` already flattened by the compiler (in which case
   this is free) or does it require a fixpoint? Measure, do not assume.
3. **Interaction with the peer's two forms.** All three re-export mechanisms feed the
   same resolver. Agree the order and the registry shape before any of us writes code —
   this session cost six review rounds partly to claims that outran evidence, and three
   agents editing one resolver is the same hazard with more actors.
