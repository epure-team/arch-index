# Research — documentation routing

Current docs already provide high-quality detailed references: installation,
change impact, reports, coverage, rules, error channels, schema, MCP, mutation
testing and OCaml functors. The gap is not absence of material but the first
five minutes: what is indexed, what answers are sound, which command to run,
and which later page applies.

The README should lead with the product outcome: a queryable architecture
index that labels uncertainty, not a universal static-analysis proof. It should
then route by user intent (CI review, structural investigation, change impact,
advanced language producer) rather than by repository internals.

The CI guide must distinguish signals from verdicts. Useful bounded signals
include changed exposed surface, forbidden bounded paths, unknown/TOP frontiers,
missing coverage, and new recurring observations. None alone proves "slop" or
a vulnerability; the guide must say what requires human review.

Language pages should describe availability and limitations before commands.
OCaml is a deep producer path (CMT, functors, C bindings) but not the product's
default identity; LSP and NDJSON make the main entry point language-neutral.
