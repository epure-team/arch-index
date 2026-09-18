# Functor targets and unknown frontiers

An OCaml functor application can make a formal member call such as `X.target`
refer to a concrete member such as `A.target`. arch-index records this only
when it can prove the correspondence inside the selected CMT artefact.

Start by asking what the database actually contains:

```sh
arch-query architecture.db analysis-status
```

`functor_target / COMPUTED / v2` means the producer published the complete
target contract. `NOT_COMPUTED` is not an empty target set: re-index with a
producer that supports the contract. `UNSUPPORTED_SCHEMA` means the database
is an older flat representation and cannot contain this evidence.

```sh
ARCH_QUERY_FORMAT=json arch-query architecture.db functor-targets 50
ARCH_QUERY_FORMAT=json arch-query architecture.db unknown-frontier F.run
```

`functor-targets` emits one row per retained witness. A row identifies the
physical formal-member occurrence, the concrete target, actual/member paths,
and separate `application_ordinal` / `formal_position` proof fields. Its edge is always `MAY_ENUMERATED`: it is a
bounded possible target, never a `MUST` claim.

`top_frontier` reports the associated original top edge when one was
authenticated. `MAY_TOP:module_param` is expected in the common case: a
known same-CMT target adds useful evidence but does not close the open-world
possibility that a module parameter denotes some other implementation.

`unknown-frontier` is the explicitly named form of `escapes`. It follows the
same bounded closure (`MUST` plus `MAY_ENUMERATED`) and prints reachable
`MAY_TOP` edges. It refuses an unknown root or a database without the
callgraph contract; an empty computed result therefore means no reachable top
edge in that closure, not a proof that every call is MUST.

None of these commands writes SQLite rows, creates graph edges, instantiates
functor bodies, or changes reachability. They explain evidence that was already
published by the indexer.
