#!/usr/bin/env node
'use strict';

const assert=require('node:assert/strict');
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
const cp=require('node:child_process');
const comparison=require('./comparison.js');
const {ComparisonInputError}=comparison;
const {probeRecords}=require('./run-probe.js');
const {validateNativePair,loadWitness,fileSha256}=require('./witness.js');

function main(){
  const root=path.resolve(__dirname,'../..');
  const evidence=path.join(root,'improvement/2026-09-14-tezos-resolution/attempt3-native-probe-script_interpreter.json');
  const records=JSON.parse(fs.readFileSync(evidence));
  const record=records[0], app=record.all_application_occurrences.find(x=>x.classification==='eligible_unique');
  assert.ok(app,'pinned native evidence has a genuine eligible occurrence');
  const c=app.matching_identity_candidates[0], caller=app.caller;
  const target=`${c.binding_name}.<fun:${c.root_function_loc.start.line}:${c.root_function_loc.start.column+1}>`;
  const callerName=caller.canonical_owner_name;
  const base={caller_path:app.head.head_loc.start.file,caller:callerName,
    call_site:`${app.application_loc.start.file}:${app.application_loc.start.line}`,
    target_path:null,target:null,callee_name:app.head.ident.name,kind:'MAY_TOP',edge_form:null,
    top_reason:'callback_param',top_anchor:`${app.application_loc.start.file}:${app.application_loc.start.line}`,
    caller_line_start:caller.stored_owner_loc.start.line,caller_line_end:caller.stored_owner_loc.end.line,
    target_line_start:null,target_line_end:null};
  const after={...base,target_path:base.caller_path,target,callee_name:target,kind:'MAY_ENUMERATED',
    top_reason:null,top_anchor:null,target_line_start:c.root_function_loc.start.line,target_line_end:c.root_function_loc.end.line};
  const native=validateNativePair(record,{native_occurrence_index:app.native_occurrence_index},base,after);
  assert.equal(native.syntactic_arity,c.root_function_arity);
  const refuse=(mutate,label)=>{const b=structuredClone(base),a=structuredClone(after),r=structuredClone(record);mutate(b,a,r);
    assert.throws(()=>validateNativePair(r,{native_occurrence_index:app.native_occurrence_index},b,a),ComparisonInputError,label);};
  refuse((b,a)=>{a.target='Raw.decoy.<fun:1:1>';a.callee_name=a.target;},'wrong body');
  refuse((b,a)=>{b.caller='foreign_homonym';a.caller=b.caller;},'wrong caller');
  refuse((b,a,r)=>{r.all_application_occurrences.find(x=>x.native_occurrence_index===app.native_occurrence_index).caller_owner_cardinality=2;},'ambiguous caller');
  refuse((b,a,r)=>{r.all_application_occurrences.find(x=>x.native_occurrence_index===app.native_occurrence_index).head.ident.unique_name='shadow';},'shadow binder');
  refuse((b)=>{b.callee_name='wrong_printed_head';},'wrong stored printed head');
  refuse((b,a,r)=>{r.all_application_occurrences.find(x=>x.native_occurrence_index===app.native_occurrence_index).caller_site_head_group.unambiguous=false;},'mixed group');
  refuse((b,a,r)=>{const x=r.all_application_occurrences.find(x=>x.native_occurrence_index===app.native_occurrence_index);
    x.application_loc.start.line--;},'stored site guessed from head rather than application');
  assert.match(fileSha256(record.cmt),/^[a-f0-9]{64}$/,'artifact has explicit SHA-256 distinct from probe MD5');
  const manifestFile=path.join(root,'roster/functor-instance-resolution/tezos-irmin-candidate/manifest-410.tsv');
  const manifest={records:fs.readFileSync(manifestFile,'utf8').split('\n').filter(x=>x&&!x.startsWith('#')).map(x=>x.split('\t'))};
  assert.ok(manifest.records.some(x=>x[2]===record.cmt),'genuine evidence artifact is fixed410-pinned');
  const baseline={digest:'a'.repeat(64),positioned_rows:[base]},candidate={digest:'b'.repeat(64),positioned_rows:[after]};
  const paired={schema_version:1,kind:'structural-open-body-invocation',baseline_digest:baseline.digest,
    candidate_digest:candidate.digest,evidence_file:evidence,evidence_sha256:fileSha256(evidence),
    probe_sha256:fileSha256(path.join(__dirname,'open-body-witness.ml')),transitions:[{before:base,after,
      native:{cmt:record.cmt,occurrence_index:app.native_occurrence_index},reviewed_by:'native-control',
      reviewed_at:'2026-09-14',source_evidence:'pinned compiler traversal'}],residuals:[]};
  const temp=fs.mkdtempSync(path.join(os.tmpdir(),'arch-index-open-body-witness-check-'));
  try {const witness=path.join(temp,'witness.json'),admit=value=>{fs.writeFileSync(witness,JSON.stringify(value));return loadWitness(witness,baseline,candidate,manifest);};
    assert.equal(admit(paired).transitions.length,1,'actual replay-backed admission is nonvacuous');
    for(const mutate of [w=>{w.probe_sha256='0'.repeat(64);},w=>{w.evidence_sha256='0'.repeat(64);},
      w=>{w.transitions[0].native.occurrence_index=999999;},
      w=>{w.transitions[0].reviewed_by='';}]) {const bad=structuredClone(paired);mutate(bad);assert.throws(()=>admit(bad),ComparisonInputError);}
    const reuse=structuredClone(paired);reuse.baseline_digest='c'.repeat(64);reuse.candidate_digest='d'.repeat(64);
    reuse.transitions.push(structuredClone(reuse.transitions[0]));
    fs.writeFileSync(witness,JSON.stringify(reuse));
    assert.throws(()=>loadWitness(witness,{digest:reuse.baseline_digest,positioned_rows:[base,base]},
      {digest:reuse.candidate_digest,positioned_rows:[after,after]},manifest),/native occurrence reused/,
    'reuse is refused after both positioned-row capacities are available');

    // A compiler-produced same-line duplicate group cannot be partially
    // discharged, even when its one supplied transition is otherwise genuine.
    const fixture=path.join(temp,'duplicate.ml');
    fs.writeFileSync(fixture,'module M = struct end\nlet step = let open M in fun x -> x\nlet caller () = step 1 + step 2\n');
    const compile=fs.existsSync(path.join(root,'_opam'))
      ? cp.spawnSync('opam',['exec',`--switch=${root}`,'--','ocamlc','-bin-annot','-c',fixture],{cwd:temp,encoding:'utf8'})
      : cp.spawnSync('ocamlc',['-bin-annot','-c',fixture],{cwd:temp,encoding:'utf8'});
    if(compile.error||compile.signal||compile.status!==0)throw new Error(compile.error?.message||compile.stderr||`fixture compiler ${compile.status}`);
    const cmt=path.join(temp,'duplicate.cmt'),duplicateRecord=probeRecords([cmt])[0];
    const duplicateApps=duplicateRecord.all_application_occurrences.filter(x=>x.classification==='eligible_unique');
    assert.equal(duplicateApps.length,2,'fixture has two genuine eligible native occurrences');
    assert.equal(duplicateApps[0].caller_site_head_group.occurrence_count,2,'fixture has a genuine indistinguishable printed-head group');
    const da=duplicateApps[0],dc=da.matching_identity_candidates[0],owner=da.caller;
    const duplicateSource=da.application_loc.start.file,duplicateSite=`${duplicateSource}:3`;
    const db={caller_path:duplicateSource,caller:owner.canonical_owner_name,call_site:duplicateSite,target_path:null,target:null,
      callee_name:'step',kind:'MAY_TOP',edge_form:null,top_reason:'callback_param',top_anchor:duplicateSite,
      caller_line_start:owner.stored_owner_loc.start.line,caller_line_end:owner.stored_owner_loc.end.line,target_line_start:null,target_line_end:null};
    const dt=`${dc.binding_name}.<fun:${dc.root_function_loc.start.line}:${dc.root_function_loc.start.column+1}>`,dd={...db,
      target_path:duplicateSource,target:dt,callee_name:dt,kind:'MAY_ENUMERATED',top_reason:null,top_anchor:null,
      target_line_start:dc.root_function_loc.start.line,target_line_end:dc.root_function_loc.end.line};
    const duplicateEvidence=path.join(temp,'duplicate-evidence.json');fs.writeFileSync(duplicateEvidence,JSON.stringify([duplicateRecord]));
    const partial={...paired,baseline_digest:'e'.repeat(64),candidate_digest:'f'.repeat(64),evidence_file:duplicateEvidence,
      evidence_sha256:fileSha256(duplicateEvidence),transitions:[{before:db,after:dd,native:{cmt,occurrence_index:da.native_occurrence_index},
        reviewed_by:'native-control',reviewed_at:'2026-09-14',source_evidence:'compiler duplicate fixture'}]};
    fs.writeFileSync(witness,JSON.stringify(partial));
    let partialError;try{loadWitness(witness,{digest:partial.baseline_digest,positioned_rows:[db]},
      {digest:partial.candidate_digest,positioned_rows:[dd]},{records:[['fixture',fileSha256(cmt),cmt]]});}catch(error){partialError=error;}
    assert.ok(partialError instanceof ComparisonInputError,'partial duplicate group is refused');
    assert.match(partialError.message,/insufficient exact capacity/);
  } finally {fs.rmSync(temp,{recursive:true,force:true});}
  // Exercise the real database-positioned candidate changes, not merely rows
  // synthesized from the native probe.  This includes the top-level
  // non-function structural binding at script_ir_translator.ml:6132, whose
  // enclosing binding and RHS membership are independently exposed by v2.
  const changes=JSON.parse(fs.readFileSync(path.join(root,
    'improvement/2026-09-14-tezos-resolution/attempt3-candidate-ytf29x/changes.json')));
  const canonical=row=>comparison.canonicalStrings([row])[0];
  const changedPositions=(rows,diff)=>{const counts=new Map();for(const row of diff)counts.set(canonical(row),(counts.get(canonical(row))||0)+1);
    return rows.filter(row=>{const key=canonical(row),n=counts.get(key)||0;if(!n)return false;counts.set(key,n-1);return true;});};
  const beforeRows=changedPositions(changes.before_positioned,changes.removed);
  const afterRows=changedPositions(changes.after_positioned,changes.added);
  const sourceFiles=[...new Set(beforeRows.map(row=>row.caller_path))];
  const cmtFiles=sourceFiles.map(sourceFile=>{const stem=path.basename(sourceFile,'.ml');
    const suffix=`__${stem[0].toUpperCase()}${stem.slice(1)}.cmt`;
    const hits=manifest.records.filter(record=>record[2].endsWith(suffix));assert.equal(hits.length,1,`one pinned CMT for ${sourceFile}`);return hits[0][2];});
  const bySource=new Map(probeRecords(cmtFiles).map(record=>[record.source,record]));
  let actualPass=0;const actualRefusals=[];
  for(const before of beforeRows){const record=bySource.get(before.caller_path),line=Number(before.call_site.slice(before.call_site.lastIndexOf(':')+1));
    const apps=record.all_application_occurrences.filter(item=>item.application_loc.start.line===line&&item.head?.ident?.name===before.callee_name);
    let accepted=0;for(const afterRow of afterRows.filter(row=>row.caller_path===before.caller_path&&row.caller===before.caller&&row.call_site===before.call_site))
      for(const nativeApp of apps)try{validateNativePair(record,{native_occurrence_index:nativeApp.native_occurrence_index},before,afterRow);accepted++;}
      catch(error){if(!(error instanceof ComparisonInputError))throw error;}
    if(accepted===1)actualPass++;else actualRefusals.push(`${before.call_site}:${before.caller}`);
  }
  assert.equal(actualPass,316,'all actual positioned database transitions have unique native proof');
  assert.deepEqual(actualRefusals,[],'no actual transition remains unsupported');
  const comparator=cp.spawnSync(process.execPath,[path.join(__dirname,'check-comparison.js')],{encoding:'utf8'});
  if (comparator.error || comparator.signal || comparator.status === null || comparator.status >= 2)
    throw new Error(comparator.error?.message || comparator.stderr || comparator.stdout);
  assert.equal(comparator.status,0,comparator.stderr||comparator.stdout);
  console.log('PASS open-body native witness inputs (316 actual DB pairs + genuine duplicate fixture; 13 negative controls)');
}
try{main();}catch(error){const assertion=error instanceof assert.AssertionError||error instanceof ComparisonInputError;
  process.stderr.write(`${assertion?'OPEN_BODY_WITNESS_ASSERTION':'OPEN_BODY_WITNESS_SETUP'}: ${error.message}\n`);process.exitCode=assertion?1:2;}
