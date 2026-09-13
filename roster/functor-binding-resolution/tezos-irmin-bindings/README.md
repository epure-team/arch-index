# Same410-CMT binding observation — 2026-09-13

This run uses the candidate producer, not a shipped release. The real binding
query returns contractv1,410 selected/collected inputs,1275 applications,
202 matched formal bindings and1073 explicit refusals. Every input was collected.
The byte-verified manifest is unchanged:
9e38880a52f855c58081b1a171af5879058cbaa2697aaa5694827cbd16f8ecd1.

| Selected slice | Applications | Matched formals | Unresolved |
|---|---:|---:|---:|
| Irmin core/pack/Unix |384|82|302|
| proto_alpha protocol |891|120|771|
| Total |1275|202|1073|

Matched positions are1:150,2:23,3:15,4:6,5:6,6:2. Thus52 observed bindings
are beyond the first formal of a literal curried telescope.149 declarations
were stored. These are application-to-formal facts, NOT resolved callees,
runtime instances, actual substitution,0CFA or closure evidence.

Refusals: unsupported_path1050, parameter_supplied_head12,
local_declaration_missing8, unsupported_alias_rhs3. Unsupported_path counts
application results (including propagated inner refusals), not distinct paths
or exclusively external units. The current contract intentionally declines every
non-Pident head. This supplies concrete prioritization evidence for a later
path/module normalization slice; first distinguish local projections from
cross-unit roots before expanding semantics. Do not widen this PR's scope silently.

Graph context only:13601MUST,23209MAY_ENUMERATED,8208MAY_TOP (45018 calls).
These equal the historical catalogue observation, but this run is not a fresh
Tezos engine A/B experiment and claims no call-target precision gain.

Tezos revision1727d7e192f2374edda7ad7adceef6f4ec51f71a was dirty47entries
before this run (earlier research recorded46). The exact pre/post porcelain
status matched; the checkout is not described as clean. CMT hashes were checked
before and after. No source edit or Tezos build occurred. The temporary symlink
selection and DB under _build/arch-index-bindings-probe-CeYDcp were removed in
finally. This is a reversible build-directory mutation, not a claim of zero
filesystem writes. Producer/query binary hashes and complete aggregates are in
report.json; producer.log retains the actual run's warnings and counters.
