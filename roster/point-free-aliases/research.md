# Research — point-free-aliases

_Generated: 2026-09-04_
_Mode: full (4 parallel specialists)_
_Online research: enabled_

## Question 1: Where are `functions` rows and outgoing call edges recorded?

**Finding:** Functions come from `Tstr_value` bindings; edges are recorded **only** at
`Texp_apply` sites. A value binding whose right-hand side is a bare path produces a
`functions` row and no `calls` row at all — there is no code path that turns a
bare-identifier RHS into an edge.

**References:**
- `lib/arch_index/arch_index_cmt.ml:2298-2390` — `process_cmt`, calls `insert_function` per binding
- `lib/arch_index/arch_index_cmt.ml:1695-1860` — the `Texp_apply` arm; `record_head` classifies the
  callee (`Head_local` / `Head_qualified` / `Head_unknown` / `Head_enumerated`)
- `lib/arch_index/arch_index_cmt.ml:1437-1452` — non-head `Texp_ident`: a `Path.Pident` is treated as
  an escape site **only when it is a stamped lambda** (→ `MAY_ENUMERATED`). A bare module-qualified
  path in a `let` RHS matches nothing here.
- `lib/arch_index/arch_index.ml:436` — the single `INSERT INTO calls`
- `lib/arch_index/arch_index.ml:402` — the single `INSERT OR REPLACE INTO functions`

## Question 2: Schema and versioning

**Finding:** 25 base tables in `architecture-schema.sql`; `current_schema_version = "1.8"` for the
CMT path. `calls` already carries an extensible, CHECK-constrained vocabulary column pattern
(`kind`, `top_reason`) — the precedent for adding a marked edge rather than a new table.

**References:**
- `architecture-schema.sql:183` — `calls` (caller_id, callee_id, call_site, kind, top_reason, top_anchor)
- `lib/arch_index/arch_index_db.ml:52` — `current_schema_version = "1.8"`
- `lib/arch_index/arch_index_support.ml` — `schema_tables_to_drop`; a producer-written table missing
  from it is unsound on re-index (`tezt/tests/schema_drop_list.ml` closes that class)

## Question 3: Every consumer of call edges — **load-bearing for the design decision**

| Consumer | Entry point | Reads via | Filters on `kind`? | NULL `callee_id` |
|---|---|---|---|---|
| `reachable-from` | `arch_query.ml:249` | direct SQL CTE | **No** | excluded by join |
| `reaches` | `arch_query.ml:268` | direct SQL CTE | **Yes — `kind='MUST'`** | excluded |
| `unreachable` / `escapes` | `arch_query.ml:292,334` | direct SQL | Yes (`MUST`,`MAY_ENUMERATED`) | counts as escape |
| `callers-of` / `callees-of` | `arch_query.ml:221,237` | direct SQL | **No** | matched by name |
| `fan-in` | `arch_query.ml:357` | direct SQL | **No** | **counted** |
| `god-modules` | `arch_query.ml:556` | direct SQL | **No** | excluded |
| `may-fail` / `raises` | `arch_query.ml:654,837` | `Arch_exn` | Only `MAY_TOP` special-cased | `ext:` leaf |
| `arch-rules` | `arch_rules.ml:192` | `Arch_graph` | **Yes — the sharpest**: `must_fwd` → VIOLATION, `fwd` → POSSIBLE, `tops` → UNKNOWN | `ext:` leaf |
| `arch-impact` / `arch-coverage` / `arch-mutants` | `arch_impact.ml:213`, `arch_coverage.ml:55`, `arch_mutants.ml:465` | `Arch_graph` | inherited | `ext:` leaf |
| MCP | `arch_mcp.ml:403` | subprocesses the CLIs | inherited | inherited |

**Three findings that decide the design:**

1. **There is no single chokepoint.** `Arch_graph` serves four consumers; `Arch_exn` is a *separate*
   loader; `arch-query`'s own commands go straight to SQL. An alias relation outside the call graph
   would have to be taught to **three** independent readers, not one.
2. **`top_reason` / `top_anchor` are written and read by NOBODY** — repo-wide grep finds no consumer.
   Precedent that a marker column can be added without any consumer changing, and a warning that such
   a column can stay inert indefinitely.
3. **`fan-in` counts every edge kind and does not exclude unresolved callees**; `god-modules` ignores
   `kind` too. Any new edge changes both metrics unless they are taught to exclude it.

**References:** `lib/arch_tools/arch_graph.ml:77-120`; `lib/arch_tools/arch_db.ml:299`
(`kind_sql` = `COALESCE(kind,'MUST')` — legacy NULL reads as MUST); `lib/arch_tools/arch_exn.ml:449-462`.

## Question 4: Qualified-path resolution and homonyms today

**Finding:** `resolve_qualified` tries readings of the dotted path from most- to least-qualified;
the first that resolves wins. `mod_name_to_path` is keyed on **the capitalized basename**
(`api.ml` → `"Api"`) and built with `Hashtbl.replace` — **last-writer-wins**. Two files with the same
basename in different libraries silently collapse onto one, invisibly. No disambiguation by caller's
compilation unit, library, or homonym count.

**References:** `arch_index.ml:655-658` (`module_name_of_path`), `:659-666` (`Hashtbl.replace`),
`:644-654` (`fn_lookup`, keyed `(module_path, function_name)`), `:701-729` (`resolve_qualified`).

## Question 5: What the formatters do on a multi-match name

**Finding:** `may-fail` and `raises` resolve a name to **all** matching keys via
`Arch_exn.keys_of_name` and emit one full verdict block per key. Emission order is
**`ORDER BY f.id` ascending** — not path, not line. **No deduplication.** **The verdict line carries
no file/line**: it is `"<bare name>: <verdict>"`, so two homonyms produce two blocks with an
*identical label* and nothing to tell them apart. (`raisers-of` does print a `file` column;
`may-fail`/`raises` do not use it.) `may-fail`/`raises` are **not exposed over MCP at all**.

**References:** `arch_query.ml:654-721`, `:837-870`; `arch_exn.ml:245-256`, `:500`, `:540-541`.

## Question 6 — **PERISHABLE** (branch `feat/qualified-unit-resolution` @8c1cad0, unmerged)

**Finding:** `resolve_qualified_unit` replaces the basename lookup with `unit_readings`, which
`"__"`-joins prefix segments into a dune compilation-unit name and returns **all** readings (it does
not stop at the first). For each, `Arch_index_cmt.paths_of_unit` gives candidate paths, and
`Hashtbl.find_opt fn_lookup (path, residual)` **is** the "touches the functions table" test. Verdict:
1 distinct id → resolved; 0 → not found (external leaf, deliberately not ⊤); 2+ → `MAY_TOP` with
`top_reason = "ambiguous_unit"`, unconditionally.

**References:** `arch_index.ml:770-798`, `:809-819`, `:918-931` (as of 8c1cad0);
`arch_index_cmt.mli:88-114` (`paths_of_unit`).

## Question 7 [ecosystem]: How other systems model aliasing and re-export

**Finding — the decisive result: NO surveyed system defines a first-class, universally transitive
alias relation distinct from reference/call edges.** Each does one of four things:

| System | Approach |
|---|---|
| **SCIP** | Overloads `Relationship`'s existing flags (`is_reference`, `is_definition`); no alias flag. `is_definition` exists precisely for "symbols which do not have a definition of their own". Consumed automatically by find-references. |
| **LSIF** | No alias edge; cross-package linking via `moniker` + `nextMoniker` chains. Multi-hop chasing not specified. |
| **CodeQL** | Ordinary call edges only at the schema layer. A **library predicate** (`FunctionWithWrappers`: `wrapperFunction`, `outermostWrapperFunctionCall`) is transitive by its own recursion — but `getCallee` does **not** skip wrappers; the query author must opt in. Documented rationale: report the violation at the wrapper call site, not the wrapped function. |
| **Glean** | Deferred to per-language schemas; alias-chasing is an explicit Angle join. |
| **rustc / rust-analyzer** | Re-exports are **resolved away** during name resolution — nothing remains to query. Known divergence between rustc and rust-analyzer precisely on alias edge cases (issues #14079, #11858). |
| **merlin / odoc** | merlin's locate tries to jump through `module N = P` and `let f = M.g` but is documented as incomplete (issue #807). odoc's `@canonical` is **author-declared and never verified** (issue #63). |

Literature: no agreed "alias edge vs call edge" terminology found; forwarding/identity routines are
documented as a source of context-insensitivity imprecision (AutoAlias, arXiv 1808.08748).

**References:** `scip.proto`; LSIF 0.4.0 spec; CodeQL `FunctionWithWrappers.qll`;
glean.software/docs/derived; rust-analyzer issues #14079/#11858; merlin issue #807 and Scherer's
merlin experience report; odoc issue #63 and `Odoc_model.Lang.Module.canonical`;
Garrigue & White, "Type-level module aliases"; arXiv 1808.08748.
