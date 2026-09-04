---
task: point-free-aliases
status: draft
date: 2026-09-04
---

# Point-free value aliases in the OCaml call graph

## Problem

`let f = M.g` — an η-reduced re-export whose body is a bare `Texp_ident`, with no
`Texp_apply` anywhere — produces a `functions` row with **zero** outgoing `calls`
rows. The walker records an edge only at an application site, so a bare-identifier
re-export produces nothing at all: not a resolved edge, not an unresolved one, not
even a ⊤ marker.

### Severity, stated precisely

Both verdicts **are** emitted today. On proto_alpha,
`may-fail apply_operation --channel exception` prints, in one output:

```
apply_operation: UNBOUNDED (⊤): {Assert_failure, Division_by_zero}   ← apply.ml:2868
apply_operation: BOUNDED: {}                                          ← main.ml:393, the alias
```

`raises` agrees with `may-fail` on both nodes. This is a **disambiguation** defect —
the right answer and a dead answer printed side by side, with nothing in either
verdict line to say which is which — **not** a soundness or false-negative defect.
An earlier report of it as a false negative was a measurement error (a truncated
read of a two-verdict output), and the framing matters: it bounds how much change
the evidence justifies.

### Measured extent (proto_alpha, 14452 nodes)

| Stratum | Count |
|---|---|
| zero outgoing edges | 3021 |
| … one-line AND arrow-typed | 620 |
| … source-shape "qualified" (`M.g`) | 248 |
| … source-shape "local" (`g`) | 87 |
| … genuine leaves / identities / η | 285 |
| homonym names (≥2 nodes) | 540 |
| … with a zero-edge node **and** a live node | **117** |

Concentration: `alpha_context.ml` 56, `storage.ml` 26, `storage_functors.ml` 14,
`main.ml` 5 — the protocol API façade. Both protocol entry points are themselves
aliases (`main.ml:393`, `main.ml:395`).

**The 248/87 split is a SOURCE-SYNTAX split and is NOT the resolution split** — see
C-10 below. It is recorded here as the extent of the problem, never as a work
breakdown.

## Decision 1 — an edge in the call graph, not a relation beside it

**Decided.** The alias becomes a `calls` row from the alias node to its target.

Rejected: an alias relation outside the call graph.
1. Raise-set propagation runs on `calls` edges. An out-of-graph relation forces a
   **second** fixpoint, and two propagation mechanisms diverge. This is not
   hypothetical — `exn_scopes` shared across channels already produced a
   4386-vs-2245 discrepancy depending on whether the channel filter was applied.
2. There is no single chokepoint to teach. `Arch_graph` serves four consumers,
   `Arch_exn` is a **separate** loader, and `arch-query`'s own commands go straight
   to SQL. An out-of-graph relation must be taught to three independent readers.

Prior art supports the edge shape: no surveyed system (SCIP, LSIF, CodeQL, Glean,
rustc/rust-analyzer, merlin/odoc) defines a first-class transitive alias relation.

## Decision 2 — the edge kind is `MAY_ENUMERATED`, not `MUST`

**This overturns the intake brief**, which specified a marked `MUST` edge. Three
frozen documents forbid `MUST`, and the existing resolution matrix reaches the same
answer by itself.

- `docs/edge-kind-contract.md:36-40` — an OCaml `MUST` requires three conjuncts, the
  third being *"the application is saturated"*. A `Texp_ident` RHS has **no
  application** to saturate.
- `docs/edge-kind-contract.md:42-44` — *"Both backends define MUST as execution-sound
  dominance computed over a real CFG… so a `reaches`/`unreachable` verdict means the
  same thing regardless of source language."* Emitting `MUST` for a non-call
  relationship in OCaml alone breaks that cross-language invariant.
- `specs/reporting-and-integration.md:46-48` (FR-011) — *"Call-like references become
  `MAY_ENUMERATED` edges… **Never `MUST`** — an indexer's reference is not a proof of
  unique resolution."* The closest textual precedent, and it rules against `MUST`.
- Nearest internal precedent: lambda **occurrence** edges are `MAY_ENUMERATED`
  whenever the occurrence is not a saturated head invocation
  (`docs/edge-kind-contract.md:78-82`).
- The matrix does **not** decide it for us, and an earlier revision of this spec said it
  did. Correction, verified: `demoted = call.cond || call.partial`
  (`arch_index.ml:832`), and `partial` means *"under-saturated / returns-a-function →
  body deferred"* (`arch_index_cmt.ml:535`) — a property of an **application**. A
  point-free alias is not an application at all, and it is not conditional, so a naively
  synthesised pending call has `demoted = false` and `Head_local`/`Head_qualified` would
  emit **`MUST`** (`arch_index.ml:859`, `:874`). Setting `partial = true` on something
  that is not an application would be a lie in the data to obtain the right answer by
  accident.

  The candidate mechanism was **`Head_enumerated`**, which forces `MAY_ENUMERATED`
  unconditionally (`arch_index.ml:843`) and whose meaning fits: a bounded
  candidate set, here of exactly one. That is the repository's own precedent —
  `specs/cfg-postdom-dominance.md:25`: *"Demotion target for a conditional call with
  uniquely-resolved callee? MAY_ENUMERATED (candidate set of one)… MAY_TOP is reserved
  for truly unknowable targets."*

  **Superseded during implementation, and this paragraph is corrected rather than
  left to contradict the code.** `Head_enumerated` resolves **same-module only**, via
  `resolve_local`. A cross-module alias routed through it would never acquire a
  `callee_id` at all — and 153 of proto_alpha's 351 alias edges are cross-module. The
  mechanism that forces the right *kind* would have destroyed the *identity*, which is
  the thing the edge exists to carry: without a `callee_id` there is nothing for the
  raise-set fixpoint to follow, and US-1 — the entire point — fails.

  The shipped design instead routes an alias through `add_path_call`'s **ordinary**
  heads (`Head_local` / `Head_qualified`), so identity resolution is exactly what it is
  for any other edge, and demotes in the **kind matrix** on `edge_form`
  (`arch_index.ml:1377`: `demoted = call.cond || call.partial || call.edge_form = Some
  "value_alias"`). This is the better separation and not merely the expedient one:
  *"which function is this"* and *"may I treat this as a definite call"* are different
  questions, the head answers the first and the matrix answers the second, and choosing
  a head constructor for its kind side-effect would have answered the second by lying
  about the first.

**What this costs, named rather than glossed.** `Arch_exn` — which powers
`may-fail`/`raises` — does **not** distinguish `MUST` from `MAY_ENUMERATED`; it
special-cases only `MAY_TOP` (`arch_exn.ml:449-462`). So effect propagation works
identically and US-1 is fully satisfied. What changes is narrower than the brief
assumed:

| Consumer | With `MAY_ENUMERATED` |
|---|---|
| `may-fail` / `raises` | traverses — **unchanged from the `MUST` design** |
| `arch-impact`, `arch-coverage`, `arch-mutants` (via `g.fwd`) | traverse |
| `arch-rules` | `POSSIBLE`, not `VIOLATION`, for a layer crossing through an alias |
| `reaches` (filters `kind='MUST'`) | does **not** traverse |

`POSSIBLE` is weaker than `VIOLATION` and it is **sound**: it never misses the
crossing, it declines to call it proven. That is honest — we have not proven the
alias is called, only that calling it would reach the target.

## Decision 3 — the marker, and who reads it on day one

A new `calls` column, **not** a new `kind` value. A new kind value would fail
`tezt/tests/callgraph_soundness.ml:300` (`kind NOT IN ('MUST','MAY_ENUMERATED','MAY_TOP')`
must be 0) and would need an amendment to `SPEC-sound-callgraph.md:89-92`, which
closes the vocabulary.

**Naming (C-15).** The column MUST NOT be called `is_alias` or carry the bare word
`alias`: `module_deps` already uses `dep_kind = 'alias'` for **module** aliases, a
different relation in a different table. Two relations sharing one word is the exact
miscounting this decision exists to prevent. The column is **`edge_form`**, with
values `NULL` (an ordinary call, the default for every existing row) and
`'value_alias'`.

**Day-one reader.** `fan-in` (`arch_query.ml:357`) and `god-modules` (`:556`) MUST
exclude `edge_form = 'value_alias'` from their counts. This is not decoration: an
alias is not a call site, and a "most-called" ranking that counts re-exports as
callers measures the façade, not the code. Naming a reader is mandatory here —
`top_reason`/`top_anchor` are written by producers and read by **no consumer
anywhere in the repository**, and a marker nobody reads is indistinguishable from
one that was never added.

## Scope

**Out of scope**, explicitly:
- Module aliases (`module N = P`) — a different object, owned by roadmap 1.6.
- Multi-hop alias chains. Resolution is a **single pass** over pending calls, not a
  fixpoint (confirmed), so hop 2 cannot resolve. Out of scope by mechanism, not by
  preference.
- Homonym disambiguation in verdict output. Two blocks with an identical bare label
  and no file/line (`arch_exn.ml:500`, `arch_query.ml:837-870`) is a real defect and
  is not this one.
- Non-OCaml producers.

## User stories

### US-1: a point-free alias forwards its target's effects (P0)

As an engineer asking "how can this function fail?", I want `may-fail`/`raises` on
`let f = M.g` to answer what the **target** can do.

**Scope**: does not cover multi-hop chains or module aliases.
**Independent test**: index a two-module fixture where `b.ml` raises and `a.ml`
contains only `let alias = B.raiser`; `may-fail alias --channel exception` names the
identity `B.raiser` can raise.

**Acceptance scenarios**
1. **Given** a fixture where `B.raiser` raises `Boom` and `a.ml` has
   `let alias = B.raiser`, **When** `may-fail alias --channel exception` runs,
   **Then** the verdict names `Boom` rather than `BOUNDED: {}`.
2. **Given** proto_alpha, **When** `may-fail apply_operation --channel exception`
   runs, **Then** the `main.ml:393` node's verdict is no longer `BOUNDED: {}` and
   its identity set is a subset of the `apply.ml:2868` node's.
3. **Given** an alias whose target is external to the index, **When** the producer
   runs, **Then** the edge is emitted with `callee_id IS NULL` and the existing
   external-leaf rules apply — the edge is never dropped.

### US-2: the alias edge is marked, and the marker is read (P0)

**Scope**: changes no reachability verdict; changes two metrics.
**Independent test**: `SELECT count(*) FROM calls WHERE edge_form = 'value_alias'`
is non-zero on a fixture, and `fan-in` for the target is unchanged by the alias.

**Acceptance scenarios**
1. **Given** a fixture with one alias, **When** `fan-in` runs, **Then** the target's
   caller count does not include the alias node.
2. **Given** the same fixture, **When** `god-modules` runs, **Then** the aliasing
   module's aggregate does not count the alias edge.
3. **Given** any indexed database, **When** `SELECT count(*) FROM calls WHERE
   edge_form IS NOT NULL AND edge_form <> 'value_alias'` runs, **Then** it returns 0.

### US-3: the resolution split is measured, not assumed (P1)

The intake brief claimed the 87 source-shape "local" aliases could ship before
roadmap 1.6 because `resolve_local` never touches `mod_name_to_path`. **That premise
is wrong as stated** (C-10): a bare identifier brought into scope by `open M` is
syntactically local and semantically qualified, and `local_fn_stamps` holds only
**same-module top-level** definitions — so an `open`-mediated alias is *not*
`ident_is_local_fn` and does not take the local path.

**Scope**: this story delivers the *measurement*, not a shipping order.
**Independent test**: on both corpora, classify every point-free alias by its
**typedtree path** (`Path.Pident` present in `local_fn_stamps` vs everything else)
and report the two counts beside the 248/87 source-syntax counts.

**Acceptance scenarios**
1. **Given** proto_alpha, **When** the classification runs, **Then** it reports
   counts by typedtree path, and the difference from 248/87 is stated.
2. **Given** a fixture containing `open B` followed by `let f = raiser`, **When** the
   producer runs, **Then** that alias is classified by the same rule as `let f =
   B.raiser`, not as a same-module local.
3. **Given** the measured split, **When** sequencing is decided, **Then** the
   decision cites the typedtree counts, never the source-syntax counts.

### US-4: no measurement regresses silently (P0)

**Acceptance scenarios**
1. **Given** octez-manager and proto_alpha indexed before and after, **When** the
   resolved-edge sets are diffed on the key
   `(caller_module, caller_name, call_site, callee_name, kind)`, **Then** every
   reference that stops resolving, **and every reference that resolves to a
   different `callee_id`**, is reported.
2. **Given** the same runs, **When** channels are reported, **Then** every channel in
   `comment_db_meta.error_contract` is reported, not only the targeted one.
3. **Given** any movement, **When** it is reported, **Then** a reference that stops
   resolving or changes target is a **hard stop**; a count that only grows is a note.

## Challenge resolutions

| # | Challenge | Resolution |
|---|---|---|
| C-2 | `partial` would demote the edge to `MAY_ENUMERATED`, contradicting the brief's `MUST` | **Accepted, and it decided Decision 2.** The matrix is right and the brief was wrong. |
| C-3 | Is `let f = M.g x` (partial application) in scope? | **No.** Scope is a bare `Texp_ident` RHS at the top of the binding. A partial application already produces an edge today. |
| C-6 | A new `kind` value breaks `reaches`/`must_fwd` | **Avoided.** Decision 3: a new column, not a new kind. |
| C-10 | `open`-mediated bindings are syntactically local, semantically qualified | **Accepted — it rewrote US-3.** Verified on a fixture. |
| C-15 | `deps.dep_kind = 'alias'` already exists for module aliases | **Accepted.** Column named `edge_form`, value `'value_alias'`. |
| C-18 | CodeQL deliberately does NOT skip wrappers; `getCallee` keeps the wrapper call site | **Divergence justified.** CodeQL's rationale is *where to report a finding*; our `call_site` is the alias binding's own location, so the reporting site is preserved exactly as CodeQL wants. We diverge only in making the forwarding visible by default, which their `FunctionWithWrappers` also does once opted into. |
| C-19 | Glean keeps alias-chasing as a consumer-side join | **Divergence justified by Decision 1.2**: Glean has one query language over one fact store; we have three independent readers. |
| C-21 | odoc's `@canonical` is author-declared and never verified | **Accepted as a limitation.** Our detection is structural, so it cannot mis-trust an author's claim — but it also cannot see a `.mli` that narrows the alias's contract. Recorded as a residual. |
| EC-3 | Non-function RHS (`let k = M.some_constant`) | **Excluded.** Verified: such a binding does get a `functions` row (signature `int`). The rule MUST require an arrow-typed RHS, or it would synthesise a call to a constant. |
| EC-4 | `let rec f = f`, mutual aliases | Self-loop MUST NOT be emitted; a cycle is left to the existing fixpoint's cycle handling. |
| EC-6 | `let _ = M.g` collides with the sink concept | **Excluded** — a wildcard binding is already skipped by the `_`-name rule. |
| EC-7 | Target is a dropped node | The existing `dropped_node` rule wins: `MAY_TOP` + `top_reason='dropped_node'`, with `edge_form='value_alias'` still set. The two are orthogonal. |

## Functional requirements

- **FR-001** [US-1]: The producer MUST emit a `calls` row for a top-level value
  binding whose RHS is a bare `Texp_ident` naming a value of arrow type.
- **FR-002** [US-1]: That row MUST carry `call_site` = the binding's own source
  location, following the existing non-application precedent (`add_path_call`).
- **FR-003** [US-1]: The producer MUST NOT emit such a row when the RHS is not of
  arrow type.
- **FR-004** [US-2]: The row MUST carry `edge_form = 'value_alias'`; every other
  `calls` row MUST carry `edge_form IS NULL`.
- **FR-005** [US-2]: The alias edge MUST be `MAY_ENUMERATED`, and that MUST follow
  from the **kind matrix keyed on `edge_form`** (`arch_index.ml:1377`), not from a
  synthesised `partial` flag and not from a head constructor chosen for its kind
  side-effect. The head MUST be the ordinary one `add_path_call` would pick
  (`Head_local` for a same-module target, `Head_qualified` for a cross-module one), so
  the edge resolves to a `callee_id` by the same rules as every other edge. The
  producer MUST NOT set `call.partial` on a binding that is not an application.

  *Amended in review.* This requirement previously mandated `Head_enumerated`.
  That is wrong and would have defeated US-1: `Head_enumerated` resolves same-module
  only, so every cross-module alias — 153 of proto_alpha's 351 — would carry no
  `callee_id` and propagate nothing. See Decision 2.
- **FR-005c** [US-1]: An alias binder whose RHS is **itself an alias binder**
  (`let t2 = t1`) MUST emit its own edge, to its **immediate** predecessor. One hop per
  binder, no transitive shortcut: the chain closes because consumers traverse the
  resulting edges. Emitting nothing here is the original defect one hop along — `t1`
  reads `BOUNDED: {Boom}` and `t2`, meaning the identical function, reads `BOUNDED: {}`.
  The binders MUST NOT be admitted to `local_fn_stamps` to achieve this (see Residuals).
- **FR-005b** [US-2]: A qualified alias MUST NOT reach `Head_qualified`'s default arm,
  which emits `MUST` when not demoted. A test MUST assert that no row with
  `edge_form='value_alias'` carries `kind='MUST'`.
- **FR-006** [US-2]: `fan-in`, `god-modules` and `callers-of` MUST exclude
  `edge_form = 'value_alias'`.

  *Amended in review.* `callers-of` was omitted from the original list and answered
  `t1|src/top.ml` for `callers-of target`, where `t1` is `let t1 = target` and calls
  nothing. The rationale for the other two — *"a point-free alias is not a CALLER of
  `M.g`; nobody invokes anything at that site"* — applies verbatim, and most sharply, to
  the one command whose whole purpose is naming callers: an inflated count is a number a
  reader may discount, a name is a file a reader goes and opens.

  The exclusion is **directional**, and `reachable-from` / `callees-of` are deliberately
  NOT gated. Those ask *"what could running this reach"*, and an alias genuinely does
  forward a body — the raise-set propagation this feature exists for depends on
  traversal continuing through the edge. `fan-in` / `god-modules` / `callers-of` ask
  *"who invokes this"*, and the answer at an alias site is nobody.
- **FR-007** [US-2]: The producer MUST NOT add a `functions` row whose name contains
  a dot in the aliasing module.
- **FR-008** [US-3]: The classification MUST be by typedtree path, never by source
  syntax.
- **FR-009** [US-4]: A reference that stops resolving, or resolves to a different
  `callee_id`, MUST be a hard stop.

## Runnable checks

- **CHECK-1** [AC-1] (authentic-success-path): `dune runtest --force` — the fixture
  test asserting `may-fail alias --channel exception` names the target's identity.
  Red-verify by reverting FR-001's emission.
- **CHECK-2** [AC-2]: `sqlite3 <db> "SELECT count(*) FROM calls WHERE edge_form IS
  NOT NULL AND edge_form <> 'value_alias'"` → `0`.
- **CHECK-3** [AC-3] (fail-closed-path): the frozen guard, before and after, on
  octez-manager **and** proto_alpha:
  `select count(*) from functions f join modules m on m.id=f.module_id where f.name
  like '%.%' and f.name not like '%<fun:%'` → unchanged (octez-manager: 638; the
  `<fun:` exclusion is load-bearing — without it the same query returns 5880).
- **CHECK-4** [AC-4]: resolved-edge-set diff on both corpora, keyed on
  `(caller_module, caller_name, call_site, callee_name, kind)` plus `callee_id`
  comparison; any disappearance or retarget exits 1.
- **CHECK-5** [AC-5]: every channel in `comment_db_meta.error_contract` reported.

## Verification discipline (binding on every check)

Run tests with `dune runtest`, **never** `dune exec tezt/tests/main.exe`. Verified
in-session: with a mutation neutralising `value_arms`, `dune exec` reported SUCCESS
with the producer hash **unchanged** (`b4c676af80fe`), while `runtest` reported
FAILURE and rebuilt it (`017e17756896`). Red-verify every new test; a red also proves
the artefact is fresh. Where a characterisation test admits no red, say so and derive
the expected value by hand **before** running.

## Residuals

- A `.mli` that narrows an alias's contract (deprecation, narrowed type) is invisible
  to structural detection (C-21).
- Multi-hop chains need a fixpoint that does not exist.
- `reaches` will not traverse an alias, by Decision 2. If that turns out to matter,
  the fix is to teach `reaches` about `edge_form`, not to promote the kind.
