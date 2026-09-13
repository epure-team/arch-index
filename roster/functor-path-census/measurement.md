# Fixed410 path census — 2026-09-13

Status: measured twice with identical semantic payload, independently reviewed
and QA-verified (including another fixed410 replay), shipped in PR104 on2026-09-13.
Exact-head CI34780257512 SUCCESS before rebase merge0ca025b.
Both runs used `run.js` and the committed fixed410 manifest; all input hashes
were checked before and after each run. Tezos revision remained
`1727d7e192f2374edda7ad7adceef6f4ec51f71a`; the same 47 porcelain entries
were observed before and after. No Tezos writes or builds were performed.
The owned replay report was removed after successful deep equality comparison.

## Results

410 artifacts, 1,275 syntactic applications, 202 matched and 1,073 unresolved.
Of those unresolved occurrences, 1,050 have reason `unsupported_path`.
The latter occupy 128 distinct display strings and 240 artifact-local
`Path.same` identity classes. These are three different counting units.

| Root category | Protocol | Irmin slices | Total |
|---|---:|---:|---:|
| Persistent unit | 630 | 216 | 846 |
| Bound application result | 141 | 6 | 147 |
| Bound alias | 0 | 37 | 37 |
| Named functor parameter | 0 | 15 | 15 |
| Bound structure | 0 | 5 | 5 |
| Total unsupported paths | 771 | 279 | 1,050 |

All unsupported terminal trees are `Pdot`; none has an applied/extra-type
root. Literal applied-head depth counts are 456 at depth 0, 300 at depth 1,
223 at depth 2, 58 at depth 3, 8 at depth 4 and 5 at depth 5.

Only 42 unsupported occurrences have an exact-name selected-unit candidate:
38 rooted at display name `Irmin`, 4 at `Irmin_pack`. The remaining 1,008
have no such candidate. This inventory is NOT declaration ownership, dependency
identity, or a resolution certificate. In particular, wrapped/persistent names
must not be normalized heuristically into authoritative owners.

High recurrence display groups include
`Tezos_raw_protocol_alpha.Storage_functors.Make_subcontext` (195),
`Tezos_raw_protocol_alpha.Storage_functors.Make_single_data_storage` (168),
and `Indexed_context.Make_map` (102). Repeated displays are not distinct targets.
An independent Terra-model interpretation reproduced the distribution from
the complete JSON report and inspected the probe's counting semantics.

## Roadmap interpretation, not an implemented feature

1. Separately specify evidence-backed persistent-unit qualified-head lookup:
   identity, wrapping, available declaration artifacts, and explicit refusal
   rules before claiming gains. The 846 occurrences make this the dominant
   measured class, not an estimate of automatically recoverable targets.
2. Then local member provenance through application results and aliases:
   application/alias/structure categories together account for 189 occurrences.
3. Parameter-member reasoning covers another 15 here; retain it as a separate
   precision question rather than conflating defunctorization with general 0CFA.

No engine, schema, call targets or graph changed in this census. The existing
202 matched outcomes remain 120 protocol / 82 Irmin. The sample is not a closed
world or source-freshness claim. Import CRCs are retained but no CMI is loaded.
Before/after hashes are not an atomic filesystem snapshot.
