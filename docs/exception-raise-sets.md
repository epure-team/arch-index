# Exception-identity may-raise sets

**Spec:** `specs/exn-raise-sets.md`. **Producer:** `arch-callgraph-ocaml` (CMT) only.
**Queries:** `arch-query <db> raises <fn>`, `raisers-of <Exn>`, `exn-stats`, each accepting
`--assume-externals-pure`.

The question answered is Java's `throws`, computed rather than declared: for every function
node — top-level bindings and promoted lambda nodes alike — **which exceptions may escape it**,
with the constructor's resolved identity, propagated through the ⊤-marked call graph and
**minus what handlers around each call site catch**. An unresolved fact is a ⊤ with a reason,
never an omission.

## What the producer records

| Table | One row per | Notes |
|---|---|---|
| `exn_origins` | raise site | `form ∈ {raise, reraise, unknown, failwith, invalid_arg, assert, partial_match, compare, division, index}`, canonical `exn_path` (NULL for `reraise`/`unknown`), innermost `scope_id`, `escapes` |
| `exn_scopes` | `try` body / `match … with exception` scrutinee | `parent_id` = enclosing scope of the same node, `catch_all` |
| `exn_scope_catches` | (scope, caught path) | from *closing* arms only |
| `call_exn_scopes` | call inside a scope | innermost scope enclosing the call site |
| `exn_rebinds` | `exception A = B` | queries canonicalise `A` to `B` |
| `comment_db_meta.exn_contract = v1` | run | absent ⇒ `NOT_ANALYSED` |

**Origins.** A raise head is recognised by its *primitive* (`%raise`, `%raise_notrace`,
`%reraise`), whatever its path — Tezos's protocol environment re-exports `raise` under its own
module. A literal `raise (E …)` records `E`'s canonical path; `raise e` where `e` is bound by a
handler arm of the same node is `reraise` (informational); any other argument is `unknown` — ⊤
with reason `unknown_exn_value`. `Stdlib.failwith` / `Stdlib.invalid_arg` (persistent `Stdlib`
root only — the protocol's `failwith` is the error-monad one and is *not* an origin) →
`Failure` / `Invalid_argument`. `assert e` → `Assert_failure`. A `Partial` `match`, `function`
or parameter pattern → `Match_failure`. Raising primitives: polymorphic comparison at a type that
may hold a closure → `Invalid_argument` (at `int`/`string`/… it cannot raise and nothing is
recorded), integer `/`/`mod` → `Division_by_zero`, bounds-checked `.()`/`.[]`/`Bytes.get` →
`Invalid_argument`.

**Scopes and closing arms.** A scope covers exactly the `try` body, or exactly the scrutinee of a
`match` with an `exception` arm — never the handlers. An arm is *closing* iff it is unguarded and
no raise in its RHS applies a raise head to a non-literal value; only closing arms contribute:
`Tpat_construct` → its path, `|` → union, `as` → the inner pattern, `_`/variable → catch-all.
So `| e -> cleanup (); raise e` and `| e -> match e with Not_found -> … | o -> raise o` close
nothing (the over-approximating direction), while `| e -> raise (Wrapped e)` closes everything and
adds `Wrapped` as an origin.

**Node attribution.** Origins and scopes inside a lambda literal belong to the lambda node; a
parent's `try` does not cover the lambda body — it covers the parent→lambda *occurrence edge* and
whatever the callback is passed to.

**Canonical paths.** Predefined exceptions are bare (`Not_found`, `Failure`, …; the `.cmt` spells
them `Stdlib.Not_found`, normalised). A persistent root prints as `Path.name`
(`Stdlib.Exit`, `Tezos_raw_protocol_alpha__Storage.Missing_key`). An exception declared by a
structure item of the current unit prints as `<cmt_modname>.<qualified>` — the same string a
cross-unit reference prints. `let exception E` (and functor-parameter roots) print as
`local:<unique_name>…`.

## What the query computes

Lattice per node: `Known s` (a bounded set of paths) or `Top rs` (unbounded, one reason per
witness). Rule:

```
raises(n) = direct(n) ∪ ⋃_{edge n→m, scope chain S} close_S( raises(m) )
close_S(X) = ∅                      if some scope in S is a catch-all
           = X − ⋃ caught(S)        otherwise   (⊤ − finite = ⊤)
```

`direct(n)` = the node's escaping literal origins, ⊤(`unknown_exn_value`) for an escaping
`unknown`. Edge contributions: `MUST` / `MAY_ENUMERATED` → `raises(m)`; `MAY_TOP` →
⊤(`may_top_edge @ site`); a callee outside the index (`callee_id IS NULL`) → ⊤(`external name`)
unless it is in the fixed `Stdlib` table (heads whose effect is already an origin, and primitives
that cannot raise) or the `externals_pure` hypothesis is stated. Worklist fixpoint; monotone over
a finite universe, so it terminates (`exn-stats` prints `fixpoint_seconds`).

Verdicts: `BOUNDED: {…}` (no ⊤ in the cone — a sound over-approximation), `UNBOUNDED (⊤)` with
one `reason: <kind> <witness>` line each, `BOUNDED_UNDER_HYP(externals_pure): {…}`. The
hypothesis never hides `may_top_edge`, `unknown_exn_value` or `dropped_node`. Rows list each
escaping exception with `via` (one callee) and `how ∈ {direct, transitive}`; under ⊤ the known
part is still listed.

`raisers-of Exn` lists bounded nodes containing `Exn` and, separately, ⊤ nodes with their dominant
reason (`may_top_edge > external > unknown_exn_value > dropped_node`). `exn-stats` gives the
bounded/unbounded shares.

## Residuals (accepted, documented)

- **Unknown exception values.** `raise (f x)`, `raise e` with `e` a parameter or a let-bound value
  — ⊤ with the site as witness. Frequency is measurable (`exn-stats` → `unknown_exn_value`);
  a dataflow extension is not planned until the number justifies it.
- **Callbacks and functor parameters** are `MAY_TOP` edges → ⊤ until roadmap 3.7 (closed-world
  enumeration). The analysis is edge-kind-agnostic: any later precision gain flows in unchanged.
- **Externals.** Anything outside the index with no fixed-table entry is ⊤: `List.hd`,
  `Hashtbl.find`, I/O, C stubs, and the protocol environment's own `failwith`/`invalid_arg`
  (non-`Stdlib` values). `--assume-externals-pure` states the hypothesis explicitly.
- **Effects** (`perform`, effect arms of `try`) are neither origins nor handlers; `perform` is an
  external call (⊤).
- **Rebinding** across units is canonicalised through `exn_rebinds`; `Obj.magic`-fabricated
  exceptions degrade to `unknown_exn_value` at best.
- **`-noassert`** builds have no `Texp_assert` nodes — the index reflects the build. Warning-8
  suppression does not change `Partial`, so `Match_failure` is still recorded.
- **Over-application** residual ⊤ edges are the walker's, and read as `may_top_edge`.
- **`Fun.protect ~finally`** and other stdlib wrappers are externals (⊤) — `Finally_raised` is
  invisible under the hypothesis.
- **Comparison on closures.** Recorded only when the argument type may hold a closure; a
  polymorphic function compared at an abstract type is conservatively an origin.

## Measurement on this repository (self-index, 2026-09-03)

`nodes 527 · bounded 109 (20.7%) · unbounded 418 (external 253, may_top_edge 165)`; under
`externals_pure`: `bounded 362 (68.7%)`. Origins 138 (`index` 106, `compare` 26, `reraise` 3,
`failwith` 2, `invalid_arg` 1), scopes 53. The external share is the Sqlite3 / compiler-libs
surface — exactly the frontier the fixed table does not cover.
