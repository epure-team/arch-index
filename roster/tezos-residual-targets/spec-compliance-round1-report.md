---
auditor: spec-compliance-auditor
date: 2026-09-14
status: 1 critical OPEN; review execution incomplete
coverage: full source review; independent required gate execution partial
---

# Round 1 / cycle 1 — preliminary specification review

Reviewed HEAD `975c73b49def2813517b00c296006417d062d8b2` against `fb9c8f3`. Embedded specialist report adapted to the task directory because KB is absent. Read the complete feature contract, spec-input/resolutions, reviewer/implementer/QA briefs, implementation evidence, changed product/test/helper files and imported comparison implementation. Source is the frozen feature contract, not a generated projection; identifiers below are its local IDs. Claims metadata is draft.

No GO or completed review is asserted. Root requested immediate recording of this native finding and explicitly paused the old-head full suite for repair. Required full guards and CHECK-1..5 must be executed independently on the repaired head before final classification.

## Actual execution

- Local-switch `dune build --root .`: exit0.
- Native compiled old/current flat comparison: setup succeeds, six observed legacy rows on each side; equality assertion exits1. Three b.ml rows change a.ml -> NULL; the three a.ml positive controls are unchanged. Tool session44653, final chunk7df57b.
- Separate native pending-metadata probe: exit0. With context both disabled/enabled, direct_run remains Head_local (probe's other), unknown_run remains callback_param, bare_callback's root_body remains Head_enumerated; partial=false/form=NULL throughout. Chunk a4b9aa.
- Full suite, bundle, whitespace and five standalone checks: not yet executed by this specialist. Owner results are not substituted for personal execution.

## Critical — OPEN

Invocation ownership leaks into unchanged unqualified and parameter flat calls.

Location: `lib/arch_index/call_graph_extractor.ml:348`. Claims: FR-007 / AC-5, C-5's instruction that existing semantics remain unchanged except the explicitly supported invocation target.

The new `local_invocation_names` set records a target name whenever a qualifying alias names it. The flat loop applies this set to every ordinary row with that displayed name. Thus `Bridge.alias = root_body` changes attribution for direct `root_body 3`, a parameter named root_body, and `List.map root_body xs`, even though these occurrences are outside the supported qualified-alias extension. The native witness demonstrates the change; it is not a hypothetical missing test. This follows the skill's CRITICAL mapping for DIVERGE, not a claim of a security exploit.

Repair: Carry occurrence-level owned-target provenance from the collector to the flat consumer and apply the new alias attribution only to supported qualified invocation occurrences. Preserve legacy direct, parameter and bare-callback rows and existing point-free behavior; add the native three-form regression controls. A Head_enumerated-only guard is insufficient because bare local callbacks have that head too.

## Compliance matrix

PENDING below means source inspected and relevant tests located, but required independent execution is outstanding; it is not PASS or a claim that implementation is missing.

| Claim | Status | Location | Test | Assessment |
|---|---|---|---|---|
| FR-001 | PENDING | arch_index_cmt.ml:1596,2174,2281 | CHECK-1 | Applied/callback/letop lookup is wired; execution pending. |
| FR-002 | PENDING | arch_index_cmt.ml:1030,1053 | CHECK-1 | Owner masks and plain bare arrow Pident guards inspected. |
| FR-003 | PENDING | arch_index_cmt.ml:1066,1133; check-witness.js:172 | CHECK-1/2 | Same-CMT Ident ownership; UID disagreement admission inspected. |
| FR-004 | PENDING | arch_index_cmt.ml:974,1052 | CHECK-1 | Stored ordinal body and source-order export masks. |
| FR-005 | PENDING | arch_index_cmt.ml:2282 | CHECK-1 | Enumerated head and existing rejected-body path. |
| FR-006 | PENDING | arch_index_cmt.ml:2203,2233,2327 | CHECK-1 | Some arguments and body syntactic arity; existing residual form. |
| FR-007 | DIVERGE | call_graph_extractor.ml:348 | Independent native RED | New all-name ownership changes legacy direct/parameter/bare-callback flat attribution. |
| FR-008 | PENDING | call_graph_extractor.ml:357 | CHECK-1 | Supported alias target same-file positive/absent symbol check inspected. |
| FR-009 | PENDING | baseline.js:24,124 | CHECK-3 | Exact predecessor pins and immutable distinct record inspected. |
| FR-010 | PENDING | prepare-baseline.js:30; baseline.js:101 | CHECK-3 | Pre-product neutral evidence read; fresh independent replay pending. |
| FR-011 | PENDING | witness.js:25; comparison.js:6 | CHECK-2/4 | Only ordinary same-site module_param-to-body pairs. |
| FR-012 | PENDING | witness.js:52; check-witness.js:131 | CHECK-2/4 | Native replay, positioned membership, unique locator consumption. |
| FR-013 | PENDING | witness.js:100; comparison.js:9 | CHECK-2/4 | Residual premise and unchanged point-free multiset checks. |
| FR-014 | PENDING | ../tezos-call-resolution/comparison.js:151 | CHECK-2/4 | Loss/new MUST/unconsumed rejection and partitioned tuple gains. |
| FR-015 | PENDING | check-native.js:120; verify.js:125 | CHECK-1/2 | Assertion/setup exit mapping inspected; native RED is actual assertion1. |
| FR-016 | PENDING | arch_index_cmt.ml:974 | CHECK-1 | Body-only table unchanged; aliases excluded. |
| FR-017 | PENDING DELIVERY | verify.js:101; reviewer.md | CHECK-4/5 + delivery | retention_authorized false; review/QA/exact-head CI/merge not completed. |

| Claim | Status | Check | Assessment |
|---|---|---|---|
| AC-1 | PENDING | CHECK-1 | Exact same-file enumerated targets. |
| AC-2 | PENDING | CHECK-1/2 | Eligibility/identity/refusal controls. |
| AC-3 | PENDING | CHECK-1 | Original ordinal target and masking. |
| AC-4 | PENDING | CHECK-1 | Pending label/hidden-arrow and residual checks. |
| AC-5 | DIVERGE | Independent native RED | Legacy bare callback attribution changes beyond supported invocation target. |
| AC-6 | PENDING | CHECK-1 | Dropped target and flat missing-symbol checks. |
| AC-7 | PENDING | CHECK-3 | Fresh pinned predecessor/replay. |
| AC-8 | PENDING | CHECK-2/4 | Witness multiplicity, heads/returns, separate gains. |
| AC-9 | PENDING | CHECK-2/3/4 | Input/provenance/witness and exit classification. |
| AC-10 | PENDING | CHECK-2/4 | Forbidden multiset changes. |
| AC-11 | PENDING | CHECK-1 | Body-table/unqualified alias-call unchanged. |
| AC-12 | PENDING DELIVERY | CHECK-4 + delivery | No keep claimed; no review/QA/CI/merge PASS inferred. |
| AC-13 | PENDING | CHECK-5 | Exact self golden. |

| Check | Status | Command |
|---|---|---|
| CHECK-1 | PENDING | node roster/tezos-residual-targets/check-native.js |
| CHECK-2 | PENDING | node roster/tezos-residual-targets/check-comparison.js |
| CHECK-3 | PENDING | node roster/tezos-residual-targets/prepare-baseline.js --check |
| CHECK-4 | PENDING | node roster/tezos-residual-targets/verify.js --witness improvement/2026-09-14-tezos-resolution/attempt2-reviewed-witness.json |
| CHECK-5 | PENDING | node roster/tezos-call-resolution/check-self-index-smoke.js |

## Reproduction

This uses the existing forced-flat harness in memory, compiles native fixtures and both extractor implementations in owned temporary directories, and deletes only those temporary directories. No repository file is changed. Both extractor variants link to the same current collector to isolate the new flat attribution policy. The separate pending probe confirms legacy collector heads do not change.

```sh
rtk proxy node <<'NODE'
const fs=require('fs'),vm=require('vm'),path=require('path'),assert=require('assert/strict');
const filename=path.resolve('roster/tezos-residual-targets/check-flat.js');
let script=fs.readFileSync(filename,'utf8');
script=script.replace('let root_run () = Bridge.alias 3\n','let root_run () = Bridge.alias 3\nlet direct_run () = root_body 3\nlet unknown_run root_body = root_body 3\nlet bare_callback xs = List.map root_body xs\n');
const start=script.indexOf("  const actual = rows.filter"),end=script.indexOf('\n} catch (error)',start);
script=script.slice(0,start)+"  console.log(JSON.stringify(rows.filter(r => ['direct_run','unknown_run','bare_callback'].includes(r.caller) && r.callee === 'root_body')));"+script.slice(end);
const legacy=script.replace("fs.copyFileSync(path.join(root, 'lib/arch_index/call_graph_extractor.ml'),\n    path.join(temporary, 'call_graph_extractor.ml'));", "fs.writeFileSync(path.join(temporary, 'call_graph_extractor.ml'), cp.execFileSync('git',['show','fb9c8f3:lib/arch_index/call_graph_extractor.ml'],{cwd:root}));");
function execute(source){let output=[];const proc={argv:['node',filename],exitCode:0,stderr:process.stderr};vm.runInNewContext(source,{require:require('module').createRequire(filename),__dirname:path.dirname(filename),process:proc,console:{log:x=>output.push(x)}},{filename});assert.equal(proc.exitCode,0,'native diagnostic setup');return JSON.parse(output[0]);}
const before=execute(legacy),after=execute(script);
console.log(JSON.stringify({before,after},null,2));
assert.equal(before.length,6);assert.equal(after.length,6);
assert.deepEqual(after,before,'legacy direct, parameter and callback flat facts must remain unchanged');
NODE
```

## Unspecified behavior and delivery limits

The flat widening above is the only confirmed extra behavior so far. The invocation API and separate consumer lookup are otherwise within the feature contract. No formatter/coverage, claims projection, hosted CI, QA or merge success is asserted. Seven pre-task unrelated paths remain outside this review's write scope. Native control cleanup completed; no worktree was created.
