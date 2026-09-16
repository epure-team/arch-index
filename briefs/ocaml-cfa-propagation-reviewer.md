# Reviewer Brief — ocaml-cfa-propagation

**Status: VALIDATED**

## Audit objective

Independently verify that the implementation satisfies
`specs/ocaml-cfa-propagation.md` without widening the supported OCaml subset or
weakening Stage-2 soundness/frontier behavior.

## Audit first

1. `arch_index_cfa.ml`: finite monotone activation, no solve-time cell/identity
   allocation, late-target scheduling and order independence.
2. `arch_index_cfa_cmt.ml`: every mutator guard, finalization atomicity, exact
   reason mapping, declaration/occurrence/residual identity and shared dispatcher.
3. Both producer integrations: direct-edge precedence, main/flat parity,
   occurrence metadata and TOP preservation.
4. Tests/checkers: independent oracle, authentic compiled controls, non-vacuous
   assertions, exact exit contracts and pinned corpus provenance.

## Required findings questions

- Can any supported call miss constraints because its operator target arrives late?
- Can any recursive/partial path allocate an unbounded identity or mutate after finalize?
- Can a known target erase callback/dropped-node uncertainty?
- Can context-insensitive merging be mistaken for `MUST` or per-site precision?
- Can an unsupported label/pattern/capture/result become bounded by name/location?
- Can direct and CFA paths emit duplicate or conflicting call rows?
- Can equal source locations collapse physical application stages?
- Did any foundation canonical row, flat tuple, consumer verdict or pinned relation regress?
- Did Stage-4 functor or storage work enter the diff?

## Gates

Run all implementer gates from a clean diff scope. A review is GO only with zero
unresolved findings, non-vacuous CHECK-1/2, exact CHECK-3 zero-loss/no-new-MUST,
and preserved foreign files.
