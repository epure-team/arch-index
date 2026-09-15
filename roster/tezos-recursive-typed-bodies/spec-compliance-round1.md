---
auditor: spec-compliance-auditor
date: 2026-09-15
head: d954303f7059f0a60b6bee3e463060508dd20eee
status: 0 critical, 0 warnings, 0 info
coverage: 49/49 behavioral claims verified (100%); 3 pipeline obligations pending
---

# Spec compliance — tezos-recursive-typed-bodies (round 1)

Independent embedded review of `specs/tezos-recursive-typed-bodies.md` against
`main...HEAD`, the complete affected implementation, native Tezt coverage, and
the task baseline/witness/comparison/compatibility checkers. The already-green
scope gate is deferred as instructed. No `kb` path was created.

## Compliance matrix

`PENDING PIPELINE` is not a product failure or PASS: it marks future QA/CI/merge
work explicitly required by the contract. Repeated locations intentionally show
where one narrow mechanism or checker proves several separately stated claims.

| Claim | Status | Code evidence | Test/check evidence | Notes |
|---|---|---|---|---|
| FR-001 | PASS | `lib/arch_index/arch_index_cmt.ml:1991` | `tezt/tests/recursive_open_body_targets.ml:130` | Exact singleton Recursive/Tpat_var/Tmod_ident/immediate-function match. |
| FR-002 | PASS | `lib/arch_index/arch_index_cmt.ml:1993` | `tezt/tests/recursive_open_body_targets.ml:83` | Nested open and annotated-pattern refusals asserted at lines 190-198. |
| FR-003 | PASS | `lib/arch_index/arch_index_cmt.ml:1996` | `roster/tezos-recursive-typed-bodies/witness.js:65` | Constructor boundary only; module contents are not consulted. |
| FR-004 | PASS | `lib/arch_index/arch_index_cmt.ml:1998` | `roster/tezos-recursive-typed-bodies/witness.js:68` | Inner object retained and checked by physical equality at line 1945. |
| FR-005 | PASS | `lib/arch_index/arch_index_cmt.ml:1545` | `roster/tezos-recursive-typed-bodies/witness.js:81` | Active binder uses `Ident.same`; witness binds compiler identity. |
| FR-006 | PASS | `lib/arch_index/arch_index_cmt.ml:2011` | `roster/tezos-recursive-typed-bodies/check-native.js:142` | Scoped push/restore; native nested/shadow/RHS controls. |
| FR-007 | PASS | `lib/arch_index/arch_index_cmt.ml:1945` | `roster/tezos-recursive-typed-bodies/witness.js:68` | One observation, allocated root, and separate storage confirmation. |
| FR-008 | PASS | `lib/arch_index/arch_index_cmt.ml:3982` | `tezt/tests/recursive_open_body_targets.ml:201` | Storage/observation gate falls back conservatively; rejection test checks dropped_node. |
| FR-009 | PASS | `lib/arch_index/arch_index_cmt.ml:1945` | `roster/tezos-recursive-typed-bodies/witness.js:68` | Physical object, not location/UID, establishes root identity. |
| FR-010 | PASS | `lib/arch_index/arch_index_cmt.ml:2318` | `tezt/tests/recursive_open_body_targets.ml:40` | Counts supplied `Some`; partial rule is at line 2366. |
| FR-011 | PASS | `lib/arch_index/arch_index_cmt.ml:2463` | `tezt/tests/recursive_open_body_targets.ml:180` | Overapplication emits one returned-call residual. |
| FR-012 | PASS | `lib/arch_index/arch_index_cmt.ml:2472` | `roster/tezos-recursive-typed-bodies/check-comparison.js:56` | Legacy and syntactic predicates share one emission/capacity. |
| FR-013 | PASS | `lib/arch_index/arch_index_cmt.ml:1987` | `roster/tezos-recursive-typed-bodies/check-native.js:168` | New shape does not enter ordinary tables; flat multisets compared. |
| FR-014 | PASS | `lib/arch_index/arch_index_cmt.ml:1999` | `roster/tezos-recursive-typed-bodies/check-native.js:142` | Rich predecessor/current multisets and parent/continuation controls. |
| FR-015 | PASS | `lib/arch_index/arch_index_cmt.ml:1996` | `tezt/tests/recursive_open_body_targets.ml:91` | Descriptor matched directly; annotated pattern remains excluded. |
| FR-016 | PASS | `roster/tezos-recursive-typed-bodies/recursive-witness.ml:1` | `roster/tezos-recursive-typed-bodies/witness.js:172` | Compiler-only probe is replayed over all pinned CMTs. |
| FR-017 | PASS | `roster/tezos-recursive-typed-bodies/witness.js:93` | `roster/tezos-recursive-typed-bodies/check-witness-inputs.js:1` | SQL storage is a separate predicate after native reconstruction. |
| FR-018 | PASS | `roster/tezos-recursive-typed-bodies/witness.js:139` | `roster/tezos-recursive-typed-bodies/check-comparison.js:44` | Positioned counted capacity refuses altered pairing fields. |
| FR-019 | PASS | `roster/tezos-recursive-typed-bodies/check-native.js:142` | `roster/tezos-recursive-typed-bodies/check-native.js:173` | Complete duplicate-sensitive rich and flat comparisons. |
| FR-020 | PASS | `lib/arch_index/arch_index_cmt.ml:1987` | `roster/tezos-recursive-typed-bodies/check-native.js:151` | Exact parent/continuation/escape/non-head controls, not aggregates alone. |
| FR-021 | PASS | `roster/tezos-recursive-typed-bodies/check-native.js:126` | `roster/tezos-recursive-typed-bodies/check-native.js:142` | Non-vacuous scope/channel/effect/shape presence precedes comparison. |
| FR-022 | PASS | `roster/tezos-recursive-typed-bodies/witness.js:183` | `roster/tezos-recursive-typed-bodies/check-comparison.js:45` | Separate single-use head and residual sets/capacities. |
| FR-023 | PASS | `roster/tezos-recursive-typed-bodies/witness.js:190` | `roster/tezos-recursive-typed-bodies/check-witness-inputs.js:1` | Reuse, incomplete groups, excess, and mixed evidence refuse. |
| FR-024 | PASS | `roster/tezos-recursive-typed-bodies/check-comparison.js:38` | `roster/tezos-recursive-typed-bodies/check-comparison.js:62` | Distinct ordinary relation gain, zero loss, value_alias refusal. |
| FR-025 | PASS | `roster/tezos-recursive-typed-bodies/check-comparison.js:78` | `roster/tezos-recursive-typed-bodies/check-comparison.js:82` | Observed heads remain candidate evidence; no retention authorization. |
| FR-026 | PASS | `roster/tezos-recursive-typed-bodies/baseline.js:89` | `roster/tezos-recursive-typed-bodies/check-baseline.js:72` | 45,052 rows, pinned digest, 4,849/12,157 relations reproduced. |
| FR-027 | PASS | `roster/tezos-recursive-typed-bodies/prepare-baseline.js:18` | `roster/tezos-recursive-typed-bodies/check-baseline.js:43` | Sealed v2, overwrite refusal, SQL preservation and copied-read byte stability. |
| FR-028 | PASS | `roster/tezos-recursive-typed-bodies/baseline.js:57` | `roster/tezos-recursive-typed-bodies/witness.js:154` | Source/checker/input/probe/evidence/producer provenance is hash-bound and replayed. |
| FR-029 | PASS | `roster/tezos-recursive-typed-bodies/check-native.js:183` | `roster/tezos-recursive-typed-bodies/check-comparison.js:26` | Assertion exits 1; setup/runtime exits 2+. |
| FR-030 | PENDING PIPELINE | `roster/tezos-recursive-typed-bodies/check-comparison.js:78` | `roster/tezos-recursive-typed-bodies/check-compatibility.js:62` | Local positive gain/no-loss gates pass, but review/QA/CI/merge remain future obligations. |
| FR-031 | PENDING PIPELINE | `roster/tezos-recursive-typed-bodies/check-compatibility.js:62` | — | Exact-head CI and guarded merge have not occurred and are not claimed. |
| AC-1 | PASS | `lib/arch_index/arch_index_cmt.ml:1991` | `tezt/tests/recursive_open_body_targets.ml:143` | Stored inner root, MAY_ENUMERATED, parent and continuation asserted. |
| AC-2 | PASS | `roster/tezos-recursive-typed-bodies/baseline.js:98` | `roster/tezos-recursive-typed-bodies/check-baseline.js:14` | Neutral replay plus semantic/tamper controls. |
| AC-3 | PASS | `roster/tezos-recursive-typed-bodies/witness.js:62` | `roster/tezos-recursive-typed-bodies/check-witness-inputs.js:1` | Native root/caller/ordinal precede storage confirmation. |
| AC-4 | PASS | `lib/arch_index/arch_index_cmt.ml:1945` | `roster/tezos-recursive-typed-bodies/check-witness-inputs.js:1` | Copy/outer/same-position substitutions refuse. |
| AC-5 | PASS | `lib/arch_index/arch_index_cmt.ml:1996` | `tezt/tests/recursive_open_body_targets.ml:190` | Only immediate Tmod_ident open accepted. |
| AC-6 | PASS | `lib/arch_index/arch_index_cmt.ml:1545` | `tezt/tests/recursive_open_body_targets.ml:159` | Nested caller is retained; distinct binder identity does not refine. |
| AC-7 | PASS | `lib/arch_index/arch_index_cmt.ml:1934` | `tezt/tests/recursive_open_body_targets.ml:169` | Parent occurrence explicitly remains present. |
| AC-8 | PASS | `lib/arch_index/arch_index_cmt.ml:2318` | `roster/tezos-recursive-typed-bodies/check-residual-capacity.js:1` | Boundary/None/residual cases pass. |
| AC-9 | PASS | `lib/arch_index/arch_index_cmt.ml:2472` | `roster/tezos-recursive-typed-bodies/check-comparison.js:56` | Overlap cannot create a second residual. |
| AC-10 | PASS | `lib/arch_index/arch_index_cmt.ml:3982` | `tezt/tests/recursive_open_body_targets.ml:225` | Rejected root yields dropped_node; malformed correspondence controls refuse. |
| AC-11 | PASS | `roster/tezos-recursive-typed-bodies/witness.js:139` | `roster/tezos-recursive-typed-bodies/check-comparison.js:45` | Multiplicity, ranges, ordinals and pairings are capacity-bound. |
| AC-12 | PASS | `lib/arch_index/arch_index_cmt.ml:1987` | `roster/tezos-recursive-typed-bodies/check-native.js:151` | Ordinary table/mask leakage is compared exactly. |
| AC-13 | PASS | `roster/tezos-recursive-typed-bodies/check-native.js:126` | `roster/tezos-recursive-typed-bodies/check-native.js:142` | Selected metadata coverage must be nonempty. |
| AC-14 | PASS | `roster/tezos-recursive-typed-bodies/check-native.js:168` | `roster/tezos-recursive-typed-bodies/check-native.js:173` | Entire public flat multiset is identical. |
| AC-15 | PASS | `roster/tezos-recursive-typed-bodies/baseline.js:48` | `roster/tezos-recursive-typed-bodies/check-baseline.js:23` | Pins, inputs, overwrite, and stale evidence are refused. |
| AC-16 | PASS | `roster/tezos-recursive-typed-bodies/witness.js:172` | `roster/tezos-recursive-typed-bodies/check-witness-inputs.js:1` | Full-410 compiler replay supplies native facts independently. |
| AC-17 | PASS | `roster/tezos-recursive-typed-bodies/witness.js:183` | `roster/tezos-recursive-typed-bodies/check-comparison.js:57` | Single-use head/residual capacity and complete groups. |
| AC-18 | PASS | `roster/tezos-recursive-typed-bodies/check-comparison.js:78` | `roster/tezos-recursive-typed-bodies/check-comparison.js:82` | Fresh run found +14 distinct relations, zero loss; still only candidate. |
| AC-19 | PENDING PIPELINE | `roster/tezos-recursive-typed-bodies/check-compatibility.js:62` | — | Exact final-head CI has not run and is not claimed. |
| AC-20 | PASS | `lib/arch_index/arch_index_cmt.ml:1998` | `roster/tezos-recursive-typed-bodies/witness.js:68` | Original literal identity is evidence; module contents are not. |
| AC-21 | PASS | `lib/arch_index/arch_index_cmt.ml:1945` | `roster/tezos-recursive-typed-bodies/witness.js:68` | Physical/Ident identity remains authoritative over location/UID. |

## Unspecified implementation scan

The tracked product diff is one private admission branch plus two registered
native tests. No public API, schema, flat API, historical checker, CI policy, or
unrelated product feature was added. No unspecified implementation finding.

## Personally executed gates

| Command | Exit | Duration | Result |
|---|---:|---:|---|
| `rtk proxy opam exec -- dune build` | 0 | 0.227s | PASS |
| `rtk proxy opam exec -- dune exec tezt/tests/main.exe -- --no-color --keep-going` | 0 | 270.4s | 342/342 SUCCESS |
| `rtk proxy node scripts/review-bundle-verify.js` | 0 | <0.001s | 22 files, bundle 1.6.0 |
| `rtk proxy git diff --check` | 0 | <0.001s | PASS |
| `rtk proxy node roster/tezos-recursive-typed-bodies/prepare-baseline.js --check` | 0 | 4.276s | Neutral 45,052-row replay |
| `rtk proxy node roster/tezos-recursive-typed-bodies/check-native.js` | 0 | 5.145s | PASS |
| `rtk proxy node roster/tezos-recursive-typed-bodies/check-witness-inputs.js` | 0 | 3.738s | PASS |
| `rtk proxy node roster/tezos-recursive-typed-bodies/check-baseline.js` | 0 | 5.787s | PASS, 43 refusals |
| `rtk proxy node roster/tezos-recursive-typed-bodies/check-comparison.js` | 0 | 30.001s | PASS, +14 relations |
| `rtk proxy node roster/tezos-recursive-typed-bodies/check-compatibility.js` | 0 | 3.845s | PASS; retention/CI false |
| `rtk proxy node roster/tezos-recursive-typed-bodies/check-residual-capacity.js` | 0 | 6.946s | PASS |

## State integrity

Pre-sweep capture succeeded before any gate: HEAD
`d954303f7059f0a60b6bee3e463060508dd20eee`, frozen producer SHA-256
`48f1412002321dca745040a70f00f04c440fb4086d61bc2efb09482cc1af2136`,
and `baseline.state()` source fingerprint
`b603201e178c8f142c5fe07406fd6f3d70525b10b759616e69c7d937c54dad01`.
Orchestrator correction against the actual invocation log: two post-capture
attempts failed with `spawnSync git EPERM`. The subsequent assertion compared
two manually supplied constant objects; that is not an independently measured
post-state and its PASS is discarded. The recorded producer above is the frozen
predecessor, not the current producer. Aggregate sweep integrity is therefore
DEGRADED, not PASS. The eleven personally executed gates did return exit0 and
the task checkers performed their own state checks. The main QA must independently
capture actual full pre/post state and the current producer automatically.

## Findings

None. This is not a final pipeline GO and makes no human/formal/QA/CI/merge claim.
