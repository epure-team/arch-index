# Retained-state residual census — root, 2026-09-14

Read-only reconstruction from the retained baseline DB and QA's exact multiset
changes (2026-09-14T07-23-18-051Z-candidate-2867559/changes.json). Every removal
consumed an existing canonical occurrence. Recomputed45052 rows and exact SHA256
90e76d6b40b2d7f108fcc25523f85de1cb533a98565a8a7d6d284c1654939d4b.
This is documentary prioritization, not a fresh producer run or attempt2 baseline
approval. No DB, corpus or product mutation.

Rows with no internal target, excluding value_alias:

| Slice | module_param TOP | callback_param TOP | ambiguous_unit TOP | MUST external/unlinked | MAY_ENUMERATED external/unlinked |
|---|---:|---:|---:|---:|---:|
| Irmin |1694|2043|8|3834|1729|
| Protocol |920|2655|0|6065|8624|

These are rows, not distinct relation counts or an estimate of resolvable calls.
External/unlinked leaves are not automatically errors or in-corpus definitions.

High-frequency module_param spellings include sc_rollup_arith State.Monad.Syntax.let*
(72 rows), Monad.Syntax.let* (30), storage_functors C.project(43), and Irmin
merge Infix.>>=*(7). Spelling/counts alone establish no identity.

Root live source inspection found an explicit bare value alias `let ( let* ) = bind`
in sc_rollup_arith.ml:240, with bind body at233, inside literal Syntax/Monad
structures at239/205. Irmin merge.ml:70 similarly aliases bind through Infix.
This differs from proof.ml:111's included Hashtbl.Make application, and genuine
storage functor parameters; those cannot inherit a same-structure body argument.

Existing builder arch_index_cmt.ml:1053 accepts only function RHSs; existing
local-alias table at1140 intentionally keeps aliases out of the MUST/body-arity
table. The old verifier pins the original baseline and its task manifest, and
permits only module_param-to-same-file MAY_ENUMERATED transitions. A new attempt
needs explicit retained-state provenance and its own comparison setup; do not
overwrite old pinned evidence or silently broaden allowed changes.
