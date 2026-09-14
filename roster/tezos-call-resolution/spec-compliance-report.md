---
auditor: spec-compliance-auditor
date: 2026-09-14
status: 1 critical, 1 warning, 0 info
coverage: 13/15 functional requirements verified (87%)
verdict: NO-GO
---

# Spec compliance — tezos-call-resolution, round 1 cycle 1

Embedded-mode path adaptation: the skill's default `kb/reports/` destination is replaced by this task-owned `roster/tezos-call-resolution/` path because that is the authorized write scope.

## Compliance Matrix

| Claim | Status | Location | Test/evidence | Notes |
|---|---|---|---|---|
| FR-001 / AC-1, AC-2 | PASS | `lib/arch_index/arch_index_cmt.ml:997` | `tezt/tests/local_module_targets.ml:120` | Roots are keyed by per-CMT compiler `Ident`; same-name cross-CMT fixture passes. |
| FR-002 / AC-2, AC-5 | PASS | `lib/arch_index/arch_index_cmt.ml:1023` | `tezt/tests/local_module_targets.ml:185` | Alias, parameter, application and unpack owners refuse; every `Pdot` hop must have concrete exports. |
| FR-003 / AC-3, AC-4 | PASS | `lib/arch_index/arch_index_cmt.ml:1040` | `tezt/tests/local_module_targets.ml:177` | Source-order fold masks all pattern-bound names before optionally installing a direct function body. |
| FR-004 / AC-3 | PASS | `lib/arch_index/arch_index_cmt.ml:1053` | `tezt/tests/local_module_targets.ml:191` | Stored binding names, including the earlier `#1`, are retained; unsupported later exports mask. |
| FR-005 / AC-4 | PASS | `lib/arch_index/arch_index_cmt.ml:1025` | `tezt/tests/local_module_targets.ml:177` | Constraints and literal includes preserve proven exports; opaque include signature names install masks. |
| FR-006 / AC-2, AC-5 | PASS | `lib/arch_index/arch_index_cmt.ml:1027` | `tezt/tests/local_module_targets.ml:181` | Recursive and functor-body direct structures are discovered without making functors/applications owners. |
| FR-007 / AC-6 | DIVERGE | `lib/arch_index/arch_index_cmt.ml:2150` | Independent labeled-argument CMT reproducer; existing test only at `tezt/tests/local_module_targets.ml:195` | Omitted labeled slots are counted as supplied arguments for residual creation, producing a spurious computed-return TOP. |
| FR-008 / AC-1, AC-6, AC-7 | PASS | `lib/arch_index/arch_index_cmt.ml:2221` | `tezt/tests/local_module_targets.ml:169`, `:195`, `:197`, `:224` | Proven heads are enumerated, not MUST; dropped bodies remain TOP and conditional/dead facts survive. |
| FR-009 / AC-7 | PASS | `lib/arch_index/arch_index_cmt.ml:1574` | `tezt/tests/local_module_targets.ml:193`; `roster/tezos-call-resolution/check-comparison.js:59` | Point-free rows retain `value_alias`; ordinary local-module heads have no `module_alias`; metric excludes aliases. |
| FR-010 / AC-8 | PASS | `lib/arch_index/call_graph_extractor.ml:275` | `tezt/tests/local_module_targets.ml:238` | Both collection paths build the same context; flat attribution is constrained to an actual same-file symbol. |
| FR-011 / AC-9 | PASS | `roster/tezos-call-resolution/comparison.js:4` | `roster/tezos-call-resolution/check-comparison.js:27` | Relation key and canonical multiset retain the specified identity and nullable diagnostic fields. |
| FR-012 / AC-9 | PASS | `roster/tezos-call-resolution/comparison.js:73` | `roster/tezos-call-resolution/check-comparison.js:30` | Bag subtraction preserves multiplicity; mutation checks cover reorder, duplicate deletion, target swap and kind change. |
| FR-013 / AC-10 | PASS | `roster/tezos-call-resolution/verify.js:71` | CHECK-3 run, exit 0 | Changed groups retain positioned old/new rows and gains are partitioned Irmin/protocol; report calls them relations. |
| FR-014 / AC-10 | UNTESTED | `roster/tezos-call-resolution/verify.js:36` | Partial coverage at `roster/tezos-call-resolution/check-comparison.js:116`; positive CHECK-3 run | Code contains fail-closed checks, but no executable negative test covers changed/missing manifest, 0/409 collection, invalid run markers/run set, or wrong witness digest. |
| FR-015 / AC-11 | PASS | `roster/tezos-call-resolution/verify.js:170` | CHECK-3 and self runs | Reports always leave `retention_authorized:false`; positive gains alone do not authorize keep. Current NO-GO therefore blocks retention. |

## Critical

### [C1] Omitted labeled argument slot fabricates a computed-return TOP

- **Spec claim:** FR-007 / AC-6 — underapplication must remain partial and only actual overapplication may retain or add the computed-return TOP residual.
- **Actual behavior:** `Texp_apply` sets `nargs = List.length args` at `lib/arch_index/arch_index_cmt.ml:2150`; Typedtree includes `None` entries for omitted labeled slots. The residual branch then uses `nargs > head_arity` at `lib/arch_index/arch_index_cmt.ml:2267`.
- **Independent reproduction:** for `module M = struct let f ~a ~b = ... end; let partial () = M.f ~b:1 2`, compiler evidence reports `supplied=2`, `slots=3`, body arity `2`. With local-module context disabled the collector emits one partial `M.f` TOP; with context enabled it emits the expected partial enumerated `M.f` **and an additional** `*TOP*/callback_param`. Thus enabling this feature introduces a TOP even though supplied arguments do not exceed the known body arity. The fully labeled call has `supplied=3`, so its residual remains legitimate.
- **Coverage gap:** the native fixture checks only positional `Arity.add a` and `Arity.make a b`; its assertion at `tezt/tests/local_module_targets.ml:195` proves a positive overapplication but has no omitted labeled/optional slot case. Consequently CHECK-1 and the 324/324 suite pass while the contract is violated.
- **Severity:** CRITICAL per the skill: implemented behavior directly contradicts FR-007. This is not downgraded by +400 Irmin/+395 protocol gains, 831 reviewed replacements, or 34 witnessed corpus residuals; those observations do not prove correctness for an uncovered Typedtree shape.
- **Recommendation:** compute supplied argument count from `Some` arguments for the overapplication comparison (while preserving the existing result-arrow partial logic), add labeled/optional omitted-slot native cases for both collector contexts, and rerun all gates plus fixed410 witness generation/review because the candidate digest and residual set may change.

## Warnings

### [W1] FR-014 fail-closed branches lack required negative coverage

- **Spec claim:** FR-014 / AC-10 and CHECK-2 require missing, changed, incomplete and wrong-shape inputs to refuse verification.
- **Implemented branches:** provenance binding and pinned values are checked at `roster/tezos-call-resolution/verify.js:36`; manifest digest, shape and artifact hashes at `:47`; database run/input completeness at `roster/tezos-call-resolution/comparison.js:21`; witness digest binding at `roster/tezos-call-resolution/verify.js:88`.
- **Existing tests:** `roster/tezos-call-resolution/check-comparison.js:116` constructs one complete positive snapshot, then exercises missing DB, missing table and orphan caller/target. Other comparator mutations cover forbidden relation transitions and residual witness counts.
- **Coverage gaps:** no executable negative test was found for a missing or changed manifest, changed artifact digest, 0/409 collected inputs, wrong catalogue/binding run markers or joined run set, baseline provenance mismatch, or witness snapshot-digest mismatch. A successful real CHECK-3 invocation proves only the positive path and cannot verify those refusal branches.
- **Recommendation:** add isolated negative cases for each input/provenance/completeness boundary and assert the specified setup/refusal exit class and absence of a keep report.

## Runnable checks executed by this auditor

| Exact command personally executed | Result |
|---|---|
| `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune build --root .` | PASS, exit 0 |
| `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune runtest --root . --force` | PASS, exit 0, 324/324 |
| `rtk proxy node roster/tezos-call-resolution/check-native.js` | PASS, exit 0, 4/4 |
| `rtk proxy node roster/tezos-call-resolution/check-native.js --self-test` | PASS, exit 0, 5 assertions |
| `rtk proxy node roster/tezos-call-resolution/check-comparison.js` | PASS, exit 0, 28 assertions |
| `rtk proxy node roster/tezos-call-resolution/verify.js --baseline /tmp/arch-index-resolution-baseline-OmhcEs/baseline.db --witness improvement/2026-09-14-tezos-resolution/attempt1-reviewed-witness.json` | PASS, exit 0; +400 Irmin, +395 protocol; `retention_authorized:false`; report `improvement/2026-09-14-tezos-resolution/2026-09-14T06-05-13-501Z-candidate-2424307/report.json` |
| `rtk proxy node roster/tezos-call-resolution/verify.js --baseline /tmp/arch-index-resolution-baseline-OmhcEs/baseline.db --self` | PASS, exit 0; zero changes; `retention_authorized:false`; report `improvement/2026-09-14-tezos-resolution/2026-09-14T06-05-21-638Z-self-2426629/report.json` |
| `rtk proxy node scripts/review-bundle-verify.js` | PASS, exit 0, 22 hashes |
| `rtk proxy git diff --check` | PASS, exit 0 |

The round-1/cycle-1 **scope gate is PASS**. The distinct **spec-compliance verdict is NO-GO**: green executable checks remain valid evidence, but FR-007/AC-6 diverges and FR-014/AC-10 lacks complete negative coverage.
