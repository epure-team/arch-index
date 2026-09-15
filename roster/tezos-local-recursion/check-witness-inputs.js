#!/usr/bin/env node
'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),os=require('node:os'),path=require('node:path'),cp=require('node:child_process');
const {probeRecords}=require('./run-probe.js');
const {ComparisonInputError,fileSha256,validateNativePair,loadWitness}=require('./witness.js');
const root=path.resolve(__dirname,'../..');
function compile(temp,file){const args=['-bin-annot','-c',file];const result=fs.existsSync(path.join(root,'_opam'))
  ?cp.spawnSync('opam',['exec',`--switch=${root}`,'--','ocamlc',...args],{cwd:temp,encoding:'utf8'})
  :cp.spawnSync('ocamlc',args,{cwd:temp,encoding:'utf8'});
  if(result.error||result.signal||result.status!==0)throw Error(result.error?.message||result.stderr||`fixture compiler ${result.status}`);}
function rows(app){const rootOwner=app.matching_recursive_scope.actual_root,site=`${app.application_loc.start.file}:${app.application_loc.start.line}`;
  const base={caller_path:app.application_loc.start.file,caller:app.caller.name,call_site:site,target_path:null,target:null,
    callee_name:app.head.ident.name,kind:'MAY_TOP',edge_form:null,top_reason:'callback_param',top_anchor:site,
    caller_line_start:app.caller.loc.start.line,caller_line_end:app.caller.loc.end.line,target_line_start:null,target_line_end:null};
  const after={...base,target_path:base.caller_path,target:rootOwner.name,callee_name:rootOwner.name,kind:'MAY_ENUMERATED',top_reason:null,top_anchor:null,
    target_line_start:rootOwner.loc.start.line,target_line_end:rootOwner.loc.end.line};
  return {base,after,storage:{stored:true,callee_name:rootOwner.name,callee_path:base.caller_path,ordinal:rootOwner.allocation_ordinal}};}
function main(){const temp=fs.mkdtempSync(path.join(os.tmpdir(),'arch-index-recursive-witness-inputs-'));try{
  const source=path.join(temp,'fixture.ml');fs.writeFileSync(source,`let outer n = let rec aux x = if x=0 then 0 else aux (x-1) in aux n\nlet over n = let rec aux x = if x=0 then (fun y -> y) else (fun y -> (aux (x-1) y) + (aux (x-1) y)) in aux n 1\n`);compile(temp,source);
  const cmt=path.join(temp,'fixture.cmt'),record=probeRecords([cmt])[0],apps=record.all_application_occurrences.filter(a=>a.classification==='native_self_head_requires_storage_confirmation');
  assert.ok(apps.length>=3,'genuine compiled fixture has ordinary and two overapplied native self heads');
  const ordinary=apps.find(a=>a.supplied_some===a.root_syntactic_arity),overs=apps.filter(a=>a.supplied_some>a.root_syntactic_arity);
  assert.equal(overs.length,2,'two genuine native overapplied heads exist');assert.ok(ordinary,'genuine ordinary native self head exists');
  const selected=[ordinary,...overs],triples=selected.map(rows);triples.forEach(x=>{x.storage.cmt=cmt;});for(let i=0;i<selected.length;i++)validateNativePair(record,{native_occurrence_index:selected[i].native_occurrence_index,storage:triples[i].storage},triples[i].base,triples[i].after);
  const evidence=path.join(temp,'evidence.json');fs.writeFileSync(evidence,JSON.stringify([record]));const baseline={digest:'a'.repeat(64),positioned_rows:triples.map(x=>x.base)};
  const residuals=overs.map((app,i)=>({native:{cmt,occurrence_index:app.native_occurrence_index},arity:app.root_syntactic_arity,arguments:app.supplied_some,after:{...triples[i+1].base,callee_name:'*TOP*',target:null,target_path:null,kind:'MAY_TOP',top_reason:'callback_param',top_anchor:triples[i+1].base.call_site}}));
  const candidate={digest:'b'.repeat(64),positioned_rows:[...triples.map(x=>x.after),...residuals.map(x=>x.after)]};
  const witness={schema_version:'local-recursive-witness-v1',baseline_digest:baseline.digest,candidate_digest:candidate.digest,evidence_file:evidence,evidence_sha256:fileSha256(evidence),probe_sha256:fileSha256(path.join(__dirname,'recursive-witness.ml')),
    transitions:selected.map((app,i)=>({before:triples[i].base,after:triples[i].after,native:{cmt,occurrence_index:app.native_occurrence_index,storage:triples[i].storage},reviewed_by:'native-control',reviewed_at:'2026-09-15'})),residuals};
  const witnessFile=path.join(temp,'witness.json'),manifest={records:[['fixture',fileSha256(cmt),cmt]]};fs.writeFileSync(witnessFile,JSON.stringify(witness));assert.deepEqual(loadWitness(witnessFile,baseline,candidate,manifest),{transitions:witness.transitions.map(t=>({before:t.before,after:t.after})),residuals:residuals.map((r,i)=>({after:r.after,head:{before:witness.transitions[i+1].before,after:witness.transitions[i+1].after},arity:r.arity,arguments:r.arguments})),sha256:fileSha256(witnessFile),head_capacity:witness.transitions.map(t=>`${cmt}#${t.native.occurrence_index}`),residual_capacity:residuals.map(r=>`${cmt}#${r.native.occurrence_index}`)});
  const reject=(mutate,label)=>{const bad=structuredClone(witness);mutate(bad);fs.writeFileSync(witnessFile,JSON.stringify(bad));assert.throws(()=>loadWitness(witnessFile,baseline,candidate,manifest),ComparisonInputError,label);};
  const rejectNative=(mutate,label)=>{const bad=structuredClone(record),app=bad.all_application_occurrences.find(a=>a.native_occurrence_index===ordinary.native_occurrence_index),pair=structuredClone(triples[0]);mutate(bad,app,pair);assert.throws(()=>validateNativePair(bad,{native_occurrence_index:ordinary.native_occurrence_index,storage:pair.storage},pair.base,pair.after),ComparisonInputError,label);};
  /* Each mutation comes from the genuine compiler-produced record above; these
     are not synthetic positive identities. */
  rejectNative((r,a)=>{a.head.ident.unique_name='forged-binder';},'wrong binder');
  rejectNative((r,a)=>{a.matching_recursive_scope.group_size=2;},'wrong singleton group');
  rejectNative((r,a)=>{a.matching_recursive_scope.actual_root.name='forged.<fun:1:1>';},'wrong physical root');
  rejectNative((r,a)=>{a.matching_recursive_scope.actual_root.allocation_ordinal++;},'wrong native ordinal');
  rejectNative((r,a)=>{a.caller.name='foreign_caller';},'wrong caller owner');
  rejectNative((r,a)=>{a.caller.native_owner_index=999999;},'unknown caller owner');
  rejectNative((r,a)=>{a.caller.loc={start:{file:'_none_',line:0,column:-1},end:{file:'_none_',line:0,column:-1},start_offset:-1,end_offset:-1,ghost:true};},'none caller owner');
  rejectNative((r,a,p)=>{p.after.target_line_end++;},'wrong full target range');
  rejectNative((r,a)=>{a.root_syntactic_arity++;},'wrong syntactic arity');
  rejectNative((r,a)=>{a.supplied_some++;},'wrong supplied-Some count');
  rejectNative((r,a)=>{a.caller_site_group.unambiguous=false;},'mixed ambiguous printed-head group');
  reject(w=>{w.transitions[0].native.storage.ordinal++;},'wrong ordinal');reject(w=>{w.transitions[0].after.target='guessed.<fun:1:1>';w.transitions[0].after.callee_name=w.transitions[0].after.target;},'guessed root');reject(w=>{w.transitions.push(structuredClone(w.transitions[1]));},'head reuse');reject(w=>{w.residuals[1].native.occurrence_index=w.residuals[0].native.occurrence_index;},'residual reuse');reject(w=>{w.probe_sha256='0'.repeat(64);},'probe provenance');
  reject(w=>{w.transitions.pop();},'same-line group partial capacity');reject(w=>{w.transitions[0].after.kind='MUST';},'new MUST');
  const wrongManifest={records:[['fixture','0'.repeat(64),cmt]]};fs.writeFileSync(witnessFile,JSON.stringify(witness));assert.throws(()=>loadWitness(witnessFile,baseline,candidate,wrongManifest),ComparisonInputError,'wrong artifact hash');
  const rejectEvidence=(mutate,label)=>{const bad=structuredClone(witness),records=structuredClone([record]);mutate(records);fs.writeFileSync(evidence,JSON.stringify(records));bad.evidence_sha256=fileSha256(evidence);fs.writeFileSync(witnessFile,JSON.stringify(bad));assert.throws(()=>loadWitness(witnessFile,baseline,candidate,manifest),ComparisonInputError,label);fs.writeFileSync(evidence,JSON.stringify([record]));};
  rejectEvidence(records=>{records[0].all_application_occurrences.find(a=>a.native_occurrence_index===ordinary.native_occurrence_index).classification='native_self_head_requires_storage_confirmation_forged';},'forged evidence replay');
  rejectEvidence(records=>{records.push(structuredClone(records[0]));},'duplicate CMT evidence');
  console.log('PASS recursive native witness inputs (genuine CMT, two overapplied heads, independent head/residual reuse refusals)');
}finally{fs.rmSync(temp,{recursive:true,force:true});}}
try{main();}catch(error){const assertion=error instanceof assert.AssertionError;console.error(`${assertion?'RECURSIVE_WITNESS_ASSERTION':'RECURSIVE_WITNESS_SETUP'}: ${error.stack||error}`);process.exitCode=assertion?1:2;}
