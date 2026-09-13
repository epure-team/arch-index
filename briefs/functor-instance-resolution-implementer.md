# Implementer Brief — functor-instance-resolution

**Date:** 2026-09-13
**Status: VALIDATED**

Worktree: /home/mathias/dev/arch-index-worktrees/functor-instance-resolution.
All shell commands start with rtk; use explicit existing opam switch above for
compiler/build work. apply_patch owns edits. One shared worktree; do not create
another or run Dune concurrently. Preserve unrelated files and never stage cost.jsonl.
No third-party scans, issue publication, graph precision/Tezos gain or formal proof.

## Goal and scope


Continue roadmap item 7 with its first independently shippable increment: an
OCaml CMT functor-application catalogue, persisted in the main SQLite index and
inspectable through arch-query. Preserve application structure, named versus
anonymous versus unit arguments, nested application order, and source provenance
without pretending to identify runtime instances. This makes the currently
discarded composition facts visible and testable before parameter substitution.

This is slice 0 of bounded functor-instance resolution, not completion of that
roadmap item. Value is observable composition coverage and explicit limitations;
no call-graph precision improvement is claimed. Subsequent separately reviewed
slices may recover heads, substitute parameters under justified closure rules,
and handle instance-dependent exceptions. Standing user authorization covers
autonomous bounded increments, full roster gates, exact-head green PRs followed
by rebase merge, roadmap updates, and owned worktree cleanup.

## Scope Boundary

In scope: source-backed application occurrences from successfully decoded OCaml
implementation CMTs; ordinary and unit applications; nested/chained applications;
named, anonymous, constrained and unsupported expression shapes with explicit
diagnostics; binder-shadowing-safe occurrence identity; deterministic ordering;
main-schema persistence and rebuild lifecycle; a read-only `functor-applications`
query with documented output and explicit refusal when collection did not run;
native owned fixtures and complete documentation/verification for this slice.

What is explicitly OUT of scope:

- Reclassifying any call, specializing or cloning function definitions, replacing
  module-parameter TOPs, or changing exception/error/rule/reachability verdicts.
- Inferring a closed world from observed applications, function exposure, or
  absence of a row; runtime application counts and cross-build UID guarantees.
- Global 0CFA, first-class-module target inference, Shape-based target reduction,
  external functor-body recovery, or compiler/toolchain upgrades.
- New standalone executable, flat/LSP schema production, MCP/UI integration,
  or publishing the private issue draft (its explicit publication hold remains).
- Third-party vulnerability scans, exploit reproduction, Tezos benchmark gains,
  or any claim of whole-program/formal verification.
- Cleaning unrelated worktrees/files or publishing local cost telemetry.


## Contract and role boundary

Read full specs/functor-instance-resolution.md before implementation; all30FR,
16AC and4CHECK obligations apply. The spec, not a remembered summary, freezes
output fields, descriptor grammar, selected-input outcomes and refusal precedence.
The current process_cmt three-list return/head taxonomy and graph facts stay unchanged.
OCaml specialist implements native tests/probes, producer/schema and query; separate
non-OCaml specialist completes independent standalone checks/docs afterward.
Root owns manifest/ACTIVE_TASK, baseline, serial integration gates, phase artifacts
and commits. No specialist writes ledger/friction or ships. Capture genuine TDD red
before product code, using actual initialized fixture and assertions, not missing
binary/setup failures. Do not mark unsupported test premises passed.

## Plan, files, risks and assumptions


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

Pipeline artifacts are added by the manifest lifecycle, not broad source prefixes.
No unrelated worktree, cost telemetry, CI bypass or held issue publication is in scope.


## Exact quality gates

```bash
rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune build --root .
rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune test --root .
rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- node scripts/check-functor-catalogue.js inventory
rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- node scripts/check-functor-catalogue.js lifecycle
rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- node scripts/check-functor-catalogue.js query
rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- node scripts/check-functor-catalogue.js compatibility
rtk proxy node scripts/review-bundle-verify.js
rtk proxy git diff --check
```

Full build before tests. At baseline the four new scripts do not yet exist;
run existing build/tests/bundle/hygiene, not fictional script passes. At completion
all checks and full suite must pass. No configured standalone formatter/linter.
Scope gate and full roster review/QA follow. Report actual self-index calibration
and CI results; no source-growth pin changes without measured attribution.

