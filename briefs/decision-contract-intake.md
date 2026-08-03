# Intake Brief — decision-contract

**Date:** 2026-08-02
**Status:** VALIDATED (autonomous run)
**Type:** feature
**Roadmap:** lot 3 — R9, the multi-language lock
(`docs/research/mcdc-coverage-feasibility.md` §8.4, R9)

## Goal

Make the NDJSON producer contract able to carry the analysis, and make it
**fail loudly** when it cannot.

The blocking finding, demonstrated rather than argued: `arch-load` reads only
the fields it knows (`rec.get("name")`, `rec.get("kind")`, …). A Go producer
emitting `mutation_sites` or a `decision` record today would have it **silently
discarded** — no error, no warning. And the asymmetry is stark: on edge *kinds*
the loader is uncompromising, dying on an invalid value with the comment
*"refuse rather than emit a lie"*; on an unknown *field* it says nothing.

So everything added in lots 1–2 is OCaml-only in practice, not because the
consumer side is language-specific — the schema and every `arch-query`
subcommand are agnostic — but because the wire format cannot carry it and gives
no signal that it didn't.

This lot:

1. Extends the NDJSON format with `decision` and `dead_site` record types, and
   with the per-function metric fields.
2. Makes `arch-load` **reject unknown fields and unknown record types** instead
   of ignoring them, with the same refuse-rather-than-lie posture it already
   takes on kinds.
3. Stamps `decision_contract` in `comment_db_meta` when a producer supplies the
   analysis, so consumers can tell a producer that computed nothing from one
   that computed nothing *to report*.

## Scope Boundary

Explicitly OUT of scope:

- Writing a Go producer. This lot makes one possible; it does not build one.
  `go/ssa` makes mutations more explicit than OCaml (`*ssa.Store`,
  `*ssa.MapUpdate`), so that is a mechanical follow-up once the contract exists.
- Changing the OCaml backend's path: it writes SQLite directly and does not go
  through `arch-load`.
- Changing edge-kind semantics or any existing query.
- Retrofitting the flat schema with the full `decisions` table: the flat schema
  stays minimal, and a flat DB continues to *refuse* the new subcommands rather
  than answer them emptily.

## Relevant Files

| file | role |
|---|---|
| `arch-load` | schema, record dispatch, strict field validation |
| `docs/edge-kind-contract.md` | document the extension alongside the kind contract |
| `selftest-load.sh` | contract tests |

## Design Decisions

**Strictness is the feature.** The existing loader already refuses a call edge
with a missing or invalid `kind`, on the stated grounds that an un-kinded edge
would be invisible to the sound queries — a silent drop. An unknown field is the
same failure with a different shape: the producer author believes data was
carried when it was not. So: unknown record `type` → die; unknown field on a
known record → die, naming the field.

**Forward compatibility has an explicit escape hatch.** A blanket rejection
makes every future field a breaking change. Fields prefixed `x_` are reserved
for producer-private extensions and are accepted-and-ignored. Anything else
must be in the contract or the load fails. That keeps the strictness honest
without freezing the format.

**Optional, not mandatory.** A producer that emits no `decision` records is
valid — it simply does not stamp `decision_contract`, and the decision
subcommands refuse on its output. Requiring every backend to implement the
analysis would block the contract on the analysis.

## Quality Gates

- `selftest-load.sh` green, extended with contract cases.
- An unknown field fails the load with a message naming it; an `x_`-prefixed
  field loads silently.
- An unknown record `type` fails the load.
- Existing valid NDJSON still loads unchanged — no regression for the Go
  backend as it stands today.
- All arch-index selftests and `STRICT=1 selftest-callgraph-soundness` green.

## Acceptance Criteria

- AC-1: `arch-load` accepts `decision` and `dead_site` records and persists them.
- AC-2: `arch-load` dies on an unknown field, naming it and the line.
- AC-3: `arch-load` dies on an unknown record `type`.
- AC-4: `x_`-prefixed fields are accepted and ignored.
- AC-5: `decision_contract=v1` is stamped only when decision records were seen.
- AC-6: the existing Go-backend NDJSON shape loads exactly as before.
