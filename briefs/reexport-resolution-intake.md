# Intake Brief — reexport-resolution

**Date:** 2026-09-04
**Status: VALIDATED**
**Type:** feature
**Trust boundary:** no  ← keyword heuristic: no hit (the Tier A "proof" hit is about edge soundness, not a cryptographic component)
**Validated autonomously** on the human's standing instruction to run without gating.

## Goal

`module_deps` records, per referencing file, what each module `include`s and what each
local name aliases. It is populated on every run and **read by nothing that resolves
names**. Teach qualified-name resolution to consult it, scoped to the referencing unit,
so that a reference reaching its target through a re-export resolves instead of
becoming an unresolved leaf.

### Why this and not a closure analysis — measured, not argued

Ceiling experiment on proto_alpha (deleting a class of edges bounds what resolving it
perfectly could ever buy):

| resolve perfectly | bounded nodes |
|---|---|
| baseline | 3436 — 23.8% |
| all `module_param` | 3676 — +1.6 pt |
| all `callback_param` (0-CFA) | 3939 — +3.5 pt |
| all ⊤ | 4249 — +5.6 pt |
| + externals assumed pure | 13069 — **+61 pt** |

The `external` cause dominates by an order of magnitude, and it is not fundamental: the
opam switch holds **1751 `.cmt` against 1783 `.cmi`**, so 98% of installed packages ship
typed trees. OCaml has no open world. What breaks the chain *X raises → Y calls X
uncaught → Y raises* is the **re-export hub** reached on the way.

Attribution of the ten heaviest unresolved names on the whole `src` tree (8615 modules,
304323 functions, 1190765 calls):

| blocking form | edges |
|---|---|
| **`include`** — `Lwt_result_syntax.*` via `include Tezos_error_monad.TzLwtreslib`; `ret_succ_adding` via `include Cache_memory_helpers` | **~49 000** |
| module **`alias`** — `S.safe_int`, `S.Syntax.+` | ~20 800 |
| index boundary — `Stdlib.*` | ~14 800 |
| genuine callback — `f` | 5 832 |

`Tezos_base` is the largest external root: **108 766 edges over 991 names**, hanging off
`tzPervasives.ml`'s 6 `include` and 33 module aliases.

## Scope Boundary

Explicitly OUT:

- **Extending the corpus to the opam dependency closure.** A separate task, and it only
  pays off after this one — the extra corpus is reached *through* the hubs.
- **`open` rows.** 8776 of them, and an `open` does not name a target the way
  `include`/`alias` do. In only if the spec argues it.
- **`local_open`.** Declared in the CHECK and written by no site — dead vocabulary.
  Do not implement a producer for it under cover of this task.
- **Re-resolving `module_deps.target_module` itself**, and the `arch-rules` `Dep` verdict
  that depends on it. Named as a known defect by the sibling branch; a separate fix.
- **Type-usage resolution**, the third sub-pass with the same basename scheme.

## Relevant Files

| File | Role | Key fact |
|---|---|---|
| `lib/arch_index/arch_index.ml:719-722` | the key function | `basename \|> remove_extension \|> capitalize` — two files with one basename collide |
| `lib/arch_index/arch_index.ml:723-730` | `mod_name_to_path` | `SELECT path FROM modules`, `Hashtbl.replace`, **no `ORDER BY`** — last row returned wins |
| `lib/arch_index/arch_index.ml:776-793` | `resolve_qualified` | readings most-qualified first, first hit wins; consults only `mod_name_to_path` + `fn_lookup` |
| `lib/arch_index/arch_index.ml:886-898` | qualified failure | `callee_id=NULL`, `top_reason=NULL`, `kind="MUST"` when unconditional+saturated — **an external leaf, not ⊤** |
| `lib/arch_index/arch_index.ml:973` / `:1003` / `:1040` | the ordering problem | call-resolution `COMMIT` **precedes** the `BEGIN` of the loop that writes `module_deps` |
| `lib/arch_index/arch_index_cmt.ml:2490/2500/2512` | producer sites | `open` / `include` / `alias`; nothing writes `local_open` |
| `architecture-schema.sql:232-241` | `module_deps` | `target_path` NOT NULL and always populated; `target_module` **nullable and unreliable** |
| `bin/arch_rules/arch_rules.ml:337-352` | the only production reader | the `Dep` rule |

## Architecture Notes

**The data is already correct; only the wire is missing.** Every `alias` row carries
`source_module` (joinable to the referencing file) and `target_path`. Measured on the
whole tree: single-letter aliases give 363 rows, and **`S` alone appears 272 times
across 34 distinct targets** — a global name match on `S` would be wrong 33 times out of
34. Per-file scoping is mandatory, and the per-file context exists.

**Read `target_path`, never `target_module`.** The FK is resolved by the same
basename/last-writer-wins scheme this task routes around, so it may point at the wrong
file. `target_path` is the raw parsed string, always populated.

**Ordering is a design constraint, not a detail.** The `module_deps` population loop
BEGINs after call resolution COMMITs. Either the population moves before resolution, or
resolution reads the in-memory structure that feeds it rather than the table. That
choice has crash-window consequences — the exact class PR #62 spent three review rounds
closing, where a marker outlived the evidence it described.

**The seam with roadmap 1.6 is declared by that branch itself**, so the two tasks
complement rather than collide: *"THE OTHER TWO RESOLUTION SITES ARE NOT TOUCHED BY
THIS… arch-rules builds its `forbid dep` verdict straight from module_deps, so a real
violation can report pass and a nonexistent one FAIL."* 1.6 re-keys **call** resolution
by compilation unit; `module_deps` resolution stays on the old scheme after it merges.

**Soundness surface — the real risk.** Resolving an edge changes its `kind`: an
unresolved external leaf becomes MUST or MAY_ENUMERATED **with a `callee_id`**. A
mis-resolution is therefore worse than no resolution — it points a proof-carrying edge
at the wrong function. The sibling branch's review caught exactly this on its own
branch: `script_interpreter.ml:842` resolving to a **test helper** of the same basename,
stamped MUST.

**Prior art will not settle the hard question.** No OCaml tool exposes the alias/include
relation as queryable data (merlin and ocaml-lsp treat it as a jump destination, odoc as
a rendering decision; odoc's `@canonical` is built for this and documents its own
leaks). No surveyed tool — CodeQL, Doop, Soot, WALA, SVF, SCIP, rust-analyzer —
distinguishes *"no candidate"* from *"several unranked candidates"* as separate output
states, and none takes a normative position on honest-unknown versus plausible-guess.
The argument must be ours.

## Quality Gates

```bash
eval $(opam env --switch=/home/mathias/dev/arch-index --set-switch)
dune build
dune runtest --force        # NEVER `dune exec tezt/tests/main.exe`
```

`dune exec` does not rebuild the producer: demonstrated with a mutation that left it
green with the producer hash unchanged while `runtest` went red and rebuilt it. The
golden (`test/fixtures/self-index-stats.txt`) is checked **only** by CI
(`.github/workflows/ci.yml:95`), never by `dune runtest`. Golden and `clean_measured`
re-measured with a 2×2 attribution (A=base bin/base src, B=new bin/base src, C=base
bin/new src, D=new bin/new src), written only when A=B and C=D.

**Every acceptance criterion counts bounded nodes, never ⊤ rate.** An SQL stand-in
resolving 3165 statically-known edges cut ⊤ by 28% and bounded **nine** more nodes out
of 14452 — ⊤ is absorbing, so one residual ⊤ edge in a node's forward closure keeps its
verdict.

## Open Questions

- [ ] **Ordering: move the population, or resolve from memory?** Populating
      `module_deps` before call resolution changes what a crashed run leaves behind;
      resolving from the in-memory structure leaves the table's own resolution
      untouched. The spec must pick one and state the crash-window consequence.
- [ ] **What kind does a re-export-resolved edge get?** The qualified failure path today
      writes `MUST` when unconditional and saturated. If resolution now succeeds through
      an `include`, is the edge MUST — an assertion that this call definitely runs and
      definitely lands there — or MAY_ENUMERATED? An `include` is not a call site.
- [ ] **What happens when a re-export chain is ambiguous** (a name reachable through two
      different `include`s)? The sibling branch answers `ambiguous_unit`/⊤ for its own
      case; this task must decide whether to reuse that vocabulary or stay an external
      leaf. Prior art offers no precedent — no surveyed tool separates "zero" from
      "several".
- [ ] **How deep does a chain follow?** `TzPervasives` includes `TzLwtreslib`, whose
      `Lwt_result_syntax` is defined inside a **functor**. One hop resolves nothing here.
      The spec must state the depth limit and what is emitted at the limit.
- [ ] **Does `open` belong after all?** 8776 rows, and an `open` makes an unqualified
      name resolvable — the `Pident`-not-in-stamps class measured at 38 on proto_alpha.
      Out of scope by default; the spec may argue it in.
