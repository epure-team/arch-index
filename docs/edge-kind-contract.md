# Edge-kind contract & soundness

arch-index tags every `calls` row with a `kind` value that encodes what is statically knowable about the call:

| `calls.kind` | Meaning | Use |
|---|---|---|
| `MUST` | Uniquely-resolved static call that runs on **every** execution of the caller (dominance: its CFG block post-dominates the entry) | `reaches` (a positive path = must-reach ground truth) |
| `MAY_ENUMERATED` | Target bounded to a **known candidate set** — a conditional call to a resolved callee (candidate set of one), a callback/lambda passed by value, a CHA interface set, or (OCaml, schema `1.10`) a **point-free value alias** `let f = M.g`, which is a *binding*, not a call site | Over-approx closure for `unreachable` (can prove UNREACHABLE) |
| `MAY_TOP` | Genuinely **unknowable** target — computed head, parameter call, dynamic module root, reflection/cgo, over-application residual | Forces `UNKNOWN`; never silently dropped |

**`MAY_ENUMERATED` bounds the target, it does not assert that a call site exists.** Since schema
`1.10` the set includes one member where no call happens at all: a point-free value alias
(`let f = M.g`), whose row carries `edge_form = 'value_alias'` — see
[`specs/point-free-aliases.md`](../specs/point-free-aliases.md). Effect and reachability
consumers are right to traverse it (the alias genuinely forwards `M.g`'s body), but a consumer
counting **call sites** or **callers** must exclude it, and the three that do are `fan-in`,
`god-modules` and `callers-of`.

**The predicate is `COALESCE(edge_form,'') <> 'value_alias'`, NOT `edge_form IS NULL`.** That
distinction did not exist while the vocabulary had one member, and this document asserted the
wrong one until `1.11` added a second. `edge_form = 'module_alias'` marks a head that was
*spelled* through a module alias (`S.f` where the file declares `module S = Saturation_repr`) —
a real `Texp_apply` at a real call site, which a caller-count consumer **must** count. Excluding
every non-NULL value would have silently dropped 3 247 genuine edges on proto_alpha. Exclude the
member that means *no call happens here*, never the column's non-emptiness.

The column is nullable and absent on a pre-`1.10` database, so gate on `Arch_db.has_col` rather
than assuming it.

When a backend produces a ⊤-marked index it sets `callgraph_contract = v1` in `comment_db_meta`. Backends that cannot tag edges must not produce a DB at all — the loader aborts on missing or invalid `kind` values (exit 2) to prevent a silent false-confidence index.

### Producer contract strictness (R9)

The NDJSON wire format (`arch-load`) carries four record types — `function`,
`call`, `decision`, `dead_site` — and is **strict in both directions**:

- an **invalid or missing `kind`** on a call edge aborts the load, because a
  silently-dropped edge would be invisible to the sound queries;
- an **unknown record type** or an **unknown field** aborts the load too. This
  is the same failure wearing a different hat: a producer author who adds a
  field the loader does not know would otherwise believe the data was carried
  when it was not.

Fields prefixed `x_` are reserved for producer-private extensions and are
accepted-and-ignored, so adding one is never a breaking change.

`decision_contract = v1` is stamped in `comment_db_meta` **only when a producer
actually supplied decision records** — so a consumer can distinguish a backend
that computed nothing from one that computed nothing *to report*. The decision
subcommands (`useless-branches`, `dead-blocks`) refuse on an index that lacks
the stamp rather than answering emptily.

### Backends

| Backend | Edge kinds | Notes |
|---|---|---|
| Go SSA (`callgraph-go` → `arch-load`) | ✅ execution-sound | A statically-resolved call (`StaticCallee() != nil`) is `MUST` only if its SSA basic block **post-dominates the function entry** (runs on every execution); a call in an `if`/`switch`/`select`/loop block is demoted to `MAY_ENUMERATED` (candidate set of one). CHA candidate set → `MAY_ENUMERATED`; interface/closure/reflection/cgo (incl. in-package `_Cfunc_*` wrappers) → `MAY_TOP`. Output is emitted in deterministic sorted order. |
| OCaml CMT (`arch-callgraph-ocaml`) | ✅ execution-sound | Each function body — and each promoted lambda — is lowered to a real per-node **CFG** (`arch_index_cfg.ml`); a call is `MUST` iff its block post-dominates the node's entry AND the head resolves uniquely AND the application is saturated. Conditional/partial calls to resolved callees → `MAY_ENUMERATED`; unknowable targets → `MAY_TOP`. A **point-free value alias** (`let f = M.g`, a bare arrow-typed `Texp_ident` RHS) also emits `MAY_ENUMERATED`, marked `edge_form = 'value_alias'`: it resolves through the ordinary heads so identity is carried, and is demoted in the kind matrix (`arch_index.ml:1376-1377`) because there is no application to saturate — never `MUST`. Resolution is `Ident`-stamp-based (shadows never forge a `MUST`). |

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
(honestly dead). This paragraph is about **`fun …`/`function` literal** bindings only: a binding is
tracked in `local_lam_stamps` iff its pattern is a plain `Tpat_var` and its RHS is a single
`Texp_function` literal (`arch_index_cmt.ml:1176-1183`). Bindings that are not that shape —
a conditional RHS, a tuple pattern, or a `Tpat_alias` **pattern-alias** (`let (p as x) = fun …`) —
are not tracked, and calls through them stay `MAY_TOP` (`top_reason = 'callback_param'`, which
folds in this `pattern_bound` sub-case; `arch_index_cmt.ml:537-548`). *"Alias" here is the OCaml
pattern form `p as x`, and is unrelated to `edge_form = 'value_alias'`*, which is a point-free
**identifier** RHS (`let f = M.g`), is tracked, resolves to a `callee_id`, and is `MAY_ENUMERATED`
rather than `MAY_TOP`. The two are different constructs that share an English word — the same
collision `edge_form` was named to avoid (`specs/point-free-aliases.md`, C-15).

`reaches` still refuses to traverse `MAY_ENUMERATED`, so a merely-passed callback never yields a false must-path; the win is that
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
  Go) terminate blocks — that part of the former residual is **closed**. The *identity* of what
  may be raised is a separate, additive analysis on the OCaml backend — `exn_origins` /
  `exn_scopes` / `call_exn_scopes` and `arch-query raises`, with handler subtraction at call
  sites and its own ⊤ reasons (`docs/exception-raise-sets.md`, `comment_db_meta.exn_contract`).
  It does not change any edge kind.
- An `assert cond` condition (other than `assert false`) is conditional (`MAY_ENUMERATED`/demoted)
  since `-noassert` elides it — a mild under-claim, the safe direction.

Every one of these only ever **over-claims `reaches`** (a must-path that might not run) — the
fail-safe direction for a blocking gate. **None can produce a false `UNREACHABLE`**: the calls are
always recorded, so `unreachable` (the security-critical over-approximation) stays sound.

Both backends also share one **precision** limitation (not a soundness issue): when *every* arm of
a branch calls the same target (`if b then f () else f ()`), the call is `MAY_ENUMERATED`, not
`MUST` — neither backend reasons about callee-level coverage across mutually-exclusive blocks.

**Precision status — measured 2026-09-05 on `main` at `70cb47f`, three scopes.** The previous
paragraph gave one unlabelled set of figures and drew a conclusion from it; both are corrected
here rather than adjusted, because the conclusion was the load-bearing half.

| scope | `MUST` | `MAY_ENUMERATED` | `MAY_TOP` |
|---|---|---|---|
| this library alone (23 modules, 5 155 calls) | 33.8 % | 60.3 % | **5.9 %** |
| this repo (93 modules, 14 578 calls) | 43.4 % | 48.7 % | **7.9 %** |
| Octez `_build/default` (10 033 modules, 1 445 080 calls) | 33.1 % | 47.1 % | **19.8 %** |

The figures this paragraph carried — 4 % / 32 % / 64 % — were the single-library scope and did
not say so. They were also stale: the same scope now measures **5.9 %**, and ⊤ has risen at every
scale since, which is the correct direction. Roadmap items 1.6, #69 and the error channels each
convert claims the tool could not support into stated unknowns; a ⊤ that rises because the tool
stopped asserting falsely is not a regression.

**RETRACTED: "the ⊤ frontier now contains only genuinely unknowable targets."** It does not, and
the taxonomy this document defines is what shows it. On Octez:

- `ambiguous_unit` — **16 151 edges**. A reference naming units that ARE in the index, where more
  than one function answers. Not unknowable: under-determined, and roadmap 1.6 records it as ⊤
  precisely because picking one would forge a `MUST`.
- `module_param` — **117 048 edges**, of which **42 987 (36.7 %)** are headed by a module alias
  (`module S = Target`) declared in the calling module, and **≈39.5 k (≈33.8 %)** have an alias
  target naming a module that is **in the index**. Both halves are already in the database and
  the resolver reads neither: a wiring gap, not an unknowable target.

  The second figure is given to two significant digits on purpose: two independent derivations
  gave **39 524** and **39 731** — a 0.5 % spread, because each matches an alias target against
  module names by a slightly different rule. That the spread is 0.5 % and not 5 % is itself the
  useful part: the quantity is robust to the matching rule, and it is a **heuristic upper bound**
  in both derivations rather than a resolved count. Quoting either figure to the unit would
  assert a precision neither has.

  **The key is the PAIR, never the name.** 3 423 distinct `(source_module, alias_name)` keys, of
  which **0 are ambiguous** — and that zero is a measurement, not a schema tautology: there is no
  UNIQUE index on the pair, so a second target would be stored and counted. It matters because
  **277 alias names are reused across modules with different targets**: the bare name is globally
  ambiguous and only the source-module scoping makes the key sound. Anyone wiring this must key
  on the pair.

  **Upper bound, not a resolution count.** Name coincidence is not proof: it excludes neither a
  local module shadowing the alias nor an alias to a *module type*, and a resolved head still has
  to find the function.
- `callback_param` — 153 157 edges. This class *is* mostly what the retracted sentence described.

**A figure the earlier paragraph did not carry, and which measures the remaining work better than
the ⊤ rate does:** on Octez, **278 826 `MUST` edges carry `callee_id IS NULL` — 58.3 % of all
`MUST`**. Each is an honest external leaf *or* a target the index could hold and does not. The ⊤
rate is the wrong progress metric here, because ⊤ is absorbing: resolving edges below a node does
not lower it while any one ⊤ edge remains in that node's forward closure.

Every number above is reproducible; re-derive rather than cite, and name the WORKING TREE, not
only the commit — an untracked file changed the repo-scope counts between two derivations of this
table while leaving the ratios identical.

```
arch_callgraph_ocaml --build-dir=<dir> --db-path=<out>.db --schema-path=architecture-schema.sql
sqlite3 <out>.db "SELECT COALESCE(kind,'NULL'), count(*), \
  round(100.0*count(*)/(SELECT count(*) FROM calls),1) FROM calls GROUP BY kind;"
sqlite3 <out>.db "SELECT count(*) FROM calls WHERE kind='MUST' AND callee_id IS NULL;"
```

Remaining precision follow-up: 0-CFA closure-flow to enumerate first-class-value calls
(research R3); see
[docs/research/control-flow-coverage-analysis.md](research/control-flow-coverage-analysis.md).

## ⊤-anchor taxonomy (roadmap 1.4)

Every `MAY_TOP` edge already means "unknowable target" — this taxonomy makes WHY into data, via
two new nullable columns on `calls`: `top_reason` (the agnostic vocabulary below) and `top_anchor`
(a location string for the expression that lost the target — not always the call site; a
callback's own parameter binding is the anchor a producer would ideally point to). Every producer
shipped today uses `call_site` verbatim as `top_anchor` (OCaml's own `call_site` is `file:line`,
with no column), not yet the finer location the roadmap's own note describes. Both columns are
`NULL` for every edge that is not `MAY_TOP` — meaningless for a resolved or bounded-candidate edge.

The agnostic vocabulary is the union of every producer's own local causes, enforced by a `CHECK`
constraint on `calls.top_reason` (main schema) and by the same closed-vocabulary discipline
`kind` already has (`bin/arch_load/arch_load.ml`) — an out-of-vocabulary value aborts the load,
never silently stored or dropped:

| Reason | Producer | Meaning |
|---|---|---|
| `callback_param` | OCaml | A function-typed parameter or local closure invoked/passed onward — the target could be anything the caller was given. Also covers, for now: a local `let`-bound lambda whose pattern was a tuple/alias/conditional binding rather than a plain identifier (`pattern_bound` in the roadmap's own vocabulary) — the CMT walker cannot yet distinguish these two structurally; see `lib/arch_index/arch_index_cmt.ml`'s own comment on `top_reason` for what tracking a future item would need to add to split them — AND a genuinely computed function value with no binding site at all (an anonymous application head, or the residual callee of an over-application). All three are "a callable value whose origin this walker did not track," read broadly under the roadmap's own "closure" wording. |
| `module_param` | OCaml | A qualified path whose root is a non-persistent ident — a functor argument or first-class module value. |
| `dropped_node` | OCaml | The callee's own row, or its whole compilation unit, was intentionally rejected this run (a genuine SQL-constraint rejection, not "not found") — its body exists but was never read, so the honest answer is ⊤, never a resolved leaf. |
| `ambiguous_unit` | OCaml | The reference names an INDEXED unit, but more than one distinct function answers to it and nothing in a `.cmt` says which one the caller was linked against. Distinct from an external leaf (no indexed unit at all), which keeps its `MUST` — conflating the two trades a precision problem for a soundness-shaped ⊤ flood. Rare, and measured on external corpora rather than only in-repo: this repo's own unit-name registry has **0** collided names among its 88 units (round-5 review; an earlier revision of this row cited "1 ambiguous unit name in 93", which does not reproduce — see `arch_index_cmt.ml`'s own comment on `unit_paths`), so no `ambiguous_unit` row is possible here today; a full run emits **0** such rows on octez-manager (58 553 calls) and **1** on proto_alpha/lib_protocol (73 588 calls). The single proto_alpha row is a test helper forwarding to the protocol module of the same basename (`test/helpers/script_big_map.ml:8`), where both readings define the referenced function — the honest two-answer case, not a resolver gap. |
| `reflection` | Go | `reflect`-based dispatch. |
| `ffi` | Go | A `cgo` foreign-function boundary. |
| `dynamic_load` | Go | `plugin.Open` dynamic loading. |
| `dispatch_unbounded` | Go | Interface dispatch with zero CHA candidates. |
| `trait_object` | Rust | `dyn Trait` dispatch. |
| `fn_pointer` | Rust | A function pointer value. |
| `extern` | Rust | `extern "C"` / FFI. |

**Residual, not silently dropped:** the OCaml walker distinguishes `callback_param` and
`module_param` correctly (verified: `tezt/tests/top_anchor_taxonomy.ml`) and `dropped_node`
correctly (verified: `tezt/tests/dropped_node_dependents.ml`), all with `top_anchor` set to the
call site as an initial approximation (not yet the parameter's own binding location for
`callback_param` — a real refinement, not yet built). Go and Rust do not emit `top_reason`/
`top_anchor` as NDJSON data yet, even though both producers already compute the underlying
distinctions internally (Go's well-known-TOP function table; Rust's `Callee.DynDispatch` variant,
which already surfaces one dimension — `dyn Trait` — via its own `x_dyn_trait`/`x_dyn_method`
producer-extension fields) — `bin/arch_load` accepts and validates the fields regardless, so
wiring either producer to emit them is a mechanical follow-up to that producer's own codebase,
not a schema/loader change. `calls.resolution` (`in_index`/`external_unit`/`dropped`, distinguishing
a MUST-with-NULL-callee edge that is a genuine external leaf from one whose owning unit was a real
dependency this run never actually indexed) is deferred entirely — the roadmap's own premise
(`cmt_imports`) refers to `Cmt_format.cmt_infos.cmt_imports`, a real compiler-libs field this
codebase does not yet consume, and its exact intended semantics need a design decision this task
did not have enough confidence to make alone.

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
- **Variant analysis**: find all callers of a fixed function to check for siblings: `arch-query db.sqlite callers-of vulnerableHelper`. On a schema-`1.10` index this list **excludes re-export bindings** (`let safe = vulnerableHelper`, `edge_form = 'value_alias'`) — nothing is invoked at such a site, so it is not a caller. To see them, use `reachable-from` / `callees-of`, which are deliberately not gated, or query directly: `SELECT * FROM calls WHERE edge_form = 'value_alias' AND callee_name = 'vulnerableHelper'`.
- **Documentation quality gate**: every function row carries a `comment_quality_score`. An agent can query `SELECT name FROM functions WHERE comment_quality_score < 50 AND exposed = 1` to find underdocumented public API.
- **Test coverage linking**: `{tests}` sections in doc-comments are parsed and stored. An agent can verify that every exported function has at least one linked test case.

For the formal soundness proof see [SPEC-sound-callgraph.md](../SPEC-sound-callgraph.md).
