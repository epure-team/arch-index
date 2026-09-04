---
task: reexport-resolution
status: draft
date: 2026-09-04
---

# Resolving a qualified name through a re-export

## What changed between intake and spec — read this first

The intake brief scoped this task on a measured impact of **~49 000 edges reached
through an `include`** and ~20 800 through a module alias. The adversarial pass found
that the first number is **not deliverable by this task**, and the measurement confirms
it.

| | in source | of which functor application | recordable | **rows in `module_deps`** | coverage |
|---|---|---|---|---|---|
| `include` | 7653 | 1283 | 6370 | **840** | **13 %** |
| `alias` | 7802 | 2437 | 5365 | **2811** | **52 %** |

(Scopes are comparable: 8714 `.ml` files in `src`, 8615 modules indexed.)

`module_path_of_expr` (`arch_index_cmt.ml:631-635`) handles only `Tmod_ident` and
`Tmod_constraint`; **every functor application yields `None`, so no row is written**.
The heaviest bucket goes through exactly that:

```ocaml
TzLwtreslib.ml:26   include Tezos_lwt_result_stdlib.Lwtreslib.Traced (TzTrace)
TzMonad.ml:29       include Monad_maker.Make (TzCore) (TzTrace) (TzLwtreslib.Monad)
```

So `Lwt_result_syntax.let*` — 25 273 unresolved edges, the single heaviest name in the
corpus — **would not resolve even with the wire connected**. The brief measured the
weight of the problem and assumed the data for the fix covered it. It does not.

**Consequence for scope.** The alias half is deliverable now: 2811 rows, per-file
context complete, `target_path` always populated. The `include` half is blocked
upstream, in the **producer**, not the resolver — and closing it is a separate slice
against `module_path_of_expr` and the `prefix = ""` guard, not a resolution change.

## Decisions

### D1 — resolution reads the in-memory `all_pending_deps`, never the table

**Verified.** `all_pending_deps` is declared at `arch_index.ml:563` and filled at `:594`
during the `.cmt` walk — before call resolution (`COMMIT` at `:973`) and long before the
table is written (`:1019-1050`). The walker already returns
`(pending_calls, pending_deps, pending_type_usages)` together "for later resolution"
(`arch_index_cmt.mli:352`); two of the three are used to resolve and one is not.

This removes the ordering problem rather than moving it: **no transaction is reordered,
so no new crash window is created** — the class PR #62 spent three review rounds
closing. It also bypasses `module_deps.target_module`, which is resolved by the same
basename/last-writer-wins scheme this task routes around and is therefore unreliable;
`target_path` is the raw parsed string and is always populated.

Answers **C-17**: the list is complete before resolution begins, so the chase is
independent of walk order. This must be asserted, not assumed — a fixture where the
hub file is walked *before* its target proves it.

### D2 — resolution sets `callee_id` and MUST NOT change `kind`

A re-exported name is still called at a real `Texp_apply`. What passed through the
re-export is the **name**, not the call. The edge kind is whatever the call site already
warranted; resolution only fills in the target.

This deliberately differs from `specs/point-free-aliases.md`, where the *edge itself*
was a non-application and therefore had to be `MAY_ENUMERATED`. The two specs are
consistent because the objects differ: there, no call; here, a call whose callee was
spelled through a hub. **No amendment to `docs/edge-kind-contract.md` is needed.**

**C-15, resolved:** the chase runs **after** the existing `dropped_qualified` check, not
before. If the chase reaches a function row dropped this run, the dropped-node path
wins (`MAY_TOP` + `dropped_node`) — setting `callee_id` to a row that does not exist
would contradict D2's own claim that resolution only fills in a target.

### D3 — ambiguity declines to resolve, and that is a no-op

If a chase reaches two or more distinct function ids, the edge stays exactly as today:
`callee_id = NULL`, `kind` untouched. Resolving to one of them is the mis-resolution
risk, and the sibling branch's review supplies the empirical case — a production call
resolved to a same-basename **test helper**, stamped MUST.

**C-16, resolved:** there is no contradiction with the sibling's `ambiguous_unit`
policy, because this chase is a **fallback tier that runs only after the existing
resolution has already failed**. It never competes for the same decision. The sibling
decides what a *unit* name means; this decides what a *re-exported* name means once the
unit path has already come up empty. On ambiguity this tier declines, which restores
precisely the behaviour that would have obtained without it.

### D4 — bounded depth, cycle detection on `(source_module, target_path)`

**C-7, resolved with a number:** the limit is **4 hops**, and the limit is
**inclusive** — a target found at hop 4 resolves. The value is not arbitrary: the
measured chains in this corpus are 1–2 hops (`TzPervasives → TzLwtreslib`), and 4 leaves
headroom without letting an unbounded walk hide behind "bounded". The implementation
MUST report the observed depth distribution so the constant can be re-derived rather
than inherited.

**C-8, resolved:** cycle detection dedupes on the pair `(source_module, target_path)`,
not on `target_path` alone — the same module spelled two ways at two hops is two
distinct pairs, so a legitimate chain is not blocked, and a true cycle re-enters an
identical pair.

**C-10 / EC-5, resolved:** when a chain is simultaneously ambiguous and at the
depth/cycle limit, **ambiguity wins** the diagnostic bucket. Ambiguity is a statement
about the program; a depth limit is a statement about our budget, and the program's
property is the more informative of the two.

### D5 — `open` stays out, and `local_open` is not implemented

An `open` does not name the target of a *qualified* reference. **C-18, resolved:** a
`local_open` row encountered in the dependency stream MUST be ignored by the chase (not
treated as `open`, not treated as `include`), and this MUST be asserted, so that a
future producer emitting `local_open` cannot silently change chase behaviour.

### D6 — the diagnostic is per-reason, and per-edge state is NOT delivered

**C-9, C-21, C-26, answered honestly rather than accommodated.** The four non-resolution
reasons — ambiguous, depth-exceeded, cyclic, no-candidate — MUST be counted
**separately**, printed by the producer and written to `comment_db_meta`. That is the
minimum that makes "did not resolve" distinguishable from "was not attempted".

A **queryable per-edge** state (SCIP's three-state model) is **not** delivered here: it
needs a schema column, and this task's value does not depend on it. So the literature
gap this task noticed — that no surveyed tool separates "no candidate" from "several
unranked candidates" as durable states — is **narrowed, not closed**, and the spec says
so rather than claiming the credit. Closing it is a follow-up with its own column.

## Scope

**In:** the `alias` tier of the chase (2811 rows), reading in-memory `pending_dep`,
scoped to the referencing file, `target_path` only.

**Out, with reasons:**
- The `include` tier — blocked on the producer (functor applications yield no row;
  87 % of recordable includes are missing). A separate slice against
  `module_path_of_expr` and the `prefix = ""` guard.
- `open` (8776 rows) and `local_open` (dead vocabulary).
- Re-resolving `module_deps.target_module` and the `arch-rules` `Dep` verdict that
  depends on it — named as a defect by the sibling branch, separate fix.
- Type-usage resolution, the third sub-pass on the same basename scheme.
- **`.mli`-declared aliases** (**C-6**): `module_path_of_expr` sees only
  `Typedtree.structure_item`. Out, and stated rather than discovered.
- **`Tstr_recmodule`** (**C-3 / EC-2**): never matched by the `Tstr_module` case, so an
  alias or include of a recursively-defined module produces no row. Out, recorded.

## User stories

### US-1: an alias resolves in the file that declares it, and only there (P0)

**Independent test.** Two fixture files each declaring `module S = <different target>`;
each file's `S.f` resolves to its own target and neither resolves to the other's.

1. **Given** `a.ml` with `module S = Impl_a` and `b.ml` with `module S = Impl_b`, both
   calling `S.f`, **When** the producer runs, **Then** `a.ml`'s edge has
   `callee_id = impl_a.ml:f` and `b.ml`'s has `callee_id = impl_b.ml:f`.
2. **Given** the same fixture, **When** `kind` is inspected, **Then** it is identical to
   what the same call sites produced before the change (D2).
3. **Given** a fixture where the hub file is walked *before* its target,
   **When** the producer runs, **Then** the alias still resolves (D1, C-17).

### US-2: an ambiguous or over-deep chase declines, and every decline is attributable (P0)

1. **Given** a file with two aliases reaching different functions of the same name,
   **When** the producer runs, **Then** `callee_id IS NULL`, `kind` is unchanged, and
   the **ambiguous** counter increments.
2. **Given** a 5-hop chain, **When** the producer runs, **Then** the edge is unresolved
   and the **depth** counter increments — while a 4-hop chain resolves (inclusive
   limit, C-7).
3. **Given** `module A = B` and `module B = A`, **When** the producer runs, **Then** the
   **cycle** counter increments and the producer terminates.

### US-3: intra-file rebinding and nesting are decided, not discovered (P0)

**C-4 / EC-3 and C-5 / EC-4** are behaviour the fixture must pin, not leave open.

1. **Given** `module S = A` … `S.f` … `module S = B` … `S.f` in one file, **When** the
   producer runs, **Then** both call sites resolve to **`A`** — the chase is *not*
   line-aware, and this is pinned as a **known limitation with a characterisation
   test**, not claimed as correct. (`module_deps` records a `line_number` per binding
   but no line for the *use* site, so line-awareness is not implementable from the data
   available; saying so is more useful than a silent first-wins.)
2. **Given** an alias declared at a file's toplevel and used inside a nested submodule
   of that file, **When** the producer runs, **Then** it resolves — scoping is keyed on
   the **file**, matching `add_dep`'s own `prefix = ""` gate.

### US-4: nothing regresses, measured in bounded nodes (P0)

1. **Given** octez-manager and proto_alpha indexed before and after, **When** compared,
   **Then** the report states **bounded-node** counts per channel, never a ⊤ rate.
2. **Given** the same runs, **When** an edge changes target, **Then** it is listed
   individually for review. **C-13 / EC-8, resolved:** a retarget is a **hard stop for
   review, not an automatic revert** — the FK it replaces is basename/last-writer-wins,
   so a retarget may be a *correction*. Each one must be justified in the PR by naming
   the old and new target; unexplained retargets block the merge.
3. **Given** the change, **When** `must_null_ceiling` is evaluated, **Then**
   `clean_measured` is re-measured in the same commit with a 2×2 attribution
   (**C-12**) — a successful chase turns MUST+NULL into MUST+`callee_id`, so the ratchet
   moves by construction.

## Functional requirements

- **FR-001** [US-1]: The resolver MUST consult the in-memory `pending_dep` list, and
  MUST NOT read the `module_deps` table.
- **FR-002** [US-1]: A chase MUST be scoped to the referencing file; a global match on
  an alias name is forbidden (`S` names 34 distinct targets across the corpus).
- **FR-003** [US-1]: The chase MUST read `target_path` and MUST NOT read
  `target_module`.
- **FR-004** [US-1/D2]: Resolution MUST set `callee_id` and MUST NOT alter `kind`,
  `top_reason` or `top_anchor`.
- **FR-005** [D2/C-15]: The chase MUST run after the existing `dropped_qualified` check;
  a target dropped this run MUST keep the dropped-node verdict.
- **FR-006** [US-2]: Two or more distinct resolved ids MUST leave the edge unresolved.
- **FR-007** [US-2]: The chase MUST stop at 4 hops inclusive and MUST detect cycles on
  `(source_module, target_path)`.
- **FR-008** [US-2/D6]: The producer MUST report ambiguous, depth-exceeded, cyclic and
  no-candidate counts **separately**.
- **FR-009** [D5]: A `local_open` row MUST be ignored by the chase.
- **FR-010** [US-4]: Every changed edge target MUST be listed individually; an
  unexplained retarget MUST block the merge.

## Runnable checks

- **CHECK-1** [AC-1] (authentic-success-path): `dune runtest --force` — the two-file
  fixture of US-1. Red-verify by disabling the chase.
- **CHECK-2** [AC-2] (fail-closed-path): the ambiguity fixture leaves `callee_id IS
  NULL`; red-verify by making the chase pick the first candidate.
- **CHECK-3** [AC-3]: `SELECT count(*) FROM calls WHERE callee_id IS NOT NULL AND kind
  IS NULL` → 0, and the kind histogram is byte-identical before/after on both corpora
  (FR-004).
- **CHECK-4** [AC-4]: bounded-node counts per channel, both corpora, before and after.
- **CHECK-5** [AC-5]: the four decline counters are present in the producer's output and
  in `comment_db_meta`, and sum to the number of unresolved qualified references.

## Verification discipline

`dune runtest --force`, **never** `dune exec tezt/tests/main.exe` — demonstrated: a
mutation left `dune exec` green with the producer hash unchanged (`b4c676af80fe`) while
`runtest` went red and rebuilt it (`017e17756896`). Red-verify every new test; where a
characterisation test admits no red (US-3 scenario 1), say so and derive the expected
value by hand **before** running. The golden is checked only by CI, never by `runtest`.
Golden and `clean_measured` re-measured per slice with a 2×2 attribution, written only
when A=B and C=D.

## Residuals

- The `include` tier, and with it the 25 273-edge `Lwt_result_syntax` bucket, until the
  producer records functor-application includes.
- Intra-file alias rebinding resolves to the first binding (US-3 scenario 1), pinned.
- **C-14, unresolved and named:** mapping `target_path` to a row still goes through
  `mod_name_to_path`, the basename/last-writer-wins table. This task routes around the
  collision on the *alias-name* side and not on the *target* side. Two `impl.ml` files
  in different libraries still collide. The sibling's roadmap-1.6 unit registry is the
  fix, and this task should adopt it once merged rather than build a second one.
- Per-edge queryable non-resolution state (D6).
