# Intake Brief — error-channels

**Date:** 2026-09-03
**Status: VALIDATED**
**Type:** feature
**Trust boundary:** no
_(Step 4.5 heuristic: no hit on the task record. Autonomous mode: human gate recorded as
pre-approved per the user's instruction; every decision below carries its rationale.)_

## Goal

Generalise the exception-identity analysis (PR #54) into **error channels**: a channel is any way
a function can fail — unwinding (`exception`), or an error *value* carried by a type
(`result`, `option`, Tezos `tzresult`, any home-made monad). The user's requirement is a
`throws`-style answer in the idiom the code actually uses; on Tezos `proto_alpha` that idiom is
`tzresult`, where PR #54 found only 20 literal raises against 14 452 functions.

Channels are **declared as data** (`arch-errors.toml`; decided: not attributes, no ppx) with one
vocabulary — carrier `type` (+ `underlying`, `error_arg`, `lift`), `error_type`, `origins`,
`binds`, `handlers`, `transforms`, `unwrap` — plus a `[summaries]` section for external callees.
Built-in defaults cover `exception`, `result`, `option`; a **shipped Tezos profile** covers
environment **V17** (`Tezos_protocol_environment_alpha.Error_monad`: `error`, `tzfail`,
`record_trace`/`trace`/`trace_eval`, `catch`/`catch_f`/`catch_s`, syntaxes
`Lwt_syntax`/`Result_syntax`/`Lwt_result_syntax` with `let*`/`and*`/`let*!`/`let*?`). Propagation is
type-directed and reuses the lattice, worklist, `close` and provenance of `lib/arch_tools/arch_exn.ml`;
the walker already records every `let*` as a call edge (`Head_qualified`, callee = operator path),
so binds are already "call sites" in `calls`. Every declared path MUST resolve in the corpus or the
producer refuses. Output: `arch-query may-fail <fn> --channel …`, `fails-with <E>`, `error-stats`;
`raises`/`raisers-of`/`exn-stats` stay as aliases of the `exception` channel. Validation on
proto_alpha (`error-stats --channel tzresult`, ≥ 4 spot checks incl. `record_trace`, `catch`, a
cross-unit `let*` chain, `main.ml` entry points) — any answer contradicting the source is a NO-GO.

## Scope Boundary

What is explicitly OUT of scope:
- Attributes (`[@@arch.…]`) and a validating ppx — a later layer with the same vocabulary.
- Dataflow on error values beyond a literal constructor argument (`let e = E in error e` → ⊤
  `unknown_error_value`, measured; roadmap 3b-ii is where it goes).
- Bind inference beyond a *report*: an undeclared operator whose type has bind shape over a
  declared carrier is reported as ⊤ `inferred_bind <site>`, never silently used as a bind.
- Non-OCaml producers (Go/Rust rows, Flat/NDJSON schema extension — roadmap 3.4-bis item 5).
- `Lwt` failure itself (`Lwt.fail`, rejected promises) as a channel; `Lwt.t` is only a `lift`
  wrapper around a carrier here.
- Effects; closure-flow / functor-parameter resolution (3.7 / item 3); `arch-rules` gate (item 4).
- Renaming `exn_*` tables: PR #54 is still OPEN — keep the names, add a `channel` column
  (default `'exception'`); the rename is dropped for good (a second language will read the
  `channel` column, not the table name).
- `runner.ml` and the schema-version write sites stay untouched **except** the deliberate
  `current_schema_version` bump below (PR #53 merged on 2026-09-03; the bump is the recorded
  follow-up of #54, now in scope).

## Relevant Files

| File | Role | Key snippet |
|---|---|---|
| `lib/arch_index/arch_index_exn.ml:23-35, 92-135, 158-183, 192-260, 273-303, 315-422` | recognisers, canonical paths, arms, scopes, origins, `finalize` — to be parameterised by channel | `is_raise_head`, `classify_pat` (only `Cstr_extension`), `record_*`, `finalize` |
| `lib/arch_index/arch_index_cmt.ml:1168-1195, 1283-1306, 1308-1394, 1432-1438, 1670-1717, 2085-2128` | `Texp_match` arms, `Texp_letop` → `add_path_call bop_op_path`, apply heads, `unit_declared`, inserts | `add_path_call let_.bop_op_path let_.bop_loc` — binds already are call edges |
| `lib/arch_index/arch_index_cmt.ml:641-669, 906-921` | return-type walk (`extract_types_from_signature`, `Tarrow`/`Tconstr`, no abbreviation expansion) | `extract_constr ty "return"` |
| `lib/arch_index/arch_index.ml:181-236, 440-467, 531-539` | prepared statements, kind decision, `exn_contract` write | `INSERT OR REPLACE INTO comment_db_meta … ('exn_contract','v1')` |
| `lib/arch_index/arch_index_db.ml`, `.mli` | insert helpers; `current_schema_version` (from #53, after rebase) | `insert_exn_origin …` |
| `lib/arch_tools/arch_exn.ml:57-76, 93-112, 116-221, 232-326, 332-377` | lattice, `known_leaf`, `load`, `close`, `direct`, `contribution`, `solve`, provenance | `direct` keyed on form strings `"reraise"`/`"unknown"` |
| `bin/arch_query/arch_query.ml:36-42, 634-728` | usage + the three arms; flag parsing from `rest` | `List.mem "--assume-externals-pure" rest` |
| `bin/arch_callgraph_ocaml/arch_callgraph_ocaml.ml:35-45` | Cmdliner flags (`--build-dir`, `--db-path`, `--schema-path`) | add `--errors-config`, `--errors-profile` |
| `bin/arch_effects_load/main.ml:37-38` | data file located next to the binary (precedent) | `Filename.concat (Filename.dirname Sys.argv.(0)) …` |
| `architecture-schema.sql:271-312` | `exn_*` tables | add `channel TEXT NOT NULL DEFAULT 'exception'` on `exn_origins`/`exn_scopes`; new `error_summaries`? (no — summaries live in config, not DB) |
| `dune-project`, `arch-index.opam`, `lib/arch_index/dune` | dependencies | add `otoml` |
| `tezt/lib/arch_tezt.ml:343, 374, 713` ; `tezt/tests/exn_raise_sets.ml` | `index` (no extra flags → local variant), `query_raw`, `Fixture.main ?seed`; regression fixture | |
| `/home/mathias/dev/tezos/tezos/src/lib_protocol_environment/sigs/v17/error_monad.mli:31,71,97,101,103-114,147,155,174,201-375` | the exact Tezos surface to encode in the profile | `type 'a tzresult = ('a, error trace) result` |
| `docs/exception-raise-sets.md`, `specs/exn-raise-sets.md`, `CHANGELOG.md`, `docs/schema-versions.md` (from #53) | docs to extend | |

## Architecture Notes

**Config model (`lib/arch_index/arch_errors_config.ml`, parsed with `otoml`).**
```toml
[channel.result]                       # built-in; shown for the shape
type       = "Stdlib.result"           # carrier type constructor path
error_arg  = 2                         # which type argument carries the error (1-based)
lift       = ["Lwt.t"]                 # wrappers to strip before matching (default: none)
error_type = ""                        # "" = closed variant / any: identity = the constructor path of the literal
origins    = ["Stdlib.Error"]          # constructor or function whose literal argument names the error
binds      = ["Stdlib.Result.bind", "Stdlib.Result.Syntax.let*", "Stdlib.Result.Syntax.and*"]
handlers   = ["Stdlib.Result.value", "Stdlib.Result.fold", "Stdlib.Result.get_ok"]
transforms = ["Stdlib.Result.map_error"]
unwrap     = []

[channel.tzresult]                     # shipped profile profiles/tezos-errors.toml
type       = "Tezos_protocol_environment_alpha.Error_monad.tzresult"
underlying = "Stdlib.result"           # the alias is not expanded in .cmt: match either spelling
error_arg  = 2
error_type = "Tezos_protocol_environment_alpha.Error_monad.error"   # type error = .. → Cstr_extension identities
unwrap     = ["Tezos_protocol_environment_alpha.Error_monad.trace"] # ('a, error trace) result
lift       = ["Lwt.t"]
origins    = ["…Error_monad.error", "…Error_monad.tzfail", "…Error_monad.Result_syntax.tzfail", "…Error_monad.Lwt_result_syntax.tzfail"]
binds      = ["…Error_monad.Result_syntax.let*", "….Result_syntax.and*", "….Lwt_result_syntax.let*", "….Lwt_result_syntax.and*", "….Lwt_result_syntax.let*?", "….Lwt_result_syntax.let*!"]
handlers   = ["…Error_monad.catch", "…Error_monad.catch_f", "…Error_monad.catch_s"]
transforms = ["…Error_monad.record_trace", "…Error_monad.trace", "…Error_monad.trace_eval"]

[summaries]
"Stdlib.List.hd"      = { exception = ["Failure"] }
"Stdlib.Hashtbl.find" = { exception = ["Not_found"] }
```
Validation at index time: every path in `origins`/`binds`/`handlers`/`transforms`/`type`/
`error_type` must resolve to a value or type *seen* in the corpus (the walker collects every
`Texp_ident`/`Tconstr` path it visits); unmatched → the producer exits 1 naming the path
(`arch-errors: 'X' in channel c matched nothing in the indexed corpus`). `--errors-config <path>`
overrides discovery (`arch-errors.toml` at the project root); `--errors-profile tezos` loads
`profiles/tezos-errors.toml` found via `ARCH_ERRORS_PROFILES_DIR`, then `<exe dir>/../../../profiles`
(dune layout), then `<project root>/profiles`. The producer writes `comment_db_meta.error_contract =
"v1:exception,result,option,tzresult"` (channels actually emitted) and `error_config_digest`.

**Producer generalisation.** `Arch_index_exn` becomes per-channel: for a `result`-like channel,
*origins* are applications of a declared origin (or the `Error` constructor) whose literal argument
is a constructor (`Cstr_extension` path for `error_type = ..`, ordinary constructor path otherwise —
canonicalised by the same rule); *scopes* are (a) `match e with Error p -> …` arms (structural, no
config: an `Error`/`None` arm classifies like a handler arm — constructor path or catch-all; a
closing arm has no origin/bind of the same channel in its RHS), (b) declared `handlers` applied to
a function-typed argument or a result value — the scope covers the argument expression; *binds*
are the call edges to declared `binds` (the edge already exists — the walker tags the call with
`channel` and the bound expression); *transforms* wrap: the inner set survives, marked in
provenance. `escapes` per origin as today. A function's *carrier check* uses the return type after
stripping `lift` wrappers: `Tconstr` path = `type`, or = `underlying` with the error argument's
head path ∈ {`error_type`} ∪ `unwrap`-of-`error_type`; functions whose return type is not a
carrier of channel c get no `c` rows.

**Query generalisation.** `Arch_exn.load` gains the channel dimension: edges are filtered to the
channel's binds for value channels (a plain call that does not bind the result does not
propagate an error value — the value is dropped or returned; a *direct return* of a callee's
result is a propagation, recognised structurally when the callee expression is in tail position
of the function body); `exception` keeps "every edge". Same `Known | Top(known, reasons)`, same
`close`, same `solve`; `known_leaf`/summaries per channel from the config; verdicts unchanged.
`NOT_ANALYSED` per channel when `error_contract` lacks it.

**Decisions (autonomous, with rationale).**
- `otoml` (MIT, TOML 1.0, `menhirLib`+`uutf`) over `toml` (LGPL) — licence and spec compliance.
- Keep `exn_*` table names + `channel` column: PR #54 open; the rename bought nothing a column
  does not.
- `current_schema_version` → `"1.3"` + `docs/schema-versions.md` entry on this branch after
  rebasing on `main` (PR #53 merged today) — the recorded #54 follow-up.
- Built-in defaults live in OCaml (`Arch_errors_config.builtin`), not in a file: zero-config runs
  must not depend on locating a data file.
- Bind propagation only along *declared* binds and tail returns; everything else that consumes
  a result value is a handler-or-drop and contributes nothing — over-approximation is kept on
  the *origin* side (unknown values → ⊤), under-approximation is avoided by reporting
  `inferred_bind` ⊤ for undeclared bind-shaped operators.

## Quality Gates

```bash
eval "$(opam env --switch=/home/mathias/dev/arch-index --set-switch)"
opam install -y otoml                      # new dependency, once
dune build --root .
dune test --root . --force
# not documented: format/lint
BIN=./_build/default/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe
$BIN --build-dir=_build/default/lib/arch_index --db-path=/tmp/self.db --schema-path=architecture-schema.sql
./_build/default/bin/arch_rules/arch_rules.exe /tmp/self.db arch-rules.txt --on-vacuous fail
sqlite3 /tmp/self.db "SELECT 'modules: '||count(*) FROM modules; SELECT 'functions: '||count(*) FROM functions; SELECT 'calls: '||count(*) FROM calls;" | diff test/fixtures/self-index-stats.txt -
```

## Open Questions

- [ ] Tail-position return of a callee's result: implementers must recognise `let f x = g x`
  (body is the application), `if … then g x else Error E`, `match … -> g x` arms, and
  `Lwt`-lifted forms only through declared `binds`; anything else is *not* a propagation. The
  spec fixes the exact syntactic set with scenarios.
- [ ] Origin argument for `error`/`tzfail` in Tezos is often `(E_constructor args)` inline —
  literal; but `error err` with `err` a parameter occurs: ⊤ `unknown_error_value` with witness,
  counted in `error-stats` — implementers must not special-case it.
- [ ] `unwrap` semantics: `error trace` carries a *list* of errors; the analysis treats the trace
  as "some E in the set" — the identity is the constructor path of the `error` inside; a
  `record_trace E` transform *adds* `E` to the carried set (wrapped marker), it does not replace.
