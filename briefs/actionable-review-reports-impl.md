# Implementer — actionable-review-reports

**Date:** 2026-09-12
**Status: COMPLETED**
**Mode:** full

## Outcome

Implemented the complete approved report-usability slice. `arch-report` optionally evaluates the
same parsed rules as `arch-rules` against its open read-only database and carries declaration-order
results, actionability-ordered alerts, witnesses, uncertainty evidence, exactness, sizes and bounded
origin contexts through JSON, SARIF and HTML. Gate policy/renderers remain in `bin/arch_rules`;
only parsing/evaluation and the result vocabulary are shared.

Native OCaml CMT indexing now stores syntax-only original-slot-2 context for recognized integer
division/remainder primitives. The reader capability-checks old schemas, strictly rejects malformed
present metadata, preserves unsupported/NULL states as unavailable, and keeps site and context caps
independent. No value inference, current-source reread, allow-identity change, or detached JSON
binding was introduced.

## Main implementation

- Added `Arch_rule_eval` and `Arch_origin_context` public library interfaces.
- Added strict `arch-report --rules` parsing, pre-write rule validation, explicit non-atomic write
  failure behavior, evaluator attribution, census availability and honest CLI summary.
- Added declaration ordinals, complete-vs-alert order contracts, SARIF code flows/properties and
  complete escaped HTML evidence.
- Added schema 1.13 nullable `exn_origins.operand_*` fields and documented writer interface.
- Added typed-AST literal/identifier/other/missing classification, integer kind, 256-byte
  representation bound and unavailable reasons.
- Added a real four-mode standalone CLI checker wired into Tezt.

## TDD evidence

- Baseline after manifest: `dune build --root . @install` exit 0; `dune test --root . --force`
  exit 0 (231/231 Tezt plus Alcotest).
- A RED: focused `report.ml` exit 1 because supplied rules remained NOT_COMPUTED and no
  rule/witness appeared. A GREEN: focused report exit 0 (6/6).
- B RED: focused `exn_raise_sets.ml` exit 1 because `operand_category` was absent. B GREEN:
  extraction 2/2 and origin rules 8/8.
- Standalone checker initial real RED: rules mode exit 1 because its synthetic DB lacked required
  graph columns; subsequent fixture and contract defects were corrected. Final direct modes:
  rules 0, ordering 0, operands 0, compatibility 0. Tezt checker: 6/6 including assertion=1 and
  execution-error=2 controls.
- Final `dune build --root . @install` exit 0.
- Final `dune test --root . --force` exit 0: 240/240 Tezt plus Alcotest.
- Final focused report 6/6, origin 8/8, exception extraction 2/2, checker 6/6.
- Self-index produced the pinned 23 modules / 828 functions / 5223 calls and the golden diff
  exited 0. Self architecture rules exited 0. `recalibrate.sh --check` correctly refused exit 2
  before commit because the feature worktree was dirty; rerun after the implementation commit is
  required and recorded below.

## Review attention

- Structured contexts are joined only from exact offender/displayed row IDs selected by the
  Origin evaluator, queried in-scope and ordered by typed site/line/column/row-id keys.
- Metadata validation distinguishes SQL NULL from empty/non-NULL values, checks SQL types,
  vocabulary, completeness, representation/reason consistency and primitive/integer-kind pairs.
- The standalone checker uses repository-anchored built-tool defaults with absolute override
  support; fixture Dune runs only under its own temporary root.
- SARIF retains full rule properties separately from its native result projection; logical-only
  repeated witnesses retain order without fabricated physical locations.
- Existing opam metadata lint debt was not changed or represented as passing.

## Documentation

Updated README, CHANGELOG, schema, fitness-function, unified-report and integration documentation
for optional rule evaluation, ordering, availability/freshness limits, operand syntax evidence,
caps, provenance and publication failure semantics.

## Out of scope retained

No abstract-value inference, source freshness certificate, concurrent-writer support, persisted
rule runs, imported rule JSON binding, gate-policy change, general operand extraction, MCP change,
vendor harness change, push, PR or merge.

