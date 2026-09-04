# Intake Brief — point-free-aliases

**Date:** 2026-09-04
**Status: VALIDATED**
**Hold lifted 2026-09-04 by the human ("reprends").**
Held earlier the same day because four branches were in flight over the same files.
#62 and #63 have since merged; #65 is pushed, green and awaiting re-review, and it is
the only remaining branch that touches a calibrated file. The spec phase writes no code
and the 1.6 resolver is an IMPLEMENTATION dependency, not a spec one — so speccing now
is the parallelism the peer recommended, not a risk.

What still does NOT change: implementation waits for the roadmap-1.6 resolver to merge.
Alias target resolution goes through it, and today's `resolve_qualified` keys
`mod_name_to_path` on the capitalised basename with `Hashtbl.replace` — last-writer-wins
— so building on it would inherit that bug.
**Type:** feature
**Trust boundary:** no  ← keyword heuristic on `task.md`: no hit

## Goal

A point-free value alias — `let f = M.g`, η-reduced, no `Texp_apply` anywhere in the
body — produces a `functions` row with **zero** outgoing call edges, because the walker
records an edge only at a `Texp_apply` site. The alias node is therefore severed from
the definition it forwards to, and answers every graph question as if it did nothing.

Give the alias an edge to its target, marked as an alias rather than an ordinary call,
so that the analyses which should follow it can, and the analyses which must not treat
it as a call can tell the difference.

### Severity — stated precisely, and deliberately not escalated

Both verdicts **are** emitted today. `may-fail apply_operation --channel exception` on
proto_alpha prints, in one output:

```
apply_operation: UNBOUNDED (⊤): {Assert_failure, Division_by_zero}   ← apply.ml:2868, the real body
apply_operation: BOUNDED: {}                                          ← main.ml:393, the alias
```

`raises` agrees with `may-fail` on both nodes. So this is a **disambiguation** defect —
the tool prints the right answer and a dead answer side by side, with nothing in either
verdict line to say which is which — **not** a soundness or false-negative defect.

This is worth stating because an earlier report of it *as* a false negative was a
measurement error (a `head`-truncated read of a two-verdict output), and a brief that
inherits that framing would justify a larger change than the evidence supports.
`briefs/error-channels-qa-scope.md` row O-7 already recorded it correctly.

### Measured extent (proto_alpha, `r2-pa.db`, 14452 nodes)

| Stratum | Count |
|---|---|
| zero outgoing edges | 3021 |
| … one-line AND arrow-typed | 620 |
| … of which qualified aliases (`M.g`) | 248 |
| … of which local aliases (`g`) | 87 |
| … genuine leaves / identities / η | 285 |
| homonym names (≥2 nodes) | 540 |
| … with a zero-edge node **and** a live node | **117** |

Concentration: `alpha_context.ml` 56, `storage.ml` 26, `storage_functors.ml` 14,
`dal_slot_repr.ml` 10, `main.ml` 5 — the protocol API façade. Both protocol entry points
are themselves aliases (`main.ml:393`, `main.ml:395`).

## Scope Boundary

Explicitly OUT of scope:

- **Module aliases** (`module N = P`). A different object with a different owner — the
  peer's roadmap-1.6 resolver. This task is value aliases only.
- **Chained aliases beyond one hop**, unless the spec's fixpoint gets them for free.
  If it does, that is a finding to state, not an unstated bonus.
- **Homonym disambiguation in the verdict output.** Two blocks with an identical bare
  label and no file/line (`arch_query.ml:837-870`, `arch_exn.ml:500`) is a real
  readability defect, and this task does not fix it. Naming it here prevents the spec
  from quietly absorbing it.
- **Changing `No_database`/capability-fallback semantics**, `top_reason` consumption, or
  anything in the coverage matrix.
- **Non-OCaml producers.** The NDJSON alias record is a separate follow-up.

## Relevant Files

| File | Role | Key snippet |
|---|---|---|
| `lib/arch_index/arch_index_cmt.ml:1695-1860` | the only site that records an edge | the `Texp_apply` arm; `record_head` classifies `Head_local`/`Head_qualified`/`Head_unknown`/`Head_enumerated` |
| `lib/arch_index/arch_index_cmt.ml:1437-1452` | the near-miss | a non-head `Texp_ident (Path.Pident id)` becomes an edge **only when `id` is a stamped lambda**; a bare qualified path in a `let` RHS matches nothing |
| `lib/arch_index/arch_index.ml:436` | the single `INSERT INTO calls` | carries `kind`, `top_reason`, `top_anchor` |
| `lib/arch_index/arch_index.ml:701-729` | `resolve_qualified` | most- to least-qualified readings, first hit wins — **to be replaced by the peer's resolver** |
| `architecture-schema.sql:183` | `calls` | `kind` + CHECK-constrained `top_reason`: the precedent for a marked edge |
| `lib/arch_tools/arch_graph.ml:77-120` | shared loader for 4 consumers | `fwd`/`bwd` = MUST ∪ MAY_ENUMERATED; `must_fwd` = MUST only; `tops` = frontier |
| `lib/arch_tools/arch_exn.ml:449-462` | **separate** loader for effects | branches on `kind` only to special-case `MAY_TOP` |
| `bin/arch_query/arch_query.ml:268` | `reaches` | filters `kind='MUST'` |
| `bin/arch_rules/arch_rules.ml:171-188` | `reach_verdict` | `must_fwd` → VIOLATION, `fwd` → POSSIBLE, `tops` → UNKNOWN |
| `bin/arch_query/arch_query.ml:357`, `:556` | `fan-in`, `god-modules` | neither filters on `kind` |
| `tezt/tests/schema_drop_list.ml` | re-index soundness | any producer-written table absent from the drop list is unsound on re-index |

## Architecture Notes

**Decided: a MARKED `MUST` call edge alias→target, not a relation outside the call graph.**

Two reasons, in priority order:

1. **Raise-set propagation runs on `calls` edges.** A relation outside the graph forces a
   second fixpoint mechanism, and two propagation mechanisms diverge. This is not
   hypothetical — `exn_scopes` shared across channels already cost us a 4386-vs-2245
   discrepancy depending on whether the channel filter was applied.
2. **There is no single chokepoint to teach.** `Arch_graph` serves four consumers,
   `Arch_exn` is a *separate* loader, and `arch-query`'s own commands go straight to SQL.
   An outside-the-graph relation must be taught to **three** independent readers.

The honest objection — an edge misrepresents the relation, since the alias does not
*call* the target, it *is* it — is answered by the marker, not by refusing the edge. A
metric that counts aliases as calls is a bug in the metric once the data distinguishes
them; while the data does not, no metric can be correct.

**Prior art supports the marked-edge shape** (research Q7): no surveyed system defines a
first-class transitive alias relation. SCIP overloads existing `Relationship` flags
(`is_definition` exists precisely for "symbols which do not have a definition of their
own"); LSIF has monikers, not alias edges; CodeQL keeps ordinary call edges and adds an
**opt-in** transitive library predicate (`FunctionWithWrappers`) while `getCallee`
deliberately does *not* skip wrappers; rustc/rust-analyzer resolve re-exports away at
name resolution so nothing remains to query; merlin's alias-jump is documented as
incomplete and odoc's `@canonical` is author-declared and never verified.

**Risk to name now:** `top_reason`/`top_anchor` are written by producers and read by **no
consumer anywhere in the repo**. A marker column can be added and stay inert
indefinitely. The spec must name which consumer reads the alias marker on day one, or
the marker is decoration.

**Sequencing.** Implementation lands *after* the peer's roadmap-1.6 resolver
(`feat/qualified-unit-resolution`, in review), because alias target resolution goes
through it. Today's `resolve_qualified` keys `mod_name_to_path` on the **capitalized
basename** with `Hashtbl.replace` — last-writer-wins, so two same-basename files in
different libraries silently collapse. Building alias resolution on that would inherit
the bug. The spec does not wait for the merge.

**Hard constraint from the peer, in their corrected formulation.** Their S4 disambiguator
rests on "exactly one reading touches the functions table". My first statement of this
constraint aimed at the wrong object: their premise concerns **module** aliases
(`module Bar = Bar`), mine concerns **value** aliases (`let f = M.g`) — and a value alias
obviously has a `functions` row, which is exactly why a second verdict exists. Corrected:

> the change may add an **edge**; it must **not** add a `functions` row whose name
> contains a dot in the **aliasing** module.

Assertable, so it belongs in the spec as a frozen guard, not prose:

```sql
select count(*) from functions f join modules m on m.id = f.module_id
where f.name like '%.%' and f.name not like '%<fun:%'
```

Measured on octez-manager: **638**, all from inline submodules
(`module For_tests = struct … end`), none from aliases — verified during research rather
than taken on trust. (Without the `<fun:` exclusion the same query returns 5880; the
exclusion is load-bearing.)

## Quality Gates

```bash
# Build (MUST use the project's own opam switch; the default octez-setup switch
# produces spurious eio/caqti/otoml errors)
eval $(opam env --switch=/home/mathias/dev/arch-index --set-switch)
dune build

# Tests — via runtest, NEVER `dune exec tezt/tests/main.exe`
dune runtest --force

# Lint/format: not documented (no .ocamlformat at the repo root)
```

**`dune exec tezt/tests/main.exe` does not rebuild the producer binary.** The `(test)`
stanza declares it in `deps`, but `deps` apply to `runtest`; and the harness locates the
producer by path (`tezt/lib/arch_tezt.ml:51`), so it happily runs a stale `.exe`.
Demonstrated in-session: with a fix reverted, `dune exec` reported SUCCESS and `runtest`
reported FAILURE on the same source. Every AC is verified with `runtest`, and every new
test is red-verified first — a red also proves the artefact is fresh, since a stale
binary would go green.

## Open Questions

- [ ] **Is the alias edge transitive for `reaches`, and is the answer uniform across
      consumers?** It cannot be answered once globally: `reaches` filters `kind='MUST'`
      (`arch_query.ml:268`) and `arch-rules`' `must_fwd` closure is what yields
      VIOLATION (`arch_rules.ml:171-188`), so a MUST-marked alias edge changes **both**
      by construction unless the marker is consulted. Position to be challenged, not
      assumed: **transitive for effect propagation** (`may-fail`/`raises` — the alias
      *is* the target, so it raises what the target raises), **visible and counted for
      layer rules** — an alias crossing a layer boundary is exactly what a rule must
      report as VIOLATION, and traversing it silently would answer OK where VIOLATION is
      correct. CodeQL's `getCallee`/`FunctionWithWrappers` split is the precedent.
      **Requires one AC per consumer.**
- [ ] **Do `fan-in` and `god-modules` count alias edges?** Neither filters on `kind`
      today (`arch_query.ml:357`, `:556`), and `fan-in` does not even exclude unresolved
      callees, so both change the moment an edge is added. The spec must decide
      explicitly; discovering it as a side effect is how a metric silently stops meaning
      what its name says.
- [ ] **Which consumer reads the alias marker on day one?** If the answer is "none", the
      marker repeats the `top_reason` precedent — written, never read — and the spec
      should say so plainly rather than imply a capability that does not exist.
- [ ] **Does the local-alias case (`let f = g`, 87 of 335) resolve by the same path as
      the qualified case (248)?** The peer's resolver addresses qualified units; a bare
      local identifier may need a different lookup. Implementers must not assume one
      mechanism covers both.
- [ ] **Can this feature make currently-resolvable references UNRESOLVABLE?** Raised by
      the peer after their round-2 review, and it is the exact mirror of the constraint
      they gave us. Their façade tier may no longer reinterpret a segment **above the
      anchor**, where the anchor is the deepest reading naming an *indexed* unit. Any
      `functions` row in an aliasing module therefore **acts as an anchor** for every
      reference passing through it, closing the façade tier at that depth. Our design
      adds no `functions` row, so the first-order risk is avoided — but the alias EDGE
      still changes what resolves, and "avoided by construction" is a claim, not a
      measurement. **Measure the resolved-edge set before/after on octez-manager AND
      proto_alpha; any reference that stops resolving is a finding, not a footnote.**
- [ ] **Who re-measures `test/fixtures/self-index-stats.txt`?** Three in-flight branches
      recalibrate it from the same base — the peer's roadmap-1.6 (5067), our #63
      (778/5051) and our #65. They are not mergeable as they stand: whichever lands
      second must **re-measure**, never adopt the other's number.
      `scripts/recalibrate.sh` (PR #64) does exactly that and refuses to write when the
      movement is not attributable to source alone. This task will collide with the same
      file and must plan for it rather than discover it at merge.
- [ ] **What moves on channels this task does not target?** The peer documented a channel
      and wrote "nothing moves"; the review found `tzresult` bounded 585 → 581, +1435
      members across 41 of 377 identities, 0 removals. Anything propagating over `calls`
      edges — which an alias edge does by construction — must report movement on **every**
      channel, measured, not on the ones the change was aimed at. A documented channel is
      not the corpus.
