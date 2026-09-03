# Research — error-channels

_Generated: 2026-09-03_
_Mode: full (Analyzer/sonnet, Locator/haiku, Pattern Finder/haiku, External/sonnet)_
_Online research: enabled_
_Orientation pack: none — blind flow. Baseline reused: `roster/exn-raise-sets/research.md` (walker, lattice, tables, query idioms)._

## Question 1: Tezos protocol-environment error monad as seen by `proto_alpha`

**Finding:** `src/proto_alpha/lib_protocol/dune:18` generates `Tezos_protocol_environment_alpha` as
`include Tezos_protocol_environment.V17.Make(Name)()` — environment **V17**, whose signature comes
from `src/lib_protocol_environment/sigs/v17.in.ml:50` (`module Error_monad : [%sig
"v17/error_monad.mli"]`, then `open Error_monad`). In `sigs/v17/error_monad.mli`: `type error = ..`
(:31); `type 'err trace` (:69, opaque); `type 'a tzresult = ('a, error trace) result` (:71);
`error : 'err -> ('a, 'err trace) result` (:97); `tzfail : 'err -> ('a, 'err trace) result Lwt.t`
(:101); `record_trace` / `trace` / `trace_eval` (:103-114); `catch` (:147), `catch_f` (:155),
`catch_s` (:174); `register_error_kind` (:39-48); `return`/`return_unit`… (:81-95). **Absent from
the V17 protocol surface:** `catch_e`, `protect`, `error_with`, and every legacy infix (`>>=?`,
`>>?`, `>|=?` appear only in doc comments of `sigs/v17/map.mli:83,94`). Binding operators are nested
submodules of `Error_monad`: `Lwt_syntax` (:201-241: `let*`, `and*`, `let+`, `and+` over `Lwt.t`),
`Result_syntax` (:267-310: `let*`, `and*`, `tzfail`, `tzjoin`, `tzall`, `tzboth` over `result`),
`Lwt_result_syntax` (:312-375: `let*`, `and*` over `('a,'e) result Lwt.t`, `let*!` lifting `Lwt.t`
(:339), `let*?` lifting `result` (:341), `tzfail` (:353)). `.cmt` facts (`ocamlobjinfo` on
`.tezos_raw_protocol_alpha.objs/byte/…Adaptive_issuance_costs.cmt`): compiled with `-open
Tezos_protocol_environment_alpha -open …alpha.Pervasives -open …alpha.Error_monad`; the environment
unit's own `.cmt` (`.tezos_protocol_environment_alpha.objs/byte/`) references
`Tezos_protocol_environment_sigs__V17` / `Tezos_protocol_environment__Environment_V17`. Resolved
paths print as `Tezos_protocol_environment_alpha.Error_monad.error`, `….Error_monad.tzfail`,
`….Error_monad.Lwt_result_syntax.let*`, `….Error_monad.tzresult`.

**References:** `src/proto_alpha/lib_protocol/dune:18`; `src/lib_protocol_environment/sigs/v17.in.ml:50`; `src/lib_protocol_environment/sigs/v17/error_monad.mli:31,39-48,69,71,81-95,97,101,103-114,147,155,174,201-241,267-310,312-375`; `src/lib_protocol_environment/environment_protocol_T.ml:176` (shell-side `error_with`, not V17).

---

## Question 2: `let*` / infix binds in the Typedtree and the walker

**Finding:** `Texp_letop {let_; ands; param; body; partial}` (`typedtree.mli:278-283`),
`binding_op = {bop_op_path; bop_op_name; bop_op_val; bop_op_type; bop_exp; bop_loc}` (:355-364);
`body : value case` whose `c_lhs` binds the yielded value. `arch_index_cmt.ml:1283-1306` walks
`let_.bop_exp` and each `and*` operand first, then `add_path_call let_.bop_op_path let_.bop_loc`
(:1295) and per-`and*` (:1296-1298) — the resolved operator path becomes a real call edge
(`Head_qualified (module, "let*")`, `add_path_call` :967-982, `path_to_module_name` :553-562);
the body is a conditional region (:1300-1306). In `calls`, a `let*` row displays as
`<module>.let*` with kind MUST/MAY_ENUMERATED per the usual rule (`arch_index.ml:440-467`). An
infix `x >>=? f` is an ordinary `Texp_apply` with a `Texp_ident` head → same `Head_qualified`
path via `record_head` (:1353-1394). So every declared bind already exists as a call edge whose
`callee_name` is the operator's resolved path — the producer already knows where binds are.

**References:** `compiler-libs/typedtree.mli:278-283,355-364`; `lib/arch_index/arch_index_cmt.ml:553-562,967-982,1283-1306,1308-1394`; `lib/arch_index/arch_index.ml:440-467`.

---

## Question 3: `Result`/`Option` matching and return-type inspection today

**Finding:** `Texp_match` (:1168-1195) walks every arm as a CFG branch; only `Tpat_exception`
computation cases open a scope (`exception_arms`); `Error e` / `Ok v` / `None` / `Some x` are
ordinary `Tpat_construct` (`Cstr_constant`/`Cstr_block`) and reach no handler logic —
`classify_pat` (`arch_index_exn.ml:218-234`) special-cases `Cstr_extension` only, wildcard for the
rest. Return types: `is_arrow`/`arrow_arity` (:909-921) look only at `Tarrow` for saturation;
`extract_types_from_signature` (:641-669) walks leading arrows and records the final `Tconstr`
path (`Path.name`) with role `return`, recursing into arguments (so `('a, err trace) result`
yields `Stdlib.result`, `…trace`, `…error`) — called on `vb.vb_pat.pat_type` (:2011-2014). No code
expands abbreviations (`Ctype.expand_head` / `Env` unused anywhere in `lib/arch_index` — by
design, `.cmt`-restored envs lack manifests, :906-908, :683-686): a function typed
`'a tzresult Lwt.t` prints `Tezos_protocol_environment_alpha.Error_monad.tzresult`; one written
`('a, error trace) result Lwt.t` prints `Stdlib.result` — both spellings occur and are NOT unified.
`option` prints bare (`option`, predef); `Stdlib.result` via `Pdot`.

**References:** `lib/arch_index/arch_index_cmt.ml:19,639,641-669,683-686,906-921,1168-1195,2011-2014`; `lib/arch_index/arch_index_exn.ml:218-234,248-254`.

---

## Question 4: Structure of the exception-identity feature on this branch

**Finding:** Tables `exn_scopes`, `exn_scope_catches`, `exn_origins`, `call_exn_scopes`,
`exn_rebinds` (`architecture-schema.sql:271-312`); `exn_contract` written beside
`callgraph_contract` (`arch_index.ml:531-539`). `arch_index_exn.ml`: `form` (:23-33) +
`form_to_string` (:35); recognisers `is_raise_prim`/`is_raise_head` (:92-99), `path_root`/
`stdlib_member`/`stdlib_head` (:104-130), `literal_exn`/`first_arg` (:132-135),
`strip_stdlib_predef` (:158-164), `canonical_path` (:166-175), `rebind_of` (:182), `arm_is_closing`
(:192-214), `classify_pat`/`classify_arms` (:216-244), `exception_arms`/`value_arms` (:248-260),
`enter_scope`/`leave_scope`/`with_cleared_scopes` (:273-303), `record_raise_head`/
`record_stdlib_head`/`prim_class`/`closure_free`/`record_prim_head`/`record_assert`/
`record_partial` (:315-391), `finalize` (:397-422). Hooks in `arch_index_cmt.ml`: `lexn` field
(:526, init :820), `current_scope` at `add_call` (:833), `Match_exception` scope (:1181-1187),
`Try` scope (:1215-1220), `record_assert` (:1272), apply-head origins (:1432-1438),
`with_cleared_scopes` (:1456), root partial (:1495), `finalize` per context (:1569),
`unit_declared` + rebinds (:1670-1717), inserts (:2085-2128). `arch_exn.ml`: `reason_kind`
(:31-42), `set = Known of SS.t | Top of SS.t * RS.t` (:57), `scope`/`edge`/`origin`/`t`
(:59-76), `not_analysed` (:78), `known_leaf` (:93-112, literal `Stdlib.*` names), `load`
(:116-221, refuses on Flat or missing `exn_contract`), `canon` (:224), lattice `join`/`equal`/
`known_part`/`close`/`top` (:232-263), `direct` (:268-280, keyed on form strings `"reraise"`,
`"unknown"`), `contribution` (:284-294), `solve` (:296-326), `rows_for`/`verdict`/`reasons_of`/
`dominant_reason` (:332-370). `arch_query.ml:634-728`: the three arms, `--assume-externals-pure`
parsed from `rest` (:638), `need_contract` (:641), `Arch_exn.load`/`solve` (:643-645), headers
`exception|via|how`, `verdict`, `function|file|how`, `top_function|file|reason`, `metric|value`;
usage :36-42. **Channel-specific by construction:** the recognisers (raise primitives, Stdlib
heads, extension-constructor identity), the `form` vocabulary and the table names; **generic:**
scopes/closing arms, the lattice, `close`, `solve`, provenance, verdicts, refusal.

**References:** as cited inline (line numbers verified on `feat/error-channels` HEAD 33f399d).

---

## Question 5: Config/data formats the repo parses; dependencies; root discovery

**Finding:** `arch-rules.txt`: grammar in the usage string (`bin/arch_rules/arch_rules.ml:22-37`),
line parser `parse_rules` (:70-127), selectors via `Arch_sel.parse` (`lib/arch_tools/arch_sel.ml:9-18`),
path = second positional arg defaulting to `"arch-rules.txt"` (:364-370). Dependencies
(`dune-project:9-37`, `arch-index.opam:7-31`, `*/dune`): `yojson`, `sqlite3`, `caqti`(+sqlite3
driver), `cmdliner`, `eio`/`cohttp-eio`/`uri`, `ppxlib`/`ppx_blob`/`ppx_deriving_yojson`,
`compiler-libs.common`, `mcp-kit` — **no TOML library**; nothing TOML-related installed in the
switch. NDJSON (`lib/arch_db/arch_load.ml:8-90`): `function` / `call` records, `kind` validated
against `["MUST";"MAY_ENUMERATED";"MAY_TOP"]` (:31, :58-66) with loud `failwith`. Sidecar loaders
find their `.sql` next to the binary (`Filename.dirname Sys.argv.(0)`, `bin/arch_effects_load/main.ml:37-38`,
`bin/arch_sidecar_load/main.ml:35-36`). `arch_callgraph_ocaml` flags: `--build-dir/-b` (required),
`--db-path/-d`, `--schema-path/-s` (`bin/arch_callgraph_ocaml/arch_callgraph_ocaml.ml:35-45`);
`Arch_index.run ?db_path ?schema_path ~build_dir` (`lib/arch_index/arch_index.ml:71`); project root
= the path prefix before `_build` in the build dir (:84-99); env defaults `ARCH_DB_PATH`,
`ARCH_SCHEMA_PATH` (`lib/arch_index/arch_index_db.ml:17-25`).

**References:** as cited inline.

---

## Question 6: How `comment_db_meta` records producer facts

**Finding:** `CREATE TABLE comment_db_meta (key TEXT PRIMARY KEY, value TEXT)`
(`architecture-schema.sql:122-125`). Writers: `arch_index.ml:531-539` (`callgraph_contract`,
`exn_contract`, only when `fn_lookup` is non-empty), `runner.ml:198-207` `set_meta` (used for
`schema_version`, `language`; owned by PR #53 — not to be touched). Readers: `Arch_db.meta_conn`/
`meta` (`lib/arch_tools/arch_db.ml:255-264`), `require_contract`/`contract_ok` (:318-351),
`Arch_exn.load` (`arch_exn.ml:118-120`), `arch-query stats`. Tests: `Fixture.main ~name ?seed ()`
seeds arbitrary SQL (`tezt/lib/arch_tezt.ml:713`); assertions read it with `Db.string_opt conn
"SELECT value FROM comment_db_meta WHERE key='…'"` (`tezt/tests/exn_raise_sets.ml:159-161`,
`tezt/tests/multilang.ml`).

---

## Question 7: Test fixtures for multi-unit libraries and refusal paths; CLI plumbing

**Finding:** Multi-unit fixtures: `exn_raise_sets.ml:24-25` (`(wrapped false) (modules exn_a exn_b)`),
`nested_module_qualification.ml:44-57`, `ocaml_shapes.ml:27,179`, `shadowed_definitions.ml:46…245`.
Refusals: `contract.ml:113` (`refuses` helper: `Batch.exit_code b ~expected:3 (query_raw db args)`),
`callgraph_soundness.ml:248` (`` `Refuses args ``), `exn_raise_sets.ml:400-441` (exit 3 +
`NOT_ANALYSED` / `NOT ⊤-marked`). Helpers (`tezt/lib/arch_tezt.ml`): `run_command ?env ?cwd ?stdin
prog args` (:202), `query_raw` (:374, `ARCH_QUERY_FORMAT=list`), `query` (:377), `index` (:343 —
passes only `--build-dir/--db-path/--schema-path`; extra producer flags need a local variant like
`dropped_node_dependents.ml:86` `index_with_schema`), `with_fixture`/`with_project` (:329/:316),
`temp_db` (:338), `locate ~env_var rel` (:40, upward search + env override), `Fixture.flat` (:693),
`Fixture.main ?seed` (:713). Data files reach tests through `tezt/tests/dune:35-53` `(deps …
../../architecture-schema.sql ../../effects-schema-migration.sql …)`.

---

## Question 8: [ecosystem] Error-monad / result-type analyses; unknown error values

**Finding:** Rust: `Result` is handled by `#[must_use]` (`unused_must_use`) and local clippy lints
(`result_unit_err`, `question_mark`) — no whole-program enumeration of error variants;
rust-analyzer shows `{unknown}` when inference is underdetermined. ML lineage: Pessaux–Leroy row
types (OCamlExc) keep an **open row variable** for unknown origins rather than a single ⊤; Koka
generalises to effect rows; recent PACMPL work ("Backwards-Compatible Row-Based Exceptions in ML",
"Programming with Effect Exclusion") stays at prototype level — **no OCaml tool computes which
error constructors a `Result`-returning function can return**. Scala 3 `CanThrow` makes it a
compile-time capability (no unknown case); ZIO widens the error type to its bound (`Throwable`).
Tezos `error_monad` is a runtime convention: `register_error_kind` with category
`Permanent | Temporary | Branch | Outdated`, `TzTrace` accumulation (`cons`, `record_trace`,
`trace`, `trace_eval`); nothing static. Tezt `Check` asserts at runtime.

**References:** https://rust-lang.github.io/rust-clippy/master/ ; https://github.com/rust-lang/rust-clippy/issues/9118 ; https://rust-analyzer.github.io/book/diagnostics.html ; https://dl.acm.org/doi/10.1145/349214.349230 ; https://arxiv.org/abs/1406.2061 ; https://doi.org/10.1145/3808303 ; https://dl.acm.org/doi/10.1145/3607846 ; https://docs.scala-lang.org/scala3/reference/experimental/canthrow.html ; https://zio.dev/overview/handling-errors/ ; https://octez.tezos.com/docs/developer/error_monad_p3_advanced.html ; https://ocaml.org/u/…/tezos-error-monad/10.2/doc/Tezos_error_monad/TzTrace/index.html

---

## Question 9: [ecosystem] TOML libraries for OCaml 5

**Finding:** Two live options on opam (checked against this switch's repo): **`toml`** (ocaml-toml/To.ml,
7.1.0, LGPL-3.0-only, deps `menhir` build-only, ocaml ≥ 4.08; spec version not stated) and
**`otoml`** (dmbaturin, 1.0.5, MIT, TOML 1.0-compliant, deps `menhirLib`, `uutf`, dune ≥ 2;
actively developed; used by soupault, fromager, camyll, lab). No `toml-parser` package; `drom`
bundles its own `drom_toml`. None of dune / ocamlformat / odoc / opam / dune-release use TOML.
Neither library is installed in the project switch today.

**References:** https://github.com/ocaml-toml/To.ml ; https://github.com/dmbaturin/otoml ; https://github.com/OCamlPro/drom ; local `opam show toml otoml`.
