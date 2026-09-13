# Existing effect exclusion — compiler-shape clarification

Root, 2026-09-13, before semantic implementation. Linked OCaml source _opam/lib/ocaml/effect.ml:16 declares %perform, :43 %resume, :44 %runstack, :75/:143 %reperform. These are compiler primitives, not necessarily dedicated expression constructors.

The intake already excludes effect execution regions. To avoid the generic unlisted-application rule contradicting that exclusion, C-11's table and FR-027 now explicitly classify those four primitive application subtrees as unsupported, reason unsupported_effect_primitive. Arguments and nested functions remain inventoried under sticky unsupported ancestry.

This adds no effect interpretation, precision or new public capability; it closes the typed representation of an already excluded construct. The same reason must be checked by numeric/unsupported tests. Claims FR/AC/CHECK counts unchanged. This clarification is included in later independent review/QA; no claim those tests have run yet.
