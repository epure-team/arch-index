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

### D1-bis — the index is keyed on BINDER IDENTITY, not on the binder's name

**Amends D1 (2026-09-05). D1's scoping was right and is measured; its key's
granularity was wrong, and the error only became unsafe once D2 was amended.**

The key is `(source_module, Ident.unique_name binder)`, not
`(source_module, alias_name)`. `alias_name` stays in the row as the display
spelling; it stops being the join.

**Why a name key is unsafe here, and was not before.** Two attacks survive a
*perfectly correct* alias/parameter classification, because they defeat the
JOIN rather than the classification:

```ocaml
(* SA-1 — nested binder, correct classification, wrong target *)
module S = Saturation_repr                (* toplevel: a row exists *)
module Internal_for_tests = struct
  module S = Test_saturation_stub         (* nested: no row of its own *)
  let cost_add x y = S.add x y
end
```
The inner binder IS a `Tstr_module`/`Tmod_ident` alias, so any origin mark
answers *alias* truthfully. A name key then finds the only row under `"S"` — the
toplevel one — and records a production call to a test stub as a call into
protocol code. This is the mirror of the defect ADR 003 documents, and it cannot
be closed by rejecting nested contexts, because **US-3 scenario 2 requires** a
toplevel alias used from a nested submodule to resolve. The two shapes are
identical from the resolver's side and separable only by binder identity.

```ocaml
(* SA-2 — toplevel rebinding *)
module C = Compare.Int
let sort_ids l = List.sort C.compare l
module C = Compare.String
let sort_names l = List.sort C.compare l
```
First-insert-wins returns `Compare.Int` for both. US-3 scenario 1 pinned that as
a known limitation, which was defensible while resolution only filled in a
target on an edge whose kind was already decided. Under D2-bis the same
limitation would manufacture a resolved edge from a sound ⊤, on an
int-versus-string comparator.

**And the contract already promised this.** `docs/edge-kind-contract.md` states
for the OCaml backend that *resolution is `Ident`-stamp-based, so shadows never
forge a MUST*. A name key here would be the first producer path to break that
guarantee, from a fallback tier.

**What does not change.** Per-file scoping stands and is now measured: 460 edges
on proto_alpha and 67 on octez-manager have a head that is an alias in a
*different* file, so a global match would have resolved **527 edges wrongly**.
The defect was the key's granularity, never the decision to scope per file.
Reading from the in-memory `all_pending_deps` rather than `module_deps` also
stands, for the reason D1 gave: `target_module` carries the basename erasure
ADR 003 accepts as permanent, and `target_path` does not.

**Consequence for ambiguity.** With a stamp key, two binders of one name are two
keys. The alias side stops having candidates to choose between, so
first-insert-wins is not a tie-break any more — it is dead. That matters because
the "0 ambiguous in 8318 chases" figure was taken *downstream* of it and could
not see the alias side at all; under this key there is no alias side left to
measure.

### D1-ter — the splice point is `Head_unknown (_, Module_param)` **(RETIRED 2026-09-05 — superseded by D1-quater; kept for the measurement that justified moving the splice at all)**

**New (2026-09-05). Replaces the `Head_qualified`/`Not_found` splice, which was
measured to observe ZERO of its own cases.**

Implemented as originally specified and instrumented, the tier reported
`0 resolved, 0 ambiguous, 0 no candidate` while 35 705 chases ran — none from a
file declaring an alias. Every one of the **3 203** unresolved calls whose head
is an alias declared in the same file is `MAY_TOP`/`module_param`: a path rooted
at a local module binder is judged dynamic by `qualified_is_dynamic` and sent
straight to ⊤ without ever reaching `Head_qualified`.

Two obligations follow, because the new arm does not inherit what the old one
had:

- **FR-005's ordering must be re-established, not inherited.** `dropped_qualified`
  is defined and used only inside the `Head_qualified` branch. At the new arm
  there is no existing check to run after, so the dropped-node test must be
  performed there explicitly or FR-005 silently degrades to "there was no check".
- **`Head_unknown` carries a rendered display string, not a `(module, name)`
  pair.** Re-splitting it is not merely inelegant: OCaml value names legally
  contain dots (`+.`, `*.`, `.%()`), so a last-dot split of `"F.( *. )"` yields an
  empty callee name; and `"*TOP*"` and `"<apply>"` are legal display values that
  are not paths at all. The producer MUST carry the split. Recovering structure
  by parsing your own rendered output is how the `top_reason` string/constructor
  divergence happened.

### D1-quater — the PRODUCER rewrites the head; there is no resolver splice

**Amends D1-ter (2026-09-05), which is hereby retired. This is a
simplification: it deletes a code path rather than adding one.**

D1-ter placed the fallback in the resolver, at the `Head_unknown (_,
Module_param)` arm, and paid for that position with two obligations —
re-establishing `dropped_qualified` ordering, and carrying a `(module, name)`
split so the resolver would not have to re-parse a rendered display string.
Both obligations exist only because the resolver is the wrong place to stand.

**The measurement that inverts it.** `qualified_is_dynamic` is

```ocaml
match path_root path with Some id -> not (Ident.persistent id) | None -> false
```

so the root `Ident` — and therefore `Ident.unique_name id`, the binder identity
D1-bis requires — is **already in hand at the exact site where the
`Module_param` ⊤ is decided**. Nothing needs to travel to the resolver.

**The decision.** At each site that classifies a dynamic-rooted path, the
producer looks the root binder's stamp up in a module-alias table and, on a
hit, **rewrites the head**: `S.safe_int` is emitted as
`Head_qualified (Some "Tezos_raw_protocol_alpha.Saturation_repr", "safe_int")`
instead of `Head_unknown ("S.safe_int", Module_param)`. On a miss the ⊤ is
emitted exactly as today. The rewritten head then flows through **1.6's
ordinary qualified resolution, ambiguity rule included** — no new resolver tier
exists.

**Measured on proto_alpha**, with a stamp-keyed table including nested binders:

| emission site | HIT | MISS |
|---|---|---|
| `record_head` (applied heads) | 3 224 | 1 847 |
| argument escape | 23 | 137 |
| **total** | **3 247** | |

against the **3 203** the name-keyed resolver design reached. The stamp table
covers everything the name key did **and more**: the `prefix = ""` gate on
`pending_deps` had excluded nested binders — the very binders SA-1 attacks.
Top rewrites are the flagship cases: `S.safe_int → Saturation_repr` (1 323),
`S.Syntax.+` (594), `S.Syntax.lsr` (393).

**What this closes by construction rather than by filter.**

- **SA-1 and SA-2 stop being attacks.** Two binders spelled `S` are two stamps,
  hence two keys. A nested `module S = Test_stub` beside a toplevel
  `module S = Saturation_repr` cannot collide, and there is no join in which to
  lose the precision. D1-bis's requirement is satisfied by the key's identity,
  not by a rule applied to it.
- **D1-ter's two obligations evaporate.** There is no rendered display string to
  re-split, so the `"F.( *. )"` empty-callee-name hazard disappears; and
  `dropped_qualified` ordering is **inherited**, because the edge now arrives at
  the `Head_qualified` arm that already performs that check. FR-005 is satisfied
  structurally rather than restated.
- **`module_deps` is not read at all**, so ADR 003 residual 4 (the
  `target_module` basename erasure) cannot bite this task. FR-001 and FR-003 are
  satisfied a fortiori: the chase reads neither the table nor `target_module`,
  because the producer never leaves the typedtree.
- **Per-file scoping (FR-002) still holds and is still required.** `Ident`
  stamps are allocated per compilation unit, so a stamp value is unique within a
  unit and **not** across units. The table is therefore built per `.cmt` and
  consumed within that same walk — the scoping is the table's lifetime, not a
  key field.

**Precedent in the tree, deliberately followed.** `build_local_alias_stamps`
(`arch_index_cmt.ml:1004`) already does exactly this shape for *value* aliases:
stamp-keyed, built with `iter_structure_items ~f:(fun ~prefix …)` so nested
binders are included, and handed to `collect_calls_from_expr` as an optional
argument. The module-alias table is its sibling and MUST mirror it, so that the
two alias mechanisms are read as one pattern rather than two inventions.

**What does NOT change: D2-bis still holds, and is still the reason.** Emitting
`Head_qualified` would land **MUST** wherever the call is neither `cond` nor
`partial`, and that is exactly what D2-bis forbids — the rewrite discharges the
**naming** conjunct of MUST and leaves uniqueness and saturation standing. The
landing kind must therefore be forced to `MAY_ENUMERATED`, and the mechanism
already exists: #69's demotion in the kind matrix, keyed on `edge_form`

```ocaml
demoted = call.cond || call.partial || call.edge_form = Some "value_alias"
```

extends to a **second member**, `'module_alias'`. Same mechanism, one more
value, **no new vocabulary in `kind`** — a test asserts the `kind` vocabulary is
closed, and `edge_form` is precisely the column added so that a demotion reason
need not become a kind.

**Why this is recorded as an amendment rather than edited in silently.** This
spec has now changed shape twice: D1-ter moved the splice because the specified
one observed zero of its own cases, and D1-quater removes the splice entirely
because the evidence it needed was available upstream all along. A spec that
moves twice owes the reader both reasons, and the second one is the more useful:
**the first design searched for the binder identity in the place where the
symptom appeared, not in the place where the fact was known.**

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

### D2-bis — the landing kind is MAY_ENUMERATED, and the reason is what it proves

**Amends D2 (2026-09-05). D2 as written forbade the only useful outcome.**

D2 said "set `callee_id`, never change `kind`", justified by *what passed
through the re-export is the name, not the call*. That holds when the original
kind was MUST or MAY_ENUMERATED — resolution only fills in a target. It does not
hold at the new splice point, where the edge is ⊤ **because the module was
unknowable**. Learning what it is and staying ⊤ is not honesty, it is discarding
what was learned. So the landing kind must be decided.

**Decision: `MAY_ENUMERATED`. Never MUST.**

**The reason, and it is not the one I first offered.** I argued MAY_ENUMERATED
"by the same argument as point-free value aliases". That argument does not
transport: there, no call happens at the site — the edge is not an application.
Here there is a real `Texp_apply`. The correct reason is narrower and stronger:

> **The chase discharges the NAMING conjunct of MUST, and only that one.**

`docs/edge-kind-contract.md` makes MUST the conjunction of post-dominance,
unique resolution, and saturation. Resolving an alias proves which module the
head denotes. It leaves the other two standing on evidence this population makes
weakest:

- **Uniqueness** — the target is re-resolved through `mod_name_to_path`, the
  basename/last-writer-wins map ADR 003 residual 4 accepts as **permanent**.
  Two `impl.ml` in different libraries still collide, and this task routes
  around the collision on the alias-name side only.
- **Saturation** — `head_arity` falls back to `arrow_arity` on the callee's
  interface type, and the walker's own comment records that a cross-module
  arrow hidden behind an alias in that interface is not expanded from a
  `.cmt`-restored environment. Alias- and signature-mediated heads are exactly
  where that residual is densest.

MAY_ENUMERATED states precisely what is proved: **the target set is bounded by
this candidate, and no claim is made that the call is definite.** That is the
sentence `docs/edge-kind-contract.md` now carries for MAY_ENUMERATED, so no
amendment to the contract is required.

**Consequences this spec must own rather than discover.** Three existing
requirements were written for a world where `kind` never moved:

- **FR-004 / CHECK-3 / US-1 scenario 2** require `kind`, `top_reason` and
  `top_anchor` unchanged, and CHECK-3 asserts a byte-identical kind histogram.
  All three are now requirements the feature is defined to violate; they are
  replaced by CHECK-3-bis below.
- **US-4's ratchet arithmetic** assumed MUST+NULL → MUST+id. The real transition
  is MAY_TOP+NULL → MAY_ENUMERATED+id, so `must_null_ceiling` does not move on
  this feature at all and is not its ratchet.
- **The ⊤ frontier shrinks by construction.** Every resolved chase deletes a ⊤
  edge, and a ⊤ edge is what makes `arch_exn` report an unknown raise and
  `arch-query` refuse `pure`. So this feature **removes raise-set members and
  promotes nodes toward `pure`** — a narrowing of an over-approximation, which
  is the unsafe direction for a may-analysis unless each removal is justified by
  a resolution. The acceptance bar is therefore not "zero removals" but
  **"every removal is attributable to a resolved chase"**, checked per edge.

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
  a target dropped this run MUST keep the dropped-node verdict. **(Satisfied
  structurally under D1-quater: the rewritten head arrives at the
  `Head_qualified` arm, which already performs that check. Nothing is
  re-established; the requirement is inherited, and a test MUST prove the
  inheritance rather than assume it.)**
- **FR-006** [US-2]: Two or more distinct resolved ids MUST leave the edge unresolved.
- **FR-007** [US-2] **(RETIRED 2026-09-05 — contradicted the frozen design)**: this
  required 4 hops with cycle detection while D4 freezes the chase at 1 hop, so
  US-2 scenarios 2 and 3 (a 5-hop chain, an `A = B`/`B = A` cycle) name
  behaviour no fixture can exercise. A spec that mandates what its own frozen
  decision forbids is not a contract. **Replaced by FR-007-bis: the chase MUST
  perform exactly one hop, and MUST NOT carry depth or cycle machinery.** The
  cut is justified on EDGES, not on aliases: a second hop reaches 21 edges on
  proto_alpha and 29 on octez-manager, 50 against 8318 chases. (My published
  justification — "6 of 2811 aliases" — was wrong: it compared the whole
  `target_path` against `alias_name`, and `Commitment.Hash` never equals
  `Commitment`. The real two-hop population is **116**, which also retires my
  §10.6 argument that a depth counter would read zero forever. Right decision,
  both stated reasons wrong.)
- **FR-007-old** (retired): The chase MUST stop at 4 hops inclusive and MUST detect cycles on
  `(source_module, target_path)`.
- **FR-008** [US-2/D6]: The producer MUST report ambiguous, depth-exceeded, cyclic and
  no-candidate counts **separately**.
- **FR-009** [D5]: A `local_open` row MUST be ignored by the chase.
- **FR-010** [US-4]: Every changed edge target MUST be listed individually; an
  unexplained retarget MUST block the merge.
- **FR-011** [D1-quater/D2-bis] **(new 2026-09-05)**: A head rewritten through a
  module alias MUST carry `edge_form = 'module_alias'`, and the kind matrix MUST
  demote on it. No rewritten edge may be `MUST`, however its head classifies —
  the same structural guarantee FR-005b gives value aliases.
- **FR-012** [D1-quater/D1-bis] **(new 2026-09-05)**: The module-alias table MUST
  be keyed on `Ident.unique_name` of the binder and MUST be built and consumed
  within a single compilation unit's walk. A name key, or a table shared across
  units, is forbidden — stamps are unique per unit and not across them.

## Runnable checks

- **CHECK-1** [AC-1] (authentic-success-path): `dune runtest --force` — the two-file
  fixture of US-1. Red-verify by disabling the chase.
- **CHECK-2** [AC-2] (fail-closed-path): the ambiguity fixture leaves `callee_id IS
  NULL`; red-verify by making the chase pick the first candidate.
- **CHECK-3-bis** [AC-3] (replaces CHECK-3, which the amendment is defined to
  fail): every edge whose `kind` moved between the before and after runs MUST be
  a chase that resolved — asserted **only where a resolution explains it**, never
  per total, because a count-level check cannot distinguish a resolved edge from
  an unrelated regression that happens to balance it.

  **CORRECTED 2026-09-05 — `(caller_id, callee_name, call_site)` is NOT an edge
  identity.** I wrote it as one. Measured on Octez: 1 445 080 edges,
  **1 407 032 distinct triples, 26 206 collisions (1.8 %)**. The worst is ×55 —
  fifty-five edges from one caller to `Brassaia.Type.|~` at one call site, which
  is what a chain of combinators on a single line produces.

  So the match must carry a **multiplicity per triple**, and the assertion is
  that the multiset of kinds at each triple changed only where a chase resolved.
  Matching on the bare triple would let one edge of a 55-way group move kind
  while another moved back, and report nothing.

  Found by applying the gesture this defect earned: run
  `GROUP BY <key> HAVING count(*) > 1` on the **largest** population the key will
  ever see, before shipping it. The same check clears two production keys —
  `(module_id, name)`, the resolver's own, is **0 collisions on 354 928
  functions**, and `modules.path` is 0 on 10 033 — so the failure is mine and
  specific, not endemic.
- **CHECK-3-old** (retired): `SELECT count(*) FROM calls WHERE callee_id IS NOT NULL AND kind
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

## Measured result (2026-09-05, both corpora, baseline = origin/main 0982a42)

Distinct binaries confirmed by md5. Neither corpus changed its total call count,
so no edge was created or destroyed — every number below is a reclassification.

| | proto_alpha base → after | octez-manager base → after |
|---|---|---|
| total calls | 73 939 → 73 939 | 59 101 → 59 101 |
| **MUST** | 22 416 → **22 416** | 22 476 → **22 476** |
| MAY_TOP `callback_param` | 5 739 → 5 739 | 5 187 → 5 187 |
| MAY_TOP `module_param` | 5 464 → **2 195** | 5 334 → **213** |
| MAY_ENUMERATED | 40 319 → 43 588 | 26 104 → 31 225 |
| `edge_form='module_alias'` | **3 247** (2 839 resolved, **0 MUST**) | **5 115** (3 009 resolved, **0 MUST**) |

The accounting closes exactly on proto_alpha: 3 247 rewritten heads + 22 edges
that were already `value_alias` and kept that (narrower) form = 3 269, which is
the `module_param` drop to the row. FR-011 holds as a measurement, not only as a
matrix argument: **zero** rewritten edges are MUST on either corpus.

### What it is worth in BOUNDED NODES, which is the only figure that decides anything

| | externals open | externals assumed pure |
|---|---|---|
| proto_alpha base | 3 084 (21.3 %) | 6 439 (44.6 %) |
| proto_alpha after | 3 085 (21.3 %) — **+1 node** | 6 576 (**45.5 %**) — **+0.9 pt** |
| octez-manager base | 2 587 (21.0 %) | 5 544 (45.0 %) |
| octez-manager after | 2 596 (21.1 %) — **+9 nodes** | 6 536 (**53.1 %**) — **+8.1 pt** |

**With externals open this feature bounds one node on one corpus and nine on the
other, having deleted 3 269 and 5 121 ⊤ edges.** That is not a disappointment to
explain away; it is ⊤'s absorption restated, and it is the finding this spec's
US-4 was written to force into the open rather than let a ⊤-rate headline hide.

What actually moved is *why* the remaining nodes are unbounded:
`unbounded.may_top_edge` falls (8 009 → 7 872, 6 773 → 5 781) while
`unbounded.external` rises (3 359 → 3 495, 2 957 → 3 940). The nodes did not
become provable — they stopped being blocked by "I cannot tell what this module
is" and started being blocked by "that module is outside the index". That is a
reclassification from an unknowable to a *fixable* cause, and it is why the
externals-pure column is the honest measure of this slice: **+0.9 pt and
+8.1 pt**, a ninefold spread between two corpora, reported per corpus because an
average of two inverted numbers describes neither.

This reproduces, on a third class, the correction already recorded against the
ceiling table: **a class measured while another dominates measures the other
class.**

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
- **An alias whose TARGET is a unit-local module** (`module D = Deep`) rewrites
  to the unqualified `Deep.Syntax.plus` and does not resolve: the rewrite is
  only as good as `Path.name` of the target, and a local path carries no unit.
  The edge is honest — MAY_ENUMERATED with no `callee_id` — and strictly better
  than the ⊤ it replaces, but it is not the resolution the cross-unit case gets.
  Pinned by a test so that closing it is a visible change.
- **`classify_head_path` is deliberately not rewritten.** It emits nothing and
  feeds error-channel config matching, so rewriting it would change which calls
  match declared `binds`/`transforms` paths — outside this spec's scope, and
  with no measurement here to justify it. Named rather than left to be found as
  a divergence from `record_head`.
