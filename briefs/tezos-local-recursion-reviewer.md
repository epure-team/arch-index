# Reviewer — tezos-local-recursion

**Status: VALIDATED**

Expected implementation (not yet completed): private singleton local recursive
literal self-head refinement only in lib/arch_index/arch_index_cmt.ml, with native
tests/witness/checkers under task scope. Audit that file first, then native proof
and comparison. Full contract: specs/tezos-local-recursion.md.

Verify actual Ident/physical-root/stored correspondence, collision cardinality,
RHS scoping including nested/default/refutable contexts, no early ordinary table
seed, no new MUST/flat/non-head/API/schema drift. Check Some-count/arity/partiality,
single overapplication residual and independent non-reusable witness capacities.
Require actual SQL rejection and complete nonempty rich/flat preservation controls.
Fixed410 predecessor is frozen PR107:45052rows,digest9ab4e0b1…,4781/12046.
Every removed/additional canonical row must be accounted for, zero old relation
loss/new MUST/unexplained change. Native proof cannot use candidate target as oracle.

Personally run build/full Tezt/bundle/diff and CHECK1–6 per spec after final edits,
under main's serialized gate schedule; record actual commands/exits and findings.
No reported or prior-head gate substitutes for your run. No source edits without
coordinating ownership. Main manages same-round fixes, convergence and final QA.
Protected old checkers, heldPR93, Tezos and unrelated files remain untouched.
