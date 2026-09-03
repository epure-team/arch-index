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

No configuration is needed for ordinary OCaml. Three channels are built in — `exception`,
`result`, `option` — so an index built the usual way already answers:

```console
$ arch-callgraph-ocaml --build-dir=_build/default --db-path=/tmp/self.db \
    --schema-path=architecture-schema.sql
$ arch-query /tmp/self.db may-fail of_toml --channel result
of_toml: UNBOUNDED (⊤): {}
  reason: external Otoml.Parser.from_string_result
  reason: unknown_exn_value #77:unknown
```

Read that as: *`of_toml` returns a `result`, and this index cannot bound what it can fail with* —
because it calls an external function whose behaviour is unknown, and because one error value at
node #77 is not a literal the analysis can name. Both reasons carry a witness, so neither is a
shrug.

For Tezos, add the shipped profile:

```console
$ arch-callgraph-ocaml --build-dir=… --db-path=… --schema-path=… --errors-profile tezos
```

which adds `tzresult` (and `tzoption`) on top of the built-ins.

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
$ arch-query /tmp/self.db may-fail current_schema_version --channel result
current_schema_version: NOT_A_CARRIER(result)

$ arch-query /tmp/self.db may-fail of_toml --channel bogus_channel
arch-query: NOT_ANALYSED: channel bogus_channel was not emitted by the producer (error_contract = v1:exception,result,option)
```

`NOT_A_CARRIER` is a real, useful answer: the analysis looked and the function cannot fail this
way. `NOT_ANALYSED` is the absence of an answer, and it exits 3 so a script cannot mistake it for
success. **An empty set and "nobody looked" must never be confusable** — every design decision in
this feature follows from that.

### What `--assume-externals-pure` does, and does not, license

It removes ⊤ contributed by *external* calls only. It does not make anything else bounded:

```console
$ arch-query /tmp/self.db may-fail of_toml --channel result --assume-externals-pure
of_toml: UNBOUNDED (⊤): {}
  reason: unknown_exn_value #77:unknown
```

The `external Otoml.Parser.from_string_result` reason is gone; the unnamed error value at node #77
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
$ arch-query /tmp/self.db may-fail bogus_fn --channel result;  echo $?
arch-query: REFUSED — function 'bogus_fn' resolves to no function in this index; 'may-fail' cannot give a sound verdict about a name it does not know.
3
```

`error-stats` is how you judge whether the analysis is worth trusting on your corpus:

```console
$ arch-query /tmp/self.db error-stats --channel result
channel|result
nodes|31
bounded|5 (16.1%)
unbounded|26 (83.9%)
unbounded.external|3
unbounded.may_top_edge|1
unbounded.unknown_exn_value|22
origins|44
escaping_origins|44
```

Read the ⊤ breakdown, not just the bounded share. Here 22 of 26 unbounded nodes are
`unknown_exn_value` — error values the analysis could not name — which tells you precisely where
precision would come from, and that it is not the call graph's fault.

## 4. Configuring your own channels

Write `arch-errors.toml` at the project root (or pass `--errors-config <path>`). Each channel
describes one way of failing:

```toml
[[channel]]
name = "myerr"
# The carrier: a function returning this type can fail on this channel.
type = "Mylib.Err.t_result"
underlying = "Stdlib.result"         # what it is an alias of, if any
aliases = ["Mylib.Err.res"]

# Where a failure is created with a known identity.
origins = ["Mylib.Err.fail", "Mylib.Err.of_string"]

# Calls that propagate the callee's failures into the caller.
binds = ["Mylib.Err.bind", "Mylib.Err.Syntax.let*"]

# Calls that rewrite the failure. mode = "add" keeps the inner set and adds the
# literal argument; mode = "replace" discards it. Choose deliberately: getting
# this backwards silently drops error identities.
[[channel.transforms]]
path = "Mylib.Err.context"
mode = "add"

# Calls that close another channel and open this one.
[[channel.converters]]
path = "Mylib.Err.catch"
from = "exception"

# Calls whose failure is discarded.
sinks = ["Mylib.Err.ignore_error"]
```

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

All three of these exit 1 rather than degrading quietly:

```
arch-errors: --errors-config <path>: <path>: No such file or directory
arch-errors: <path>: arch-errors.toml: channel <c>: unknown key '<k>'
arch-errors: channel <c>: carrier type matched nothing in the indexed corpus
```

The third is the interesting one: you declared a carrier type that never appears in the code being
indexed, which almost always means a typo or a wrong module path — the channel would have silently
answered `NOT_A_CARRIER` for everything. Declared paths that match nothing are recorded in
`comment_db_meta.error_config_unmatched` as a warning; `--errors-strict` promotes those warnings to
a fatal error, which is what you want in CI.

## 5. What the database records

`exn_origins` and `exn_scopes` carry a `channel` column (`DEFAULT 'exception'`, so pre-existing
rows keep meaning what they meant); `exn_edges(call_id, channel, role)` records propagation,
transforms, converters and sinks; `channel_carriers` marks which nodes carry which channel.
`comment_db_meta.error_contract` declares what was analysed. Schema version **1.6**; every change
is additive. See [`docs/schema.md`](schema.md).

## 6. Residuals — what this does not do

Honest limits, so nobody reads more into a verdict than it carries:

- **⊤ is common on real code, and that is the honest answer.** On this repository the `result`
  channel bounds 16.1 % of carriers; on Tezos `proto_alpha`, `tzresult` bounds 27.4 % (44.3 %
  under the externals-pure hypothesis). The dominant reasons are unnamed error values and
  unresolved call edges, not missing rules.
- **A `replace` transform whose mapper is not a literal lambda yields ⊤.** Resolving a named
  mapper's own set is possible and not implemented; the over-approximation is deliberate.
- **`catch_f`-style converters only close the exception channel within the same CFG node.** A
  guarded thunk gets its own lambda node, and the converter's scope does not reach into it, so the
  exception side of such a conversion can stay ⊤ while the value side is bounded. Architectural,
  not a rule gap.
- **Channel selection is first-match-wins over carrier types.** A channel whose carrier type is
  also matched by an earlier channel is unreachable — this is why the shipped Tezos profile's
  `tzoption` is inert behind the built-in `option`.
- **Point-free re-exports (`let f = M.g`) record no call edge**, so they carry no error set. This
  is a pre-existing call-graph limitation, not specific to error channels, and it affects
  `Main.apply_operation` / `finalize_application` in `proto_alpha`.
- **Non-OCaml producers cannot emit these rows yet** — the NDJSON record types do not exist. A
  Flat-schema database answers `NOT_ANALYSED`, which is correct. See the porting guide.
- **`arch-coverage-matrix` does not yet report error channels.** Its analysis vocabulary
  (`callgraph`, `effects`, `types`, `coverage`, `decisions`) predates this feature, so the coverage
  matrix is silent about whether error channels were computed. Until that row exists,
  `comment_db_meta.error_contract` is the authority on what was analysed.
