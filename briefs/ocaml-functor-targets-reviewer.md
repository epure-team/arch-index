# Reviewer Brief — ocaml-functor-targets

**Status: VALIDATED**

## Expected Change

The implementation should add a bounded main-CMT functor formal-to-actual member
correspondence, durable positive provenance witnesses, safe exact-copy/nonidentical
variant handling, authentic checks and pinned410 attribution. It must retain the
open-world TOP frontier and must not change flat/LSP inference.

## Audit First

1. `architecture-schema.sql`: witness keys, foreign/exact-key chain, lifecycle marker,
   uniqueness, partial-input behavior and indexes.
2. `lib/arch_index/arch_index_bindings.ml`: no weakened identity/refusal premises and no
   cross-artifact use of `Ident.unique_name`.
3. `lib/arch_index/arch_index_cmt.ml`: physical occurrence identity, formal-member match,
   direct/one-hop export semantics, TOP retention and proof-before-drop variant path.
4. `lib/arch_index/arch_index.ml`: unique representative reconciliation, target kind,
   transaction/finalizer behavior, relation vs witness deduplication.
5. New Tezt fixtures and `roster/ocaml-functor-targets/check-*.js`: authentic path,
   mutation/negative controls, exit classification and non-vacuous pinned attribution.

## Required Review Findings

- Verify every positive relation is backed by a complete artifact-local proof and no
  display-name/source/basename-only join exists.
- Verify multiple applications/curried positions cannot cross declarations or slots.
- Verify missing/opaque/unsupported cases leave one TOP and add no target/extra TOP.
- Verify target rows stay `MAY_ENUMERATED` through persistence/queries and no singleton
  normalization promotes to `MUST`.
- Verify equal-location occurrences and variant reconciliation refuse ambiguity.
- Verify exact-copy graph sharing does not borrow compiler identities or erase artifact
  witness provenance.
- Verify nonidentical variants add only call/witness facts to existing nodes and never
  merge or create other graph entities.
- Verify flat/LSP behavior is unchanged and no CMT-equivalent claim is made.
- Verify CHECK-3 compares a frozen Stage-3 baseline, not merely the older Stage-1
  baseline; every gain is witnessed, every loss/new MUST fails, and missing corpus is 2+.
- Verify docs state no whole-program guarantee, no completeness guarantee and no
  performance bound.

## Expected Behaviors

- Direct, repeated, curried, nested/include and one-hop fixtures resolve exactly the
  intended actual members plus retained TOP.
- Persistent/Papply/anonymous/unpack/module-alias/opaque/ambiguous cases fail closed.
- Reordered input produces byte-equivalent canonical rows and witness serialization.
- At least one Irmin-or-protocol candidate-only relation is new and exactly attributed;
  both slice counts are reported and no old relation is lost.

## Gates to Re-run

Run every command from `briefs/ocaml-functor-targets-qa-scope.md`. Treat any skipped,
degraded, partial-success or corpus-unavailable result as non-GO unless explicitly out
of validated scope. Inspect the actual report JSON and relation/witness sets, not only
the process exit status.
