---
name: roster-spec
type: spec
status: live
feature: Error channels — configurable error-carrying monads, Tezos profile, summaries (roadmap 3.4-bis items 1–2)
brief: briefs/error-channels-intake.md
extends: specs/exn-raise-sets.md
date: 2026-09-03
version: 1.0.0
---

# Spec — Error channels (`error-channels`)

Extends `specs/exn-raise-sets.md` (FR-001..020, AC-1..14 stay in force for the `exception`
channel). Autonomous-mode spec: 25 challenges resolved from sources; rule changes forced by the
challenger are marked **[C-n]**.

## Clarifications

| Q | A |
|---|---|
| What is a channel? | A way for a function to fail. `exception` = unwinding (shipped). A **value channel** = an error carried by the function's *returned value*: carrier type `T` with the error in type argument `error_arg`, optionally behind `lift` wrappers (`Lwt.t`) and `unwrap` containers (`trace`). Built-ins: `exception`, `result` (`Stdlib.result`, arg 2), `option` (`option`, error = `None`, identity `None`). |
| Config file vocabulary (`arch-errors.toml`) | `[channel.<name>]`: `type` (carrier constructor path), `underlying = [paths]` (alias targets — the `.cmt` never expands abbreviations, and Tezos prints the underlying as `Tezos_protocol_environment_alpha.Pervasives.result`, so both spellings must match) **[research]**, `error_arg` (1-based), `lift = [paths]`, `error_type` (path of the error type; `""` = identity is the literal constructor's own path), `aliases = [paths]` (other paths under which `type`/`error_type` print — re-exports, environment aliases) **[EC-10]**, `origins = [{path, arg=1}]` (functions/constructors whose LITERAL constructor argument at `arg` names the error; `Stdlib.Error`, `Error_monad.error`, `error_when cond E` → `arg=2`) **[research]**, `binds = [paths]`, `handlers = [{path, arg=1}]` (declared handler applied to the value at `arg`), `transforms = [{path, mode="add"|"replace", arg}]` **[C-3, C-13]**, `converters = [{path, from, to, arg, error="path"|""}]` **[C-12, EC-8]**, `sinks = [paths]` (default `Stdlib.ignore`), `unwrap = [paths]`. `[summaries] "<callee path>" = { <channel> = ["path", …] }`. Composition order: built-ins < profile < user file, keyed by channel name (a later definition replaces the whole channel) **[C-6]**. |
| Built-in channels that match nothing **[implementation amendment, 2026-09-03]** | The whole-carrier-miss **fatal** rule applies only to channels that came from a **file** (`--errors-config` / `--errors-profile`); a *built-in* channel (`result`, `option`) whose carrier type is absent from the corpus is simply **not emitted** — it is omitted from `error_contract`, so a later query for it answers `NOT_ANALYSED`, which is the honest outcome. Rationale: FR-023's bug class is "the user declared something that does not exist", and a codebase that never uses `Stdlib.result` has declared nothing wrong; making the built-ins fatal would exit 1 on almost every small project. Per-path misses of built-ins are still recorded in `error_config_unmatched` (informational). |
| Config validation | For each channel, every declared path is looked up in the set of paths the walker *saw* in the corpus (values: `Texp_ident`/`bop_op_path`/constructor paths; types: `Tconstr` paths, incl. `aliases`). Per-path miss → **warning** printed (`arch-errors: channel c: 'X' matched nothing`) and recorded in `comment_db_meta.error_config_unmatched`; a channel whose `type` (or every `underlying`/`aliases`) matches nothing → **exit 1** (`arch-errors: channel c: carrier type matched nothing in the indexed corpus`) — the "declaration matching nothing" bug class; `--errors-strict` promotes every warning to exit 1 **[C-5]**. |
| Discovery, precedence, digest | `--errors-config <path>` > `arch-errors.toml` at the project root > none. `--errors-profile <name>` resolves `profiles/<name>-errors.toml` in order `ARCH_ERRORS_PROFILES_DIR`, `<project root>/profiles`, `<exe dir>/../../../profiles` (dune layout); the first hit wins and its path is printed **[C-7]**. `comment_db_meta.error_contract = "v1:<channels emitted, comma-separated>"`, `error_config_digest` = SHA-256 of the canonical serialisation of the *effective merged* config (sorted keys), `error_config_source` = the file paths used **[C-6]**. |
| Carrier check (which functions are analysed on channel c) | A function node is a c-carrier iff its return type (after stripping leading `Tarrow`s and any `lift` wrappers) is `Tconstr p` with `p ∈ {type} ∪ underlying ∪ aliases` and the type argument `error_arg` has head `∈ {error_type} ∪ unwrap-of-error_type ∪ aliases`, **or** is a type variable **[C-8]**, or `error_type = ""`. Non-carriers get no rows on channel c. A lambda node is checked on its own type. |
| Polymorphic-variant errors **[smoke finding, 2026-09-03 — REQUIRED, not optional]** | The Rresult/Bos idiom `('a, [> `Msg of string]) result` is the dominant `result` spelling in ordinary OCaml: octez-manager has **394** `Error \`X` sites against 71 ordinary-constructor ones (proto_alpha, which uses extensible constructors, has 8). Origins MUST therefore also recognise `Texp_variant (label, arg)` as the error literal, and handler arms `Tpat_variant (label, …)` as the caught set. **Identity = the bare label** (`` `Msg ``), with no unit qualification: OCaml's polymorphic variants are structural, so two `` `Msg `` from different modules *are* the same variant — the bare label is the correct global identity, not a collision, and this case needs no canonicalisation table at all. Without this the `result` channel answers ⊤ `unknown_error_value` on most real OCaml code, which is sound but useless. |
| Origins (value channel) | An application of a declared origin (or the `Error`/`None`-style constructor) whose argument `arg` is a literal constructor (`Cstr_extension` for `error_type = ..`, ordinary constructor otherwise) → canonical path (same rule as exceptions, plus `aliases`); non-literal argument → ⊤ `unknown_error_value` (site witness). Recorded wherever it occurs in the node; `escapes` per the scope chain. An `exception`-channel origin inside a tzresult function is an exception fact only **[US-2.9]**. |
| Propagating edges (value channel) **[decision, C-20, C-21]** | Inside a c-carrier node, **every** call edge — MUST, MAY_ENUMERATED (incl. lambda occurrence edges and named-function arguments), MAY_TOP — to a c-carrier callee, or ⊤ edge, is propagating unless its head call is covered by a c handler scope or a sink. Over-approximation by design: a carrier value may flow out through data (lists, records, HOFs). A carrier value received as a **parameter** contributes nothing to the callee's set: its creation site's node already counts it (induction over callers) — this is what keeps generic combinators (`wrap r = match r with Error e -> Error (Wrap e) | ok -> ok`) bounded instead of ⊤. |
| Handler scopes (value channel) | (a) `match E with Error p -> rhs | …` (or `None ->`) where the scope covers the **head call** of `E` — `E` is a call, or a variable bound by a chain of single-variable `let`s to a call (`let r = f () in let r2 = r in match r2 …`) **[C-2]**; nested carrier calls in argument position are NOT covered (an intermediate function may transform the error — subtracting would be unsound) **[decision]**; (b) a declared handler applied to the value at `arg` (head call rule again); (c) declared `binds` are NOT scopes. Arm classification: `Error p` → paths of `p` (constructor / or / alias) or catch-all (`Error _`, `Error e`, `_`); **an arm is closing iff unguarded AND the variable(s) bound by `p` do not occur in its RHS** **[C-1, EC-3]** — `Error e -> Error e` (re-return), `Error e -> log e; Ok 0` are non-closing (over-approx); `Error _ -> Error A` is closing (and `A` is an ordinary origin of the node). An irrefutable `let (Ok x \| Error x) = f ()` is neither handler nor sink: propagates **[C-1]**. |
| Sinks | `ignore (E)`, `let _ = E in`, a non-final `Texp_sequence` position, declared `sinks`: the head call of `E` does not propagate; nested carrier calls inside `E` still do (over-approx) **[decision]**. `Texp_sequence` is walked structurally, independent of warning 10 **[C-14]**. |
| Binds | A call to a declared bind neither closes nor sinks: the bound expression's head call propagates, and the continuation argument (lambda occurrence edge / named function) is a propagating edge too **[C-4]**; `let*` bodies are inline in the node (their origins are the node's). `Lwt_syntax.let*` / `let*!` bind a plain `Lwt.t`: the bound call is not a carrier call → contributes nothing by the carrier rule **[EC-6]**. An undeclared operator whose type has bind shape over a carrier of c (`c -> ('a -> c) -> c`) → ⊤ `inferred_bind <site>`, never used silently. |
| Transforms **[C-3, C-13]** | `mode = "add"` (`record_trace`, `trace`, `trace_eval`): result set = inner set ∪ literal argument origins (`arg`), inner marked `wrapped`. `mode = "replace"` (`Result.map_error`): result set = the literal-constructor returns of the mapping function when it is a lambda literal or a named function whose set is Known, else ⊤ `unknown_error_value`; the inner set does NOT survive. |
| Converters **[C-12, EC-8]** | `{path, from, to, arg, error}`: the argument at `arg` (a thunk / function / value) is a catch-all handler scope on channel `from` (closes ⊤ too) and an origin on channel `to`: `error` path if given (Tezos `catch` → `Exn`-style error constructor when the profile names it), else opaque identity `<to>:converted_<from>` (bounded, one element). `Result.to_option` → `to = option`, identity `None`. |
| Recursion / lattice **[C-11, C-22]** | Same as exceptions: per node `Known of paths × wrapped-marks \| Top(known, reasons)`; initial value `Known ∅`; monotone join; per-edge `close` with the head-call scope chain; worklist to fixpoint. Caps: a Known set larger than 256 paths collapses to ⊤ `set_too_large`; reason sets keep at most 64 witnesses per kind (count kept). |
| Query vocabulary **[C-15, C-16, C-23]** | `may-fail <fn> --channel c` → `BOUNDED: {…}` / `UNBOUNDED (⊤): {…} + reasons` / `BOUNDED_UNDER_HYP(externals_pure)` / **`NOT_A_CARRIER(c)`** when the function is not a c-carrier; `--channel all` prints one block per emitted channel; `fails-with <E> [--channel c]` lists bounded nodes containing the canonical `E` and, separately, ⊤ nodes ("may include"); `error-stats [--channel c]`. `raises`/`raisers-of`/`exn-stats` remain aliases of `--channel exception` with **byte-identical output** (the `channel` column is never printed there). `NOT_ANALYSED` per channel when `error_contract` lacks it. |
| Schema version number **[peer conflict, 2026-09-03]** | Do NOT hardcode a version literal: two branches bump `Arch_index_db.current_schema_version` in parallel (`feat/language-universe` bumps it for `functions.language`/`universe`). Rule: at implement time read the constant **from the rebase base**, bump the **minor** component by one (additive change), and append the matching `docs/schema.md` history row naming the tables/columns that version adds. QA checks the written number equals base+1 and that no other history row claims it. |
| Schema **[C-18]** | `exn_origins.channel TEXT NOT NULL DEFAULT 'exception'`, `exn_scopes.channel` likewise, `call_exn_scopes` unchanged (scope carries the channel), new `exn_edges(call_id, channel, role ∈ {propagates, bind_arg, sink, transform_add, transform_replace, convert})` (additive; only rows for value channels — the exception channel keeps "every edge"). Producers always rebuild the DB; a consumer opening a DB without the `channel` column (pre-1.3) reads it as exception-only (`has_col`). `current_schema_version` bumped per the rule above (base+1 minor) with its `docs/schema.md` history row. |
| Canonical paths across units **[C-17, EC-10]** | Same canonicalisation as exceptions + `aliases`; matching is by canonical string; a shadowing collision is a documented residual (over-approximating). |
| proto_alpha oracle **[C-19]** | The QA scope carries an **expected-result table written from source before running**: for each of ≥ 4 functions, the expected set/verdict and why; any mismatch is a NO-GO. |
| Out of scope (recorded) | `register_error_kind` categories as metadata **[C-24]** (roadmap follow-up: `fails-with --category`), function-level declared contracts **[C-25]** (attributes layer, 3.4-bis future), functor instances (residual as for exceptions **[C-10]**), abstract error types behind `.mli` (origins resolve inside the defining module only; elsewhere via declared origin functions **[C-9]**). |

## User Stories

### US-1: Configurable channels with loud validation (Priority: P0)
As an engineer, I want to declare my project's error monads in `arch-errors.toml` (or use a shipped profile) and be told when a declaration matches nothing, so the analysis speaks my code's idiom without silent no-ops.
**Scope**: does NOT cover attributes/ppx, categories, function contracts.
**Independent Test**: index a fixture with/without config files and read `comment_db_meta`.
**Acceptance Scenarios**:
1. **Given** no config file, **When** indexing, **Then** built-ins apply and `error_contract = "v1:exception,result,option"`, `error_config_source = "builtin"`.
2. **Given** `arch-errors.toml` at the project root declaring `[channel.myres]` with a typo'd bind `Fx.Res.bindd`, **When** indexing, **Then** a warning `arch-errors: channel myres: 'Fx.Res.bindd' matched nothing` and `error_config_unmatched` lists it; with `--errors-strict` exit 1.
3. **Given** a channel whose `type = "Fx.Nope.t"` matches nothing, **When** indexing, **Then** exit 1 naming the channel and the type.
4. **Given** `--errors-profile tezos` on the non-Tezos fixture, **When** indexing, **Then** exit 1 (the carrier type is absent).
5. **Given** the same effective config from two differently-formatted files, **When** indexed twice, **Then** `error_config_digest` is identical; a changed `binds` list changes it.
6. **Given** `ARCH_ERRORS_PROFILES_DIR` pointing at a directory with `tezos-errors.toml` and a `profiles/` in the project root too, **When** `--errors-profile tezos`, **Then** the env-var file is used and its path printed.

### US-2: Producer — value-channel origins, scopes, propagating edges (Priority: P0)
As the CMT producer, I want to record per c-carrier node its origins, handler scopes, sinks, binds, transforms and converters, so the query can compute may-fail sets with the same machinery as exceptions.
**Scope**: does NOT cover dataflow beyond literals and single-let alias chains, or non-OCaml producers.
**Independent Test**: fixture library `errch` (unwrapped, units `ec_a`, `ec_b`) with `type err = A | B of int`, `type ('a) r = ('a, err) result`, a `Res` module with `bind`/`Syntax.let*`/`map_error`/`value`, an `option` part, and a Tezos-shaped part `type error = ..`, `type 'a tz = ('a, error trace) result` with `error`/`tzfail`/`record_trace`/`catch`/`Lwt`-free `let*`; a test config declares channels `myres` and `mytz`.
**Acceptance Scenarios**:
1. **Given** `let f () = Error A`, **Then** `exn_origins` row channel `myres`, `exn_path = Ec_a.A`, `escapes = 1`.
2. **Given** `let g () = match f () with Error A -> Ok 0 | r -> r`, **Then** a `myres` scope on `g` catching `Ec_a.A` (closing: `A` binds nothing), and `may-fail g --channel myres` = `BOUNDED: {}`.
3. **Given** `let g2 () = match f () with Error e -> Error e | ok -> ok`, **Then** the arm is non-closing (`e` occurs) and `may-fail g2` = `BOUNDED: {Ec_a.A}`.
4. **Given** `let g3 () = match f () with Error _ -> Error (B 1) | ok -> ok`, **Then** `BOUNDED: {Ec_a.B}`.
5. **Given** `let h () = Res.bind (f ()) (fun x -> Ok x)` and `let h2 () = Res.bind (f ()) (fun _ -> Error (B 2))`, **Then** `h` = `{Ec_a.A}`, `h2` = `{Ec_a.A, Ec_a.B}` (continuation edge propagates).
6. **Given** `let k () = let open Res.Syntax in let* x = f () in Ok x`, **Then** `{Ec_a.A}`; **Given** `let s () = ignore (f ()); Ok 0` and `let s2 () = let _ = f () in Ok 0`, **Then** `BOUNDED: {}` (sinks).
7. **Given** `let w () = Res.map_error (fun _ -> B 3) (f ())` with `map_error` declared `mode = "replace"`, **Then** `{Ec_a.B}` (inner `A` gone); **Given** `let w2 () = Res.map_error fn (f ())` with `fn` a parameter, **Then** `UNBOUNDED (⊤)` reason `unknown_error_value`.
8. **Given** `let al () = let r = f () in let r2 = r in match r2 with Error A -> Ok 1 | ok -> ok`, **Then** `BOUNDED: {}` (alias chain).
9. **Given** `let nest () = match wrap (f ()) with Error (Wrap _) -> Ok 0 | ok -> ok` where `wrap r = match r with Error e -> Error (Wrap e) | ok -> ok`, **Then** `may-fail nest` = `BOUNDED: {Ec_a.A}` (only the head call `wrap` is covered; `f`'s `A` still propagates — sound) and `may-fail wrap` = `BOUNDED: {Ec_a.Wrap}` (parameter contributes nothing).
10. **Given** `let o () = if c then None else Some 1` and `let o2 () = Option.bind (o ()) (fun x -> Some x)`, **Then** channel `option`: `o` = `{None}`, `o2` = `{None}`.
11. **Given** the Tezos-shaped part: `type error += E1 | E2 of int`, `let t1 () = error E1`, `let t2 () = let* x = t1 () in Ok x` in `ec_a`, and in `ec_b` `let t3 () = let* x = Ec_a.t2 () in error (E2 x)`, `let t4 () = record_trace E2 (t3 ())`, `let t5 () = catch (fun () -> raise Not_found)`, `let t6 () = error_when true E1`, **Then** `t2` = `{Ec_a.E1}`, `t3` = `{Ec_a.E1, Ec_a.E2}` (cross-unit, canonical strings agree), `t4` = `{Ec_a.E1, Ec_a.E2}` with `E1`/`E2` from `t3` marked wrapped (`mode = add`, `E2` literal added), `t5` = `{mytz:converted_exception}` on `mytz` and `BOUNDED: {}` on `exception`, `t6` = `{Ec_a.E1}` (`arg = 2`).
12. **Given** `let mixed () : int tz = if c then raise Not_found else Ok 0`, **Then** `exception` channel `{Not_found}`, `mytz` channel `BOUNDED: {}`.
13. **Given** an undeclared operator `let ( >>=? ) = Res.bind` used as `f () >>=? g`, **Then** `UNBOUNDED (⊤)` reason `inferred_bind ec_a.ml:L`.
14. **Given** the previous feature's fixture, **When** `raises`/`raisers-of`/`exn-stats` run, **Then** output is byte-identical to before (tezt `exn_raise_sets.ml` green unchanged).

### US-3: Query — `may-fail`, `fails-with`, `error-stats`, summaries, NOT_ANALYSED (Priority: P1)
As an engineer, I want per-channel answers and honest refusals.
**Scope**: does NOT cover SARIF/`arch-lint`.
**Acceptance Scenarios**:
1. **Given** `let plain () = 42`, **When** `may-fail plain --channel myres`, **Then** `NOT_A_CARRIER(myres)`.
2. **Given** `may-fail t3 --channel all`, **Then** one block per emitted channel, `exception` block byte-identical to `raises t3`.
3. **Given** `fails-with Ec_a.A --channel myres`, **Then** `f`, `g2`, `h`, `h2`, `k`, `nest` listed (bounded), `w2` in the ⊤ section.
4. **Given** `[summaries] "Stdlib.List.hd" = { exception = ["Failure"] }` in the config and `let m xs = List.hd xs`, **When** `raises m`, **Then** `BOUNDED: {Failure}`; without the summary `UNBOUNDED (⊤)` `external Stdlib.List.hd`.
5. **Given** a DB indexed without `mytz` declared, **When** `may-fail t2 --channel mytz`, **Then** exit 3 `NOT_ANALYSED: channel mytz was not emitted by the producer (error_contract = …)`.
6. **Given** a Flat DB, **When** any command, **Then** exit 3 `NOT_ANALYSED` as today.

### US-4: Tezos profile, proto_alpha validation, schema hygiene (Priority: P1)
**Acceptance Scenarios**:
1. **Given** `profiles/tezos-errors.toml` (V17 paths, `underlying = ["Stdlib.result", "Tezos_protocol_environment_alpha.Pervasives.result"]`, `unwrap = […Error_monad.trace]`, origins `error`/`tzfail` (both syntaxes)/`error_when arg=2`/`error_unless arg=2`/`fail_unless arg=2`/`Result_syntax.tzfail`/`Lwt_result_syntax.tzfail`, binds `Result_syntax.let*/and*`, `Lwt_result_syntax.let*/and*/let*?/let+`, handlers `catch`/`catch_f`/`catch_s` as **converters** from `exception`, transforms `record_trace`/`trace`/`trace_eval` `mode=add`), **When** indexing `lib_protocol` with `--errors-profile tezos`, **Then** exit 0, zero per-channel fatal misses, warnings listed for unused members.
2. **Given** that DB, **When** `error-stats --channel tzresult` (and `--assume-externals-pure`), **Then** node/bounded/unbounded counts, origins by form, recorded in the QA brief with `fixpoint_seconds`.
3. **Given** the pre-written oracle table (≥ 4 functions: one `record_trace`, one `catch`, one cross-unit `let*` chain, `main.ml` `begin_application`/`apply_operation`/`finalize_block`), **When** `may-fail … --channel tzresult`, **Then** every answer matches the oracle (soundness NO-GO otherwise).
4. **Given** the branch rebased on `main`, **Then** `current_schema_version` = base value with minor+1, `docs/schema.md` lists that version (exn tables + `channel` + `exn_edges`) and no other row claims it, CHANGELOG updated, self-index golden regenerated, `must_null_ceiling` recalibrated only with the reason recorded.

## Challenges (resolutions)

| # | Resolution |
|---|---|
| C-1 | or-pattern `let` = neither handler nor sink → propagates. |
| C-2 | single-variable `let` alias chains resolved (stamp table). |
| C-3 / C-13 | `transforms.mode` add vs replace. |
| C-4 | continuation argument of a bind is a propagating edge. |
| C-5 | per-path warning; whole-carrier miss fatal; `--errors-strict`. |
| C-6 | digest over the effective merged config; composition order fixed. |
| C-7 | fixed precedence, path printed. |
| C-8 | type-variable error arg ⇒ carrier (over-approx). |
| C-9 | abstract types: origins via declared functions; documented. |
| C-10 | functor instances conflated — residual, over-approximating. |
| C-11 | `Known ∅` seed, monotone join, per-edge close. |
| C-12 / EC-2 / EC-8 | `converters` role. |
| C-14 | `Texp_sequence` structural. |
| C-15 | `NOT_A_CARRIER(c)`. |
| C-16 / EC-7 | aliases byte-identical; `channel` never printed there. |
| C-17 | canonical strings; collision residual. |
| C-18 | rebuild-only producer; consumers tolerate the missing column. |
| C-19 | oracle table before running. |
| C-20 / C-21 | every edge propagates unless head-covered; parameters contribute nothing. |
| C-22 | `set_too_large` cap 256, witnesses 64. |
| C-23 | ⊤ nodes listed as "may include". |
| C-24 / C-25 | out of scope, recorded as roadmap follow-ups. |
| EC-3 | closing = unguarded ∧ bound var absent from RHS. |
| EC-5 | never-matched handler → unmatched warning. |
| EC-9 | post-rebase exception-channel diff must be empty on the self-index golden and the tezt. |
| EC-10 | `aliases`. |

## Functional Requirements

#### Config (US-1)
- **FR-021** [US-1]: The producer MUST accept `--errors-config <path>`, `--errors-profile <name>`, `--errors-strict`, and MUST discover `arch-errors.toml` at the project root when no flag is given; built-ins MUST apply with no file.
- **FR-022** [US-1]: The config MUST be parsed as TOML 1.0 (`otoml`) with the vocabulary in Clarifications; an unknown key or role MUST be a parse error naming it.
- **FR-023** [US-1]: Every declared path MUST be checked against the paths the walker saw; per-path misses MUST be printed and recorded in `error_config_unmatched`; a channel whose carrier type matches nothing MUST abort with exit 1; `--errors-strict` MUST make any miss fatal.
- **FR-024** [US-1]: The producer MUST write `error_contract`, `error_config_digest` (effective merged config) and `error_config_source` into `comment_db_meta`.

#### Producer (US-2)
- **FR-025** [US-2]: For each c-carrier node the producer MUST record origins (literal ordinary/extension constructor → canonical path; literal **polymorphic variant** → its bare label; else ⊤ `unknown_error_value`), handler scopes (`match … Error/None` on the head call or its single-let alias chain; declared handlers), sinks, binds (bound-call + continuation edges), transforms (mode), converters, each with `channel = c`, in `exn_origins`/`exn_scopes`/`exn_scope_catches`/`call_exn_scopes`/`exn_edges`.
- **FR-026** [US-2]: An arm MUST be closing iff unguarded and the variables bound by its pattern do not occur in its RHS.
- **FR-027** [US-2]: The carrier check MUST follow the Clarifications rule (type/underlying/aliases, error_arg head or type variable, lift stripping).
- **FR-028** [US-2]: An undeclared bind-shaped operator over a carrier MUST produce ⊤ `inferred_bind` with the site.
- **FR-029** [US-2]: The `exception` channel's rows and query output MUST be unchanged (byte-identical `raises`/`raisers-of`/`exn-stats`).

#### Query (US-3)
- **FR-030** [US-3]: `may-fail <fn> --channel c|all`, `fails-with <E> [--channel c]`, `error-stats [--channel c]` MUST exist with the verdict vocabulary incl. `NOT_A_CARRIER(c)`; propagation MUST treat every edge to a c-carrier as propagating unless its head call is scope-covered or sunk; carrier parameters MUST contribute nothing; transforms/converters per their mode.
- **FR-031** [US-3]: `[summaries]` MUST replace ⊤ `external` for the listed callees on the listed channels.
- **FR-032** [US-3]: A channel absent from `error_contract` MUST refuse with exit 3 `NOT_ANALYSED`; Flat DBs likewise.

#### Tezos, hygiene (US-4)
- **FR-033** [US-4]: A shipped `profiles/tezos-errors.toml` for environment V17 MUST index `proto_alpha/lib_protocol` with exit 0 and MUST be validated against the pre-written oracle.
- **FR-034** [US-4]: `current_schema_version` MUST equal the rebase base's value with the minor component incremented by exactly one, accompanied by a `docs/schema.md` history row for the tables/columns this version adds and claimed by no other row; schema changes MUST be additive; `runner.ml` untouched.

## Acceptance Criteria

- AC-15 [US-1]: scenarios 1–6 → tezt `error_channels.ml` (config section).
- AC-16 [US-2, FR-025..028]: scenarios 1–13 → tezt (producer + query sections).
- AC-17 [US-2, FR-029]: `exn_raise_sets.ml` unchanged and green; self-index exception numbers unchanged.
- AC-18 [US-3]: scenarios 1–6 → tezt.
- AC-19 [US-4, FR-033]: proto_alpha run exit 0; `error-stats` recorded; oracle table matched.
- AC-20 [US-4, FR-034]: schema 1.3 + docs + CHANGELOG + golden.

## Runnable Checks

- CHECK-5 [AC-15..18]: `dune test --root . --force` (tezt `error_channels.ml`, `exn_raise_sets.ml`) — red before, green after.
- CHECK-6 [AC-17, AC-20]: CHECK-2 of `specs/exn-raise-sets.md` (self-index, rules, golden) + `git diff origin/main -- lib/arch_index/runner.ml` empty + FR-034's version check (base+1, unique history row).
- CHECK-7 [AC-19]: `$BIN --build-dir=…/lib_protocol --errors-profile tezos --db-path=/mnt/ssd-external-2to/arch-index-runs/proto-alpha-errors.db` exit 0; `arch-query <db> error-stats --channel tzresult`; oracle table in `briefs/error-channels-qa-scope.md` matched line by line.

## Entities

- `error channel`: a way to fail — `exception`, or a value channel defined by carrier type, error argument, lift/unwrap, and roles (origins, binds, handlers, transforms, converters, sinks).
- `carrier`: a function whose (lifted) return type carries channel c's error type.
- `propagating edge`: a call edge inside a carrier whose callee's c-set flows to the caller unless head-covered by a c scope or sink.
- `closing arm` (value): unguarded arm whose bound variables do not occur in its RHS.
- `transform`: `add` (union with literal arg) or `replace` (mapping function's literal returns or ⊤).
- `converter`: a role that closes channel `from` on its argument and opens an origin on channel `to`.
- `error contract`: `comment_db_meta.error_contract = "v1:<channels>"`; its absence for a channel = NOT_ANALYSED.
- (from `specs/exn-raise-sets.md`) `exception origin`, `handler scope`, `raise-set`, `verdict`, `canonical exception path` — unchanged.
