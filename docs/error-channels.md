# Error channels

**What it answers:** *how can this function fail, and with what identity?* — not only through
exceptions, but through whatever error-carrying type your codebase actually uses (`result`,
`option`, Tezos `tzresult`, your own monad).

Exceptions alone are not the answer in OCaml, because most real codebases move their errors
through values. This feature generalises the exception analysis
([`docs/exception-raise-sets.md`](exception-raise-sets.md)) to any number of **channels**, one per
way of failing, described in a configuration file rather than hardcoded.

- Porting the analysis to another language: [`error-channels-porting.md`](error-channels-porting.md)
- The normative contract: [`specs/error-channels.md`](../specs/error-channels.md)
- Measured results: [`exception-raise-sets-validation.md`](exception-raise-sets-validation.md)

---

## 1. Quick start

> **Every `console` block in this guide was captured by running the command shown, in this
> repository, against an index of its own `_build/default`.** Where a command needs an environment
> variable, the variable is in the command. `arch-query` renders box-drawing tables by default;
> that is what you will see too. Reproduce with:
>
> ```console
> $ ./_build/default/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe \
>     --build-dir=_build/default --db-path=/tmp/self.db --schema-path=architecture-schema.sql
> ```
>
> (The `./arch-callgraph-ocaml` wrapper needs an installed `bin/arch-callgraph-ocaml`; the
> `_build` path above is what CI and [`docs/adr/001-self-index-golden.md`](adr/001-self-index-golden.md)
> use. `./arch-query`, by contrast, falls back to `_build` on its own.)

No configuration is needed for ordinary OCaml. Three channels are built in — `exception`,
`result`, `option` — so an index built the usual way already answers:

```console
$ ./arch-query /tmp/self.db may-fail of_toml --channel result
┌────────────────────────────────────────────────────┐
│                      verdict                       │
├────────────────────────────────────────────────────┤
│ of_toml: UNBOUNDED (⊤): {}                         │
│   reason: external Otoml.Parser.from_string_result │
│   reason: unknown_exn_value #208:unknown           │
└────────────────────────────────────────────────────┘
```

Read that as: *`of_toml` returns a `result`, and this index cannot bound what it can fail with* —
because it calls an external function whose behaviour is unknown, and because one error value at
node #208 is not a literal the analysis can name. Both reasons carry a witness, so neither is a
shrug. (Node numbers are database row ids: yours will differ, the shape will not.)

Box drawing is the default because a human reads these one at a time. For scripts, set
`ARCH_QUERY_FORMAT=list` — the same answer, one `key|value` per line:

```console
$ ARCH_QUERY_FORMAT=list ./arch-query /tmp/self.db may-fail of_toml --channel result
of_toml: UNBOUNDED (⊤): {}
  reason: external Otoml.Parser.from_string_result
  reason: unknown_exn_value #208:unknown
```

For Tezos, add the shipped profile:

```console
$ ./_build/default/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe \
    --build-dir=… --db-path=… --schema-path=… --errors-profile tezos
```

which adds `tzresult` on top of the built-ins, and extends the built-in `option` channel with the
protocol environment's own `Option_syntax`/`Lwt_option_syntax` bind vocabulary.

## 2. Reading a verdict

This is the part worth reading carefully — the whole feature exists to keep these five apart.

| Verdict | Means | Exit |
|---|---|---|
| `BOUNDED: {A, B}` | The complete set. It can fail with `A` or `B` and **nothing else**. | 0 |
| `BOUNDED: {}` | It is a carrier for this channel, and provably never fails on it. | 0 |
| `UNBOUNDED (⊤): {A}` | It can fail with `A` **and possibly more** — the listed reasons say where the analysis lost track. Never treat the listed part as complete. | 0 |
| `BOUNDED_UNDER_HYP(externals_pure): {A}` | Bounded **only if** you accept that every external call is pure on this channel. A hypothesis you are asserting, not a fact the index proved. | 0 |
| `NOT_A_CARRIER(result)` | The function does not use this channel at all — it does not return a `result`. | 0 |
| `NOT_ANALYSED` | **Nobody looked.** The producer never emitted this channel. | 3 |

The last two are the ones people conflate, and conflating them is how a static analysis quietly
lies:

```console
$ ./arch-query /tmp/self.db may-fail current_schema_version --channel result
┌───────────────────────────────────────────────┐
│                    verdict                    │
├───────────────────────────────────────────────┤
│ current_schema_version: NOT_A_CARRIER(result) │
└───────────────────────────────────────────────┘

$ ./arch-query /tmp/self.db may-fail of_toml --channel bogus_channel; echo "exit $?"
arch-query: NOT_ANALYSED: channel bogus_channel was not emitted by the producer (error_contract = v1:exception,result,option)
exit 3
```

`NOT_A_CARRIER` is a real, useful answer: the analysis looked and the function cannot fail this
way. `NOT_ANALYSED` is the absence of an answer, and it exits 3 so a script cannot mistake it for
success. **An empty set and "nobody looked" must never be confusable** — every design decision in
this feature follows from that.

### What `--assume-externals-pure` does, and does not, license

It removes ⊤ contributed by *external* calls only. It does not make anything else bounded:

```console
$ ./arch-query /tmp/self.db may-fail of_toml --channel result --assume-externals-pure
┌──────────────────────────────────────────┐
│                 verdict                  │
├──────────────────────────────────────────┤
│ of_toml: UNBOUNDED (⊤): {}               │
│   reason: unknown_exn_value #208:unknown │
└──────────────────────────────────────────┘
```

The `external Otoml.Parser.from_string_result` reason is gone; the unnamed error value at node #208
remains, so the verdict is still ⊤. Use the flag to ask "how much of my ⊤ is my own code?" — never
to manufacture a clean answer. A `BOUNDED_UNDER_HYP` verdict is a claim about your dependencies
that you are making, and it is labelled that way on purpose.

## 3. Commands

```console
arch-query <db> may-fail    <fn> --channel <name|all> [--assume-externals-pure] [--builtin-summaries]
arch-query <db> fails-with  <E>  [--channel <name>]   [--assume-externals-pure] [--builtin-summaries]
arch-query <db> error-stats      --channel <name|all> [--assume-externals-pure] [--builtin-summaries]
```

`fails-with` inverts the question — who can fail with this identity — and defaults to the
`exception` channel. `raises` / `raisers-of` / `exn-stats` are the pre-existing exception-only
spellings and continue to work unchanged; `may-fail … --channel exception` is the same query.

An unknown function name is refused rather than answered:

```console
$ ./arch-query /tmp/self.db may-fail bogus_fn --channel result; echo "exit $?"
arch-query: REFUSED — function 'bogus_fn' resolves to no function in this index; 'may-fail' cannot give a sound verdict about a name it does not know.
exit 3
```

`error-stats` is how you judge whether the analysis is worth trusting on your corpus:

```console
$ ./arch-query /tmp/self.db error-stats --channel result
┌─────────────────────────────┬────────────┐
│           metric            │   value    │
├─────────────────────────────┼────────────┤
│ channel                     │ result     │
│ nodes                       │ 60         │
│ bounded                     │ 14 (23.3%) │
│ unbounded                   │ 46 (76.7%) │
│ unbounded.external          │ 4          │
│ unbounded.may_top_edge      │ 4          │
│ unbounded.unknown_exn_value │ 38         │
│ origins                     │ 97         │
│ escaping_origins            │ 97         │
│ scopes                      │ 75         │
│ fixpoint_seconds            │ 0.001      │
└─────────────────────────────┴────────────┘
```

Read the ⊤ breakdown, not just the bounded share. Here 38 of 46 unbounded nodes are
`unknown_exn_value` — error values the analysis could not name — which tells you precisely where
precision would come from, and that it is not the call graph's fault.

Those numbers are for this repository's whole `_build/default` (85 modules, 2131 function nodes);
a different build-dir scope gives different totals, so quote the scope whenever you quote a
percentage.

## 4. Configuring your own channels

Write `arch-errors.toml` at the project root (or pass `--errors-config <path>`). Each channel
describes one way of failing:

```toml
# Each channel is one table under [channel.<name>] — the table name IS the
# channel name.
[channel.myerr]
# The carrier: a function returning this type can fail on this channel.
type = "Mylib.Err.t_result"
underlying = ["Stdlib.result"]      # other spellings of the same type
aliases = ["Mylib.Err.res"]
error_arg = 2                       # 1-based: which type argument is the error
error_type = "Mylib.Err.t"

# Where a failure is created with a known identity, and which argument
# carries it.
origins = [
  { path = "Mylib.Err.fail", arg = 1 },
  { path = "Mylib.Err.of_string", arg = 1 },
]

# Calls that propagate the callee's failures into the caller.
binds = ["Mylib.Err.bind", "Mylib.Err.Syntax.let*"]

# Calls that consume a failure. arg = the carrier-valued argument.
handlers = [{ path = "Mylib.Err.value", arg = 1 }]

# Calls that rewrite the failure. mode = "add" keeps the inner set and adds
# the literal at arg; mode = "replace" discards it. Choose deliberately:
# getting this backwards silently drops error identities.
transforms = [{ path = "Mylib.Err.context", mode = "add", arg = 1 }]

# Calls that close another channel and open this one.
converters = [{ path = "Mylib.Err.catch", from = "exception", to = "myerr", arg = 1 }]

# Calls whose failure is discarded.
sinks = ["Mylib.Err.ignore_error"]
```

That block is verbatim what the parser accepts — it was fed to
`--errors-config` and loaded before this paragraph was written. The previous
revision of this guide showed a `[[channel]]` array-of-tables form with a
`name =` key, which the decoder rejects outright:
`arch-errors.toml: channel must be a table`. `lift` and `unwrap` are the two
keys not shown here; both take a list of TYPE paths (wrapper constructors
stripped before the carrier check — `Lwt.t`, a `trace` container), never
value paths.

Merge order is **built-in < profile < user file**, so your file refines rather than replaces the
defaults. The effective configuration is digested into the database
(`comment_db_meta.error_config_digest`), so a query can tell which configuration produced an
answer.

### Discovery and precedence

`--errors-config <path>` wins; otherwise `arch-errors.toml` at the project root; otherwise the
built-ins alone. `--errors-profile <name>` resolves through `ARCH_ERRORS_PROFILES_DIR`, then
`<root>/profiles`, then the directory beside the executable — first hit wins, and the chosen path
is printed so a run is reproducible from its own log.

### When something is wrong

All four of these exit 1 rather than degrading quietly:

```
arch-errors: --errors-config <path>: <path>: No such file or directory
arch-errors: <path>: arch-errors.toml: channel <c>: unknown key '<k>'
arch-errors: channel <c>: carrier type matched nothing in the indexed corpus
arch-errors: channel <c>: carrier type '<t>' is already claimed by channel '<c'>', declared
  earlier — channel selection is first-match-wins, so <c> could never own a carrier and every
  query on it would answer NOT_A_CARRIER(<c>) about code it never examined. Reorder the channels
  so the more specific one comes first, or merge the two declarations into one.
```

The last two are the interesting ones, and they are the same bug in two disguises: a declaration
that can never be honoured, published as if it were a fact about your code.

- *carrier type matched nothing* — you declared a type that never appears in the code being
  indexed, almost always a typo or a wrong module path.
- *already claimed by* — your channel is behind another one that covers the same carrier type.
  Selection is first-match-wins, so yours can never own a carrier, yet it would still be listed in
  `error_contract` and answer `NOT_A_CARRIER` for every function in the corpus. Two channels over
  one carrier type are fine when a distinguishing `error_type`/`error_arg` tells them apart; this
  fires only when the earlier channel would swallow everything.

Declared paths that match nothing are recorded in `comment_db_meta.error_config_unmatched` as a
warning; `--errors-strict` promotes those warnings to a fatal error, which is what you want in CI.
Strict only counts declarations *you* are responsible for: an untouched built-in channel's own
`Stdlib.*` paths stay warnings (one of them, `Stdlib.option`, is a spelling the compiler never
prints, so counting them made `--errors-strict` unsatisfiable everywhere). Redeclare
`[channel.option]` in your own file and the whole channel, built-in paths included, comes back
under strict — it is yours now.

## 5. What the database records

`exn_origins` and `exn_scopes` carry a `channel` column (`DEFAULT 'exception'`, so pre-existing
rows keep meaning what they meant); `exn_edges(call_id, channel, role)` records propagation,
transforms, converters and sinks; `channel_carriers` marks which nodes carry which channel.
`comment_db_meta.error_contract` declares what was analysed. Schema version **1.8**; every change
is additive. See [`docs/schema.md`](schema.md).

Re-indexing into an existing database drops and recreates all of these first, so a second run over
the same file produces the same rows as the first — not twice as many. If you are extending the
schema, add your table to `Arch_index_support.schema_tables_to_drop` in the same commit.

## 6. Residuals — what this does not do

Honest limits, so nobody reads more into a verdict than it carries:

- **⊤ is common on real code, and that is the honest answer.** Measured, not estimated: over this
  repository's whole `_build/default` (2131 function nodes, 60 of them `result` carriers) the
  `result` channel bounds **14 of 60, 23.3 %** — the `error-stats` block in §3 is that
  measurement. Over
  `tezos/_build/default/src/proto_alpha/lib_protocol` (14 452 nodes, 2137 `tzresult` carriers)
  with `--errors-profile tezos`, `tzresult` bounds **585 of 2137, 27.4 %**, and 947 of 2137,
  44.3 %, under the externals-pure hypothesis. The dominant reasons differ by corpus: unnamed
  error values here (38 of 46 ⊤ nodes), unresolved call edges on `proto_alpha` (1148 of 1552) —
  neither is a missing rule.
- **A `replace` transform whose mapper is not a literal lambda yields ⊤.** Resolving a named
  mapper's own set is possible and not implemented; the over-approximation is deliberate.
- **`catch_f`-style converters only close the exception channel within the same CFG node.** A
  guarded thunk gets its own lambda node, and the converter's scope does not reach into it, so the
  exception side of such a conversion can stay ⊤ while the value side is bounded. Architectural,
  not a rule gap.
- **Channel selection is first-match-wins over carrier types**, so a function is a carrier of at
  most one channel. This is a real narrowing of FR-027's per-channel carrier check, and it is why
  the shipped Tezos profile no longer declares a separate `tzoption`: its carrier type was plain
  `option`, already owned by the built-in `option` channel, so it could never have matched. Such a
  declaration is now **refused at load time** rather than shipped inert (§4), and the profile
  extends `[channel.option]` with the environment's own bind vocabulary instead. If you genuinely
  need two channels over one carrier type, give them distinguishing `error_type`/`error_arg`
  declarations; discriminating by bind vocabulary as well as by carrier type is not implemented.
- **The shipped Tezos profile is not `--errors-strict`-clean on `proto_alpha`.** Measured on a
  fresh index of `tezos/_build/default/src/proto_alpha/lib_protocol`, `--errors-profile tezos
  --errors-strict` exits 1 on 11 declared paths that never appear in that corpus: ten
  `Error_monad…return_none/return_true/return_unit/return_false` sinks and the
  `…Error_monad.Pervasives.result` underlying spelling. The identifiers themselves are used
  heavily there (`return_unit` alone occurs 888 times in the sources), so they resolve under a
  different qualified spelling than the profile declares — a path-inventory question about the
  profile, not a bug in strict, which is reporting exactly what it is for. Without
  `--errors-strict` the run exits 0 and those declarations are simply inert; the misses are listed
  in `comment_db_meta.error_config_unmatched`.
- **Point-free re-exports (`let f = M.g`) record no call edge**, so they carry no error set. This
  is a pre-existing call-graph limitation, not specific to error channels, and it affects
  `Main.apply_operation` / `finalize_application` in `proto_alpha`.
- **Non-OCaml producers cannot emit these rows yet** — the NDJSON record types do not exist. A
  Flat-schema database answers `NOT_ANALYSED`, which is correct. See the porting guide.
- **`arch-coverage-matrix` does not yet report error channels.** Its analysis vocabulary
  (`callgraph`, `effects`, `types`, `coverage`, `decisions`) predates this feature, so the coverage
  matrix is silent about whether error channels were computed. Until that row exists,
  `comment_db_meta.error_contract` is the authority on what was analysed.
