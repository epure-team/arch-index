# Edge-kind contract & soundness

arch-index tags every `calls` row with a `kind` value that encodes what is statically knowable about the call:

| `calls.kind` | Meaning | Use |
|---|---|---|
| `MUST` | Uniquely-resolved static call that runs on **every** execution of the caller (dominance) | `reaches` (a positive path = must-reach ground truth) |
| `MAY_ENUMERATED` | Dynamic call bounded to a candidate set (e.g. all interface implementers) | Over-approx closure for `unreachable` |
| `MAY_TOP` | Unresolvable / dynamic / reflective / FFI call — **could call anything** | Forces `UNKNOWN`; never silently dropped |

When a backend produces a ⊤-marked index it sets `callgraph_contract = v1` in `comment_db_meta`. Backends that cannot tag edges must not produce a DB at all — the loader aborts on missing or invalid `kind` values (exit 2) to prevent a silent false-confidence index.

### Backends

| Backend | Edge kinds | Notes |
|---|---|---|
| Go SSA (`callgraph-go` → `arch-load`) | ✅ execution-sound | A statically-resolved call (`StaticCallee() != nil`) is `MUST` only if its SSA basic block **post-dominates the function entry** (runs on every execution); a call in an `if`/`switch`/`select`/loop block is demoted to `MAY_TOP`. CHA candidate set → `MAY_ENUMERATED`; interface/closure/reflection/cgo → `MAY_TOP`. Output is emitted in deterministic sorted order. |
| OCaml CMT (`arch-callgraph-ocaml`) | ✅ execution-sound | A call is `MUST` only if it runs on **every** execution of the enclosing function (dominance): it sits on the unconditional straight-line path and resolves to a unique same-module/qualified target. Every call in a position that is *not* guaranteed to run is demoted to `MAY_TOP`. Named local function passed as a callback → `MAY_ENUMERATED`. Resolution is `Ident`-stamp-based, so a parameter/local that shadows a top-level name is correctly `MAY_TOP` (not a spurious `MUST`). |

**Both backends now define `MUST` as execution-sound dominance** — the definitions agree, so a
`reaches`/`unreachable` verdict means the same thing regardless of source language. The Go backend
computes dominance precisely over the SSA control-flow graph (post-dominators); the OCaml backend
approximates it syntactically over the Typedtree (no CFG). See the shared-residuals note below for
the two places this dominance is deliberately *insensitive*.

### OCaml dominance-MUST — what is demoted to `MAY_TOP`

A `MUST` edge is *execution-sound*: it never over-claims that a call happens. The walker
(`arch_index_cmt.ml`, `collect_calls_from_expr`) demotes a call to `MAY_TOP` whenever it sits in a
position that is not guaranteed to run on every execution of the enclosing function:

- **Deferred bodies** — function literals (`fun …`), `lazy` thunks, object method bodies, and
  un-applied functor bodies: they run only if invoked / forced / applied.
- **Conditional bodies** — `if`/`match` arms, `try` handlers, loop bodies (`while`/`for`, which may
  iterate zero times), and the right operand of a short-circuit `&&` / `||`.
- **Optional-argument default expressions** (`?(x = e)`) — `e` runs only when the caller omits `x`.

Only the genuinely-unconditional positions stay at `MUST`: a sequence step, a `let`-binding RHS, the
scrutinee of a `match`, an `if` condition, a `try` body, the left operand of `&&`/`||`, and call
arguments. Demoted calls are **never dropped** — they are still recorded as `MAY_TOP`, so
`unreachable` stays a sound over-approximation. These cases are locked by
`selftest-callgraph-soundness.sh` (run `STRICT=1` in CI).

### Shared residuals (accepted) — where dominance is deliberately insensitive

Both backends' dominance is **termination-, exception-, and divergence-insensitive**, the standard
approximation of every practical intraprocedural analysis without a whole-program termination /
`noreturn` oracle. Concretely, a call is still `MUST` even when a *preceding* construct may prevent
it from running:

- **After a possibly-non-terminating loop** — `while c do … done; f ()` marks `f` `MUST` though the
  loop may spin forever.
- **After a call that may raise/panic/exit** — `g (); f ()` (or Go `mayPanic(); f()`) marks `f`
  `MUST` though `g` may divert.
- **After an *unconditional* divergence** — `raise Exit; f ()` / `failwith …; f ()` / Go
  `os.Exit(0); f()` marks `f` `MUST` though `f` is dead code.
- An `assert` condition is treated as conditional (`MAY_TOP`) since `-noassert` elides it — a mild
  under-claim, the opposite (safe) direction.

Every one of these only ever **over-claims `reaches`** (a must-path that might not run) — the
fail-safe direction for a blocking gate. **None can produce a false `UNREACHABLE`**: the calls are
always recorded, so `unreachable` (the security-critical over-approximation) stays sound. Closing
these would require a `noreturn`/termination analysis (a curated diverging-function set plus loop
termination reasoning); tracked as future work, not a soundness blocker for `unreachable`.

Both backends also share one **precision** limitation (not a soundness issue): when *every* arm of
a branch calls the same target (`if b then f () else f ()`), the call is `MAY_TOP`, not `MUST` —
neither backend reasons about callee-level coverage across mutually-exclusive blocks.

**Precision follow-up (not soundness):** the syntactic walk approximates dominance without a real
control-flow graph, so ~76% of self-index edges are `MAY_TOP` — sound but blunt. The precise version
builds a per-function CFG + post-dominator tree (MUST = post-dominance) and recovers precision by
linking invoked higher-order-function bodies; see
[docs/research/control-flow-coverage-analysis.md](research/control-flow-coverage-analysis.md).

## Reachability semantics

**`reaches A B`** — MUST-only under-approximation.
A positive result (`PATH EXISTS (must-reach)`) is ground truth: there is a call chain from A to B in
which **every hop runs on every execution** of its caller (each edge is a dominance-`MUST`). A
negative result (`no MUST path`) does not prove unreachability — the call may still happen on some
executions via `MAY_*` edges (use `unreachable` for that direction).

**`unreachable A B`** — sound over-approximation (requires ⊤-marking).
Returns one of three verdicts:

- `REACHABLE (may-reach)` — B is in the MUST ∪ MAY_ENUMERATED closure of A (not definitely reachable, but plausibly so).
- `UNREACHABLE` — B is outside the full closure AND no MAY_TOP edge is reachable from A. This is a sound negative: the closed-universe assumption holds.
- `UNKNOWN` — A can reach a MAY_TOP edge; the universe is open and the verdict cannot be determined.

**`escapes A`** — lists the MAY_TOP edges reachable from A: the frontier that forces `UNKNOWN`.

## Agents and code-quality enforcement

arch-index makes call-graph reachability answerable as a SQL query. This makes it suitable for use by both AI agents and human reviewers to enforce invariants:

- **Reachability gates**: "does `paymentHandler` reach any `log_plaintext` sink?" → `reaches paymentHandler log_plaintext`. Block a PR if the answer is PATH EXISTS.
- **Attack surface audits**: `arch-query db.sqlite exported` lists every externally-callable function. An agent can cross-reference this against an allowlist.
- **Panic/error-exit reachability**: "is `os.Exit` reachable from `ServeHTTP`?" → `reaches ServeHTTP os.Exit`. Useful for detecting accidental shutdown paths in handlers.
- **Variant analysis**: find all callers of a fixed function to check for siblings: `arch-query db.sqlite callers-of vulnerableHelper`.
- **Documentation quality gate**: every function row carries a `comment_quality_score`. An agent can query `SELECT name FROM functions WHERE comment_quality_score < 50 AND exposed = 1` to find underdocumented public API.
- **Test coverage linking**: `{tests}` sections in doc-comments are parsed and stored. An agent can verify that every exported function has at least one linked test case.

For the formal soundness proof see [SPEC-sound-callgraph.md](../SPEC-sound-callgraph.md).
