# Research — exn-raise-sets

_Generated: 2026-09-03_
_Mode: full (Locator/haiku, Analyzer/sonnet, Pattern Finder/haiku, External Researcher/sonnet)_
_Online research: enabled_
_Orientation pack: none (`scripts/code-intel-resolve.js` absent) — blind flow used._
_Note: the Locator read the main checkout instead of the worktree; every fact below was re-verified
against the worktree at `69e5c3d` (e.g. `tezt/tests/main.ml` has 20 `register ()` calls, last two
`Must_null_ceiling`/`Query_limits` at :91-92; there is no `Lsp_doc_comment_lines` registration)._

## Question 1: How are exception constructors, declarations and raise/failwith/invalid_arg/assert expressions recognised during the `.cmt` walk?

**Finding:** Only as *control-flow terminators*, never as identities. `noreturn_head` is a
Path-based, shadow-proof recogniser of the saturated heads `Stdlib.raise | raise_notrace |
failwith | invalid_arg | exit` (root must be the persistent `Stdlib` unit); it is consulted after
`record_head` in the `Texp_apply` case and calls `diverge ()`. `Texp_assert` special-cases
`assert false` (compiler never elides it) → `diverge ()`; an ordinary `assert e` is walked as a
conditional region. Nothing in `lib/`, `bin/` or `lib/arch_effects/` matches `Tpat_exception`,
`Tstr_exception`, `Tstr_typext`, `Texp_letexception` or `Cstr_extension` (grep count 0). Exception
*declarations* are not indexed at all; `Tstr_type` is the only type-level structure item handled.
The `divergence-reachability` branch (not on main) adds a form-level `(kind, call_site)` third
return from the walker and a `divergence_sites` table — still no constructor identity.

**References:**
- `lib/arch_index/arch_index_cmt.ml:974-995` — `noreturn_head fn nargs`: `nargs >= 1`, `Texp_ident path`, `not (qualified_is_dynamic path)`, `path_to_module_name path = (Some "Stdlib", name)`
- `lib/arch_index/arch_index_cmt.ml:1002-1008` — `diverge ()`: edge to innermost `lhandlers` dispatch, `Arch_index_cfg.terminate`, fresh block
- `lib/arch_index/arch_index_cmt.ml:1387-1392` — apply case: `default_iterator.expr` (args first), `record_head ()`, then `if noreturn_head fn_expr nargs then diverge ()`
- `lib/arch_index/arch_index_cmt.ml:1231-1241` — `Texp_assert`: `Texp_construct (_, {cstr_name = "false"; _}, _)` → `diverge`, else `walk_conditional e`
- `lib/arch_index/arch_index_cmt.ml:1937-1960` — `Tstr_type` handling (records/variants/open/abstract); no `Tstr_exception` arm
- `lib/arch_index/arch_index_cmt.ml:913-923` — `path_root`, `qualified_is_dynamic` (non-persistent root ⇒ dynamic)

---

## Question 2: Where are `try…with` / `match…with exception` analysed, and what handler-scope information is kept?

**Finding:** `Texp_try (body, val_cases, eff_cases)` pushes a fresh `dispatch` block on
`(!cur).lhandlers`, walks the body, pops, then edges `body_end → join` and `body_end → dispatch`,
and walks every handler case (value and effect cases alike) in its own block off `dispatch`.
`Texp_match (scrut, comp_cases, val_cases, partiality)` walks every arm uniformly as a CFG branch
with a `Match_failure` bypass edge when `Partial`; `Tpat_exception` computation cases get no
special treatment. Preserved: block ids only (`lhandlers : int list`, innermost first) and the
per-node `lcaller`. Discarded: which patterns a handler matches, guards, whether a handler is a
catch-all, which raise sites a handler could cover. A diverging call inside a try body always
edges to the innermost dispatch regardless of whether that handler matches. `Texp_letop` body is
a conditional region; `Texp_lazy`/`Texp_object`/functor bodies walk in isolated `deferred_blk`s.

**References:**
- `lib/arch_index/arch_index_cmt.ml:511-522` — `lctx` record: `cid`, `lg`, `lblk`, `lhandlers`, `ldeferred`, `lcaller`
- `lib/arch_index/arch_index_cmt.ml:1171-1198` — `Texp_try` lowering
- `lib/arch_index/arch_index_cmt.ml:1149-1170` — `Texp_match` lowering, `walk_case_in` (guard then rhs)
- `lib/arch_index/arch_index_cmt.ml:1046-1052` — `walk_case_in : type k. k Typedtree.case -> unit`
- `lib/arch_index/arch_index_cfg.ml` — `create`, `new_block`, `add_edge`, `terminate`, `solve ~deferred`, `always_exec`, `may_run`

---

## Question 3: Top-level bindings vs promoted lambda nodes — naming, insertion order, attribution

**Finding:** At a nested `Texp_function` visit the walker mints `lambda_name loc` =
`<lcaller>.<fun:LINE:COL>` (1-based col; `#N` suffix on same-position collision via `markers`),
stores it in `lam_names` (loc → name), pushes a `lambda_node {lam_name; lam_line_start;
lam_line_end; lam_arity}`, emits a `Head_enumerated name` occurrence edge unless the literal is a
let-binding RHS (`binding_literals`), and walks the literal's peeled body (`walk_function_root`)
in a **new `lctx`** whose `lcaller = name`. `local_lam_stamps` maps a let-bound literal's
`Ident.unique_name` → `(node_name, arity)` so head applications resolve to the lambda node
(`Head_local node_name`) and non-head occurrences emit `Head_enumerated`. Every raw call is
`(cid, blk, lcaller, head, partial, call_site)`; after solving each context's CFG, `cond`/`dead`
are computed and `pending_call.caller_name = lcaller`. Return value: `(pending_call list,
lambda_node list)`.

In `process_cmt`, the top-level binding's `functions` row is inserted **before** the walk
(`insert_function` → `Some function_id` / `None` → `record_dropped_node`), then
`collect_calls_from_expr` runs, then one `insert_function` per `lambda_node` (`exposed:false`,
`signature:None`), then the calls are appended to `pending_calls`. Lambda rows are keyed by their
synthetic name like any function; `arch_index.ml` resolves callers/callees after all units via
`fn_lookup : (module_path, name) → id`. `call_graph_extractor.ml:288-320` (LSP-fallback flat path)
consumes only the calls half via `pending_display`.

**References:**
- `lib/arch_index/arch_index_cmt.ml:498-508` — `lambda_node` type
- `lib/arch_index/arch_index_cmt.ml:842-878` — `lambdas`, `markers`, `lam_names`, `binding_literals`, `local_lam_stamps`, `lambda_name`
- `lib/arch_index/arch_index_cmt.ml:1054-1080` — promotion + `new_ctx name` + `!walk_fn_body_ref expr`
- `lib/arch_index/arch_index_cmt.ml:1081-1123` — let-bound literal stamping; escape edges
- `lib/arch_index/arch_index_cmt.ml:1423-1468` — `walk_function_root` (peel params, optional defaults in deferred blocks, `Tfunction_cases` arms with Partial bypass)
- `lib/arch_index/arch_index_cmt.ml:1469-1498` — solve + finalize; return `(calls, List.rev !lambdas)`
- `lib/arch_index/arch_index_cmt.ml:1650-1935` — `Tstr_value` arm of `process_item`; parent insert before walk (~1710/1855-1875), lambda inserts after (1905-1932)
- `lib/arch_index/arch_index.ml:287-297,341-343` — `fn_lookup`, `resolve_local`
- `lib/arch_index/call_graph_extractor.ml:288-320` — second consumer (discards lambda nodes)

---

## Question 4: Edge-kind generation rules; NULL callee; dropped nodes

**Finding:** `call_head` = `Head_local` (stamp-resolved same-module fn) | `Head_qualified (module
opt, name)` (persistent-root path) | `Head_enumerated name` (named local fn passed as function
argument / escaping let-bound lambda) | `Head_unknown display` (parameter, computed head, dynamic
root, over-application residual; `"*TOP*"` when nameless). `partial = is_arrow result || nargs <
head_arity`; `cond = not (always_exec verdict blk)`; `dead = not (may_run verdict blk)`. Kind
decision in `arch_index.ml:412-462`: `Head_unknown` → `MAY_TOP` (the only ⊤ source);
`Head_enumerated` → `MAY_ENUMERATED` (or `MAY_TOP` if the target is a dropped node);
`Head_local`/unqualified → `MUST` if resolved and not `demoted (= cond || partial)`,
`MAY_ENUMERATED` if resolved-but-demoted, `MAY_TOP` if unresolved; `Head_qualified` → resolved via
`resolve_qualified` → `MUST`/`MAY_ENUMERATED` per demoted; unresolved → `MAY_TOP` if dropped, else
external leaf with the demoted-computed kind and `callee_id = NULL`. `insert_call` binds NULL for
an absent callee id and always writes `callee_name` + `kind`. `Arch_graph.load` maps NULL callee to
key `ext:<callee_name>`; `MAY_TOP`/`*TOP*`/`ext:*TOP*` rows are **not** edges — they increment
`tops : int SM.t` per caller. `fwd`/`bwd` = MUST ∪ MAY_ENUMERATED; `must_fwd` = MUST only.
Dropped nodes: in-memory `dropped_nodes`/`dropped_units` hashtables (no SQL table), filled when
`insert_function`/`insert_module` reject a row, consulted so an analysed-but-unstored callee
becomes ⊤ instead of a MUST leaf.

**References:**
- `lib/arch_index/arch_index_cmt.ml:456-469` — `call_head`
- `lib/arch_index/arch_index_cmt.ml:1306,1477-1496` — `partial`, `cond`, `dead`
- `lib/arch_index/arch_index.ml:411-462` — `demoted`, kind match
- `lib/arch_index/arch_index_db.ml:236-244` — `insert_call`
- `lib/arch_tools/arch_graph.ml:28-34,77-120` — `t`, `load`, `top_sentinel`, `tops`
- `lib/arch_index/arch_index_cmt.ml:42-62` — dropped tables, `record_dropped_node`, `is_dropped_node`
- `docs/edge-kind-contract.md:5-11,38-39,64,83-93,110` — kind table; deferred bodies; "termination- and exception-insensitive" residual; closure-flow = research R3

---

## Question 5: How `arch-query` computes transitive properties; ⊤ surfacing; `arch_graph`/`arch_db` API

**Finding:** Pure SQL recursive CTEs, one per command, branching on `flat` (Flat: name joins;
Main: id joins). `reaches` = MUST-only closure (kind filter only `if t.kinded`), no contract
needed. `unreachable` = `need_contract ()` + `need_known` both endpoints; closure over
`kind IN ('MUST','MAY_ENUMERATED')`; two EXISTS facts `(hit, escapes)` → REACHABLE / UNKNOWN ("…
reaches a non-resolved (MAY_TOP / NULL / unknown-kind) edge — could-call-anything") / UNREACHABLE
prose built in OCaml. `escapes` = same closure, lists rows whose kind ∉ {MUST, MAY_ENUMERATED}.
`reachable-from` = unfiltered closure. `dead-code` (`arch_effects_queries.ml:169-373`) seeds
roots, closes, and per-row degrades `verdict_soundness` to `candidate (MAY_TOP reachable …)`.
Effects: `mutators-of`/`effects-of` require `function_effects` (`need_table` → exit 3 with the
migration command), close over MUST/MAY_ENUMERATED; `pure-fns` seeds the *impure* backward
closure with every function holding a `MAY_TOP` edge (⊤ ⇒ not certifiably pure). Shared
idioms: `q ~h ~shape ~cells ~pty sql params` = `Arch_db.rows` + `Arch_fmt.print`; `need_contract`
→ `Arch_db.require_contract` (raises `Refused` → exit 3 when no `callgraph_contract` meta, no
`kind` column, or any NULL/invalid kind); `need_known role name`. `Arch_db.t = {conn; path;
schema; kinded; contract}`; `open_ro` detects Flat by `calls.caller_name`; `kind_sql` =
`COALESCE(kind,'MUST')` or `'MUST'`; `nonempty t table` = exists ∧ count>0; `Rows.tN`/`cN` Caqti
shapes + cell projectors; `count2`, `find`, `has_table`, `has_col`. `Arch_graph.closure seeds adj`
= worklist DFS excluding seeds; `label g key` strips `ext:`.

**References:**
- `bin/arch_query/arch_query.ml:25-60` — usage text listing subcommands
- `bin/arch_query/arch_query.ml:103-151` — `flat`, `q`, `str1/str2`, `need_contract`, `known`, `need_known`
- `bin/arch_query/arch_query.ml:222-329` — `reachable-from`, `reaches`, `unreachable`, `escapes`
- `bin/arch_query/arch_query.ml:367-405` — `stats` (row counts + contract status; `has_table` guards)
- `bin/arch_query/arch_query.ml:627` — fallthrough to `Arch_effects_queries.dispatch`
- `bin/arch_query/arch_effects_queries.ml:15-35,68-168,169-373` — `suffix_match`, `need_table`, effects queries, `dead-code`
- `lib/arch_tools/arch_graph.ml:19-150` — full module
- `lib/arch_tools/arch_db.ml:39-49,97-201,207,231-264,276-305,318-358` — types, `Rows`, `rows`, introspection, `open_ro`, `kind_sql`, `count2`, `require_contract`, `contract_ok`, `nonempty`
- `lib/arch_tools/arch_fmt.ml` — `print fmt headers rows`

---

## Question 6: Per-function attribute tables — declaration, insertion, read-back

**Finding:** Pattern A (indexer-owned, id-keyed): `dead_code_sites(id, function_id NOT NULL FK
CASCADE, call_site, callee_name, created_at)` in `architecture-schema.sql:242-248`; prepared once
in `Arch_index.run` (`arch_index.ml:213-217`), bound with `Arch_index_db.bind_int/bind_text`, and
executed with `exec_stmt db ~what:"dead_code_sites"` (the `~what` label is mandatory and feeds
`rejections_by_table`); written in the resolution loop when `call.dead` (`arch_index.ml:476-480`)
and counted in `n_dead_sites`. Read in `arch-query dead-blocks` behind `Arch_db.has_table`
(`arch_query.ml:391-393`, joins `functions`/`modules`). `decisions(function_id, file_path, line,
col, form, arity, verdict, decided_by, evidence, snippet)` (`:178-196`) is the site-shaped
precedent with `form` + `line`/`col` columns. `coverage` (`:264-277`) is keyed by function_id with a
`UNIQUE(function_id, recorded_at)`. Pattern B (sidecar producer, name-keyed): `function_effects`
(`effects-schema-migration.sql:43-85`, `function_id` nullable, `function_name`/`file_path`,
`soundness CHECK IN ('sound','candidate','manual')`, `producer`, unique identity index) loaded by
`bin/arch_effects_load` via `Effects_db` with `INSERT OR IGNORE` and `lookup_fn_id` by name.
Views: `v_dead_code_sites`, `v_open_tasks`, `v_violation_graph` in the main schema. `Arch_index.result`
(`arch_index.mli:15-40`) exposes per-table counts plus `rejections_by_table`.

**References:**
- `architecture-schema.sql:105-117,178-196,242-262,264-277` — `calls`, `decisions`, `dead_code_sites` (+ index/view), `coverage`
- `lib/arch_index/arch_index.ml:181-236` — all `Sqlite3.prepare` statements; `:213-217` `stmt_dead`; `:476-480` write site
- `lib/arch_index/arch_index_db.ml:102-150,155-262` — `exec_stmt_ok/exec_stmt/exec_stmt_rowid`, `bind_*`, `insert_*` helpers
- `lib/arch_index/arch_index.mli:15-40` — `result`
- `lib/arch_effects/effects_db.ml:127-154` — sidecar insert pattern
- `bin/arch_query/arch_query.ml:387-393` — `stats`/`dead-blocks` guarded reads

---

## Question 7: Flat/NDJSON schema behaviour for unpopulated tables; "not analysed" precedent

**Finding:** Schema is detected at open (`Flat` iff `calls.caller_name` exists). Absence vs
emptiness: `Arch_db.has_table` (sqlite_master probe) vs `Arch_db.nonempty` (exists ∧ count>0;
documented because `arch-load` creates every table unconditionally so existence proves nothing).
Every optional-analysis query refuses with exit 3 and an actionable message when its table is
absent (`need_table`, effects: "requires the effects tables. Run: sqlite3 <db> <
effects-schema-migration.sql && arch-effects-load <db>"; capabilities: "requires Phase-2 tables.
Run the migration first"); `stats` prints `has_table`-guarded counts. There is no literal
`NOT_ANALYSED` token anywhere yet (roadmap item 1.3 introduces it); the existing precedent is
"refuse loudly with the remedy" rather than returning zero rows. `require_contract` is the same
discipline for ⊤-marking. The Flat schema has no `functions.id`, keys are global names.

**References:**
- `lib/arch_tools/arch_db.ml:276-292` — `open_ro`, schema/kinded/contract detection
- `lib/arch_tools/arch_db.ml:231-253,357-358` — `has_table`, `has_col`, `nonempty`
- `bin/arch_query/arch_effects_queries.ml:33-35,68-72,108-109,379,401,412` — refusal messages
- `lib/arch_db/arch_load.ml:58-66` — kind validation on load (rejects invalid kind)

---

## Question 8: tezt fixtures/helpers, registration, self-index golden

**Finding:** `Arch_tezt` (tezt/lib/arch_tezt.ml) provides `with_fixture ~name ~files k` (writes a
dune project, `dune build --root`, yields `{name; root; build_dir}`), `index fixture` (runs
`arch_callgraph_ocaml.exe --build-dir … --db-path … --schema-path …`, fails on non-zero),
`index_project` (LSP path), `query db args` / `query_raw db args` (`ARCH_QUERY_FORMAT=list`;
`query` fails on non-zero, `query_raw` returns `(code, output)`), `Db.with_db` (read-only),
`Db.rows/int/int_opt/string_opt/strings`, `Batch.run` collecting `note/check/eq_int/ge_int/
eq_string/eq_string_opt/contains`, `Fixture.dune_project`, `Fixture.flat` (NDJSON via arch_load),
`Fixture.raw`, `Fixture.main ?seed`, `Fixture.malformed_contract`. Tests: `let register () =
Test.register ~__FILE__ ~title ~tags @@ fun () -> … ; Lwt.return_unit`, registered in
`tezt/tests/main.ml` (20 calls at `69e5c3d`, `Tezt.Test.run ()` last); `tezt/tests/dune` lists every
binary and `../../architecture-schema.sql` as deps. Golden: `test/fixtures/self-index-stats.txt` =
`modules: 19 / functions: 460 / calls: 3489`, checked only by the CI "Self-index smoke test"
(`.github/workflows/ci.yml:83-96`, indexes `_build/default/lib/arch_index`); ADR 001 gives the
regeneration recipe (index self, three `count(*)` selects, commit).

**References:**
- `tezt/lib/arch_tezt.ml:327-381,400-489,576-663,673-766` — fixtures, Batch, Db, Fixture
- `tezt/tests/callgraph_soundness.ml:316-342`, `tezt/tests/callgraph_nested.ml:159-251` — full test examples
- `tezt/tests/main.ml:8-93`, `tezt/tests/dune:32-53`
- `docs/adr/001-self-index-golden.md`, `test/fixtures/self-index-stats.txt`, `.github/workflows/ci.yml:83-96`

---

## Question 9: [ecosystem] Prior art for exception identity / handler coverage in analysers

**Finding:** The direct precedent is Pessaux & Leroy, "Type-based analysis of uncaught
exceptions" (POPL 1999 / TOPLAS 2000; implementation OCamlExc, now `OCamlPro/ocamlexc`, research
prototype): exception sets are **row types** on function types with row *variables* giving
polymorphism — a HOF inherits its argument's row without knowing the closure's identity (the
mechanism Koka later generalised; Koka's docs frame Java `throws` as its non-polymorphic special
case). Unknown exception values surface as unresolved row variables ("raises whatever the argument
raises"), not as failure; handler coverage is subtractive on rows, not path-sensitive. Yi (SML)
used abstract interpretation / 0-CFA over exception values, later a sparse variant; Guzmán &
Suárez (SML) constraint-based with the PAM raise/catch visualiser. Java: checked exceptions are a
compiler discipline; tools (Infer, Checker Framework, SpotBugs, IntelliJ inspections) lint the
discipline (swallowed/over-broad catches, redundant throws) rather than infer sets; one academic
"uncaught exception analysis for Java" propagates unchecked exceptions over a call graph. Kotlin
has no throws. Go `errcheck` and Python bare-except lints check handler *shape*, not identity.
Today's OCaml ecosystem (Merlin, ocaml-lsp, Semgrep OCaml rules, Jane Street tooling) ships no
may-raise reporter; convention is `@raise` in odoc comments.

**References:**
- https://xavierleroy.org/publi/exceptions-popl.pdf — Pessaux & Leroy, POPL 1999
- https://dl.acm.org/doi/10.1145/349214.349230 — TOPLAS 2000 version
- https://github.com/OCamlPro/ocamlexc — OCamlExc
- https://link.springer.com/chapter/10.1007/3-540-58485-4_44 ; https://link.springer.com/chapter/10.1007/BFb0032736 — Yi, SML exception analyses
- https://www2.eecs.berkeley.edu/Pubs/TechRpts/1998/5561.html — Guzmán & Suárez, PAM
- https://dl.acm.org/doi/10.1145/372202.372786 — interprocedural exception analysis for Java
- https://www.jetbrains.com/help/inspectopedia/ThrowsRuntimeException.html — IntelliJ inspection family
- https://github.com/kisielk/errcheck — Go errcheck
- https://koka-lang.github.io/koka/doc/book.html ; https://arxiv.org/abs/1406.2061 — Leijen, Koka row-polymorphic effects
- https://registry.semgrep.dev/ruleset/ocaml — Semgrep OCaml (pattern-only)

---

## Question 10: [ecosystem] OCaml 5.3 Typedtree/Types constructors for exceptions

**Finding:** From `_opam/lib/ocaml/compiler-libs` (5.3.0): `Texp_construct of Longident.t loc *
Types.constructor_description * expression list` (`typedtree.mli:232-237`); exception-ness is
`cstr_tag = Cstr_extension of Path.t * bool` (`types.mli:684-689`, `Path.t` = the constructor's
path, bool = constant form). Patterns: `Tpat_construct` (`:93-104`), `Tpat_exception : value
general_pattern -> computation pattern_desc` (`:141-142`), `Tpat_or` (`:144-151`), `Tpat_any`
(`:79-80`), `Tpat_var` (`:81-82`), `Tpat_alias` (`:83-85`); `case = {c_lhs; c_guard : expression
option; c_rhs}` (`:295-301`). `Texp_try of expression * value case list * value case list`
(`:224-229`; exception cases, then effect cases). `Texp_match of expression * computation case
list * value case list * partial` (`:214-223`). `Texp_assert of expression * Location.t` (`:274`).
`Texp_letexception of extension_constructor * expression` (`:273`). `Tstr_typext of
type_extension | Tstr_exception of type_exception` (`:474-475`; `type_exception =
{tyexn_constructor; tyexn_loc; tyexn_attributes}` `:763-768`). `type partial = Partial | Total`
(`:29`), on `Texp_match`, `Tfunction_cases.partial` (`:340`), `function_param.fp_partial`
(`:310-315`). `extension_constructor = {ext_id : Ident.t; ext_name; ext_type :
Types.extension_constructor; ext_kind = Text_decl of string loc list * constructor_arguments *
core_type option | Text_rebind of Path.t * Longident.t loc; ext_loc; ext_attributes}`
(`:770-782`). `Path.t = Pident | Pdot of t * string | Papply | Pextra_ty` (`path.mli:18-27`): an
exception `E` in module `M` of unit `U` is `Pdot (Pdot (Pident U, "M"), "E")` with `U` persistent
(`Ident.persistent`, `ident.mli:46`; created by `create_persistent`); a `let exception E` is
`Pident local_id` (scoped/local ident), distinguished by `Ident.same`, not by name. Predefined
exceptions (`Not_found`, `Failure`, `Invalid_argument`, `Match_failure`, `Assert_failure`) are
`Pident` of predef idents (`Ident.persistent` true via `create_predef`).

**References:**
- `_opam/lib/ocaml/compiler-libs/typedtree.mli:29,79-104,141-151,214-237,273-274,295-301,310-315,340,474-475,752-782`
- `_opam/lib/ocaml/compiler-libs/types.mli:558-568,667-696`
- `_opam/lib/ocaml/compiler-libs/path.mli:18-27`, `ident.mli:33-58`
- https://ocaml.org/manual/5.3/ ; https://github.com/ocaml/ocaml/blob/5.3/typing/typedtree.mli
