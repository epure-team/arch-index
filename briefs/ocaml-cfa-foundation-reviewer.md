# Reviewer — ocaml-cfa-foundation

**Date:** 2026-09-16
**Status: VALIDATED**

Expected change, not implementation claim: finite function-target inclusion
kernel wired through one CMT batch to main/flat authentic call targets. Review
the actual diff and all44 normative requirements in specs/ocaml-cfa-foundation.md.

Audit first: private CFA/CMT modules, arch_index_cmt.ml/.mli, flat fallback,
native fixtures and standalone independent checks. Main risks: wrong physical/
binder identity, unobserved lambda treated bounded, outer-local capture leakage,
known+unknown absorption, premature per-function solving, arity/residual loss,
same-line occurrence merging, scope/channel corruption, false flat homonym target.
Confirm original static calls and immediate predecessor value_alias semantics.
No numeric guard behavior/API changes or stage3/4 scope expansion.

Require actual RED proof and full GREEN gates, independent domain oracle,
authentic main/flat/query assertions and frozen Tezos delta accounting. Counts
alone do not establish correctness. Review may not approve an absent test,
unexplained relation loss, unqualified incomplete corpus or weakened golden policy.
Use standard Roster review tooling/trace/convergence gates; do not invent results.
Source-growth changes outside scope require explicit authority, not retroactive
manifest widening. Independent QA follows GO; root owns PR/exact-head green merge.
