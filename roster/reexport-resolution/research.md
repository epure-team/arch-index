# Research — reexport-resolution

_Generated: 2026-09-04_
_Mode: full (4 parallel specialists)_
_Online research: enabled_

## Q1 — the dependency table's schema and its `kind` vocabulary

**Finding.** `module_deps` (`architecture-schema.sql:232-241`) carries `source_module`
(FK, NOT NULL), `target_module` (FK, **NULL if external**), `target_path` (TEXT NOT
NULL), `dep_kind`, `alias_name`, `line_number`. The CHECK is
`dep_kind IN ('open','include','alias','local_open')`.

Three of the four values have a producer site; **`'local_open'` has none** — it is
declared vocabulary that nothing ever writes.

| value | producer site |
|---|---|
| `open` | `arch_index_cmt.ml:2490` (`Tstr_open`) |
| `include` | `arch_index_cmt.ml:2500` (`Tstr_include`) |
| `alias` | `arch_index_cmt.ml:2512` (`Tstr_module`) |
| `local_open` | **none** |

Row counts — proto_alpha: open 563, include 50, alias 133. Whole `src`: open 8776,
include 840, alias 2811. **`target_path` is populated on every row** (746/746 and
12427/12427); `alias_name` is populated exactly on the `alias` rows.

## Q2 — how resolution builds and queries its map, and what failure writes

**Finding.** `module_name_of_path` (`arch_index.ml:719-722`) is
`basename |> remove_extension |> capitalize`. `mod_name_to_path` is filled from
`SELECT path FROM modules` with `Hashtbl.replace` and **no `ORDER BY`** — so on a
basename collision the winner is whichever row SQLite returned last, i.e. insertion
order. `resolve_qualified` (`:776-793`) tries readings most-qualified first, first hit
wins.

**Three sub-passes each build their own copy of this scheme** — calls, module-deps
(`:1006-1017`), and type-usages (`:1064-1076`) — and each fails differently.

Failure behaviour, and it matters for the ratchet: a **qualified** call that resolves to
nothing is written with `callee_id = NULL`, `top_reason = NULL`, and
`kind = "MUST"` when unconditional and saturated (`MAY_ENUMERATED` when demoted)
— it is treated as a genuine external leaf, **not flagged ⊤** (`:886-898`). An
*unqualified* failure by contrast becomes `MAY_TOP` + `callback_param` (`:868-885`).

## Q3 — how an unresolved leaf is represented

**Finding.** `calls` (`architecture-schema.sql:183-215`). The distinguishing mark is
`callee_id IS NULL` with `callee_name` holding the qualified string. `top_reason` /
`top_anchor` are non-NULL only when `kind='MAY_TOP'`, enforced by
`CHECK(top_reason IS NULL OR kind = 'MAY_TOP')`.

Four INSERT sites: `arch_index.ml:498-499` (main schema, 8 columns) and three
flat-schema writers (`arch_db/arch_load.ml:130`, `runner.ml:190`, `runner.ml:503`).

## Q4 — who reads `module_deps` — **load-bearing, verified as an absence**

**Finding: the claim is TRUE, and no contradicting reader exists.** Six search methods
were run rather than one confirmation.

- **One writer**: `arch_index.ml:504-505` via `insert_module_dep`
  (`arch_index_db.ml:472-482`), one call site (`:1040`).
- **One production reader**: `bin/arch_rules/arch_rules.ml:347-352`, the `Dep` rule,
  gated on `has_table` at `:337`.
- **The resolver never reads it**, directly or indirectly. Both its supporting tables
  are traced to their populating queries — `fn_lookup` from
  `functions ⋈ modules` (`:717-718`), `mod_name_to_path` from `SELECT path FROM
  modules` (`:730`) — neither from `module_deps`.
- Everything else naming it is non-consulting: two views (`v_module_deps`,
  `v_high_deps`, `architecture-schema.sql:687-706`) defined and **never queried**, a
  drop-list entry (`arch_index_support.ml:48-49,98`), one test
  (`tezt/tests/callgraph_nested.ml:225-232`), and prose.
- All 20 binaries under `bin/` were enumerated individually; only `arch_rules`
  references the table.

**And a structural finding nobody had measured: the population loop runs in a separate
transaction AFTER call resolution commits** — `COMMIT` at `:973`, then `BEGIN` at
`:1003`, `insert_module_dep` at `:1040`. So at the moment resolution would want the
table, **it is not yet written**. This is not "add a lookup"; it is an ordering change,
with the crash-window consequences that PR #62 has just spent three rounds on.

## Q5 — is per-file aliasing context stored? **Yes, and it is write-only**

**Finding.** Every `alias` row carries `source_module` (joinable to the referencing
file) **and** `target_path`. The context needed to say *"in file X, `S` means
`Saturation_repr`"* is already in the database.

Measured on the whole tree: single-letter aliases give 363 rows; **`S` alone appears
272 times across 34 distinct targets**. Per-file scoping is therefore not a refinement
— a global name match on `S` would be wrong 33 times out of 34.

The information is stored correctly and consulted by nothing.

**Caveat that shapes any design.** `target_module` (the FK) is itself resolved by the
same basename/last-writer-wins scheme (Q2), so it may point at the wrong file.
`target_path` is the raw parsed string and is always populated — it is the trustworthy
column, `target_module` is not.

## Q6 — the sibling branch **[PERISHABLE — `feat/qualified-unit-resolution`, in review]**

> **Ahead-count corrected 2026-09-04, plan phase.** This section was written claiming
> "15 commits ahead". Re-measured during `/roster-plan`: **29**, then **30** twenty
> minutes later, with `636 ++++` / 596 insertions / 40 deletions on
> `lib/arch_index/arch_index.ml` alone. The figure is not merely stale, it is *moving*;
> do not quote a number from this file without re-running
> `git rev-list --count origin/main..origin/feat/qualified-unit-resolution`.

**Finding.** It replaces basename keying with a compilation-unit registry
(`unit_paths : (string, string list) Hashtbl.t` keyed on `cmt_modname`, a **multimap**,
not last-writer-wins), exposed as `paths_of_unit` / `known_unit_names`. It adds
`'ambiguous_unit'` to the `top_reason` CHECK, and `resolve_qualified_unit` returns
`Resolved` on exactly one distinct id, `Not_found` on zero (external leaf, **not** ⊤),
and `Ambiguous` on two or more — stored as `MAY_TOP` + `ambiguous_unit`
**regardless of `demoted`**. A second "facade" tier matches bare suffix segments,
gated by an `anchor_depth` so it fires only below the deepest reading that already
names an indexed unit. 13 scenarios in a new `tezt/tests/qualified_library_scoping.ml`;
golden recalibrated 782→803 functions, 5062→5168 calls.

**The seam, disclosed by the branch itself.** Its own comment states it does **not**
touch the other two resolution sites: *"THE OTHER TWO RESOLUTION SITES ARE NOT TOUCHED
BY THIS… arch-rules builds its `forbid dep` verdict straight from module_deps, so a
real violation can report pass and a nonexistent one FAIL."* Module-dependency and
type-usage resolution keep the old scheme. So `module_deps.target_module` remains
resolved by the buggy path even after 1.6 merges — which is exactly the column this
task must not trust.

## Q7 [ecosystem] — how OCaml tooling resolves aliases and includes

**Finding.** Coverage is uneven and **no tool exposes the relation as queryable data**.

- **odoc's `@canonical` targets our exact problem**: dune emits
  `(** @canonical Hello.A *) module A = Hello__A`, and odoc reads the tag to render the
  canonical spelling instead of the mangled one — but it "first has to check that the
  specified canonical path actually resolves", and its tracker documents hidden modules
  leaking into output as dead links (odoc#560).
- **merlin's alias-chasing stops one hop short** (merlin#807: `module LL = Llvm` jumps
  to the alias, not to `Llvm`'s definition) and can resolve a module alias to an
  unrelated *variant* of the same name (merlin#647) — a namespace-search-order
  ambiguity, not a soundness argument.
- **merlin / ocaml-lsp expose it only as a jump destination**, odoc only as a rendering
  decision. No source found describes any OCaml tool surfacing the alias/include
  relation as inspectable data for a third party.

## Q8 [ecosystem] — unresolved versus mis-resolved, and how "unknown" is represented

**Finding.** Three patterns exist, and one distinction does **not**.

- **Placeholder nodes**: Soot fabricates *phantom classes/methods* rather than dropping
  the edge; SVF uses a curated `extapi` allowlist of hand-written summaries; SCIP has a
  `local <id>` symbol shape plus an `external_symbols` bucket for "resolved to an
  identity defined outside this index". LSIF by contrast **defines no symbol semantics
  at all** — SCIP's stated motivation for replacing it.
- **Measured unsoundness, not claimed**: 13 Android tools over 1000 apps miss on
  average **61% of dynamically-executed methods** (ISSTA 2024, arXiv:2407.07804); 24%
  of missed JS call edges trace to unmodelled stdlib functions (arXiv:2205.06780).
- **The gap that concerns us**: no retrieved source presents a tool distinguishing
  *"no candidate found"* from *"several unranked candidates"* as two labelled output
  states — everywhere it is one points-to set that happens to have 0, 1 or n members.
  The peer's `ambiguous_unit` is therefore **ahead of the surveyed prior art**, and
  nobody will tell us how to do it.
- **And no source takes a normative position** on whether an honest unknown beats a
  plausible guess. The literature measures unsoundness or describes a schema mechanism;
  it does not argue the trade-off. Our argument has to be our own — and the empirical
  case we hold (a production call resolved to a same-basename test helper, stamped
  MUST) is not in the published record.
