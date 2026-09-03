# Implementer sub-brief — exn-raise-sets

**Status: VALIDATED**
**Read also:** `specs/exn-raise-sets.md` (normative: Clarifications, FR-001..020, AC-1..14),
`briefs/exn-raise-sets-plan.md` (slices A–H), `roster/exn-raise-sets/research.md` (file:line map).

## Environment

- Worktree `/tmp/claude-1000/-home-mathias-dev-arch-index/31263480-e1a5-4466-ad8a-8603e6671282/scratchpad/wt-exn`, branch `feat/exn-raise-sets` (off `origin/main` `69e5c3d`). Never edit `/home/mathias/dev/arch-index`.
- `eval "$(opam env --switch=/home/mathias/dev/arch-index --set-switch)"` before every build; `dune build`; `dune test --force`.
- OCaml 5.3.0. Compiler-libs facts: `Texp_ident (path, lid, vd)` with `vd.val_kind = Val_prim {prim_name; _}`; `Texp_try (body, val_cases, eff_cases)`; `Texp_match (scrut, comp_cases, val_cases, partial)`; `Tpat_exception : value general_pattern -> computation pattern_desc`; `Texp_construct (_, {cstr_tag = Cstr_extension (path, _); _}, args)`; `Texp_assert (e, loc)`; `Texp_letexception (ext, body)`; `Tstr_exception {tyexn_constructor; _}`, `Tstr_typext {tyext_constructors; _}`, `extension_constructor = {ext_id; ext_name; ext_kind = Text_decl _ | Text_rebind (path, _); _}`; `Tfunction_cases {cases; partial; _}`; `function_param.fp_partial`; `Ident.is_predef`, `Ident.persistent`, `Ident.unique_name`.

## Goal

Per function node (top-level binding or promoted lambda), record exception origins with resolved
identity, handler scopes with caught sets, and the scope enclosing each call; at query time
compute the transitive, handler-aware may-raise set with ⊤ reasons. See spec Clarifications for
every semantic rule — do not re-derive them.

## Scope boundary

Out: effects, exception declarations as entities, dataflow beyond literal/bound-variable, stdlib
summaries beyond the fixed table, closure-flow, `calls`/`functions` column changes,
`schema_version`, `lib/arch_index/runner.ml`, the schema-version parts of
`arch_index_db.ml/.mli` and `arch_index.mli`, SARIF.

## Schema (Slice A) — `architecture-schema.sql`, additive, after `dead_code_sites`

```sql
CREATE TABLE IF NOT EXISTS exn_scopes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    function_id INTEGER NOT NULL REFERENCES functions(id) ON DELETE CASCADE,
    parent_id INTEGER REFERENCES exn_scopes(id) ON DELETE CASCADE,
    form TEXT NOT NULL CHECK(form IN ('try','match_exception')),
    line INTEGER NOT NULL, col INTEGER NOT NULL,
    catch_all BOOLEAN NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS exn_scope_catches (
    scope_id INTEGER NOT NULL REFERENCES exn_scopes(id) ON DELETE CASCADE,
    exn_path TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS exn_origins (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    function_id INTEGER NOT NULL REFERENCES functions(id) ON DELETE CASCADE,
    scope_id INTEGER REFERENCES exn_scopes(id) ON DELETE SET NULL,
    form TEXT NOT NULL CHECK(form IN ('raise','reraise','unknown','failwith','invalid_arg','assert','partial_match')),
    exn_path TEXT,
    escapes BOOLEAN NOT NULL DEFAULT 1,
    line INTEGER NOT NULL, col INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS call_exn_scopes (
    call_id INTEGER NOT NULL REFERENCES calls(id) ON DELETE CASCADE,
    scope_id INTEGER NOT NULL REFERENCES exn_scopes(id) ON DELETE CASCADE,
    PRIMARY KEY (call_id)
);
CREATE TABLE IF NOT EXISTS exn_rebinds (
    alias_path TEXT NOT NULL, target_path TEXT NOT NULL, PRIMARY KEY (alias_path)
);
CREATE INDEX IF NOT EXISTS idx_exn_scopes_fn ON exn_scopes(function_id);
CREATE INDEX IF NOT EXISTS idx_exn_origins_fn ON exn_origins(function_id);
CREATE INDEX IF NOT EXISTS idx_exn_scope_catches_scope ON exn_scope_catches(scope_id);
```
Meta: `INSERT OR REPLACE INTO comment_db_meta VALUES ('exn_contract','v1')` next to the existing
`callgraph_contract` write in `arch_index.ml:~494`.

## Producer — `lib/arch_index/arch_index_exn.ml` (+ `.mli`)

Pure, walker-agnostic API (no Sqlite, no CFG):

```ocaml
type form = Raise | Reraise | Unknown | Failwith | Invalid_arg | Assert | Partial_match
type origin = { o_form : form; o_path : string option; o_scope : int option; o_line : int; o_col : int }
type scope  = { s_id : int; s_parent : int option; s_form : [`Try | `Match_exception];
                s_line : int; s_col : int; s_catch_all : bool; s_caught : string list;
                s_bound : string list (* Ident.unique_name of arm-bound idents, for reraise *) }
type node_acc  (* per-context accumulator: scopes, origins, current scope stack *)
val create : unit -> node_acc
val enter_scope : node_acc -> form:[`Try|`Match_exception] -> loc:Location.t
                  -> arms:Typedtree.value Typedtree.case list -> int   (* returns local scope id *)
val leave_scope : node_acc -> unit
val current_scope : node_acc -> int option
val record_raise_head : node_acc -> canon:(Path.t -> string) -> args:(Asttypes.arg_label * Typedtree.expression option) list -> loc:Location.t -> unit
val record_assert : node_acc -> loc:Location.t -> unit
val record_partial : node_acc -> loc:Location.t -> unit
val is_raise_head : Typedtree.expression -> bool   (* Val_prim %raise|%raise_notrace|%reraise *)
val stdlib_head : Typedtree.expression -> [`Failwith|`Invalid_arg|`Raise_with_backtrace] option
val finalize : node_acc -> scope list * origin list   (* computes escapes *)
val canonical_path : unit_declared:(string -> string option) -> cmt_modname:string -> Path.t -> string
val classify_arms : canon:(Path.t -> string) -> Typedtree.value Typedtree.case list -> catch_all:bool * caught:string list * bound:string list
val arm_is_closing : Typedtree.value Typedtree.case -> bool   (* unguarded && no raise-head applied to a non-literal in c_rhs *)
val rebind_of : Typedtree.extension_constructor -> (string * string) option
```

Rules (from the spec, restated as code obligations):
- `is_raise_head`: `Texp_ident (_, _, {val_kind = Val_prim {prim_name = "%raise"|"%raise_notrace"|"%reraise"; _}; _})`. Also treat `Stdlib.Printexc.raise_with_backtrace` (Path-keyed, persistent `Stdlib` root) as a raise head on its **first** argument.
- `stdlib_head`: the existing `path_to_module_name` + `qualified_is_dynamic` rule (`arch_index_cmt.ml:913-923, 546-556`): `(Some "Stdlib", "failwith"|"invalid_arg")`.
- `record_raise_head`: arg `Texp_construct (_, {cstr_tag = Cstr_extension (p, _); _}, _)` → `Raise` with `canon p`; arg `Texp_ident (Pident id, _, _)` with `Ident.unique_name id ∈ s_bound` of an enclosing scope → `Reraise` (scope = that one); else `Unknown`. Unsaturated (`args = []`) → nothing.
- `arm_is_closing`: `c_guard = None` and a `Tast_iterator` over `c_rhs` finds no `Texp_apply` whose head `is_raise_head` and whose first argument is not a literal `Cstr_extension` construct.
- `classify_arms`: only closing arms contribute; pattern → `Tpat_construct` extension → path; `Tpat_or (a, b, _)` → union; `Tpat_alias (p, _, _, _)` → recurse; `Tpat_any | Tpat_var _` → catch_all; else nothing. `s_bound` collects `Tpat_var`/`Tpat_alias` idents of **all** arms (closing or not) for reraise detection.
- `canonical_path`: root `Ident.is_predef` → `Path.name`; root `Ident.persistent` → `Path.name`; `unit_declared (Ident.unique_name root) = Some q` → `cmt_modname ^ "." ^ q ^ rest`; else `"local:" ^ Ident.unique_name root ^ rest`. `rest` = the `Pdot` tail joined with `.`; `Papply`/`Pextra_ty` → `local:` form with `Path.name`.
- `finalize`: `escapes` = walk `o_scope` → `s_parent` …: stop with `false` at a `catch_all` scope or a scope whose `s_caught` contains `o_path`; `Unknown` origins are closed only by catch_all; `Reraise` origins keep `escapes = 1`.

## Hooks in `lib/arch_index/arch_index_cmt.ml` (keep them to these sites)

1. `pending_call` (`:472-488`): add `exn_scope : int option` (local scope id, rewritten to the DB id in `process_cmt`). `raw` tuple and the finalize `List.rev_map` (`:1477-1496`) carry it via `Arch_index_exn.current_scope (!cur).lexn`.
2. `lctx` (`:511-522`): add `lexn : Arch_index_exn.node_acc` (one per context, created in `new_ctx`).
3. `Texp_try` (`:1171-1198`): `let sid = Arch_index_exn.enter_scope c.lexn ~form:`Try ~loc ~arms:val_cases in` before `self.expr self body`; `leave_scope` right after; handlers walked outside the scope.
4. `Texp_match` (`:1149-1170`): if any `comp_cases` pattern is `Tpat_exception` → `enter_scope ~form:`Match_exception ~arms:(exception arms as value cases)` around `self.expr self scrut` only. If `partiality = Partial` → `record_partial`.
5. `Texp_assert` (`:1231-1241`): `record_assert` in both arms.
6. `Texp_apply` (`:1384-1392`, after `record_head ()`): if `is_raise_head fn_expr` or `stdlib_head fn_expr <> None` → `record_raise_head` / record `Failwith`/`Invalid_arg` origins. Keep `noreturn_head`/`diverge` unchanged.
7. `walk_function_root` (`:1445-1460`): `Tfunction_cases` with `partial = Partial` → `record_partial` at the root; `fp_partial = Partial` on a param → `record_partial`.
8. Return value: `collect_calls_from_expr` returns `(calls, lambdas, exn_by_node)` where `exn_by_node : (string * (scope list * origin list)) list` keyed by `lcaller` (from `!all_ctxs`). Update `arch_index_cmt.mli:246-261` and `call_graph_extractor.ml:288-300` (ignore third component).
9. `process_cmt` `Tstr_value` arm (`:1893-1934`): after lambda rows exist, build `name → function_id` for the parent and every lambda; for each node: insert scopes in local-id order (parent before child — ids are minted in enter order so this holds), keep `local → db id`; insert `exn_scope_catches`; insert origins with mapped `scope_id`; then rewrite each pending call's `exn_scope` from local to DB id (calls are keyed by `caller_name` = node name). Prepared statements are passed in like `stmt_ctor` (add `stmt_scope`, `stmt_catch`, `stmt_origin`, `stmt_rebind`).
10. Structure walk (`process_item`, `:1606-1935`): on `Tstr_exception` / `Tstr_typext` register `Ident.unique_name ext_id → qualify ~prefix name` in a `unit_declared` table (also `Tstr_module` ids → `qualify ~prefix (Ident.name id)`), and write `exn_rebinds` for `Text_rebind`. The table must be filled **before** value bindings are walked (two passes over items, or register during `iter_structure_items` which already runs first — check `build_local_fn_stamps` at `:675-790` for the precedent).

## `lib/arch_index/arch_index.ml`

- Prepare `stmt_call` unchanged; add `insert_call_rowid` in `arch_index_db.ml` (same binds, `exec_stmt_rowid ~what:"calls"`), export in the `.mli` **without touching other declarations**.
- In the resolution loop (`:411-480`): after the call insert, `match call.exn_scope with Some sid -> bind + exec_stmt ~what:"call_exn_scopes" | None -> ()`.
- Write `exn_contract` meta beside `callgraph_contract` (`:494`). Report `n_exn_origins`/`n_exn_scopes` in the printed summary (do not change the `result` record — it is in `arch_index.mli`; print only).

## Query — `lib/arch_tools/arch_exn.ml` (+ `.mli`) and `bin/arch_query/arch_query.ml`

- `Arch_exn.load : Arch_db.t -> t` reads `functions` (key `'#'||id`, name, file), `calls` with `LEFT JOIN call_exn_scopes` (caller, callee or `ext:name`, kind, scope_id), `exn_scopes`, `exn_scope_catches`, `exn_origins`, `exn_rebinds`. Refuse (`Arch_db.refuse`-style, exit 3) with `NOT_ANALYSED: this index has no exception sites — rebuild with arch-callgraph-ocaml` when `comment_db_meta.exn_contract` is absent or schema is `Flat`.
- Lattice `type set = Known of SS.t | Top of reason list` with `reason = {kind : [`May_top_edge|`External|`Unknown_exn_value|`Dropped_node]; witness : string}`; `join`, `close chain set`.
- `solve : ?assume_externals_pure:bool -> t -> set SM.t` worklist: init `D(n)`; on pop, recompute `n` from edges; push predecessors on change. Deterministic order (sorted keys).
- `raises t fn`, `raisers_of t exn`, `stats t` produce rows for `Arch_fmt.print`.
- `arch_query.ml`: add three arms before the `_ ->` fallthrough (`:627`); flag parsing: accept `--assume-externals-pure` anywhere after the subcommand (mirror the `--roots` handling in `arch_effects_queries.ml:169-362`); call `need_contract ()` then `Arch_exn.load`; `need_known` for `raises`. Update `usage` (`:25-60`).
- Output shapes (spec FR-012, FR-016, FR-017): headers `["exception"; "via"; "how"]` then `["verdict"]`; `raisers-of`: `["function"; "file"; "how"]` then a `["top_function"; "reason"]` block; `exn-stats`: `["metric"; "value"]`.

## Tests — `tezt/tests/exn_raise_sets.ml`

One fixture library `testexn` covering US-1.1–1.8 and US-2/US-3 scenarios, plus a second library
`testexn_other` (same dune project) for US-1.9 (cross-unit canonical path) and US-1.10 (a local
`external my_raise : exn -> 'a = "%raise"` and a local `let failwith _ = 0`). Assertions: SQL via
`Db.*` for US-1; `query`/`query_raw` text via `Batch.contains`/`eq_string` for US-2/3; Flat refusal
via `Fixture.flat ~name Fixture.minimal_flat_stream`; pre-feature refusal via `Fixture.main` seeded
without `exn_contract`. Register `Exn_raise_sets.register ()` in `tezt/tests/main.ml`. Red first:
commit the test before the producer compiles it green (CHECK-1).

## Docs (Slice G)

`docs/exception-raise-sets.md` (semantics, tables, verdicts, residual list from spec Edge Cases +
"environment `failwith` is external ⊤"), `docs/edge-kind-contract.md:83-93` add a pointer,
`~/notes/2026-09-01-arch-index-roadmap.md` item 3.4 implementer notes, golden regeneration per
`docs/adr/001-self-index-golden.md`.

## Quality gates

```bash
eval "$(opam env --switch=/home/mathias/dev/arch-index --set-switch)"
dune build
dune test --force
BIN=./_build/default/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe
$BIN --build-dir=_build/default/lib/arch_index --db-path=/tmp/self.db --schema-path=architecture-schema.sql
./_build/default/bin/arch_rules/arch_rules.exe /tmp/self.db arch-rules.txt --on-vacuous fail
sqlite3 /tmp/self.db "SELECT 'modules: '||count(*) FROM modules; SELECT 'functions: '||count(*) FROM functions; SELECT 'calls: '||count(*) FROM calls;" | diff test/fixtures/self-index-stats.txt -
git diff origin/main --stat -- lib/arch_index/runner.ml   # must be empty
```

## Risks to keep in view

Scope-stack/CFG drift (one hook per site; add a `let%test` asserting balanced enter/leave);
insertion order for ids (parent row → walk → lambda rows → scopes → catches → origins → calls
later with links); canonical path across units (Slice E fixture); fixpoint time (print it in
`exn-stats`).
