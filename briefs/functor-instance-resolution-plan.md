# Plan — functor-instance-resolution

**Date:** 2026-09-13
**Status: VALIDATED**

## Sequential steps

1. **Baseline and native red test** — capture manifest base/dirty state before
   baseline build/tests; use one existing worktree and explicit OCaml5.3 switch.
   Add the smallest owned native ordinary-application test that observes missing
   catalogue storage/query; show a genuine assertion failure after fixture setup
   succeeds. No product code before red. Exact contract is already specified.
2. **Ordinary application end-to-end** — introduce the main-schema catalogue,
   collector/data boundary and read-only query for the small native fixture.
   Include marker clearing, per-input atomic publication, drop/recreate and
   valid-empty/refusal behavior now. Preserve existing definitions/calls and
   process_cmt three-list result. The fixture must demonstrate producer-to-query
   plus a hand-authored query DB; no horizontal layer is considered delivered.
3. **Composition and failure slices** — extend the same end-to-end path to unit,
   nested/chained, constrained, anonymous, unnamed/local/opaque contexts; preserve
   preorder references and diagnostics. Add explicit typed-artifact probes for
   otherwise unavailable Papply/ghost/position premises. Exercise every input
   outcome, failed input with zero rows, reindex/interruption and consistency
   refusals including a corrupt row beyond the requested limit. Keep feature
   failures separate from existing graph publication.
4. **Independent checks and delivery documentation** — complete standalone Node
   assertion groups inventory/lifecycle/query/compatibility and wire them into
   deterministic tests. Validate all existing output formats and no DB writes.
   Document SQL/query/schema/reindex/limits and syntax-only boundaries. Attribute
   any self-index source-growth calibration; never weaken graph semantic gates.
5. **Full gates and sequential shipping** — full build before all tests, all four
   spec checks, bundle and scope hygiene, roster review then QA. Only after GO:
   PR, exact-head green CI, fixes/re-gates as required, rebase merge, local sync,
   private roadmap update and cleanup of this owned worktree/build. No next
   roadmap resolution slice before this PR lands.

Steps2–4 are internal TDD increments within one catalogue PR, not separately
shipped partial features. The full spec and every gate apply before shipping.

## Dependencies

Step1 precedes product work. Step2 establishes a testable vertical path and lifecycle
before step3 adds coverage. OCaml specialist handles native tests/probes and product
code first; non-OCaml specialist then completes independent scripts/docs. Root
integrates and owns serial builds/tests, manifest, phase ledger and gate handoffs.

## Identified risks

| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| Missed/doubled Typedtree child | medium | high | Default5.3 traversal boundary, independent native/probe census and reference checks. |
| Stale eligibility after failure | medium | high | Central clear/drop lifecycle, data commit before marker, interrupted-reindex test. |
| Catalogue mutates graph semantics | medium | high | Separate collection, preserved pending tuple/head types, fixed-fixture fact/verdict snapshot. |
| Inconsistent query hidden by limit | medium | high | Validate one complete read-only snapshot before applying limit or stdout. |
| Name/location mistaken for identity | medium | high | Exact artifact path plus preorder ordinal; collision and copied-path fixtures. |
| Self-index changes due to new source | high | medium | Attribute source growth via existing calibration; no semantic gate relaxation. |
| CWR/harness components absent | certain | low | No fabricated workflow/claims validation; manual roster dispatch, explicit skip log. |

## Decisions made

| Point | Decision | Reason |
|---|---|---|
| Initial integration | One ordinary application through producer/storage/query plus lifecycle | Exposes integration and completeness failures early. |
| Publication granularity | One completed catalogue PR | Prevents partial query/collection contract being shipped. |
| Occurrence model | Syntactic application only | Runtime, target and closed-world identities remain out of scope. |
| Persistence | Additive main schema with new producer-owned tables | Existing graph/schema entities stay unchanged; reindex owns migration. |
| Query | Read-only snapshot; usage first, whole-data validation before limit/output | Stable exits and no partial valid-looking report. |
| Dual-voice ordering disagreement | Vertical path chosen by operator under autonomy | Both voices agree scope and risk; no user-direction change. |

## Assumptions

No universal completeness or freshness claim. Stored counts check persistence,
not correctness of all compiler traversals. Exact private helper/table names are
implementation decisions constrained by the validated public spec. Existing opam
switch/tooling from READY preflight is used without installation. Schema version
must be reconfirmed at ship. No in-place old-DB migration or general concurrent
indexing redesign is assumed.

## Files authorized for implementation

- `architecture-schema.sql`
- `lib/arch_index/arch_index_functors.ml`, `lib/arch_index/arch_index_functors.mli` (new)
- `lib/arch_index/arch_index_cmt.ml`, `lib/arch_index/arch_index_cmt.mli`
- `lib/arch_index/arch_index.ml`, `lib/arch_index/arch_index_db.ml`
- `lib/arch_index/arch_index_support.ml`, `lib/arch_index/dune`
- `lib/arch_tools/arch_functor_catalogue.ml` (new), `lib/arch_tools/dune`
- `bin/arch_query/arch_query.ml`
- `tezt/tests/functor_catalogue.ml` (new), `tezt/tests/main.ml`, `tezt/tests/dune`
- `tezt/fixtures/functor_catalogue/` (new native/probe fixtures)
- `tezt/tests/callgraph_nested.ml`, `tezt/tests/schema_drop_list.ml`, `tezt/tests/completion_markers.ml`
- `scripts/check-functor-catalogue.js` (new)
- `README.md`, `docs/schema.md`, `docs/functor-catalogue.md` (new)
- `test/fixtures/self-index-stats.txt`, `tezt/tests/must_null_ceiling.ml` (only measured, attributed source-growth calibration if required)
- `test/fixtures/origin-consumer/reference.json`, `checks/origin-recurring-consumer.js`, `docs/origin-consumer.md` (only independently attributed source-population observation, matching exact-total assertion, and separate review rationale; no evaluator, policy, allowance or checker-semantics change)

Pipeline artifacts are added by the manifest lifecycle, not broad source prefixes.
No unrelated worktree, cost telemetry, CI bypass or held issue publication is in scope.

## Validation

Spec gate VALIDATED; two sequential fresh voices (Sol/Terra), consensus archived
in roster/functor-instance-resolution/plan-voices.md. Operator approves plan and
sub-briefs under standing explicit autonomy, not a fabricated quiz response.
No KB/claims/hook installation exists to run those conditional gates.
