# Task — error-channels

Roadmap item "3.4-bis — error channels v2", sub-items 1 and 2 (`~/notes/2026-09-01-arch-index-roadmap.md`).
Branch `feat/error-channels`, stacked on `feat/exn-raise-sets` (PR #54, HEAD 33f399d); base `origin/main` 69e5c3d.
Worktree `/tmp/claude-1000/-home-mathias-dev-arch-index/31263480-e1a5-4466-ad8a-8603e6671282/scratchpad/wt-exn`.
Env: `eval "$(opam env --switch=/home/mathias/dev/arch-index --set-switch)"`; always `dune build --root .` / `dune test --root . --force`.
Autonomous: human gates pre-approved and recorded; ask only critical questions; ask once before the ship push; never merge.

## Goal

Make error detection configurable by CHANNEL so it covers error-carrying monads, not only
exceptions — with a shipped Tezos profile.

- Generic data file `arch-errors.toml` (decided: data file, not attributes, no ppx). Per channel:
  `type` (carrier type constructor path, e.g. `Stdlib.result`) + `error_arg` (which type argument
  carries the error); `error_type` (where identities live — an extensible `type error += E` is a
  `Cstr_extension`, same recogniser as `exn`; closed variants use ordinary constructor paths;
  abstract → opaque identity); `origins` (functions/constructors building the error from a literal
  constructor argument: `Stdlib.Error`, `Error_monad.error`/`fail`/`tzfail`); `binds` (the channel's
  "call sites" where handler subtraction applies: `Result.bind`, `Result.Syntax.let*`,
  `Lwt_result_syntax.let*`, `>>=?`, `>>?`); `handlers` (`match … with Error` recognised
  structurally without config; plus `Result.value/fold`, `Error_monad.catch/catch_e/protect`);
  `transforms` (`map_error`, `record_trace`/`trace`: the inner set survives, marked wrapped);
  `unwrap` (`tzresult = ('a, error trace) result` → identity lives inside `trace`).
- Built-in defaults: `exception` (existing behaviour, unchanged), `result` (`Stdlib.result` +
  `Result`/`Result.Syntax`), `option` (`None` as failure, `Option.bind`/`Option.Syntax`).
- SHIPPED Tezos profile `profiles/tezos-errors.toml` for `Tezos_protocol_environment_alpha.Error_monad`
  (verify exact paths against `/home/mathias/dev/tezos/tezos/src/lib_protocol_environment/sigs/v15/*.mli`
  and the proto_alpha `.cmt` at `/home/mathias/dev/tezos/tezos/_build/default/src/proto_alpha/lib_protocol`;
  check the environment version proto_alpha uses in its dune).
- Every declared path MUST resolve in the indexed corpus or the producer refuses loudly (a
  declaration matching nothing is a bug, not a silence — roadmap 0.2 lesson). Unknown binds whose
  TYPE has bind shape over a declared carrier may be reported as `inferred_bind` (⊤ reason with
  witness), never silently ignored.
- Propagation is type-directed: a function "may fail with E" on channel c iff its return type
  carries c's error type and it (a) has an origin with literal E, or (b) binds (declared bind) or
  directly returns a callee's result that may fail with E, minus what handlers around that bind
  close; same lattice `Known | Top(known, reasons)`, same worklist, same `close`, generalised over
  channels. Non-literal error values → ⊤ `unknown_error_value`.
- `[summaries]` section (sub-item 2): `"Stdlib.List.hd" = { exception = ["Failure"] }` … —
  external callees with a declared summary contribute that set instead of ⊤ `external`; ship a
  small default Stdlib table (List.hd/tl/nth, Hashtbl.find, Option.get, String.sub/get,
  int_of_string, Map.find…).
- Schema: generalise the `exn_*` tables with a `channel` column (renaming to `error_*` is
  acceptable while PR #54 is unmerged — decide at implement time from `gh pr view 54`); additive
  only; `schema_version` untouched (PR #53 owns it). `comment_db_meta.error_contract = v1` listing
  the channels the producer emitted; the producer records the config digest it used.
- Query: `arch-query may-fail <fn> [--channel exception|result|option|<custom>|all]
  [--assume-externals-pure] [--config arch-errors.toml]`; `raises` stays as the alias for
  `--channel exception`; `raisers-of` → `fails-with <E>`; `exn-stats` → `error-stats` per channel.
  `NOT_ANALYSED` per channel when the producer did not emit it; Flat/LSP DBs refuse as today.
- Config discovery: `--config`, else `arch-errors.toml` at the project root, else built-ins;
  `--profile tezos` selects the shipped profile.
- Validation corpus (hard requirement): proto_alpha — where `tzresult` IS the error idiom.
  Measure `error-stats --channel tzresult`; spot-check ≥ 4 functions against source incl. one
  `record_trace` transform, one `catch`, one `let*` chain crossing units, and `main.ml`'s
  `begin_application` / `apply_operation` / `finalize_block`. Any answer contradicting the source
  is a soundness NO-GO. Re-run the exception channel to show it is unchanged (self-index golden,
  `tezt/tests/exn_raise_sets.ml` green).
- Tests: tezt `tezt/tests/error_channels.ml` (fixture with a home-made result monad, option, and a
  Tezos-shaped `type error += …` monad; config validation refusal; NOT_ANALYSED per channel;
  summaries), spec `specs/error-channels.md`, doc (extend `docs/exception-raise-sets.md` or new
  `docs/error-channels.md`), CHANGELOG. Existing tests, golden and `must_null_ceiling` stay green
  (recalibrate only with the reason recorded).
- Reuse: `roster/exn-raise-sets/research.md`, `specs/exn-raise-sets.md`,
  `lib/arch_index/arch_index_exn.ml`, `lib/arch_tools/arch_exn.ml` are the code to generalise.
