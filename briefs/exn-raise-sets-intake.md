# Intake Brief — exn-raise-sets

**Date:** 2026-09-03
**Status: VALIDATED**
**Type:** feature
**Trust boundary:** no
_(Step 4.5 heuristic fired on the word "evidence" in `roster/exn-raise-sets/task.md`; that is the
project's evidence-gate vocabulary, not an auth/attestation surface. The feature adds a static
analysis and a read-only query. Autonomous-mode decision, recorded here; the human may overturn
it before `/roster-spec` runs.)_

_Validation note: the user requested autonomous handling ("only ask critical questions"). Every
decision below that would normally be a question has an answer derivable from the task record,
the research, or the roadmap; each is recorded with its rationale. The user added two hard
requirements mid-pipeline (handler-aware propagation at call sites; validation on Tezos
`proto_alpha`) — both are binding and appear in Goal / Architecture Notes / Acceptance._

## Goal

Give arch-index a Java-`throws`-style answer for OCaml: for every function node (top-level
bindings and promoted lambda nodes alike), **which exceptions may escape it**, computed with
resolved exception identity from the `.cmt` Typedtree and propagated transitively through the
existing ⊤-marked call graph. The answer is honest in the project's sense — an unresolved fact is
marked ⊤ with a reason (callback/functor-parameter edge, external callee not in the index,
`raise` of a non-literal exception value), never dropped and never presented as "raises nothing".

This is roadmap item 3.4 ("error-handling coverage") in a stronger form than the roadmap's
form-level sketch: the roadmap records `origin`/`handler` *sites* by construct; this task records
the **exception constructor path** at origins, the **caught set** (or catch-all / re-raise) per
handler scope, and — the user's hard requirement — links every **call edge to the handler scope
enclosing the call site**, so that `let g () = try f () with Not_found -> 0` yields
`raises(g) = raises(f) − {Not_found}`. Value: a real may-raise contract for OCaml code that has
none today (research Q9: no working tool exists in the ecosystem), directly usable as an
`arch-rules` gate and as the "handler half" that item 4.2 (`divergence-reachability`) is waiting
on. Acceptance includes a measurement on Tezos `proto_alpha` (closed-world corpus).

## Scope Boundary

What is explicitly OUT of scope:
- OCaml 5 effects (`perform`, `Texp_try` effect cases, `Tpat_exception`-free effect handlers):
  effect arms are not handlers for exceptions and are not recorded; `perform` is not an origin.
- Indexing exception **declarations** (`Tstr_exception`, `Tstr_typext`) as rows in `types` /
  `type_constructors`. Identity is the resolved `Path` string; no FK to a declaration row.
- Data-flow on exception values beyond two idioms: literal constructor argument to
  `raise`/`raise_notrace`, and re-raise of the variable bound by the enclosing handler arm.
  Everything else (`raise e` with `e` a parameter, a `let`-bound exn, a stored exn) is ⊤ with
  reason `unknown_exn_value`.
- Summaries for stdlib / external functions beyond a tiny fixed table (`Stdlib.raise`,
  `raise_notrace`, `failwith`, `invalid_arg`, `exit` → contribute nothing as *callees* because
  their effect is recorded at the origin). `List.hd`, `Hashtbl.find`, `Option.get` etc. stay ⊤
  with reason `external`. A `--assume-externals-pure` hypothesis flag is IN scope (see
  Architecture Notes) so the proto_alpha measurement can be read both ways.
- Closure-flow / functor-parameter resolution (roadmap 3.7). Calls through parameters stay
  `MAY_TOP` → ⊤ with reason `may_top_edge`.
- Changing `calls`/`functions` columns, `schema_version`, or anything in `fix/schema-versioning`'s
  file set. Follow-up recorded for the ship gate: bump `Arch_index_db.current_schema_version` to
  `"1.3"` and add a `docs/schema-versions.md` entry after that PR merges.
- The LSP / Flat-schema producers (`call_graph_extractor.ml`, `arch_load`): they emit no
  exception rows; the query must refuse with a `NOT_ANALYSED` message on such a DB.
- Whole-Octez indexing. `proto_alpha` is the required corpus; the rest is optional.
- SARIF / `arch-report` output (roadmap Phase 2).

## Relevant Files

| File | Role | Key snippet |
|---|---|---|
| `lib/arch_index/arch_index_cmt.ml:456-522` | `call_head`, `pending_call`, `lambda_node`, `lctx` types | `type pending_call = {caller_module; caller_name; head; partial; cond; dead; call_site}` — gains an `exn_scope : int option` field |
| `lib/arch_index/arch_index_cmt.ml:792-878` | walker context, `add_call`, `lambda_name` | `raw := (c.cid, c.lblk, c.lcaller, head, partial, call_site) :: !raw` |
| `lib/arch_index/arch_index_cmt.ml:974-1008` | `noreturn_head`, `diverge` | `path_to_module_name path = (Some "Stdlib", ("raise"\|"raise_notrace"\|"failwith"\|"invalid_arg"\|"exit"))` |
| `lib/arch_index/arch_index_cmt.ml:1054-1080` | lambda promotion, `new_ctx name` | node attribution for anything inside a literal |
| `lib/arch_index/arch_index_cmt.ml:1149-1198` | `Texp_match` / `Texp_try` lowering | `(!cur).lhandlers <- dispatch :: …` — block ids only; patterns discarded |
| `lib/arch_index/arch_index_cmt.ml:1231-1241` | `Texp_assert` | `assert false` → `diverge ()`; other → `walk_conditional` |
| `lib/arch_index/arch_index_cmt.ml:1267-1392` | `Texp_apply`, `record_head`, `noreturn_head` call | origins are recognised here |
| `lib/arch_index/arch_index_cmt.ml:1423-1498` | `walk_function_root`, finalize, return `(calls, lambdas)` | `Tfunction_cases {cases; partial}` — `Partial` ⇒ `Match_failure` origin |
| `lib/arch_index/arch_index_cmt.ml:1650-1935` | `process_item`/`Tstr_value`: insert fn row, walk, insert lambda rows | `function_id` known before the walk; lambda ids only after |
| `lib/arch_index/arch_index_cmt.mli:188-262` | public types + `collect_calls_from_expr` signature | must gain the new field / return value |
| `lib/arch_index/arch_index.ml:181-236, 287-297, 411-480` | prepared statements, `fn_lookup`, kind decision, `insert_call`, `dead_code_sites` write | `Head_unknown _ -> MAY_TOP`; `if call.dead then … exec_stmt ~what:"dead_code_sites"` |
| `lib/arch_index/arch_index_db.ml:102-150, 236-244` | `exec_stmt ~what`, `exec_stmt_rowid`, `bind_*`, `insert_call` | `insert_call` uses `exec_stmt` (no rowid) — needs a rowid-returning variant for scope linking |
| `lib/arch_index/call_graph_extractor.ml:288-320` | second consumer of `collect_calls_from_expr` | discards lambdas; must ignore the new field too |
| `architecture-schema.sql:105-117, 178-196, 242-262` | `calls`, `decisions` (site-shaped precedent), `dead_code_sites` (+ index + view) | new tables follow `decisions`' `form/line/col` shape |
| `lib/arch_tools/arch_graph.ml` | graph load (`#id`/`ext:` keys, `tops`), `closure` | the new fixpoint needs per-edge scope, so it loads its own edge list |
| `lib/arch_tools/arch_db.ml:231-358` | `has_table`, `nonempty`, `require_contract`, `Rows` | refusal + contract idioms |
| `bin/arch_query/arch_query.ml:25-60, 103-151, 265-329, 627` | usage, `q`/`need_contract`/`need_known`, `unreachable`/`escapes`, dispatch fallthrough | new subcommands plug in here |
| `bin/arch_query/arch_effects_queries.ml:33-35, 138-168` | `need_table` refusal, `pure-fns` ⊤ seeding | precedent for "⊤-holder ⇒ cannot certify" |
| `tezt/lib/arch_tezt.ml:327-381, 400-489, 576-663` | `with_fixture`, `index`, `query(_raw)`, `Batch`, `Db` | test harness |
| `tezt/tests/main.ml`, `tezt/tests/dune` | registration (20 `register ()` at `69e5c3d`), deps | add `Exn_raise_sets.register ()` |
| `test/fixtures/self-index-stats.txt`, `docs/adr/001-self-index-golden.md` | golden `modules: 19 / functions: 460 / calls: 3489` | regenerate (new module ⇒ +functions, +calls) |
| `docs/edge-kind-contract.md:83-93` | "termination- and exception-insensitive" residual | update: the CFG stays exception-insensitive; exception identity now lives in the new tables |
| `~/notes/2026-09-01-arch-index-roadmap.md` (3.4, 3.7, 1.4, in-flight list) | roadmap; claim line already added | implementer notes to add under 3.4 |
| `/home/mathias/dev/tezos/tezos/_build/default/src/proto_alpha/lib_protocol/.*objs/` | acceptance corpus (500 `.cmt`, HEAD `1727d7e192f`) | index with `--build-dir` pointed at `lib_protocol` |

## Architecture Notes

**Producer (index time), all in new `lib/arch_index/arch_index_exn.ml` + `.mli`, hooked from
`collect_calls_from_expr` / `process_cmt`:**

1. *Node attribution* reuses the walker's contexts: origins and handler scopes are recorded
   against `(!cur).lcaller`, exactly like calls, so a `raise` inside a nested literal belongs to
   the lambda node and is not covered by the parent's `try`.
2. *Handler scopes.* A lexical stack per context, parallel to `lhandlers`. Pushed for the body of
   `Texp_try` and for the **scrutinee only** of a `Texp_match` that has at least one
   `Tpat_exception` arm; popped after. Each scope: `form ∈ {try, match_exception}`, `line`, `col`,
   `parent` (enclosing scope in the same node, or none), and its arms. Per arm: guarded ⇒ ignored
   (does not catch); pattern → caught set via `Tpat_construct` with `Cstr_extension` (resolved
   path), `Tpat_or` union, `Tpat_alias`/`Tpat_var`/`Tpat_any` ⇒ catch-all; an arm whose RHS
   applies `Stdlib.raise`/`raise_notrace` to the variable the pattern bound (`Tpat_var`/
   `Tpat_alias` ident) is a **re-raise** arm and contributes nothing to the caught set. Scope
   summary: `caught_paths` (union of non-reraise, unguarded, constructor arms) and `catch_all`
   (some unguarded, non-reraise catch-all arm). Effect arms (`eff_cases`) ignored.
3. *Origins*, each with the innermost enclosing scope of its node (or none): saturated
   `Stdlib.raise`/`raise_notrace` (form `raise`) with `exn_path` = resolved constructor path when
   the argument is `Texp_construct` with `Cstr_extension`, or `exn_path` = the caught set's
   forwarding marker when the argument is the ident bound by an enclosing handler arm (recorded
   as `form=reraise`, path NULL, scope = that handler's scope), else NULL (⊤,
   `unknown_exn_value`); `Stdlib.failwith` → `Stdlib.Failure`; `Stdlib.invalid_arg` →
   `Stdlib.Invalid_argument`; `Texp_assert _` → `Stdlib.Assert_failure` (form `assert`);
   `Texp_match`/`Tfunction_cases`/`Texp_function` param with `Partial` → `Stdlib.Match_failure`
   (form `partial_match`). `Stdlib.exit` is not an origin. Path-identity rule: same recogniser as
   `noreturn_head` (persistent `Stdlib` root; local shadowing never matches).
4. *Escape flag* computed at index time per origin: `escapes = not caught by the chain of its
   enclosing scopes` (a catch-all closes; a constructor match closes that path; ⊤ origins are
   closed only by a catch-all).
5. *Call ↔ scope link.* `pending_call` gains `exn_scope : int option` — the walker's local scope
   index; `process_cmt` inserts scope rows first, maps local index → DB id, and rewrites the
   field; `arch_index.ml` inserts the call with a rowid-returning statement and, when the field is
   set, one `call_exn_scopes(call_id, scope_id)` row. `call_graph_extractor.ml` ignores the field.
6. *Exception path string:* `Path.name` of the resolved constructor path, with the same unit-name
   normalisation `path_to_module_name` applies to callees (so `Stdlib.Not_found`,
   `Tezos_raw_protocol_alpha.Storage.Missing_key` style). `let exception E` (non-persistent root,
   local ident) → `local:<Ident.unique_name>` — distinct per binding, never merged by name.
7. *Schema (additive, `IF NOT EXISTS`, in `architecture-schema.sql`; no `schema_version`
   change):* `exn_scopes(id, function_id FK CASCADE, parent_id NULL FK, form, line, col,
   catch_all BOOL)`, `exn_scope_catches(scope_id FK, exn_path TEXT)`, `exn_origins(id,
   function_id FK, scope_id NULL FK, form, exn_path TEXT NULL, escapes BOOL, line, col)`,
   `call_exn_scopes(call_id FK CASCADE, scope_id FK CASCADE)`, plus a
   `comment_db_meta('exn_contract','v1')` flag set by the CMT producer only. Rejections use
   `exec_stmt ~what:"<table>"` so `rejections_by_table` sees them.

**Query (read time), new `lib/arch_tools/arch_exn.ml` + `arch-query` subcommands:**

8. Lattice per node: `Known of PathSet | Top of reason list` (reasons carry a witness:
   `may_top_edge <call_site>`, `external <callee_name>`, `unknown_exn_value <site>`,
   `dropped_node`). Direct set = escaping origins of the node (re-raise origins forward the
   scope's caught set). Edge contribution for `n → m` under scope chain `S` of the call:
   `close_S(raises(m))` where `close_S` returns ∅ if any scope in `S` is `catch_all`, else
   subtracts the union of `caught_paths` (⊤ minus a finite set is ⊤). `MAY_TOP` edge ⇒ `Top`
   unless closed by a catch-all. `ext:` callee ⇒ `Top(external)` unless in the fixed table
   (`Stdlib.raise|raise_notrace|failwith|invalid_arg|exit` ⇒ ∅, since the origin row already
   carries the effect) or `--assume-externals-pure` is given (⇒ ∅, and every output line is
   stamped `UNDER_HYP(externals_pure)` — never a bare `SOUND`). Worklist fixpoint over
   `MUST ∪ MAY_ENUMERATED` edges; monotone and finite, so it terminates.
9. Subcommands: `raises <fn>` (rows `exception | via | how` with `how ∈ {direct, transitive}`,
   then a verdict row `SOUND: {…}` / `UNKNOWN (⊤): {…} + reasons` / `UNDER_HYP(...)`);
   `raisers-of <Exn>` (nodes whose set contains `Exn` or is ⊤, flagged); `exn-stats` (node
   count, share `Known`, share `Top` by dominant reason, origin/scope counts) — the measurement
   command for acceptance. All three: `need_contract ()`; refuse exit 3 with
   `NOT_ANALYSED: this index has no exception sites (producer did not emit them — rebuild with
   arch-callgraph-ocaml)` when `exn_contract` meta is absent; `raises`/`raisers-of` use
   `need_known`. Flat schema ⇒ the same `NOT_ANALYSED` refusal.

**Acceptance corpus.** Index `proto_alpha/lib_protocol` (`--build-dir` at that directory) into
`/mnt/ssd-external-2to/arch-index-runs/proto-alpha-exn.db`; run `exn-stats` with and without
`--assume-externals-pure`; hand-verify ≥ 3 functions (one direct raiser, one `try…with` wrapper
that must close it, one caller through a callback that must be ⊤ with `may_top_edge`). Numbers
and the spot-check transcript go in the ship gate and the roadmap 3.4 notes.

**Decisions taken autonomously (with rationale):**
- Side table `call_exn_scopes` rather than a column on `calls`: keeps the commitment made to the
  parallel schema-versioning session (no `calls`/`functions` column change) and needs no
  `ALTER TABLE` on existing DBs.
- Fixpoint in OCaml, not a recursive CTE: per-edge set subtraction and ⊤-with-reasons do not fit
  SQL's closure idiom (research Q5); `Arch_graph` stays untouched, `Arch_exn` loads its own rows.
- Escape flag stored *and* recomputable: the stored bit is what `exn-stats` and future
  `arch-rules` selectors read cheaply; the query still recomputes from scopes for transitive edges.
- `--assume-externals-pure` shipped now rather than deferred: on `proto_alpha` most leaves are
  protocol-environment calls; without the flag the measurement would be ⊤-dominated and
  uninformative; with the flag it is explicitly a hypothesis (roadmap 3.2 vocabulary).

## Quality Gates

```bash
# Environment (non-negotiable — default switch gives spurious eio/cohttp errors)
eval "$(opam env --switch=/home/mathias/dev/arch-index --set-switch)"

# Build
dune build

# Tests (tezt suite included; --force because dune caches aggressively)
dune test --force

# Lint/Format
# not documented (no .ocamlformat, no fmt step in CI)

# Soundness gate extras (roadmap): self-index + rules + golden
BIN=./_build/default/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe
"$BIN" --build-dir=_build/default/lib/arch_index --db-path=/tmp/self.db --schema-path=architecture-schema.sql
./_build/default/bin/arch_rules/arch_rules.exe /tmp/self.db arch-rules.txt --on-vacuous fail
sqlite3 /tmp/self.db "SELECT 'modules: '||count(*) FROM modules; SELECT 'functions: '||count(*) FROM functions; SELECT 'calls: '||count(*) FROM calls;" | diff test/fixtures/self-index-stats.txt -
```

## Open Questions

- [ ] Exact unit-name normalisation for `exn_path` across compilation units (dune `Unit__Module`
  mangling): implementers must reuse the walker's existing callee normalisation
  (`path_to_module_name` / `resolve_qualified` readings) rather than invent a second one, and
  the spec must state the rule so a raise site in unit A and a handler in unit B agree.
- [ ] Whether `Texp_letop` bodies (`let*`) and `Texp_lazy` thunks should attribute origins to the
  enclosing node (walked in conditional/deferred blocks today) — implementers must treat them
  like any other expression of the node (they *are* the node's code) and not skip them; the
  spec confirms this with a scenario.

_(Both are precise implementation constraints, not TBDs; neither blocks planning.)_
