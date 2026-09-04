# Plan — point-free-aliases

**Date:** 2026-09-04
**Status: VALIDATED** (autonomous run — the human asked for it; the two voices agreed
on every step, no DISAGREE and no USER-CHALLENGE arose, so nothing needed a gate)

## What the two voices changed before a line was written

Three claims in the upstream artefacts were wrong. Each was verified in the tree, not
argued.

1. **The spec's justification for `MAY_ENUMERATED` was false.** It said the existing
   kind matrix demotes an alias via `call.partial`. It does not: `partial` means
   *under-saturated application* (`arch_index_cmt.ml:535`), and an alias is not an
   application, so `demoted = false` and `Head_local`/`Head_qualified` emit **`MUST`**
   (`arch_index.ml:859`, `:874`). The conclusion survives, the reasoning did not. The
   spec is corrected; the mechanism is `Head_enumerated`, which forces `MAY_ENUMERATED`
   unconditionally (`:843`).
2. **The resolver is not a waitable dependency.** `feat/qualified-unit-resolution` is
   **15 commits ahead** of `main`, on review round 4, and has recalibrated the golden
   **five times on its own branch** — its HEAD is `782 → 802`. `main` will jump +20
   functions when it merges.
3. **A fourth producer of `calls` rows exists and no upstream artefact mentions it.**
   `lib/arch_index/runner.ml` writes its own inline flat schema, and its doc comment
   calls itself the production entry point via `arch_index_cli`. The spec's
   "no chokepoint" inventory named `Arch_graph`, `Arch_exn` and `arch-query` — not this.

## Sequential steps

**S0 — Measure the typedtree-path split.** Instrument the drop site to count, on both
corpora, bare-`Texp_ident` RHS bindings by `Path.Pident` / `Path.Pdot` / other, crossed
with arrow-typed or not. Deliverable is a number in `briefs/`, **not** product code.
Explicitly a horizontal spike and justified as such: the spec retracted the 248/87
source-syntax split, so nothing downstream can be sized until this exists. Timeboxed;
design decisions belong in S1, not here.

**S1 — Local alias slice, end to end.** RHS peels to `Texp_ident (Path.Pident id)`,
arrow-typed. Schema column + producer + consumer + tests in one slice.
- `architecture-schema.sql`: `edge_form TEXT CHECK(edge_form IS NULL OR edge_form =
  'value_alias')`; bump `current_schema_version` (`arch_index_db.ml:52`).
- `arch_index_db.ml`: `insert_call_rowid` binds 8 positional params today; a 9th touches
  the DDL, the prepared statement, both signatures and every call site.
- `arch_index_cmt.ml`: at the `peel` no-op, emit via `add_path_call` classified
  **`Head_enumerated`** — no new `Head_*` constructor, no classify-match change.
- `arch_query.ml`: gate the `fan-in`/`god-modules` exclusion on
  `Arch_db.has_col t "calls" "edge_form"`. The flat schema has no such column and an
  unconditional `WHERE edge_form <> …` would error against it.
- Exclusion fixtures, one test each: `let _ = M.g` (no `functions` row exists at all —
  assert no orphan call), non-arrow RHS (`let k = M.pi` — assert still zero edges),
  `let rec f = f`, and a dropped-node target (assert `kind='MAY_TOP'`,
  `top_reason='dropped_node'`, `edge_form='value_alias'` coexist).

**S2 — Resolve whether `open`-shadowing is a distinct case at all.** Typedtree paths are
post-resolution, so a `Path.Pident` for an `open`-brought name may already carry the
target's own stamp — in which case S1 covers it by construction and this step's
deliverable is *"confirmed, residual closed"*, not code. S0's measurement settles it.
Must complete before S3, because it moves S3's scope.

**S3 — Qualified alias slice.** `Texp_ident (Path.Pdot …)`. Needs a real classify-match
change: `Head_qualified` defaults to `MUST` when not demoted, so the alias must be routed
to `Head_enumerated` there too, and a test must assert no `edge_form='value_alias'` row
carries `kind='MUST'` (FR-005b). Keep the resolution call behind one named function so
the 1.6 rewrite is a drop-in replacement, not a rewrite of alias logic.

**S4 — Prove the raise-set claim.** The entire rationale for putting the alias in `calls`
is that `Arch_exn`'s fixpoint runs there. `Arch_exn` is a **separate loader**, so S1–S3's
tests do not exercise it. Assert on the motivating example that the alias node's verdict
stops being `BOUNDED: {}`. Include a **mutual** alias fixture (`let rec f = g and g = f`),
not only a self-loop.

**S5 — The flat-schema path: parity or a written non-goal.** Determine whether
`runner.ml`/`Call_graph_extractor` has the same gap. Either fix it or record it as an
explicit non-goal with its reason. It must not be skipped silently because an upstream
inventory forgot it.

## Dependencies

- S0 → everything. S1 → S2 → S3. S4 after S3. S5 independent, may run any time.
- **S3 is the only step touching `resolve_qualified`.** Given finding 2, S3 must land
  either entirely before the 1.6 merge or entirely after it — never straddling, because
  the golden moves +20 on that merge and a straddling slice cannot attribute its own
  movement.

## Identified risks

| Risk | Prob. | Impact | Mitigation |
|---|---|---|---|
| Qualified alias silently emits `MUST` | High | Wrong soundness claim | FR-005b test asserts zero `value_alias` rows with `kind='MUST'` |
| Blast radius understated: `is_alias` threads through `pending_call`, touching ~10 `Head_*` sites | Med | Slice grows | S1 uses `Head_enumerated` to avoid the classify match entirely |
| Golden churn across S1 and S3 plus the 1.6 merge | High | Repeated NO-GO | 2×2 attribution per slice; S3 not straddling the merge |
| `MAY_ENUMERATED` now conflates "callback candidate" and "alias" | Med | Silent semantic shift for anything counting that bucket | `edge_form` is exactly the disambiguator; document it in `docs/edge-kind-contract.md` |
| Adding an `edge_form` filter exposes pre-existing `MAY_TOP`/`MAY_ENUMERATED` inflation in `fan-in` | Med | Scope creep | Name it a separate finding when it surfaces; do not fix it in this task |
| Arrow-type detection under-detects on `.cmt`-restored aliased arrow types | Med | Missed aliases | Fails to today's zero-edge behaviour, the safe direction; track as a residual |
| Flat-schema path unfixed | Med | Defect survives where it is observed | S5 forces the decision to be written down |
| Fixpoint cost | **Low** | — | Measured: proto_alpha indexes in 3969 ms for 73 588 edges; ≤620 alias edges is **+0.84 %** |

## Decisions made

| Point | Decision | Reason |
|---|---|---|
| Kind mechanism | `Head_enumerated`, not a synthesised `partial` | `partial` on a non-application would be a lie in the data to get the right answer by accident |
| New `Head_*` constructor? | No | `Head_enumerated` already means "bounded candidate set"; here of exactly one — the repo's own precedent (`cfg-postdom-dominance.md:25`) |
| Legacy databases | `has_col` gate, mirroring `kinded`/`kind_sql` (`arch_db.ml:290`, `:299`) | A pre-migration database must answer "no aliases", never fail a query |
| S0 tooling | Throwaway | The spec asks for a measurement, not a maintained diagnostic |
| Consumers other than fan-in/god-modules | Alias edges **are** traversed by `Arch_graph`'s consumers | The alias *is* the target; not traversing would be a false negative on real reachability |

## Assumptions

- Typedtree `Path.Pident` is post-`open`-resolution, so S2 likely collapses to a
  confirmation. **Not verified** — S0 settles it, and S2 is a real slice if wrong.
- `reaches` losing alias traversal (a consequence of `MAY_ENUMERATED`) is acceptable and
  is carried as a tracked residual, not a silent cost — see the spec's Residuals section.
