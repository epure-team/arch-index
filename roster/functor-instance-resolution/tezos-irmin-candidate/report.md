# Tezos / Irmin candidate syntactic catalogue

This is one bounded candidate run of the already-built producer. It is not an
A/B comparison and does not claim target resolution, graph precision, or a
resolution gain.

## Provenance and input boundary

The run began with Tezos `1727d7e192f2374edda7ad7adceef6f4ec51f71a`.
The checkout was dirty (46 porcelain entries at inventory time) and is not
described as clean. The subsequently supplied source checkpoint
`c2a8add5e394c162eeef4d204a73e1058a436df2` is recorded as metadata-only
post-run provenance: it refers to the same compiled product sources, but it
does not retroactively change this run's revision label.

The producer used the arch-index OCaml-5.3 executable and a temporary symlink
corpus under Tezos `_build/`, so CMT-relative source paths resolved against the
real Tezos root. The corpus was created by `mktemp -d
/home/mathias/dev/tezos/tezos/_build/arch-index-functor-candidate.XXXXXX` and
deleted by its shell trap, together with its `/tmp/arch-index-functor-candidate.*.db`.
This was a reversible temporary mutation below `_build`, not a persistent source
or Git-checkout mutation; it is nevertheless a deviation from a literal
"no Tezos mutation" reading and is recorded here. Aggregate and per-slice
content digests are in `provenance.json`; the exact original paths and byte
hashes are in `manifest-410.tsv`.

The earlier raw inventory contained 414 CMTs. The effective producer set is
410, rather than silently claiming all 414:

| Slice | CMTs | Collected inputs | Syntax applications |
|---|---:|---:|---:|
| Irmin core | 66 | 66 | 228 |
| Irmin pack | 17 | 17 | 13 |
| Irmin pack Unix | 52 | 52 | 143 |
| Tezos proto_alpha raw | 275 | 275 | 891 |
| **Total** | **410** | **410** | **1,275** |

The four raw exclusions are coverage limits of the raw 414-CMT inventory:
three generated Dune alias CMTs are intentionally skipped by `find_cmt_files`, and
`tezos_raw_protocol_alpha.cmt` names generated source
`src/proto_alpha/lib_protocol/tezos_raw_protocol_alpha.ml-gen`, which is not
resolvable in this checkout. Including that CMT makes the catalogue contract
absent (`missing_source=1`). The 410-input catalogue is complete only relative
to its manifest; it does not cover all 414 raw inventory entries.

## Outcome

`arch-query functor-applications 2000` reported catalogue contract `v1`,
`selected_inputs=410`, `collected_inputs=410`, `total=1275`, `returned=1275`,
and `truncated=0`. Every recorded application has kind `apply`; there were no
`apply_unit` records in this bounded input set.

| Diagnostic | Applications |
|---|---:|
| none (`[]`) | 962 |
| `anonymous_argument` | 313 |

These diagnostics classify syntax only. In particular, an anonymous module
argument is not an error and does not say whether any downstream call target is
resolvable.

For context only, the concurrently produced graph had 12,373 functions and
45,018 calls: 13,601 `MUST`, 23,209 `MAY_ENUMERATED`, and 8,208 `MAY_TOP`.
Those are single-run graph facts, not a before/after metric.

## Bounded real-shape examples

The catalogue preserved source locations and nested application structure. In
`irmin/lib_irmin/irmin.ml`, lines 59--65, it recorded nested applications such
as `Backend.Contents_store.Key (S.Hash) (S.Contents)` and
`Backend.Contents_store.Make (S.Hash) (S.Contents)`: the outer application
head is represented as a reference to its inner application ordinal, while the
inner head is the typed path (`Backend.Contents_store.Key` or `.Make`).

The high-density production families were also observed directly: protocol
`storage.ml` contributed 732 syntax applications, Irmin Pack Unix `store.ml`
78, Irmin `irmin.ml` 62, and protocol `storage_functors.ml` 23. These counts
show that the selected corpus actually exercises both Irmin composition and
Alpha storage construction; they do not establish that functor-result member
calls now resolve.

## Limits

The catalogue explicitly states `not_runtime_instances`, `not_closed_world`,
`no_target_resolution`, `no_source_freshness_check`, and
`paths_are_artifact_selections`. A fresh baseline with the identical 410-CMT
digest manifest is required before any resolution delta can be calculated.
`reproduce.sh` contains the exact no-build command sequence, and
`raw-run-410.txt` is the compact stdout capture from its final rerun.
