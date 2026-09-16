# Spec compliance — round2/cycle1

Spec: `specs/ocaml-cfa-foundation.md`, unchanged digest07e4ea8f….
Reviewed product HEAD: `791d1f9ac8947edc13a2101b0e86cfa9bced1f3f`.
Execution: root in spec-compliance-auditor role, following independent Terra
read-only preparation. Subagent continuation twice failed with thread limit;
do not describe this execution as an independent third runtime/agent.
Default KB report location is adapted to this manifest-approved directory.

All44 FRs and19 ACs were rechecked against the finite-fragment boundary and
executed checks. PASS means code plus executable coverage, not formal proof.
The round1 matrix is historical: its old green missed opaque-root-alias joins.

| Requirements | ACs | Code and executable evidence | Status |
|---|---|---|---|
| FR-001/002/003/004/005/008 | AC-1/2/4/5 | `arch_index_cfa.ml` value/bottom/update/join; `test/test_cfa.ml` mixed_chain, bottom_and_unknown; mixed root regression `ocaml_cfa_foundation.ml:440` | PASS |
| FR-006/007 | AC-3 | `arch_index_cfa.ml` enqueue/copy/solve; independent list oracle,512 graphs in3 orders, late_updates/long_chain; CHECK1 independent517 cases | PASS |
| FR-009/014/044 | AC-19 | Kernel has only seeds/copies; CMT owner(session,serial), create per CMT; stage3/4 exclusions; CHECK3 frozen baseline unchanged | PASS |
| FR-010/035 | AC-4/17 | `arch_index_cmt.ml:709` invoked-bottom fallback; `call_graph_extractor.ml:404` exact flat fallback; native bottom/recursive refusal controls plus kernel bottom cycle | PASS |
| FR-011 | AC-6 | CHECK1 classifier/injection controls0/1/2, personally executed | PASS |
| FR-012/013/024/025 | AC-8/15 | CMT Ident.unique_name, physical expressions, observe/store/finalize after whole CMT; `ocaml_cfa_foundation.ml:110` equal ghost locations, actual collision ordinals, wrong-owner/body/missing/late-conflict controls | PASS |
| FR-015/016/017/018/023/040 | AC-7/9/11 | CMT create/register_local_alias/register_call owner restriction; existing static branch precedes CFA; `local_value_targets.ml` module/recursive/returned refusal, foundation shadow/unit-visible/capture checks | PASS |
| FR-019/020/021/022 | AC-9/10 | root_expr_cell/expr_cell branches join every RHS; original collector still visits guards/scrutinee/prefix. `named_joins.ml` and foundation named/match/exception/sequence/pattern checks | PASS |
| FR-026/027/028/029/030 | AC-7/12 | `arch_index_cmt.ml:676` per-occurrence expansion; MAY only, aliases independent, copied metadata. Foundation pending metadata + SQL same-line4 rows/cond/dead/scopes tests and caller alias exclusion | PASS |
| FR-031/032/033/034/036 | AC-13/14/15 | expand_cfa_value supplied/omitted/arity and independent reasons/residuals; native tuple/cases/curried/labeled, injected arity0/-1, exact2TOP overapplication, rejected-body cause and mixed root regression | PASS |
| FR-037/038/039/041 | AC-16/17 | `call_graph_extractor.ml:304` unique same-file mapping and :404 CFA-only exact unknown tuple; ambiguous caller/shadowed target/homonym/flat literal checks; private marker removed, no schema/API change | PASS |
| FR-042 | AC-18 | CHECK2 personally ran authentic main/flat/consumer fixture; assertion/setup/compiler-marker/empty-success controls1/2/2/2 | PASS |
| FR-043 | AC-19 | CHECK3 personally replays pinned410; exact gains/losses and resources, no semantic proof; pure exit/multiset/relation controls pass | PASS |

## Corrected acceptance boundary

At `lib/arch_index/arch_index_cfa_cmt.ml:134`, a root alias whose source is not
eligible now explicitly seeds callback uncertainty. `named_joins.ml:6` uses an
opaque source and two alias hops. `ocaml_cfa_foundation.ml:440` verifies one known
target plus one TOP for mixed selection, no TOP for the pure-known control,
direct opaque invocation TOP, and no MUST. This repairs the demonstrated
FR-005/019/034/036 and AC-9 loss without adding call-return propagation.
The regression passed the real CHECK2 runner with its required assertion markers.

## Execution

Root personally executed build then CHECK1/2/3 serially: all exit0. CHECK1:
517cases. CHECK2: authentic fixture1/1. CHECK3 report:
`improvement/2026-09-15-ocaml-cfa/check3-1789558319040-472195.json`:
45054rows, canonical08f491da…, +1Irmin/+2protocol,0 losses/newMUST,
producer2f2d3f72…, wall2826.006122ms, sampled145188KiB, input/baseline stable.
All three pure-control scripts pass; explicit CHECK2 controls1/2/2/2 pass.
Fullsuite not repeated in this specialist pass: root implementation and owner
reviewer independently observed345/345 on this product; reviewer execution
artifact records unchanged source/five binaries. Formal QA still must run.

No new public API, persisted vocabulary or unspecified stage3/4 feature found.
Existing architecture advisories remain separate, not spec failures.
No DIVERGE/MISSING/UNTESTED finding identified in this round.
