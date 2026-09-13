# Reviewer — functor-binding-resolution

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

## Intended change (not a claim of completed implementation)

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

## Audit priority

Read the implementation brief and diff, then frozen spec26FR/12AC. Audit collector
identity/ordinal correspondence and constraint peeling first, then schema/input counts,
savepoint rollback/marker clearing and independent catalogue behavior, then whole-query
validation/format/error boundaries. Audit new tests for real RED evidence, native
success, premise-checked synthetic negatives, six independent byte oracles and
0/1/>=2 wrapper distinction. No implementation is currently claimed.

## Files to audit

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

## Expected behaviors and risks

F(A)(B) binds different formal positions of one local declaration without evaluating
actual contents. Every existing collected occurrence gets match/refusal, zero inputs
are accounted, failed collection never fabricates occurrence IDs. Identity collisions,
alias cycles and unsupported shapes never guess. Failed binding persistence cannot
invalidate old catalogue/graph or earn binding completion. Query validates beyondlimit0.
Same410 observations are matched-formal/refusal counts only, never resolvedtargets.

## Gates and handoff

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

Run roster-review with actual independent specialist/tool evidence, convergence and
scope checks. Do not invent second-runtime approval when unavailable. Emit GO only
after contract coverage and fixes are verified; QA follows before ship.
