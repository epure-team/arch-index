#!/usr/bin/env node
'use strict';
// Native admission controls; positioned rows are deliberately synthesized from
// real compiler traversal, not presented as producer/database measurements.
const fs=require('node:fs'),os=require('node:os'),path=require('node:path');
const cp=require('node:child_process'),assert=require('node:assert/strict');
const {probeRecords}=require('./run-probe.js');
const {loadWitness,fileSha256}=require('./witness.js');
const {compareSnapshots,ComparisonInputError}=require('./comparison.js');
const root=path.resolve(__dirname,'../..');
let temp;
try {
  temp=fs.mkdtempSync(path.join(os.tmpdir(),'arch-index-residual-witness-'));
  const source=path.join(temp,'native.ml');
  fs.writeFileSync(source,`module M = struct end
let wrapped = let open M in fun x -> if x > 0 then (fun y -> y) else (fun y -> y)
let run_mixed () = let _ = wrapped 1 in wrapped 1 2
let run_both () = wrapped 1 2 + wrapped 2 3
`);
  const local=fs.existsSync(path.join(root,'_opam'));
  const compile=cp.spawnSync(local?'opam':'ocamlc',
    [...(local?['exec',`--switch=${root}`,'--','ocamlc']:[]),'-bin-annot','-c',source],
    {cwd:temp,encoding:'utf8',timeout:120000});
  if(compile.error||compile.signal||compile.status!==0)
    throw new Error(`native compiler: ${compile.error||compile.signal||compile.stderr}`);
  const cmt=path.join(temp,'native.cmt'),records=probeRecords([cmt]),record=records[0];
  const evidence=path.join(temp,'evidence.json');
  fs.writeFileSync(evidence,JSON.stringify(records));
  const manifest={records:[['native',fileSha256(cmt),cmt]]};
  const provenance={reviewed_by:'native-regression-control',reviewed_at:'2026-09-14',
    source_evidence:'real compiler traversal; synthesized positioned admission controls, not database output'};
  function check(caller,residualHeads,expectedSupplied) {
    const apps=record.all_application_occurrences.filter(a=>
      a.classification==='eligible_unique'&&a.caller?.canonical_owner_name===caller);
    assert.equal(apps.length,2);
    assert.equal(apps[0].caller_site_head_group.occurrence_count,2);
    assert.deepEqual(apps.map(a=>a.supplied_some),expectedSupplied);
    assert.notEqual(apps[0].native_occurrence_index,apps[1].native_occurrence_index);
    const transitions=apps.map(a=>{
      const c=a.matching_identity_candidates[0],owner=a.caller;
      const file=a.application_loc.start.file,site=`${file}:${a.application_loc.start.line}`;
      assert.equal(c.root_function_arity,1);
      const before={caller_path:file,caller,call_site:site,target_path:null,target:null,
        callee_name:'wrapped',kind:'MAY_TOP',edge_form:null,top_reason:'callback_param',top_anchor:site,
        caller_line_start:owner.stored_owner_loc.start.line,caller_line_end:owner.stored_owner_loc.end.line,
        target_line_start:null,target_line_end:null};
      const target=`${c.binding_name}.<fun:${c.root_function_loc.start.line}:${c.root_function_loc.start.column+1}>`;
      const after={...before,target_path:file,target,callee_name:target,kind:'MAY_ENUMERATED',
        top_reason:null,top_anchor:null,target_line_start:c.root_function_loc.start.line,
        target_line_end:c.root_function_loc.end.line};
      return {...provenance,before,after,native:{cmt,occurrence_index:a.native_occurrence_index}};
    });
    assert.deepEqual(transitions[0].before,transitions[1].before,'indistinguishable stored heads');
    assert.deepEqual(transitions[0].after,transitions[1].after,'same canonical target rows');
    const residuals=residualHeads.map(head_index=>({...provenance,head_index,arity:1,
      arguments:apps[head_index].supplied_some,
      after:{...transitions[head_index].before,callee_name:'*TOP*'}}));
    const beforeRows=transitions.map(t=>t.before);
    const afterRows=[...transitions.map(t=>t.after),...residuals.map(r=>r.after)];
    const baseline={digest:'a'.repeat(64),rows:beforeRows,positioned_rows:beforeRows};
    const candidate={digest:'b'.repeat(64),rows:afterRows,positioned_rows:afterRows};
    const witness={schema_version:1,kind:'structural-open-body-invocation',
      baseline_digest:baseline.digest,candidate_digest:candidate.digest,evidence_file:evidence,
      evidence_sha256:fileSha256(evidence),probe_sha256:fileSha256(path.join(__dirname,'open-body-witness.ml')),
      transitions,residuals};
    const file=path.join(temp,'witness.json');fs.writeFileSync(file,JSON.stringify(witness));
    const approved=loadWitness(file,baseline,candidate,manifest);
    assert.equal(approved.residuals.length,residualHeads.length);
    return compareSnapshots(baseline,candidate,
      {approvedTransitions:approved.transitions,approvedResiduals:approved.residuals});
  }
  assert.equal(check('run_mixed',[1],[1,2]).ok,true,'one actual overapplied head');
  assert.equal(check('run_both',[0,1],[2,2]).ok,true,'two distinct overapplied heads retain two residuals');
  assert.throws(()=>check('run_mixed',[1,1],[1,2]),
    error=>error instanceof ComparisonInputError&&/residual head.*reused/.test(error.message),
    'one overapplied native occurrence cannot spend another identical head capacity');
  assert.throws(()=>check('run_both',[0,0],[2,2]),
    error=>error instanceof ComparisonInputError&&/residual head.*reused/.test(error.message),
    'even two overapplied heads must each supply their own residual witness');
  console.log('PASS residual witness: two genuine native positives; reused head refused twice');
} catch(error) {
  const assertion=error instanceof assert.AssertionError;
  console.error(`${assertion?'ASSERTION':'SETUP'}: ${error.message}`);
  process.exitCode=assertion?1:2;
} finally {if(temp)fs.rmSync(temp,{recursive:true,force:true});}
