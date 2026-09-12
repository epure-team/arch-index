# Cross-spec consistency — guard-division-analysis

2026-09-13, root read-only review of existing specs' Entities sections and neighboring status definitions.

- New entity names will be GuardArtifact, GuardSite, GuardAbstractValue, GuardClassification and GuardCensus. None duplicates an existing Entities definition.
- specs/actionable-review-reports.md:229 defines DivisorOperandContext as syntax metadata, never a value-analysis result. Keep it unchanged: GuardSite is a separate CLI record, not a DB origin enrichment or exemption.
- specs/exn-raise-sets.md:212 reserves verdict for BOUNDED/UNBOUNDED/BOUNDED_UNDER_HYP. GuardClassification is not that verdict and never rewrites it.
- specs/cfg-postdom-dominance.md:144 defines graph unreachable query behavior. GuardClassification.UNREACHABLE means only a local supported branch contradiction under fresh function-entry contexts, not graph unreachability. Documentation must state this distinction explicitly.
- specs/origin-recurring-consumer.md:289-292 keeps its reference and package meaning. This slice must not edit its corpus/reference to manufacture green results or interpret GuardCensus as production origin counts.
- No conflicting existing canonical entity definition found; no user arbitration required.
- Claims reconciler/authority/KB installation was absent at intake; metadata remains draft until actual tooling can validate/project it. Do not call generated claims active.
