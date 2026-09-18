# Research — analysis report profiles

`arch-report` already has the right rendering architecture: `collect` produces
one value, then JSON/SARIF/HTML are pure renderings. The profile mechanism must
therefore enter at collection, not as scripts which independently query SQLite.

The current report knows two persisted analyses (`dead_code`, `sarif_import`)
and optional `arch-rules` evaluation. `Arch_graph` gives bounded
`MUST ∪ MAY_ENUMERATED` traversal, while `MAY_TOP` must remain a distinct
frontier. Stage6 adds target-v2 evidence and `analysis-status`; no stored field
identifies which MAY edge came specifically from CFA, so a profile must not
claim a CFA precision metric.

`api-review` can safely begin as a transparent inventory/report of exported
roots, top-frontier count and availability of error/effect/functor evidence. A
profile which presents uncomputed error or effect analyses as alerts would be
wrong; it needs a labelled unavailable section. `architecture` is naturally a
named wrapper around an explicit rule file, not a new rules engine.

`change-review` needs a next-stage semantic identity and an explicit baseline:
function/location/call identity, tool/corpus/config fingerprints, contract
compatibility and a classification of unavailable or reduced scope. It remains
planned, not emulated by `git diff` text in this stage.
