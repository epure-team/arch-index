# Research — functor explained queries

## Current evidence

The producer atomically publishes `functor_target_contract=v2` with four
normal-form tables: inputs, physical occurrences, candidates, and witnesses.
`functor_target_witnesses` binds an application/formal/actual/member proof to a
candidate call and concrete target function. `functor_target_occurrences` also
retains `top_call_id`; known candidates therefore do not erase the open-world
module-parameter frontier.

`Arch_graph` already consumes `MUST` and `MAY_ENUMERATED` for bounded
traversal. This intake must only read its evidence: a target row is not a new
call graph edge and a `MAY_ENUMERATED` relation is not a MUST path.

## Reader boundary

The existing `Arch_functor_bindings` reader is the appropriate validation
baseline: it rejects flat/wide/partial schemas, validates marker and storage
classes, uses a transaction snapshot, and treats producer-table disagreement as
`INCONSISTENT_BINDINGS`. The target reader must be at least as strict, then
validate foreign-key-like relationships itself rather than trusting SQLite
foreign-key enforcement in a read-only database.

## Interface decisions

- New commands receive their own versioned summary object/tables; legacy
  `ARCH_QUERY_FORMAT=json` commands remain untouched because several deliberately
  emit a JSON stream.
- `analysis-status` is availability metadata, never a claim that a result set
  is empty.
- `unknown-frontier` uses the exact `escapes` closure (`MUST ∪ MAY_ENUMERATED`)
  and labels its result `MAY_TOP`; it refuses an unknown root and an absent
  callgraph contract, exactly as `escapes` does.
- Initial function selection for `functor-targets` stays deliberately narrow:
  either all validated evidence or an exact caller name. Path/glob selectors
  would add ambiguity without solving a present user question.

## Validation matrix

Use native authentic-CMT fixtures for: multiple witnesses for one candidate,
known target plus `MAY_TOP`, same function name in different modules, repeated
physical site, zero limit, corruption, flat and markerless database. Assert no
graph mutation with row-count snapshots. Run the target reader against the
pinned Tezos corpus as an observation only; its result must not become a
precision claim.

## First implementation receipt

`analysis-status` is implemented first because it makes later optional readers
observable without conflating absent computation with an empty query. The
targeted `functor_catalogue` native test passed on 2026-09-18, including the
new status assertion. Its three pre-existing native-probe/checker setup
failures were caused by deliberately scoped `dune build tezt/tests/main.exe`
not building the catalogue probe executables; a full `dune runtest`/hosted CI
is required for that separate setup contract. The temporary `_build` was
removed immediately after the check.
