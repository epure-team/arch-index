# Cross-spec consistency (operator)

Enumerated `specs/*.md` and read every existing `## Entities` block mechanically
on 2026-09-13. New entity names are `FunctorCatalogueInput`,
`FunctorApplicationOccurrence`, `FunctorExpressionDescriptor`, and
`FunctorCatalogueContract`; none already has a conflicting definition.

Existing `call kind`, `MAY_TOP edge`, lambda node, exception origin, canonical
exception path, error contract, reach verdict and raise-set verdict remain
unchanged. The catalogue marker describes collection over selected artifacts,
not any of those graph/effect contracts. `GuardArtifact` and `GuardSite` belong
to the separate arch-guard command and are not reused or broadened.

Research identified existing functor-application residuals in reexport-resolution,
qualified-unit-resolution, exn-raise-sets and error-channels. Keeping catalogue
data separate from resolution preserves them rather than declaring them fixed.
No entity-definition conflict requires human arbitration for this slice.

Standalone human-validation.md protocol was searched under installed skill roots
but is absent. Repeated quiz is overridden by explicit standing autonomy; no
human response is invented. Technical challenge/check obligations remain active.
