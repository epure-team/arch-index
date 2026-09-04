# Implementer brief — point-free-aliases

**Status: VALIDATED**

Self-contained: assume no access to prior conversation.

## Goal
`let f = M.g` (eta-reduced re-export, body a bare `Texp_ident`, no `Texp_apply`) yields a
`functions` row with zero outgoing `calls` rows. Give it an edge to its target, marked.

## Contract
`specs/point-free-aliases.md` — 4 US, 10 FR (incl. FR-005b), 5 CHECK. Plan:
`briefs/point-free-aliases-plan.md`, steps S0–S5.

## The trap, read this first
`arch_index.ml:832` computes `demoted = call.cond || call.partial`. `partial` means
*under-saturated application* (`arch_index_cmt.ml:535`). An alias is **not** an
application, so `demoted = false`, and `Head_local` (`:859`) / `Head_qualified` (`:874`)
emit **`MUST`** — which three frozen documents forbid for a non-application edge. Do NOT
set `partial = true` to work around it; that puts a false claim in the data to obtain the
right kind by accident. Classify the alias as **`Head_enumerated`**, which forces
`MAY_ENUMERATED` unconditionally at `:843`.

## Files
| File | Change |
|---|---|
| `architecture-schema.sql` | `calls.edge_form TEXT CHECK(edge_form IS NULL OR edge_form='value_alias')` |
| `lib/arch_index/arch_index_db.ml:52` | bump `current_schema_version` |
| `lib/arch_index/arch_index_db.ml:394` | `insert_call_rowid` binds 8 params; a 9th touches DDL, prepared stmt, both signatures, every call site |
| `lib/arch_index/arch_index_cmt.ml` | at `walk_function_root`'s `peel` no-op, emit via `add_path_call` as `Head_enumerated` |
| `bin/arch_query/arch_query.ml:357,556` | `fan-in`/`god-modules` exclude `edge_form='value_alias'`, gated on `Arch_db.has_col t "calls" "edge_form"` |
| `docs/edge-kind-contract.md` | document that `MAY_ENUMERATED` now also covers value aliases, disambiguated by `edge_form` |

## Naming
The column is `edge_form`, the value `'value_alias'`. **Never** the bare word `alias`:
`module_deps.dep_kind='alias'` already means module alias, and two relations sharing one
word is the miscounting the marker exists to prevent.

## Quality gates
```bash
eval $(opam env --switch=/home/mathias/dev/arch-index --set-switch)
dune build
dune runtest --force        # NEVER `dune exec tezt/tests/main.exe`
```
`dune exec` does not rebuild the producer binary: demonstrated with a mutation that left
`dune exec` green with the producer hash unchanged while `runtest` went red and rebuilt
it. Red-verify every new test. Where a characterisation test admits no red, say so and
derive the expected value by hand **before** running.

The golden (`test/fixtures/self-index-stats.txt`) is checked **only** by CI
(`.github/workflows/ci.yml:95`), never by `dune runtest` — a local green says nothing
about it. Re-measure golden and `clean_measured` per slice with a 2×2 attribution
(A=base bin/base src, B=new bin/base src, C=base bin/new src, D=new bin/new src) and
write only when A=B and C=D.

## Do not
- Add a `functions` row whose name contains a dot in the aliasing module (FR-007).
- Emit an edge for a non-arrow-typed RHS (`let k = M.pi` gets a `functions` row with
  signature `int`; a call edge to a constant would be nonsense).
- Attach an edge to `let _ = M.g` — that binding has no `functions` row at all.
- Touch `resolve_qualified` outside S3, and do not let S3 straddle the roadmap-1.6 merge.
