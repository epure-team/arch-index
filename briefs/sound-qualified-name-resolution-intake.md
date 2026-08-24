# Intake — sound-qualified-name-resolution

**Type:** bug-fix (soundness contract violation)
**Trust boundary:** no (no auth/custody/attestation surface)
**Mode:** full
**Status:** VALIDATED

## Problem, as proven by execution

The OCaml producer stamps `MUST` edges that point at the **wrong function** when two dune
libraries contain a module with the same file basename. Reproduced independently twice, with
different fixtures:

```
liba/api.ml : let run () = ...
libc/api.ml : let run () = ...
libb/caller.ml : let go_a () = Liba.Api.run ()

calls: go_a → run@libc/api.ml   kind=MUST      ← identity theft, not a missing edge
```

The verdict still reads `sound`. Per `docs/edge-kind-contract.md:5`, `MUST` means
"uniquely-resolved static call" — so this **violates the contract as written**, even though no
document names this case (the spec covers "unresolvable target → MAY_TOP", not "resolved to the
wrong homonym").

## Root cause (file:line)

1. Three tables in `lib/arch_index/arch_index.ml` are keyed by **capitalised file basename**, built
   with `Hashtbl.replace` (last writer wins, no warning, no collision count), from a
   `SELECT path FROM modules` with **no `ORDER BY`** (so the winner is not even deterministic):
   - `arch_index.ml:275-284` — call resolution (`mod_name_to_path`)
   - `arch_index.ml:421-432` + `:443-453` — module dependencies
   - `arch_index.ml:479-493` — type usages (`type_lookup`)
2. `resolve_qualified` (`arch_index.ml:321-338`) falls back to that table at every level it tries,
   so it inherits the collision.
3. **The identity exists but is discarded**: the raw `Path.t` from the Typedtree carries the
   persistent root ident of the dune library wrapper, but `path_to_module_name`
   (`arch_index_cmt.ml:499-510`) flattens `Path.Pdot` to `(Some "Api", "run")` — dropping the root.
   **This is the point of intervention.**
4. A fourth, worse instance: `call_graph_extractor.ml:202-205` keys by **raw function name**
   (`Hashtbl.replace name_to_file r.name r.file_path`), read at `:264`; plus `arch_query.ml:162-199`
   resolves user arguments by `WHERE name=?`. Independent copies of one pattern — no shared
   `resolve_module_name` helper exists.

## What is NOT broken (bounds the work)

- `include`, module alias, and functor application degrade to **`MAY_TOP`**, never a false `MUST`
  (`arch_index_cmt.ml:33-70` deliberately does not descend into `Tmod_ident`/`Tmod_apply`;
  non-persistent roots are demoted at `:800-811`). Verified by execution.
- The dune-generated `<libname>.cmt` wrapper escapes `is_dune_alias_module`
  (`arch_index_cmt.ml:192-194`, matches only the `__` suffix) but does **not** pollute `modules` —
  incidentally, because `source_path_of_cmt` (`arch_index_support.ml:129-153`) fails to resolve its
  path. Incidental, not intentional: worth hardening but not the bug.

## Acceptance criteria

- **AC1** — For a fixture with two dune libraries each defining a same-named module, a qualified
  call resolves to the **correct** function, or is degraded to `MAY_ENUMERATED`/`MAY_TOP`. Never a
  `MUST` to the wrong owner. (This is the red-then-green test; no such fixture exists today —
  every OCaml callgraph fixture is single-library, verified across 8 fixtures.)
- **AC2** — All three `arch_index.ml` sites are fixed, not just call resolution (they are three
  instances of one bug).
- **AC3** — Where library identity is unavailable (`(wrapped false)`, LSP path, vendored code),
  the producer degrades honestly to `MAY_TOP` rather than guessing by basename — per
  `SPEC-sound-callgraph.md:44-46` ("never collapse a dynamic site to one target").
- **AC4** — The self-index golden (`test/fixtures/self-index-stats.txt`,
  `modules: 19, functions: 426, calls: 3391`) is re-baselined **with the change explained**, not
  silently updated; edge-kind distribution shift is stated.
- **AC5** — No `MUST` count increase that is not justified by a correctness improvement; the
  `arch-rules --on-vacuous fail` self-check still passes.

## Out of scope (capture separately)

- The 4th site (`call_graph_extractor.ml` raw-function-name keying) and `arch_query`'s
  `WHERE name=?` — same pattern, different layer; fix after the producer is sound.
- Hardening `is_dune_alias_module` for the modern wrapper shape.
- The LSP nominal path (not audited; only the CMT fallback was).

## Prior attempt

PR #20 tried "bind to a MAY_ENUMERATED candidate set" and was closed: narrowing candidates by
"modules holding a `functions` row for the name" removes the true owner under `include`/re-export,
leaving one survivor that the single-candidate branch stamps `MUST`. Any design must not
reintroduce a single-candidate → `MUST` path.
