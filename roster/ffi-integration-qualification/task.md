# Roster intake — FFI Stage 5: integration and qualification

## Objective

Publish a deterministic FFI evidence report for a corpus root, combining the
four staged sidecars and connector descriptors into one user-consumable status.
It must make resolved evidence and retained frontiers queryable without writing
to SQLite or changing call-graph semantics.

## Acceptance evidence

1. The report preserves Stage1–4 digests/counts and identifies every connector
   version used.
2. Its summary distinguishes strict OCaml-C bindings, Rust archive endpoints,
   callback frontiers and all retained `MAY_TOP` records.
3. Missing prerequisite artefacts result in explicit `NOT_ANALYSED`/frontier
   status, never zero findings or synthetic graph edges.
4. The Tezos replay is deterministic; it reports that FFI graph precision is
   unchanged until a separately approved graph integration.

## Non-goals

- No schema migration, loader change, call edge, reachability verdict change or
  MUST claim.
- No implicit discovery outside the supplied corpus root.
