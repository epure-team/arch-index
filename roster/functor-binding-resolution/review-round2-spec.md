---
auditor: spec-compliance-auditor
date: 2026-09-13
status: 0 critical, 0 warnings, 0 info
coverage: 39/39 qualified claims verified (100%)
scope_gate: 0
review_round: 2
---

# Round 2 spec-compliance review — functor binding resolution

## Context and execution boundary

This is embedded roster-review round 2. The agent context was deliberately reused after the
correction-planning pass; it is not represented as an independent fresh-context review. The frozen
source of truth was `specs/functor-binding-resolution.md` version 1.0.1 (26 FRs, 13 ACs).

I read the implementation and reviewer briefs, inspected the complete `main...HEAD` feature diff
and the `b98fcd0..49bc78b` correction diff, and traced AC-13 through the actual producer code rather
than relying on the correction brief or prior report.

Executed under the selected opam switch, all exit 0:

```text
node scripts/check-functor-bindings.js inventory
node scripts/check-functor-bindings.js lifecycle
node scripts/check-functor-bindings.js query
node scripts/check-functor-bindings.js compatibility
```

Observed summaries were inventory 13 occurrences/6 declarations/9 matches with all synthetic
premises satisfied; lifecycle direct-API and real-producer failure boundaries satisfied; query 57
limit-zero corruptions, six formats and 18+18 byte oracles satisfied; compatibility preserved 16
semantic surfaces, legacy queries, flat semantics, catalogue bytes and database bytes.

I intentionally did not run Dune/build commands because root owns every build in this review,
including CHECK-5's internal build. I also did not execute the standalone archived CHECK-5 ratchet;
root owns that exact-checkout/RED-export execution. CHECK-5 was reviewed statically as executable
acceptance evidence, not claimed as executed here.

Root subsequently supplied the official archived-ratchet result: `red_verified:true` against
pre-fix `5338a81`, checker blob `70e8a2fde546b256766506450a691bf5872a7556`, and
`greenFailed:false` on the corrected head. This execution is attributed to the root reviewer, not
to this specialist.

## Independent AC-13 transaction-topology audit

The producer collects binding data while Typedtrees are live and queues only the public immutable
`collection` payload (`arch_index.ml:497-500,675-681`; payload fields are strings, integers,
options and lists in `arch_index_bindings.mli:1-31`). The initial module/catalogue transaction
commits at `arch_index.ml:703`; the later calls transaction commits at 1636, module dependencies at
1714, and type usages at 1777. Only after those commits and intent restoration does the binding
drain begin at 1804-1824.

Each collected input opens `SAVEPOINT functor_binding_input` and releases it on success
(`arch_index_bindings.ml:260-277`). Because no outer producer transaction is active at the drain,
this is an outermost SQLite transaction: trigger `RAISE(ROLLBACK)` can erase only the current
input, not catalogue/graph facts or earlier binding jobs. Rollback/release uncertainty escapes
(`arch_index_bindings.ml:278-285`), is caught by the per-job loop, latches eligibility false,
warns, attempts the zero-count failed row, and continues iteration (`arch_index.ml:1807-1824`).
Finalization is last and gated by that latch (`arch_index.ml:1826-1836`).

The standalone checker builds the producer from its computed repository root and invokes that
exact `_build` artifact (`check-global-rollback.js:13-16,65-71,92-95`). It premise-checks healthy
two-input/two-application data (`:155-176`), injects ordinal-2 `RAISE(ROLLBACK)` only after a
different input has two rows and without naming an artifact (`:243-259`), compares every old
semantic table except the new binding tables and binding marker (`:97-130,178-180`), and asserts
the failed row, zero children, intact successful inputs and absent marker (`:181-229`). The separate
three-input case proves post-failure continuation because the trigger suppresses itself after the
failed row is recorded (`:285-307`). Selection depends on persisted state, not artifact names or
filesystem ordering.

## Functional-requirement compliance matrix

| Claim | Status | Implementation anchor | Test anchor | Notes |
|---|---|---|---|---|
| FR-001 exact occurrence accounting | PASS | `arch_index_bindings.ml:208-242` | CHECK-1 inventory; CHECK-2 lifecycle | Reuses catalogue traversal/callback ordinals; failed catalogue inputs create no jobs. |
| FR-002 closed declaration traversal | PASS | `arch_index_bindings.ml:78-134` | CHECK-1 traversal census | Default typed iterator covers named module and let-module binders; only peeled direct functors persist. |
| FR-003 compiler identity | PASS | `arch_index_bindings.ml:44,62-76,136-151` | CHECK-1 shadow/cross-CMT cases | `Ident.same` matches; `Ident.unique_name` serializes artifact-local keys. |
| FR-004 conflicting identity failure | PASS | `arch_index_bindings.ml:64-76,208-210` | CHECK-1 duplicate mutation; CHECK-2 failure lifecycle | Collection raises before returning a payload. |
| FR-005 maximal telescope | PASS | `arch_index_bindings.ml:115-133` | CHECK-1 curried/native/synthetic cases | Constraint peeled, consecutive and one-based. |
| FR-006 closed formal grammar | PASS | `arch_index_bindings.ml:106-113,254-258`; reader `arch_functor_bindings.ml:56-76` | CHECK-1 four nullable combinations; CHECK-3 corruptions | Unit and named nullability rules validated. |
| FR-007 matched-result grammar | PASS | `arch_index_bindings.ml:217-235`; validators `:613-637` | CHECK-1; CHECK-3 | Same-input declaration, positive position, null reason and kind agreement enforced. |
| FR-008 unresolved grammar | PASS | `arch_index_bindings.ml:199-206`; validators `:446-450,631-636` | CHECK-1/3 all nine reasons | Closed vocabulary and null matched fields enforced. |
| FR-009 head ordinal/linkage | PASS | `arch_index_functors.ml` callback; `arch_index_bindings.ml:212-235,643-651` | CHECK-1 overapplication/chain; CHECK-3 corruptions | Application-headed rows retain stripped ordinal; parent linkage validated. |
| FR-010 refusal precedence | PASS | `arch_index_bindings.ml:139-177` | CHECK-1 synthetic precedence | Inner errors propagate before advance/kind; exhaustion yields curried refusal. |
| FR-011 actual-root grammar | PASS | `arch_index_bindings.ml:179-197` | CHECK-1 root matrix; CHECK-3 malformed roots | Local nonpersistent Pident/Pdot only; no alias chasing. |
| FR-012 unchanged argument/facts | PASS | Argument remains catalogue-owned; binding payload stores no argument | CHECK-1 byte identity; CHECK-4 semantic snapshots | No declaration cloning into results and no graph mutation. |
| FR-013 one input/outcome/counts | PASS | `arch_index_bindings.ml:260-290,575-587` | CHECK-1; CHECK-2 zero-result and failure cases | Collected zero counts accepted; outcomes closed by schema. |
| FR-014 isolated failure | PASS | `arch_index.ml:1804-1824`; `arch_index_bindings.ml:260-290` | CHECK-2 plus CHECK-5 static audit | Corrected topology removes enclosing old producer transaction. |
| FR-015 marker lifecycle | PASS | `arch_index_support.ml:30-35`; `arch_index_bindings.ml:652-672`; `arch_index.ml:1826-1836` | CHECK-2 marker boundaries; CHECK-5 static audit | Cleared before replacement; written only after committed-data validation. |
| FR-016 complete eligibility | PASS | `arch_index_bindings.ml:499-651` | CHECK-1/2 corruption and lifecycle; CHECK-5 static audit | Catalogue, selection, counts, rows, grammar and linkage all validated. |
| FR-017 bounded meaning | PASS | Reader fixed scope/limitations `arch_functor_bindings.ml:5-6`; README `:62-66` | CHECK-4; CHECK-1 identity evidence | No target, closure, substitution, runtime or freshness claim. |
| FR-018 command/six formats/limit | PASS | `arch_query.ml:106,143-156,275-288` | CHECK-3 CLI and six renderers | Strict ASCII decimal, default 50, zero accepted, early usage refusal. |
| FR-019 whole snapshot validation | PASS | `arch_functor_bindings.ml:39-50,145-273` | CHECK-3 limit-zero/unused-data corruptions | Full validation precedes filtering and rendering. |
| FR-020 closed validation scope | PASS | `arch_functor_bindings.ml:9-24,56-267` | CHECK-3 57 corruptions and unrelated-table control | Old catalogue closure plus all new rows; unrelated old tables ignored. |
| FR-021 error precedence | PASS | `arch_query.ml:143-156`; reader `:127-148`; `arch_functor_bindings.ml:39-50` | CHECK-3 schema/marker/operational cases; CHECK-4 flat | Correct 2/3 categories and ordered guards. |
| FR-022 empty stdout before success | PASS | `arch_query.ml:275-288`; snapshot completes in reader before return | CHECK-3 all refusal families | Rendering begins only with returned validated cells. |
| FR-023 summary/counts | PASS | `arch_functor_bindings.ml:267-271`; `arch_query.ml:279-281` | CHECK-3 semantic cells/oracles | Full counts precede limit; ten columns and fixed strings match. |
| FR-024 row projection/order/nulls | PASS | `arch_functor_bindings.ml:211-267`; `arch_query.ml:284-288` | CHECK-3 semantic and byte oracles | Fifteen columns, same-run joins, artifact/ordinal order, native null cells. |
| FR-025 six renderer bytes | PASS | `arch_query.ml:279-288` using existing `Arch_fmt` | CHECK-3 18 nonempty + 18 zero-row oracles | Summary first; JSON always emits second array; argument remains one text cell. |
| FR-026 read-only/compatibility | PASS | Reader contains no writes; additive schema and unchanged flat version | CHECK-4 database/catalogue bytes and legacy/flat semantics | No existing query or graph contract change found. |

## Acceptance-criterion compliance matrix

| Claim | Status | Evidence anchors | Notes |
|---|---|---|---|
| AC-1 | PASS | `arch_index_bindings.ml:115-242`; CHECK-1 inventory; CHECK-4 | Native curried positions 1/2 and unchanged old facts. |
| AC-2 | PASS | `arch_functor_bindings.ml:145-271`; CHECK-3/4 | Two-input/three-result, limit 2, all formats and unchanged bytes. |
| AC-3 | PASS | Producer callback `arch_index.ml:670-681`; final validator `arch_index_bindings.ml:499-651`; CHECK-1/2 | Nested coverage and failed/no-fabricated input exercised. |
| AC-4 | PASS | `arch_index_bindings.ml:78-104`; CHECK-1 traversal census | Typed contexts and excluded untyped payload premise covered. |
| AC-5 | PASS | `arch_index_bindings.ml:152-177`; CHECK-1/3 | Overapplication refusal and preceding-position linkage covered. |
| AC-6 | PASS | Producer/reader formal grammar anchors above; CHECK-1/3 | All named nullability combinations, unit, empty/malformed rejection. |
| AC-7 | PASS | `arch_index_bindings.ml:64-76,139-177`; CHECK-1/2 | Genuine identity failure and all nine premise-checked refusals. |
| AC-8 | PASS | `arch_index_bindings.ml:260-290,652-672`; `arch_index.ml:1804-1836`; CHECK-2/4 | Isolated API/CLI failures, failed-row failure and absent marker. |
| AC-9 | PASS | `arch_functor_bindings.ml:145-267`; CHECK-3 | Corruption beyond limit and unused declarations rejected at limit 0. |
| AC-10 | PASS | `arch_query.ml:279-288`; CHECK-3 byte oracles | Frozen headers, ordering, nulls, escaping and JSON stream verified. |
| AC-11 | PASS | CLI early parse plus reader guard/snapshot anchors; CHECK-3/4 | Every precedence stage and accessed-operation failure covered. |
| AC-12 | PASS | Identity/root/limitations anchors; CHECK-1/4 | Local syntactic meaning only; misleading display/cross-CMT cases covered. |
| AC-13 | PASS | Independent topology audit above; `check-global-rollback.js:13-320` | Exact-checkout two-input ratchet is present and authentic by static inspection; execution is root-owned. |

## Unspecified implementation and scope review

Scope gate result: **0** violations. Product changes are confined to the accepted additive schema,
collector/persistence, reader/CLI, wiring, documentation and tests. The correction diff changes the
producer orchestration and owned regression/evidence surfaces. The three-input continuation case is
test evidence for the explicit no-short-circuit correction requirement, not a product API or grammar
extension. Authorized attribution-gated calibration files change frozen references only; no new
allowance or graph semantics appears in this feature diff. Flat schema remains unchanged.

No public API, refusal reason, supported-head class, graph certainty, target-resolution claim, or
new consumer behavior was found outside the 26-FR/13-AC contract.

## Findings

None. The round-one FR-014/AC-8 global-rollback finding is resolved by the corrected transaction
topology and the linked AC-13 ratchet. Final GO still depends on root-owned build/Dune and archived
CHECK-5 execution; those are orchestration gates, not unverified claims in this specialist result.
