---
auditor: spec-compliance-auditor
date: 2026-09-16
status: EXECUTED evidence preparation — no spec findings; not a ship verdict
report_path_adaptation: "Skill default kb/reports/spec-compliance-report.md was deliberately redirected to roster/ocaml-cfa-foundation/spec-review-preparation.md because this task's manifest permits no new KB artifact."
spec: specs/ocaml-cfa-foundation.md
scope: committed-source review plus personally executed build/CHECK-1/CHECK-2/CHECK-3 and checker controls; no full-suite execution by this specialist
---

# OCaml CFA Foundation — Spec Compliance Preparation

This is not a ship decision. This specialist personally executed the build and
CHECK-1/2/3, including their controls, at `0af3625`. The full suite was not
rerun by this specialist: its same-HEAD `345/345` plus `6/6` result belongs to
the owner/reviewer and is not claimed here. Source locations remain necessary
alongside execution evidence; reported corpus counts are not semantic proof.

## Compliance matrix — functional requirements

| Claim | Static status | Implementation evidence | Test/check evidence | Review note |
|---|---|---|---|---|
| FR-001 | PASS (static) | `lib/arch_index/arch_index_cfa.ml:3-5,48-54` | `test/test_cfa.ml:50-54` | Separate target/reason sets. |
| FR-002 | PASS (static) | `arch_index_cfa.ml:39-46,56-63` | `test/test_cfa.ml:43-48` | Componentwise set union/equality. |
| FR-003 | PASS (static) | `arch_index_cfa.ml:11,22` | `test/test_cfa.ml:103-111` | Bottom is two empty sets. |
| FR-004 | PASS (static) | `arch_index_cfa.ml:32-37` | `test/test_cfa.ml:50-58` | Seed/copy primitives; joins are copies. |
| FR-005 | PASS (static) | `arch_index_cfa.ml:28-30,48-54` | `test/test_cfa.ml:50-54` | Neither component absorbs the other. |
| FR-006 | PASS (static) | `arch_index_cfa.ml:56-63` | `test/test_cfa.ml:56-86` | Worklist requeues changed cells. |
| FR-007 | PASS (static) | `arch_index_cfa.ml:56-63` | `test/test_cfa.ml:11-48`; `check-domain.js:1-210` | Independent repeated-scan oracle exists. |
| FR-008 | PASS (static) | `arch_index_cfa.ml:3-5,39-46` | `test/test_cfa.ml:50-54` | No witness data in the semantic value. |
| FR-009 | PASS (static) | `arch_index_cfa.ml:32-63`; `arch_index_cfa_cmt.ml:83-101` | `test/test_cfa.ml:56-86` | Kernel supplies only copy closure. |
| FR-010 | PASS (static) | `arch_index_cmt.ml:709-712` | `tezt/tests/ocaml_cfa_foundation.ml:241-260` | Empty CFA value retains an occurrence. |
| FR-011 | PASS | `roster/ocaml-cfa-foundation/check-domain.js:180-210` | CHECK-1 pass; controls pass/assertion/setup returned 0/1/2 | Personally executed at HEAD. |
| FR-012 | PASS (static) | `arch_index_cmt.ml:3438-3442,4169-4173` | `tezt/tests/ocaml_cfa_foundation.ml:77-205` | Session finalizes after CMT walk. |
| FR-013 | PASS (static) | `arch_index_cfa_cmt.ml:74-81,154-169`; `arch_index_cmt.ml:2539-2556` | `tezt/tests/ocaml_cfa_foundation.ml:121-205` | Binders use `Ident.unique_name`; expressions use physical equality. |
| FR-014 | PASS (static) | `arch_index_cfa_cmt.ml:10-13,56,194-197` | `arch_index_cfa_cmt.ml:53-54` | Session token prevents cross-session equality. |
| FR-015 | PASS (static) | `arch_index_cfa_cmt.ml:103-147,199-219`; `arch_index_cmt.ml:2140-2152` | `tezt/tests/ocaml_cfa_foundation.ml:220-276` | Root and same-callable nonrecursive forms are enrolled. |
| FR-016 | PASS (static) | `arch_index_cfa_cmt.ml:103-147` pre-indexes only root items; same-callable local-let path is `arch_index_cmt.ml:2140-2152` | `tezt/tests/local_value_targets.ml:37-50,121-126` | `Refuse.chain` (nested-module alias chain), computed, persistent, qualified, and partial RHS forms remain TOP; allowed local lets are distinct. |
| FR-017 | PASS (static) | `arch_index_cmt.ml:2508-2538` | `tezt/tests/ocaml_cfa_foundation.ml:241-276` | Existing direct/static paths precede CFA fallback. |
| FR-018 | PASS (static) | `arch_index_cfa_cmt.ml:199-219,223-229` | `tezt/tests/ocaml_cfa_foundation.ml:305-320` | Binder stamp, not rendered name, selects source. |
| FR-019 | PASS (static) | `arch_index_cfa_cmt.ml:83-101,249-258` | `tezt/fixtures/ocaml_cfa/named_joins.ml:6-24`; `tezt/tests/ocaml_cfa_foundation.ml:392-441` | If/match/sequence results join without feasibility filtering. |
| FR-020 | PASS (static) | `arch_index_cfa_cmt.ml:95-97,253-255` | `named_joins.ml:22-24`; `ocaml_cfa_foundation.ml:426-441` | Computation/value cases both join. |
| FR-021 | PASS (static) | `arch_index_cfa_cmt.ml:98,256`; existing walker at `arch_index_cmt.ml:1993-2021` | `ocaml_cfa_foundation.ml:416-441` | CFA copies only result while ordinary walker visits guards/prefixes. |
| FR-022 | PASS (static) | `arch_index_cfa_cmt.ml:87-91,249-250` | `named_joins.ml:19-21`; `ocaml_cfa_foundation.ml:440-441` | Pattern binder has no enrolled source and remains callback frontier. |
| FR-023 | PASS (static) | `arch_index_cfa_cmt.ml:213-217,223-229,274-278` | `ocaml_cfa_foundation.ml:362-390` | Unit owner is visible; distinct callable owner is callback. |
| FR-024 | PASS (static) | `arch_index_cfa_cmt.ml:154-175,302-315`; `arch_index_cmt.ml:3892-3895` | `ocaml_cfa_foundation.ml:184-205` | Literal target requires physical observation plus storage notice. |
| FR-025 | PASS (static) | `arch_index_cfa_cmt.ml:66-72,154-169` | `ocaml_cfa_foundation.ml:121-160` | Physical object equality does not use locations. |
| FR-026 | PASS (static) | `arch_index_cmt.ml:676-713`; `arch_index_cmt.ml:2539-2556` | `ocaml_cfa_foundation.ml:220-260` | CFA expansion creates enumerated, not static, heads. |
| FR-027 | PASS (static) | `arch_index_cfa_cmt.ml:267-288`; `arch_index_cmt.ml:681-685` | `ocaml_cfa_foundation.ml:465-480` | Tokens preserve occurrence identity; targets expand per occurrence. |
| FR-028 | PASS (static) | CFA fallback follows existing alias branch at `arch_index_cmt.ml:2531-2539` | `ocaml_cfa_foundation.ml:262-276` | CFA only runs after existing alias provenance path declines. |
| FR-029 | PASS (static) | `arch_index_cmt.ml:681-708` | `ocaml_cfa_foundation.ml:67-75,465-486` | Expansion copies pending-call metadata; bounded head has no TOP fields at resolution. |
| FR-030 | PASS (static) | `arch_index_cfa_cmt.ml:285-288` | `ocaml_cfa_foundation.ml:165-181,465-466` | Distinct registrations have distinct tokens. |
| FR-031 | PASS | Existing `fn_arity` passed at `arch_index_cmt.ml:3440-3442` and stored at `arch_index_cfa_cmt.ml:115-116,313-314` | `ocaml_cfa_foundation.ml:81-108,491-496`; CHECK-2 pass | Includes arity `0` and `-1` with two bounded candidates plus one unknown. |
| FR-032 | PASS | `arch_index_cmt.ml:2542-2546,2600-2603`; `arch_index_cmt.ml:676-708` | `ocaml_cfa_foundation.ml:81-108,491-496`; CHECK-2 pass | Uses supplied `Some` count and omitted-slot frontier, including nonpositive arity. |
| FR-033 | PASS (static) | `arch_index_cmt.ml:701-707` | `ocaml_cfa_foundation.ml:477-480` | One residual list element per occurrence. |
| FR-034 | PASS (static) | `arch_index_cmt.ml:691-708` | `ocaml_cfa_foundation.ml:477-480` | Reason and residual are independently appended. |
| FR-035 | PASS (static) | `arch_index_cmt.ml:709-712` | `ocaml_cfa_foundation.ml:241-260` | Bottom keeps unknown main occurrence. |
| FR-036 | PASS (static) | `arch_index_cmt.ml:686-697`; `arch_index_cfa_cmt.ml:217,229,299-315` | `ocaml_cfa_foundation.ml:362-380,184-205` | New reasons map to callback/dropped; existing reasons remain outside CFA mapping. |
| FR-037 | PASS (static) | `call_graph_extractor.ml:404-429` | `ocaml_cfa_foundation.ml:277-303` | New flat unknown is `*TOP*`, no callee file/edge form. |
| FR-038 | PASS (static) | `call_graph_extractor.ml:304-351,404-429` | `ocaml_cfa_foundation.ml:315-329` | CFA path bypasses homonym `name_to_file` lookup. |
| FR-039 | PASS (static) | `call_graph_extractor.ml:404-429` | `ocaml_cfa_foundation.ml:277-289` | Nonunique caller becomes flat unknown. |
| FR-040 | PASS (static) | `arch_index_cmt.ml:3801-3826` | `ocaml_cfa_foundation.ml:305-320` | Main notifications retain existing missing-caller drop branch. |
| FR-041 | PASS (static) | `call_graph_extractor.ml:404-449`; `arch_index_cmt.ml:730-732` | `ocaml_cfa_foundation.ml:277-303` | Private marker is removed before persistence. |
| FR-042 | PASS | `roster/ocaml-cfa-foundation/check-cmt.js:1-88` | CHECK-2 authentic fixture pass; controls 1/2/2/2 | Personally executed at HEAD. |
| FR-043 | PASS | `roster/ocaml-cfa-foundation/check-tezos.js:1-317` | CHECK-3 measured pass; controls pass/assertion/setup 0/1/2 | Replay had no relation loss/new MUST; accounting remains nonsemantic. |
| FR-044 | PASS (static) | `arch_index_cfa.ml:32-63`; `arch_index_cfa_cmt.ml:83-101` | `check-tezos.js:144-169` | No stage-3/4 transfer primitive found in new kernel. |

## Compliance matrix — acceptance criteria

| Claim | Static status | Evidence | Gate status |
|---|---|---|---|
| AC-1 | PASS | `test/test_cfa.ml:50-54` | CHECK-1 pass |
| AC-2 | PASS | `test/test_cfa.ml:50-54` | CHECK-1 pass |
| AC-3 | PASS | `test/test_cfa.ml:56-86` | CHECK-1 pass |
| AC-4 | PASS | `test/test_cfa.ml:103-111`; `ocaml_cfa_foundation.ml:241-260` | CHECK-1/2 pass |
| AC-5 | PASS | `test/test_cfa.ml:50-54,103-111` | CHECK-1 pass |
| AC-6 | PASS | `check-domain.js:180-210` | Controls 0/1/2 |
| AC-7 | PASS | `ocaml_cfa_foundation.ml:220-276` | CHECK-2 pass |
| AC-8 | PASS | `ocaml_cfa_foundation.ml:121-160` | CHECK-2 pass |
| AC-9 | PASS | `named_joins.ml:6-12`; `ocaml_cfa_foundation.ml:408-415,362-390` | CHECK-2 pass |
| AC-10 | PASS | `named_joins.ml:13-24`; `ocaml_cfa_foundation.ml:426-441` | CHECK-2 pass |
| AC-11 | PASS | `ocaml_cfa_foundation.ml:305-320` | CHECK-2 pass |
| AC-12 | PASS | `ocaml_cfa_foundation.ml:465-486` | CHECK-2 pass |
| AC-13 | PASS | `ocaml_cfa_foundation.ml:81-108,491-496` | CHECK-2 pass; arity 0/-1 covered |
| AC-14 | PASS | `ocaml_cfa_foundation.ml:497-500` | CHECK-2 pass |
| AC-15 | PASS | `ocaml_cfa_foundation.ml:213-234` | CHECK-2 pass |
| AC-16 | PASS | `ocaml_cfa_foundation.ml:311-363` | CHECK-2 pass |
| AC-17 | PASS | `arch_index_cmt.ml:709-712`; `call_graph_extractor.ml:404-429` | CHECK-2 pass |
| AC-18 | PASS | `check-cmt.js:1-88` | Controls 1/2/2/2 |
| AC-19 | PASS | `check-tezos.js:1-317` | CHECK-3 pass; controls 0/1/2 |

## Findings

No DIVERGE, MISSING, or UNTESTED claim remains in this round.

## Personal execution record

- `rtk proxy opam exec -- dune build`: exit 0.
- `CHECK-1`: exit 0, 517 oracle cases; pass/assertion/setup controls: 0/1/2.
- `CHECK-2`: exit 0, authentic main/flat/metadata/identity/consumer test; assertion/setup/compiler-marker/empty-success controls: 1/2/2/2.
- `CHECK-3`: exit 0; 45,054 rows; three relation gains, zero relation losses, zero new MUST rows; its before/after tracked-state digest was identical. Pass/assertion/setup controls: 0/1/2.
- Full suite intentionally not rerun by this specialist; owner/reviewer separately owns the same-HEAD result.

## Unspecified-implementation scan

No new public API or persisted schema extension was identified in the reviewed CFA modules. The private `__cfa:` marker is removed before persistence (`arch_index_cmt.ml:730-732`; `call_graph_extractor.ml:404-429`). This is not a finding.
