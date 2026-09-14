---
name: roster-spec
type: spec
status: live
feature: identity-backed local-module call targets and fixed410 comparison
brief: briefs/tezos-call-resolution-intake.md
date: 2026-09-14
version: 1.0.0
---

# Spec — Local-module call targets (iteration 1 of 5)

Scope is the validated intake. This spec does not promise general defunctorization or 0CFA. The five-attempt loop remains intact; this is its first focused candidate. Comparison setup is not a retained improvement.

## Clarifications

The eight resolved Q&A are recorded in [spec-input](../roster/tezos-call-resolution/spec-input.md) and [adversarial resolutions](../roster/tezos-call-resolution/spec-resolutions.md). In particular, structural traversal alone is not module ownership, and SQL counts are not a semantic oracle.

Review round1 clarification of C-5/FR-007: Typedtree application slots containing
`None` are absent arguments, not supplied expressions. For newly known local
structure bodies, saturation/residual accounting counts `Some` expressions.
Compiler-inserted default expressions inside `Some` still count. Given a body
`f ~a ~b` returning a function and `f ~b:1 2`, the head remains partial and no
computed-return residual is introduced merely by the absent `~a` slot. The fully
supplied `f ~a:3 ~b:1 2` retains its residual. Existing non-owned head and CFG
classification are outside this focused correction. This clarifies the existing
obligation; it does not waive the discovered failure or change resolution scope.

## User Stories

### US-1: Follow known local-module calls (P0)

As an arch-index consumer inspecting Irmin or protocol call chains, I want calls through actual local structured modules to reach their indexed function bodies without mistaking a caller-supplied module for one.

Why P0: measured TOP rows already have candidate bodies in the fixed corpus. Scope excludes module-alias chasing, functor instantiation and general value flow. Independent test: a native compiled fixture queries exact caller/target identities and edge kinds.

1. Given `module Local = struct let f x = x end`, when a function calls `Local.f`, then the rich graph links that exact stored body as MAY_ENUMERATED.
2. Given nested/renamed-shadowed structured module binders and same-named value bindings, when calls use their typed paths, then each reaches its own final exported body using its actual stored ordinal-qualified name, never a sibling or earlier shadowed member.
3. Given a functor parameter named Local, its alias, an application result or an unpacked module, when its member is called, then existing TOP/refusal behavior remains even if a real Local.f exists elsewhere.
4. Given a later nonfunction binding or opaque include masking f, when M.f is called, then the previous body is not selected. Literal structure inclusion is eligible only with actual member identity.
5. Given an eligible member used as an applied head, let operator, callback argument or point-free RHS, when indexed, then the corresponding existing emission is resolved without losing metadata; only point-free rows retain value_alias and remain excluded from call counts.
6. Given a target row rejected by the storage layer, when its caller is emitted, then it remains TOP/dropped_node, never an enumerated external leaf.

### US-2: Compare real-corpus resolution changes (P0)

As the maintainer deciding whether to retain an iteration, I want a replayable fixed410 relation/multiset comparison with concrete changed-target witnesses, so a diagnostic gain or dropped call cannot masquerade as improved resolution.

Why P0: existing aggregate scripts delete detailed DBs. Scope excludes new general benchmark product/CLI. Independent test: self-comparison and deliberately changed fixture snapshots exercise a standalone comparator.

1. Given two snapshots of the same binary and unchanged 410 CMT hashes, when compared, then zero gains/losses/movements are reported despite duplicate same-line calls.
2. Given a candidate with additional exact internal relations and unchanged existing targets/sites/multiplicities, when compared, then gains are enumerated separately for Irmin and protocol, excluding value_alias rows only.
3. Given a missing artifact, changed hash, incomplete collection, missing DB/table, missing caller/target, lost existing target, unexplained TOP loss or new MUST promotion, when verified, then the run refuses with a nonzero exit and does not report a keep.
4. Given two same-line rows with different kinds, when compared against reordered identical rows, then no phantom kind movement is reported. Swapping targets or removing one duplicate must be detected.
5. Given a neutral diagnostic-only change, when measured, then it does not count as a retained iteration. Given genuine gain and passing native/full/roster/CI guards, retain and merge before the next improvement attempt.

## Challenges

Eight challenges (C-1–C-8) were raised by a fresh Sol pass and resolved before this spec. Their per-story observable resolutions are in [spec-resolutions](../roster/tezos-call-resolution/spec-resolutions.md). C-1–C-6 govern US-1; C-7/C-8 govern US-2. No unsupported compiler-interface/version or name-identity assumption is accepted.

## Functional Requirements

- **FR-001** [US-1]: The producer MUST establish local-module roots by compiler binding identity within one CMT, never printed-name or cross-CMT/global-stamp coincidence.
- **FR-002** [US-1]: Every member hop MUST belong to a proven concrete structure; an alias, parameter, functor/application result, unpack or unproven hop MUST refuse the whole candidate.
- **FR-003** [US-1]: Exports MUST follow source order. Every name introduced by a value pattern MUST mask a prior same-name export; only a plain-variable Texp_function binding may install an eligible body.
- **FR-004** [US-1]: Targets MUST use their existing binding_name, including #N suffixes; a later nonbody or unsupported binding MUST NOT expose an earlier body's identity.
- **FR-005** [US-1]: A literal Tmod_structure through zero or more Tmod_constraint wrappers MUST retain its actual member ownership. Literal includes MUST preserve their actual final members; opaque includes MUST mask value/module names from incl_type until a later explicit declaration replaces them.
- **FR-006** [US-1]: Direct structures in recursive declarations and functor bodies MUST use their own proven identities without chasing recursive references, argument substitution or instance expansion. An unproven intermediate path MUST refuse.
- **FR-007** [US-1]: Eligible bodies MUST follow existing is_function_rhs and fn_arity. exp_extra constraints MUST NOT erase them. Underapplication MUST remain partial; overapplication MUST retain or add its computed-return TOP residual.
- **FR-008** [US-1]: Newly resolved call heads MUST be MAY_ENUMERATED with null TOP fields, never newly MUST. Caller, location, CFG cond/dead, scope links, channel classification, site form and unrelated rows MUST survive; storage-rejected targets MUST remain TOP/dropped_node.
- **FR-009** [US-1]: Point-free edges MUST preserve value_alias and their ordinary-head/kind-matrix contract and MUST NOT count as call-target gains. Ordinary local-module calls MUST NOT be mislabeled module_alias.
- **FR-010** [US-1]: Both collector paths MUST receive equivalent per-CMT identity input. Flat fallback MUST retain current caller naming/coverage and MUST NOT attribute a newly proven local target to a same-named row in another file; absent same-file row MUST remain unattributed.
- **FR-011** [US-2]: The primary metric MUST be distinct caller-path/name, call_site, target-path/name tuples excluding value_alias only. Canonical row multisets MUST also retain callee display, kind, edge_form, top_reason and top_anchor, including nulls.
- **FR-012** [US-2]: Comparison MUST preserve multiplicities: identical row reordering is neutral; duplicate deletion, target swaps and differing-kind changes MUST be detected. Added copies of an existing relation MUST NOT increase the metric.
- **FR-013** [US-2]: Reports MUST partition Irmin/protocol and retain complete old/new changed groups and source/target positions. They MUST NOT describe relation counts as syntactic-call counts or semantic-correctness certificates.
- **FR-014** [US-2]: Missing/changed/incomplete inputs, missing DB/table/caller/target, existing-target loss, unrelated TOP/refusal loss, new MUST or unclassifiable changed groups MUST refuse verification. Only the supported same-file module_param-to-body transition and separately witnessed return residuals are permitted in iteration 1.
- **FR-015** [US-2]: Retention MUST require positive permitted relation gain plus native identity/refusal checks, full guards and independent roster review/QA/exact-head CI. Diagnostics or model consensus alone MUST NOT authorize keep; retained iterations MUST merge before the next attempt.

## Acceptance Criteria

- AC-1 [US-1 happy path]: Local.f applied call reaches its exact same-file body as MAY_ENUMERATED.
- AC-2 [US-1, C-1/C-4]: Nested and cross-CMT homonymous roots and multi-hop structures select only the actual owner; unproven hops refuse.
- AC-3 [US-1, C-2]: Value/module shadowing uses actual #N target identities; pattern/nonbody masking never reveals an earlier body.
- AC-4 [US-1, C-3]: Literal include/constraint ownership, opaque include masks, and later replacement obey source order.
- AC-5 [US-1, C-4]: Parameters, aliases, applications and unpack refuse despite decoys; direct functor-local structures use definition-only targets.
- AC-6 [US-1, C-5]: Applied and under/overapplied heads respect syntactic body/arity and preserve return TOP.
- AC-7 [US-1, C-6]: Applied/let-operator/callback/point-free rows retain relevant metadata/forms; rejected targets remain dropped_node TOP.
- AC-8 [US-1, C-6]: Flat fallback handles proven same-file targets without cross-file name capture or fictitious coverage.
- AC-9 [US-2 happy path/C-7]: Same-binary replay and reordered duplicate rows report zero change; deletion/swap/kind mutations fail the appropriate assertions.
- AC-10 [US-2, C-8]: Fixed410 verifies hashes/completeness and enumerates permitted gains by slice with full old/new groups; malformed/incomplete/unsupported changes refuse.
- AC-11 [US-2, C-8]: Only positive product gain plus all gates qualifies for keep; neutral instrumentation is excluded and each retained PR merges sequentially.
- AC-12 [US-1, C-5, review round1]: A native omitted-label partial call retains its partial owned head without an invented return residual; its fully supplied overapplication control retains the residual.
- AC-13 [US-2, C-8, review round1]: Isolated malformed/missing provenance, input, collection and witness cases exercise the actual refusal functions and cannot produce a successful keep result; real Tezos inputs remain untouched.
- AC-14 [US-2, FR-015, review round2]: The current built producer's self-index module/function/call counts match the committed smoke golden byte-for-byte under the exact CI query; stale expectations fail locally, with no threshold or automatic refresh.

## Edge Cases

- EC-1 [US-1]: same printed module/member name in another scope/artifact → never establishes identity.
- EC-2 [US-1]: later pattern, alias or computed-function export → masks earlier eligible body.
- EC-3 [US-1]: include with unavailable member bodies → exported names masked; a later direct declaration may replace the mask.
- EC-4 [US-1]: recursive/alias/application/extra-type or otherwise unproven hop → whole candidate refused; no suffix fallback.
- EC-5 [US-1]: returned function applied beyond the known body's arity → return TOP remains, independent of the body edge.
- EC-6 [US-1]: storage rejection or flat same-file target absent → no false enumerated external/cross-file attribution.
- EC-7 [US-2]: duplicate same-line rows → multiset comparison, not pairwise cross-product; indistinguishable-row permutations make no stronger claim.
- EC-8 [US-2]: changed/missing corpus, absent semantic witness class, or diagnostic-only movement → no keep.

## Runnable Checks

Commands below are implementation deliverables, not a claim they already exist or have passed. Build the exact checkout before native checks. Standalone check convention: 0=pass, 1=assertion/forbidden transition, >=2=setup/parse/tool error. No test-runner exit code is relabeled as assertion evidence without an actual parsed assertion.

- CHECK-1 [AC-1, AC-2, AC-3, AC-4, AC-5, AC-6, AC-7, AC-8]: `node roster/tezos-call-resolution/check-native.js` → native compiled identity/arity/refusal/storage/fallback assertions pass. Exercise real producer boundaries, not a stub resolver.
- CHECK-2 [AC-9, AC-10]: `node roster/tezos-call-resolution/check-comparison.js` → standalone fixture comparison tests, including zero/partial/missing/wrong-shape inputs, duplicated-line reordering, target/kind changes and deletions.
- CHECK-3 [AC-9, AC-10, AC-11]: `node roster/tezos-call-resolution/verify.js --baseline /tmp/arch-index-resolution-baseline-OmhcEs/baseline.db --witness improvement/2026-09-14-tezos-resolution/attempt1-reviewed-witness.json` → hash-locked fixed410 producer run, per-group relation/multiset comparison and report. The exact witness is generated from independently reviewed compiler evidence as documented in roster/tezos-call-resolution/uid-witness-report.md; missing evidence refuses. Baseline self-comparison uses `--self` without `--witness`. Actual keep additionally requires positive permitted gain and the full pipeline.
- CHECK-4 [AC-12] (authentic-success-path, fail-closed-path): `node roster/tezos-call-resolution/check-labeled-arity.js` → self-contained native compiler/collector regression verifies supplied slots, partial head metadata and exact return-residual counts; 1 is an assertion failure, >=2 a setup error. Introduced on the round1 NO-GO bounce and must be observed red before the product fix.
- CHECK-5 [AC-13] (fail-closed-path): `node roster/tezos-call-resolution/check-verifier-inputs.js` → isolated negative tests of provenance, input hashes, collection completeness and exact witness binding, with no writes to Tezos or retained baseline. Positive controls prevent vacuous refusal tests.
- CHECK-6 [AC-14] (authentic-success-path): `node roster/tezos-call-resolution/check-self-index-smoke.js` → index the current built library into an owned temporary DB, execute the exact CI SQLite stats query and compare the committed golden byte-for-byte. Exit1 requires an actual mismatch after successful production/query; setup errors exit>=2. The checker never rewrites the golden and cleans only its own temporary DB.

Full guard: `opam exec --switch=/home/mathias/dev/arch-index -- dune build --root .`, then `opam exec --switch=/home/mathias/dev/arch-index -- dune runtest --root . --force`, bundle verification and whitespace check. Exact report filenames, self-comparison mode, cleanup ownership and machine provenance binding are fixed by the implementation plan before checker construction. Verify MUST refuse a baseline lacking its matching recorded producer/corpus provenance; a naked DB path does not establish comparability.

## Claims Metadata

```claims
{"record":"claims-header","schema_version":1,"namespace":"tezos-call-resolution","spec_lifecycle":"draft"}
{"record":"requirement","id":"FR-001","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-002","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-003","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-004","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-005","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-006","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-007","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-008","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-009","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-010","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-011","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-012","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-013","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-014","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-015","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"acceptance-criterion","id":"AC-1","for":["FR-001","FR-002","FR-008"]}
{"record":"acceptance-criterion","id":"AC-2","for":["FR-001","FR-002","FR-006"]}
{"record":"acceptance-criterion","id":"AC-3","for":["FR-003","FR-004"]}
{"record":"acceptance-criterion","id":"AC-4","for":["FR-003","FR-005"]}
{"record":"acceptance-criterion","id":"AC-5","for":["FR-002","FR-006"]}
{"record":"acceptance-criterion","id":"AC-6","for":["FR-007","FR-008"]}
{"record":"acceptance-criterion","id":"AC-7","for":["FR-008","FR-009"]}
{"record":"acceptance-criterion","id":"AC-8","for":["FR-010"]}
{"record":"acceptance-criterion","id":"AC-9","for":["FR-011","FR-012"]}
{"record":"acceptance-criterion","id":"AC-10","for":["FR-013","FR-014"]}
{"record":"acceptance-criterion","id":"AC-11","for":["FR-015"]}
{"record":"acceptance-criterion","id":"AC-12","for":["FR-007","FR-008"]}
{"record":"acceptance-criterion","id":"AC-13","for":["FR-014"]}
{"record":"acceptance-criterion","id":"AC-14","for":["FR-015"]}
{"record":"check","id":"CHECK-1","for":["AC-1","AC-2","AC-3","AC-4","AC-5","AC-6","AC-7","AC-8"]}
{"record":"check","id":"CHECK-2","for":["AC-9","AC-10"]}
{"record":"check","id":"CHECK-3","for":["AC-9","AC-10","AC-11"]}
{"record":"check","id":"CHECK-4","for":["AC-12"]}
{"record":"check","id":"CHECK-5","for":["AC-13"]}
{"record":"check","id":"CHECK-6","for":["AC-14"]}
```

Claims stay draft metadata: canonical claims validation/projection tooling is not installed. No projection success is claimed.

## Entities

- `LocalStructureTarget`: an existing function-body definition selected through same-CMT structured-module binder ownership, not a runtime instance.
- `ResolutionRelation`: one canonical caller/source-line/internal-target tuple; not a unique syntactic expression.
- `ResolutionRowMultiset`: canonical stored call facts with multiplicity, excluding database surrogate IDs from identity.
