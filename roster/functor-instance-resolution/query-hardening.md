# Query hardening evidence

Scope: reader-side FR-021--FR-030 validation in
`lib/arch_tools/arch_functor_catalogue.ml`. CLI argument parsing and rendering remain
owned by the primary OCaml implementer.

## Implemented validation

- Starts a Caqti transaction before schema, marker, header, input, or application
  reads and commits only after the complete snapshot has validated.
- Applies refusal precedence: required schema first, exact marker second (including
  available failed-outcome counts), semantic consistency third.
- Requires one positive header linked to `producer_runs`, an exact collected input
  census, nonempty provenance, and a real `modules.id` whose path equals the input
  source.
- Scans inputs and applications directly and rejects orphan rows rather than relying
  on inner joins. Checks each input's expected count independently.
- Validates SQLite integer storage classes before parsing bounded OCaml integers.
- Validates the closed location, descriptor, diagnostic and unit-placement grammar;
  checks sorted exact diagnostics, contiguous per-artifact ordinals, and strictly
  forward same-input application references.
- Builds the full sorted public snapshot before computing totals or applying `limit`,
  including `limit=0`.

## Verification provenance

Root subsequently expanded compressed OCaml pattern matches and validation flow
with apply_patch. `ocamlc -stop-after parsing -dsource` before and after returned0
and byte-identical canonical parsed-source output: readability-only change, no
parsed behavior change. No formatter is installed. No Dune was run by root during
the specialist's ownership; final serial build was requested after the stable
formatting savepoint. Runtime thread limits prevented restarting the query agent
for this cleanup, so root integrated it locally.

The initial native RED preceded this delegated hardening slice and is not claimed
here. Per shared-worktree ownership, this agent did not invoke Dune or the test suite.
The primary OCaml implementer ran
`dune build --root . tezt/tests/main.exe` against the stable file and reported a
clean compile. That owner also ran the four current functor-catalogue native Tezt
tests and reported all four passing. This delegated agent did not execute or
independently observe those commands; final suite ownership remains with the root
agent.
