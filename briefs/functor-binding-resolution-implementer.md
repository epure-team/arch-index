# Implementer — functor-binding-resolution

**Date:** 2026-09-13

## Authorized calibration amendment (2026-09-13)

User explicitly approved attribution-gated reference recalibration after the
first native checkpoint. Headroom remains25; graph semantics and allowances
remain unchanged. Extend this task's scope solely to measured reference updates:
tezt/tests/must_null_ceiling.ml (clean_measured and attribution comment only),
test/fixtures/self-index-stats.txt, test/fixtures/origin-consumer/reference.json,
and checks/origin-recurring-consumer.js (authentic frozen totals only).
Require fresh symmetric2x2 engine/corpus measurements; refuse behavioral drift.
No revision is invented for uncommitted product sources: record base+snapshot
content digest. Original script requires clean commits, so use documented
fresh disposable snapshots, not incremental builds or a fake script pass.
**Status: VALIDATED**

## Goal and Scope Boundary

Same OCaml5.3 Implementation CMT named functor formal-to-actual provenance only.
Support local Pident heads, constraint-peeled local identity alias chains and consecutive
literal functor result telescopes for F(A)(B). One result per existing collected
catalogue occurrence, matched formal or explicit refusal. No fabricated ordinals
for failed catalogue inputs. Actual descriptors stay byte-identical; root keys
are symbolic artifact-local identity. No cross-build stability promise.
Do not change calls, catalogue output, MAY_TOP, exception/alias consumer semantics,
flat schema, Tezos source, held private issue draft or PR93. No cross-unit,
Pdot/Papply/Pextra_ty head resolution, inline head support, application-valued
binder evaluation, actual substitution, 0CFA, closure or target-resolution claims.
No additional calibration allowance is authorized.

## Required contract

Read briefs/functor-binding-resolution-intake.md and specs/functor-binding-resolution.md
fully. Implement26FR and12AC with4plain Node check families. Closed grammar, nine
refusal reasons, error precedence and projection must not be reinterpreted.
Spec validation does not claim current tests pass.

## Files

- architecture-schema.sql
- lib/arch_index/arch_index_db.ml (verified main schema version owner)
- docs/schema.md (matching schema history)
- lib/arch_index/arch_index_functors.ml
- lib/arch_index/arch_index_functors.mli
- lib/arch_index/arch_index.ml
- lib/arch_index/arch_index_support.ml
- lib/arch_index/arch_index_bindings.ml (new collector/persistence integration as needed)
- lib/arch_index/arch_index_bindings.mli (new)
- lib/arch_index/dune (only required module wiring)
- lib/arch_tools/arch_functor_catalogue.ml (minimal validation reuse, preserve old API)
- lib/arch_tools/arch_functor_catalogue.mli (only needed reusable interface)
- lib/arch_tools/arch_functor_bindings.ml (new)
- lib/arch_tools/arch_functor_bindings.mli (new)
- lib/arch_tools/dune (only required module wiring)
- bin/arch_query/ (CLI dispatch and its build wiring only; verify actual path before edits)
- tezt/tests/functor_bindings.ml (new)
- tezt/tests/functor_catalogue.ml (compatibility controls only)
- tezt/tests/main.ml (test registration)
- tezt/tests/dune (test wiring)
- scripts/check-functor-bindings.js (new)
- README.md (public command documentation)
- specs/functor-binding-resolution.md (evidence/status corrections only)
- briefs/ and roster/functor-binding-resolution/ (pipeline and bounded benchmark evidence)
- skills-meta/friction.jsonl

Relevant anchors supplied by intake: existing collector uses Path.name/Tmod_apply
(display only); CMT identity lookup uses Ident.unique_name; schema catalogue PK
links occurrences; query catalogue uses snapshot/fullvalidation beforelimit.
Verify exact CLI path and schema/module wiring before editing; if not in manifest,
amend the brief/manifest explicitly, never silently widen scope.

## Sequential steps

1. **Direct native binding end to end.** Capture manifest/base before baseline tests.
   Add genuine failing native single-functor/application expectation and plain Node
   wrapper with pass0/assertion1/infrastructure>=2. Implement the minimal path through
   additive tables, identity-aware collection, isolated persistence and basic read-only
   query. Check original catalogue/graph facts in the same checkpoint. Frozen output
   grammar applies immediately; no temporary public schema. Checkpoint ends green.
2. **Alias and curried provenance end to end.** Expand the same path with pre-indexed
   named module/recmodule/local-expression binders across nested/deferred contexts,
   identity-based local aliases, consecutive literal formal telescopes and one
   accounted result per occurrence. Add shadowing, anonymous/unit, curried position,
   nested-head reference, actual descriptor/root and every refusal test alongside.
   Unsupported native-source shapes require explicitly premise-checked synthetics;
   never claim they prove source-valid behavior.
3. **Complete lifecycle and trustworthy query.** Add zero-application accounting,
   independent marker eligibility and real partial-storage failures, including
   failure recording and uncertain rollback. Complete whole-database validation
   before limit0/output, strict CLI errors and all six independent renderer oracles.
   Existing catalogue and graph must survive binding failure. All four check
   families are executable and green by this checkpoint.
4. **Verify, measure and land one product PR.** Full gates, fresh digest-verified
   exact410-CMT observation with matched-formal/refusal/failed-input counts, and
   documented limitations. Roster review then QA, fix any gate failures within
   pipeline rules; check schema slot, open PR, wait for exact-head green CI,
   rebase merge, refresh local main and roadmap. Remove only the exact owned
   now-unused worktree/build artifacts after verifying preservation of changes.

## Quality Gates

```sh
rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune build --root .
rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune test --root . --force
rtk proxy node scripts/check-functor-bindings.js inventory
rtk proxy node scripts/check-functor-bindings.js lifecycle
rtk proxy node scripts/check-functor-bindings.js query
rtk proxy node scripts/check-functor-bindings.js compatibility
rtk proxy node scripts/review-bundle-verify.js
rtk proxy git diff --check
```

## Risks and execution constraints

Capture base/dirty manifest before baseline builds/tests. Preserve user untracked
files; one owned worktree, root-only Dune. TDD is mandatory because tests are specified.
The OCaml specialist profile is absent locally: use an explicitly briefed OCaml-capable
Sol/Terra subagent as fallback, not a claimed installed specialist. Mixed scope:
OCaml first, then script/docs implementation. Delegate bounded disjoint edits only.
No statement of completion until full gates pass; commit round before review.
High risks: ordinal drift, shadowed Ident joins, curried off-by-one, partial marker,
wholevalidation limit bypass, invalid synthetic premises and overclaimed benchmark.
No unrelated refactors or calibration relaxations. Claims/KB/hooks unavailable,
so manual pipeline with actual evidence, not simulated managed validation.
