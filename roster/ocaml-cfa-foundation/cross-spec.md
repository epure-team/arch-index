# Cross-spec examination — stage2 foundation

2026-09-15. Root listed all23 current specs with rg --files and read their
Entities sections. An initial guessed specs/callgraph-soundness.md path was
absent; discovery corrected that search. Executable test of that name exists,
not a matching spec file. No claim of reading every complete spec in this scan.

The new proposed entities CFAValue, CFACell, CFAApplicationOccurrence and
CFAAnalysisSession do not redefine existing GuardAbstractValue, raise-set,
lambda node, call kind, LocalValueAliasInvocation or ResolutionRelation.
Session occurrence identity is finer than ResolutionRelation (caller/source-line/
target), whose documented definition explicitly does not identify expressions.
ResolutionRowMultiset still preserves multiplicity.

Existing lambda display convention and actual collision suffixes remain in force.
MUST post-dominance/saturation, MAY_TOP frontier, exception/error channels and
immediate-predecessor alias provenance retain their current meaning.

Historical refusal obligations need an explicit scope amendment in the new spec:
tezos-residual-targets FR005–007/016 and AC11 describe a previous one-hop slice;
only the newly supported same-CMT nonrecursive single-variable value-flow subset
is refined. Body-only function stamps, independent residuals, scopes and old
measured baselines remain mandatory and unchanged. The doc/test expectation
updates belong to stage2 implementation, not a rewritten historical experiment.

Flat is deliberately kind-less; no new proof-bearing schema or uniquely resolved
caller identity is asserted. Its unsupported representation must remain visible.
This limitation is not an entity-definition change or a reason to migrate LSP
function naming without separate authority.
