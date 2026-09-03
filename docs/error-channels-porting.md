# Porting the error-channel analysis to another language

**Audience:** someone writing or extending an arch-index producer (Go, Rust, TypeScript, Python,
C…) who wants that language's failures to answer `arch-query may-fail`.
**Companion documents:** `docs/error-channels.md` (what the feature does and how to use it),
`specs/error-channels.md` (the normative contract), `docs/edge-kind-contract.md` (the ⊤ marking
this builds on), `docs/adr/002-*` (`sound_with_top` / `heuristic` / `asserted`).

The OCaml producer is the reference implementation. **Nothing in the query layer is
OCaml-specific**: it reads rows. If your producer emits the rows described here, `may-fail`,
`fails-with` and `error-stats` work for your language with no query-side change.

---

## 1. The model in language-neutral terms

A **channel** is one way a function can fail. Two shapes exist:

| Shape | The failure travels… | Examples |
|---|---|---|
| **unwinding** | out of band, through every frame, until a handler | OCaml/Java/Python exceptions, Rust `panic!`, Go `panic` |
| **value** | in the returned value, only where the caller propagates it | OCaml `result`/`tzresult`, Rust `Result`, Go `(T, error)`, TS `neverthrow`/`Effect`, `option`/`Option`/`None` |

Seven roles describe any of them. Your producer's job is to recognise these seven things in your
language's syntax and record them.

**The "Recorded as" column below is what the reference producer actually writes**, verified
against the code, not against the schema's vocabulary. The important surprise is that only three
of the seven are rows of their own: **a transform, a converter and a sink are expressed through
`exn_origins` and through the *absence* of a propagating edge**, never through a distinct
`exn_edges.role`. See "Reserved-but-unused roles" below before you implement against the CHECK
constraint.

| Role | What it is | Recorded as |
|---|---|---|
| **origin** | where a failure is *created* with a known identity | an `exn_origins` row: `channel`, `form`, `exn_path` (the identity, or NULL if not statically known), `escapes`, line/col |
| **carrier** | a function that can *return* this channel's failure | a `channel_carriers` row for the function node: `(function_id, channel)` |
| **propagating edge** | a call whose callee's failures can reach the caller | an `exn_edges` row with `role='propagates'` — **the only role the producer writes and the only one the solver reads** (`arch_index.ml`'s single `insert_exn_edge` call site; `arch_exn.ml`'s `role='propagates'` join) |
| **handler scope** | a region where some identities are *caught* | an `exn_scopes` row (carries `channel`) + `exn_scope_catches` rows for the caught identities, linked to each covered call by a `call_exn_scopes` row |
| **transform (`add`)** | a call that unions a new identity into the failure set | an `exn_origins` row on the transform's channel, at the call site, whose `exn_path` is the literal at the declared `arg`. The inner set survives on its own: the *other* argument's head call is an ordinary propagating edge, so nothing extra records it |
| **transform (`replace`)** | a call that discards the inner set and substitutes its own | **no row says "replace".** Every argument other than the mapper is marked *sunk*, so those calls emit **no propagating edge** — the inner set disappears by absence. The mapper's literal return, when the mapper is a lambda literal, becomes an `exn_origins` row; otherwise an `unknown` origin, i.e. ⊤ |
| **converter** | a call that closes one channel and opens another (`try/catch` returning a `Result`) | **two facts, no `convert` row.** (1) A catch-all `exn_scopes` row on the **`from`** channel covering the guarded argument's call, linked through `call_exn_scopes` — that is what closes the source channel. (2) An `exn_origins` row on the **`to`** channel naming the converted identity: the declared `error`, else the handler lambda's literal return, else the opaque `"<to>:converted_<from>"` |
| **sink** | a call whose failure is *discarded* | **no row at all.** The call site simply emits no propagating edge. Absence *is* the record |

Everything else — the lattice, the fixpoint, handler subtraction, ⊤ reasons, the verdicts — is
computed by `lib/arch_tools/arch_exn.ml` from those rows.

### Which tables carry a `channel`

Four do: `exn_scopes`, `exn_origins`, `exn_edges`, `channel_carriers`. Three do **not**:

- `exn_scope_catches (scope_id, exn_path)` — the scope it points at already carries the channel;
- `call_exn_scopes (call_id, scope_id)` — likewise, and note `call_id` is its **primary key**, so
  a call has at most one scope across all channels;
- `exn_rebinds (alias_path, target_path)` — a name-canonicalisation table, channel-independent.

Do not add a `channel` column to those in your adapter, and do not expect to filter on one.

### Reserved-but-unused roles — do not implement these

`exn_edges.role`'s CHECK constraint admits six values:

```sql
role TEXT NOT NULL CHECK(role IN ('propagates','bind_arg','sink','transform_add','transform_replace','convert'))
```

Only **`propagates`** is written by the reference producer and only `propagates` is read by the
solver. `bind_arg`, `sink`, `transform_add`, `transform_replace` and `convert` are **reserved
vocabulary with no consumer**: a row carrying one of them is accepted by the database and then
ignored by every query. A producer that emitted them — and that therefore did *not* emit
`propagates` — would silently answer nothing.

The constraint is deliberately left wide rather than narrowed to `('propagates')`. Narrowing would
be a schema change requiring a version bump and a migration, to buy nothing: an unknown role is
already rejected, and the five reserved names cost only this paragraph. If a later slice gives one
of them a consumer, it can start writing rows without touching the schema. Treat the CHECK list as
*what the column may one day hold*, and this table as *what to emit today*.

---

## 2. The five obligations (this is the part that matters)

1. **Never omit a possible failure.** Omission is unsound and is treated as a CRITICAL defect in
   review. If you cannot determine an identity, emit an origin with `exn_path = NULL` and
   `form = 'unknown'`; the query renders it ⊤ `unknown_exn_value` with a witness. An honest ⊤
   is always acceptable; a missing element never is.
2. **Over-approximate deliberately, and only in the safe direction.** Extra elements, or ⊤ where a
   precise answer was possible, cost precision. Missing elements cost correctness. When a rule is
   ambiguous, choose the version that reports *more*.
3. **Only close what is really caught.** A handler scope must cover exactly the calls the handler
   can intercept. If you are not certain a construct catches, do not record it as closing — the
   OCaml producer, for instance, treats a handler arm that merely *mentions* the caught value as
   non-closing, because it may re-raise it.
4. **Declare what you did and did not analyse.** Set `comment_db_meta.error_contract` to
   `v1:<comma-separated channels you emitted>`. A channel absent from that list makes the query
   answer `NOT_ANALYSED` (exit 3) instead of an empty set. *An empty answer and "nobody looked"
   must never be confusable* — this is the project's core rule, not a nicety.
5. **Carrier-ness should be a local fact.** In OCaml the callee's type is available at the call
   site, so an edge's channel is stamped at emission with no cross-unit lookup. If your language
   gives you the same (Rust's HIR/MIR, Go's `go/types`, TS's checker all do), do it that way: it
   avoids a second pass entirely.

---

## 3. Mapping your language

### Rust
| Role | Construct |
|---|---|
| carrier | return type `Result<T, E>` (after stripping `impl Future`/async); `Option<T>` for the option channel |
| origin | `Err(E::Variant(..))`, `bail!`, `Err(anyhow!(..))`, `.ok_or(E::X)`; identity = the enum variant path |
| propagating edge | `?` on a call, an early `return Err(..)`, a tail call returning `Result` |
| handler | `match r { Err(E::X) => …, .. }`, `if let Err(..)`, `unwrap_or_else`, `.ok()` |
| transform | `.map_err(..)` (**replace**), `.context(..)`/`.with_context(..)` (**add** — anyhow keeps the source) |
| converter | `catch_unwind` (panic → `Result`), `From`/`?` conversions that change the error type — model as `replace` with the target identity when the `From` impl is resolvable, else ⊤ |
| sink | `let _ = …`, `.ok()` used for effect, `drop(..)` |
| notes | `anyhow::Error` is type-erased: its identity is not statically known, so `bail!("msg")` is an `unknown` origin, not a bounded one. Say so rather than inventing a string identity. `?` with a `From` conversion is the single most important thing to model correctly. |

### Go
| Role | Construct |
|---|---|
| carrier | **a convention, not a type**: a function whose *last result* is `error`. The config vocabulary needs a `carrier = "convention:last-result-error"` form for this — it is the one place Go does not fit the type-based model |
| origin | `errors.New("…")`, `fmt.Errorf(…)` (identity = ⊤ unless a sentinel), a returned sentinel `ErrFoo` (identity = the package-level var), a custom error type literal |
| propagating edge | `if err != nil { return …, err }`, `return f()` in tail position |
| handler | `if errors.Is(err, ErrFoo)`, `errors.As(&target)`, a branch that returns `nil` error |
| transform | `fmt.Errorf("…: %w", err)` — **add** (the `%w` verb wraps and keeps the source); without `%w` it is **replace** and the original identity is lost |
| converter | `recover()` in a deferred function returning an error — panic channel → value channel |
| sink | `_ = f()`, ignoring the error result |
| notes | `%w` vs no-`%w` is exactly the `add`/`replace` distinction, and getting it backwards silently drops error identities. Sentinel `var ErrX = errors.New(...)` gives you real identities; `fmt.Errorf` without a sentinel does not. |

### TypeScript
| Role | Construct |
|---|---|
| carrier | a *library* type, not a language one: `Result<T, E>`/`ResultAsync` (neverthrow), `Effect<A, E, R>` (Effect-TS), or a hand-rolled discriminated union `{ ok: false, error: … }` |
| origin | `err(E)`, `Effect.fail(E)`, `{ ok: false, error: … }`; identity = the discriminant literal or class name |
| propagating edge | `.andThen(..)`, `yield*` in an Effect generator, `await` on a returned carrier |
| handler | `.mapErr`/`.orElse`/`match`, `Effect.catchTag`/`catchAll`, a `switch` on the discriminant |
| transform | `.mapErr(..)` (replace), `Effect.mapError` (replace), tag-adding wrappers (add) |
| converter | `Effect.tryPromise`, `Result.fromThrowable` — exception → value channel |
| notes | Because the carrier is a library type, TS needs **no new config vocabulary** — declare the library's type path and combinators like any other channel. This is the case the config design was made for. |

### Python / C
Python: exceptions only (there is no idiomatic value channel); the interesting work is
`raise`/`except`/`finally` and re-raise, exactly parallel to OCaml. C: no channel model applies —
error codes are values with no type-level identity; ingest a C analyser's findings through the
SARIF adapter instead (roadmap 2.3) rather than declaring a channel.

---

## 4. Emitting the rows

Main schema (`architecture-schema.sql`): write `exn_origins`, `exn_scopes`,
`exn_scope_catches`, `call_exn_scopes`, `exn_edges`, `channel_carriers`, all carrying `channel`;
then `comment_db_meta.error_contract`. Every insert must go through a counted statement so
rejected rows are attributed (`exec_stmt ~what:"<table>"` in the OCaml producer) — a silently
dropped row is a silently wrong answer.

Flat/NDJSON producers (`lib/arch_db/arch_load.ml`): **the record types for these rows do not exist
yet.** Adding them is roadmap item 3.4-bis §5 and is the prerequisite for any non-OCaml producer.
Until then a Flat database answers `NOT_ANALYSED`, which is correct — not a bug to work around.
The expected shape, for whoever adds it, mirrors the existing `function`/`call` records:
`{"type":"error_origin","channel":…,"function_name":…,"form":…,"error_path":…,"escapes":…}` and
so on, with `kind`-style validation that rejects an unknown `channel`/`form`/`role` loudly.

---

## 5. Conformance checklist

Before claiming a channel is supported:

- [ ] `error_contract` lists exactly the channels you emit — no more.
- [ ] A function of the language's ordinary "cannot fail" shape answers `NOT_A_CARRIER(c)`, not
      `BOUNDED: {}`.
- [ ] A failure created and returned unchanged is `BOUNDED` with the right identity.
- [ ] A failure caught by an enclosing handler **at the call site** disappears from the caller's
      set (this is the feature's whole point — subtraction happens per call, not per function).
- [ ] A handler that re-emits the value it caught does **not** close it.
- [ ] An unresolvable identity is ⊤ `unknown_exn_value` *with a witness*, never absent.
- [ ] A call through a function parameter / interface / dynamic dispatch yields ⊤ `may_top_edge`
      with the call site as witness.
- [ ] `add` and `replace` transforms are distinguished (Go's `%w`, Rust's `context` vs `map_err`).
- [ ] Measured on a real corpus of that language, with the bounded share and the dominant ⊤
      reason recorded — the OCaml precedent is `docs/exception-raise-sets-validation.md`
      (three corpora, stable 18–25 % bounded, ⊤ dominated by `external` and `may_top_edge`).
- [ ] The other channels' numbers are unchanged by your addition (assert on an external corpus
      you do not control, not on this repository — its own counts move whenever code is added).

One gap to be aware of rather than work around: `arch-coverage-matrix`'s analysis vocabulary
(`callgraph`, `effects`, `types`, `coverage`, `decisions`) predates this feature and has no
`error_channels` row, so the coverage matrix currently says nothing about whether error channels
were analysed for your language. `comment_db_meta.error_contract` is the authority until that row
exists. If you add a producer, adding the row is the natural companion change — it is the same
honest-absence guarantee in the place users look for it.
