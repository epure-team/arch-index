# Edge-kind contract & soundness

arch-index tags every `calls` row with a `kind` value that encodes what is statically knowable about the call:

| `calls.kind` | Meaning | Use |
|---|---|---|
| `MUST` | Uniquely-resolved static call that runs on **every** execution of the caller (dominance: its CFG block post-dominates the entry) | `reaches` (a positive path = must-reach ground truth) |
| `MAY_ENUMERATED` | Call bounded to a **known candidate set** — a conditional call to a resolved callee (candidate set of one), a callback/lambda passed by value, or a CHA interface set | Over-approx closure for `unreachable` (can prove UNREACHABLE) |
| `MAY_TOP` | Genuinely **unknowable** target — computed head, parameter call, dynamic module root, reflection/cgo, over-application residual | Forces `UNKNOWN`; never silently dropped |

When a backend produces a ⊤-marked index it sets `callgraph_contract = v1` in `comment_db_meta`. Backends that cannot tag edges must not produce a DB at all — the loader aborts on missing or invalid `kind` values (exit 2) to prevent a silent false-confidence index.

### Backends

| Backend | Edge kinds | Notes |
|---|---|---|
| Go SSA (`callgraph-go` → `arch-load`) | ✅ execution-sound | A statically-resolved call (`StaticCallee() != nil`) is `MUST` only if its SSA basic block **post-dominates the function entry** (runs on every execution); a call in an `if`/`switch`/`select`/loop block is demoted to `MAY_ENUMERATED` (candidate set of one). CHA candidate set → `MAY_ENUMERATED`; interface/closure/reflection/cgo (incl. in-package `_Cfunc_*` wrappers) → `MAY_TOP`. Output is emitted in deterministic sorted order. |
| OCaml CMT (`arch-callgraph-ocaml`) | ✅ execution-sound | Each function body — and each promoted lambda — is lowered to a real per-node **CFG** (`arch_index_cfg.ml`); a call is `MUST` iff its block post-dominates the node's entry AND the head resolves uniquely AND the application is saturated. Conditional/partial calls to resolved callees → `MAY_ENUMERATED`; unknowable targets → `MAY_TOP`. Resolution is `Ident`-stamp-based (shadows never forge a `MUST`). |

**Both backends define `MUST` as execution-sound dominance computed over a real CFG** (Go: SSA
post-dominators; OCaml: Typedtree lowered onto a per-node CFG with an iterative post-dominance
fixpoint) — the definitions agree, so a `reaches`/`unreachable` verdict means the same thing
regardless of source language.

### OCaml CFG model

The walker (`arch_index_cmt.ml`, `collect_calls_from_expr`) lowers each body onto a CFG:

- **Branch structure** — `if`/`match` arms (with a `Match_failure` bypass edge when the compiler
  marks the match `Partial`, so a lone refutable/guarded arm cannot forge a `MUST`; a single TOTAL
  unguarded arm always runs and IS `MUST`), `try` handlers (hung off a dispatch block that never
  post-dominates), `while`/`for` bodies (may iterate zero times), `&&`/`||` right operands,
  `let*` continuations, `assert` conditions, optional-argument defaults.
- **Diverging terminators** — a saturated application whose head Path-resolves to
  `Stdlib.{raise,raise_notrace,failwith,invalid_arg,exit}` (persistent root only — a local shadow
  does not terminate) or `assert false` ends its block: inside a `try` body it edges to the handler
  dispatch (may catch) and always to the virtual exit (may not match); code sequenced after it is
  entry-unreachable → recorded, demoted. **This closes the former divergence residual** for
  syntactic noreturn heads: `raise Exit; g x` no longer forges a `MUST` to `g`.
- **Evaluation order** — a call's head is recorded in the block reached *after* its arguments
  evaluate, so a diverging or branching argument demotes the head (`h (raise A)` is never a
  `MUST` to `h`).
- **Deferred bodies** — `lazy` thunks, object methods, and un-applied functor bodies walk in
  isolated (entry-unreachable) blocks: recorded, demoted, never dropped.

### Lambda nodes

Every `fun …`/`function` literal is promoted to a **synthetic function node** named
`<parent-chain>.<fun:LINE:COL>` (1-based column; `#N` in-marker ordinal on same-position
collisions; chained through enclosing lambdas), `exposed = 0`, with its **own CFG** — so calls in
callback bodies are precise `MUST` edges of the lambda node instead of ⊤ noise on the parent.
Occurrence edges are per-site: a saturated head invocation of a let-bound literal on an always-exec
block → `MUST`; every other occurrence (argument, record/tuple/ref store, return, partial or
conditional invocation) → `MAY_ENUMERATED`; a literal bound and never referenced gets **no** edge
(honestly dead). Bindings that are not a single-literal `Tpat_var` (conditional RHS, tuple pattern,
alias) are not tracked — calls through them stay `MAY_TOP`. `reaches` still refuses to traverse
`MAY_ENUMERATED`, so a merely-passed callback never yields a false must-path; the win is that
`unreachable` decides through callbacks and `escapes` shows only true ⊤.

All cases are locked by `selftest-callgraph-soundness.sh` (run `STRICT=1` in CI).

### Shared residuals (accepted) — where dominance is deliberately insensitive

Both backends' dominance remains **termination- and exception-insensitive** for *ordinary* calls,
the standard approximation of every practical intraprocedural analysis without a whole-program
termination oracle. Concretely, a call is still `MUST` even when a *preceding* construct may
prevent it from running:

- **After a possibly-non-terminating loop** — `while c do … done; f ()` marks `f` `MUST` though the
  loop may spin forever (OCaml gives loops an exit edge without constant-folding the condition; Go
  detects only the structurally exit-less `for {}`).
- **After an ordinary call that may raise/panic** — `g (); f ()` marks `f` `MUST` though `g` may
  divert. Only *syntactic noreturn heads* (`raise`/`failwith`/… in OCaml; terminal panic blocks in
  Go) terminate blocks — that part of the former residual is **closed**.
- An `assert cond` condition (other than `assert false`) is conditional (`MAY_ENUMERATED`/demoted)
  since `-noassert` elides it — a mild under-claim, the safe direction.

Every one of these only ever **over-claims `reaches`** (a must-path that might not run) — the
fail-safe direction for a blocking gate. **None can produce a false `UNREACHABLE`**: the calls are
always recorded, so `unreachable` (the security-critical over-approximation) stays sound.

Both backends also share one **precision** limitation (not a soundness issue): when *every* arm of
a branch calls the same target (`if b then f () else f ()`), the call is `MAY_ENUMERATED`, not
`MUST` — neither backend reasons about callee-level coverage across mutually-exclusive blocks.

**Precision status (self-index):** `MAY_TOP` ≈ 4% (down from ~79% pre-CFG), `MUST` ≈ 32%,
`MAY_ENUMERATED` ≈ 64% — the ⊤ frontier now contains only genuinely unknowable targets (computed
heads, parameter calls, dynamic roots, FFI anchors). Remaining precision follow-up: 0-CFA
closure-flow to enumerate first-class-value calls (research R3); see
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
