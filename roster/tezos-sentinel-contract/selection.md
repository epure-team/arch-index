# Selection — Tezos defensive sentinel contract

## Chosen first slice

Start with the shared contract and the P2/P7 structural sentinel, rather than
starting another call-resolution or 0-CFA implementation.

The pinned `proto_alpha` measurements already show a useful origin surface but
also substantial unresolved/frontier evidence.  Better call resolution can
make a particular cone more informative, but cannot decide whether a verifier
binds its claimed data, a budget is sufficient, or a state machine progresses.
The first product value is therefore an honest, reviewable signal around
explicit error origins and unfinished paths.

## Reused work and boundaries

`origin-class-precision` owns typed-tree distinctions for literal divisors and
`assert false`; its implementation must be reused rather than re-specified.
`vuln-reachability-triage` is about third-party advisory identity/ingestion and
is not this sentinel.  The new programme may consume `arch-query` and
`arch-rules` output but cannot claim their lower-bound traversal is a closed
world.

## Deferred decision

Whether a later common interchange should be SQLite, NDJSON or a library API
is deferred until two specialized consumers need the same facts.  The first
sentinel may use existing CLIs and versioned output; it must not migrate the
database schema merely for future convenience.
