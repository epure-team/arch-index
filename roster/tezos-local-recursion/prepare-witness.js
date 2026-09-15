#!/usr/bin/env node
'use strict';
/* Mechanical draft preparation only.  This never runs a producer or a native
   probe: it turns an already-pinned candidate delta plus CMT evidence into a
   review-required witness, or refuses. */
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const b=require('./baseline.js');
const {ComparisonInputError,canonicalStrings}=require('./comparison.js');
const {fileSha256,positionKey,validateNativePair}=require('./witness.js');
const fail=message=>{throw new ComparisonInputError(`prepare recursive witness: ${message}`);};
const readJson=file=>{try{return JSON.parse(fs.readFileSync(file,'utf8'));}catch(error){fail(`${path.basename(file)}: ${error.message}`);}};
const sha256=value=>crypto.createHash('sha256').update(value).digest('hex');
const validDigest=value=>typeof value==='string'&&/^[a-f0-9]{64}$/.test(value);
const canonicalKey=row=>canonicalStrings([row])[0];
const exact=(rows,row)=>rows.positions.get(positionKey(row))||[];
function positionedDelta(canonicalRows,positionedRows,label){
  if(!Array.isArray(canonicalRows)||!Array.isArray(positionedRows))fail(`${label} delta/positioned arrays required`);
  const counts=new Map(),positions=new Map();
  for(const row of canonicalRows){const key=canonicalKey(row);counts.set(key,(counts.get(key)||0)+1);}
  for(const row of positionedRows){const canonical=canonicalKey(row);if(!counts.has(canonical))continue;
    const key=positionKey(row),values=positions.get(key)||[];values.push(row);positions.set(key,values);}
  return {counts,positions};
}
function take(rows,row,label){
  const canonical=canonicalKey(row),available=rows.counts.get(canonical)||0,values=exact(rows,row);
  if(available<1||values.length===0)fail(`${label} lacks exact canonical-to-positioned capacity`);
  rows.counts.set(canonical,available-1);return values.shift();
}
const remaining=rows=>[...rows.counts.values()].reduce((n,count)=>n+count,0);
function nativeBefore(app){const site=`${app.application_loc.start.file}:${app.application_loc.start.line}`,caller=app.caller.loc;
  return {caller_path:app.application_loc.start.file,caller:app.caller.name,call_site:site,target_path:null,target:null,
    callee_name:app.head.ident.name,kind:'MAY_TOP',edge_form:null,top_reason:'callback_param',top_anchor:site,
    caller_line_start:caller.start.line,caller_line_end:caller.end.line,target_line_start:null,target_line_end:null};}
function nativeAfter(app){const before=nativeBefore(app),root=app.matching_recursive_scope.actual_root;
  return {...before,target_path:before.caller_path,target:root.name,callee_name:root.name,kind:'MAY_ENUMERATED',
    top_reason:null,top_anchor:null,target_line_start:root.loc.start.line,target_line_end:root.loc.end.line};}
function residualAfter(app){const before=nativeBefore(app);
  return {...before,callee_name:'*TOP*'};}
function storage(record,app){const root=app.matching_recursive_scope.actual_root;return {stored:true,cmt:record.cmt,
  callee_name:root.name,callee_path:app.application_loc.start.file,ordinal:root.allocation_ordinal};}
function validateCandidate(candidate,manifest){
  const files=['changes.json','provenance.json','report.json'].map(name=>path.join(candidate,name));
  if(files.some(file=>!fs.existsSync(file)))fail('candidate changes/provenance/report files required');
  const [changes,provenance,report]=files.map(readJson);
  if(!changes||!Array.isArray(changes.removed)||!Array.isArray(changes.added)
    ||!Array.isArray(changes.before_positioned)||!Array.isArray(changes.after_positioned))fail('candidate change arrays required');
  if(!provenance||!validDigest(provenance.baseline_digest)||!validDigest(provenance.candidate_digest)
    ||!validDigest(provenance.producer_sha256)||!validDigest(provenance.schema_sha256)
    ||provenance.baseline_provenance_sha256!==b.PROVENANCE_SHA256
    ||provenance.manifest_sha256!==b.EXPECTED.manifestSha256||provenance.selected!==manifest.records.length
    ||provenance.source_status_unchanged!==true||provenance.input_hashes_unchanged!==true
    ||!provenance.state||typeof provenance.state!=='object'||Array.isArray(provenance.state))fail('candidate provenance shape/bindings refused');
  const frozen=b.loadFrozen(),old=b.frozenSnapshot(frozen,manifest);
  if(provenance.baseline_digest!==old.digest||provenance.producer_sha256!==fileSha256(b.CURRENT_PRODUCER)
    ||provenance.schema_sha256!==b.EXPECTED.schemaSha256||fileSha256(b.CURRENT_SCHEMA)!==b.EXPECTED.schemaSha256)
    fail('candidate provenance is not bound to frozen/current authoritative inputs');
  if(!report||report.baseline_digest!==old.digest||report.candidate_digest!==provenance.candidate_digest
    ||typeof report.verdict!=='string')fail('candidate report provenance refused');
  return {changes,provenance};
}
function validateNative(records,manifest){
  if(!Array.isArray(records)||records.length!==410)fail('exact410 native evidence must contain exactly 410 records');
  const pins=new Map();
  for(const entry of manifest.records||[]){if(!Array.isArray(entry)||entry.length!==3||pins.has(entry[2]))fail('malformed fixed410 manifest');pins.set(entry[2],entry[1]);}
  if(pins.size!==410)fail('fixed410 manifest cardinality mismatch');
  const seen=new Set();
  for(const record of records){
    if(!record||typeof record.cmt!=='string'||seen.has(record.cmt)||!pins.has(record.cmt)
      ||fileSha256(record.cmt)!==pins.get(record.cmt)||record.artifact_digest_algorithm!=='md5'
      ||crypto.createHash('md5').update(fs.readFileSync(record.cmt)).digest('hex')!==record.artifact_digest)fail('native evidence is not exact fixed410 CMT evidence');
    seen.add(record.cmt);
  } if(seen.size!==pins.size||[...pins.keys()].some(cmt=>!seen.has(cmt)))fail('native evidence does not cover every exact410 CMT');
}
function prepare(candidate,nativeFile,output){
  if(!path.isAbsolute(candidate)||!path.isAbsolute(nativeFile)||!path.isAbsolute(output))fail('all paths must be absolute');
  if(path.basename(nativeFile)!=='attempt4-native-410.json')fail('native evidence must be attempt4-native-410.json');
  const ownedOutputRoot=path.join(b.ROOT,'improvement','2026-09-14-tezos-resolution');
  if(path.relative(ownedOutputRoot,output).startsWith('..')||path.relative(ownedOutputRoot,output)===''
    ||!/draft/i.test(path.basename(output))||/reviewed/i.test(path.basename(output))||fs.existsSync(output)
    ||fs.existsSync(`${output}.report.json`))fail('output must be a new draft filename (never reviewed or overwritten)');
  const stateBefore=b.state(),stateBeforeSha256=sha256(JSON.stringify(stateBefore));
  const manifest=b.readManifest({expected:b.EXPECTED}),{changes,provenance}=validateCandidate(candidate,manifest);
  const evidence=readJson(nativeFile);validateNative(evidence,manifest);
  const removed=positionedDelta(changes.removed,changes.before_positioned,'removed');
  const added=positionedDelta(changes.added,changes.after_positioned,'added');
  const transitions=[],residuals=[],seenHeads=new Set();
  const groups=[];
  for(const record of evidence)for(const app of record.all_application_occurrences||[])
    if(app.classification==='native_self_head_requires_storage_confirmation')groups.push({record,app});
  for(const {record,app} of groups){
    const before=nativeBefore(app),after=nativeAfter(app),hasBefore=(removed.counts.get(canonicalKey(before))||0)>0&&exact(removed,before).length>0,
      hasAfter=(added.counts.get(canonicalKey(after))||0)>0&&exact(added,after).length>0;
    if(hasBefore!==hasAfter)fail('native positioned transition is only half present');
    if(!hasBefore)continue;
    const stored=storage(record,app),locator={cmt:record.cmt,occurrence_index:app.native_occurrence_index,storage:stored};
    validateNativePair(record,{native_occurrence_index:locator.occurrence_index,storage:stored},before,after);
    const key=`${record.cmt}#${app.native_occurrence_index}`;
    if(seenHeads.has(key))fail('native occurrence reused while preparing draft');
    transitions.push({before:take(removed,before,'removed'),after:take(added,after,'added'),native:locator,
      reviewed_by:'mechanical-draft-NOT-human-review',reviewed_at:new Date().toISOString()});seenHeads.add(key);
  }
  /* validateNativePair establishes group membership.  A partial changed group
     cannot become a draft because the final witness would be rejected too. */
  for(const transition of transitions){const record=evidence.find(x=>x.cmt===transition.native.cmt);
    const app=record.all_application_occurrences.find(x=>x.native_occurrence_index===transition.native.occurrence_index);
    for(const index of app.caller_site_group.member_occurrence_indices)if(!seenHeads.has(`${record.cmt}#${index}`))fail('same-site printed-head group is only partially changed');
    if(app.supplied_some>app.root_syntactic_arity&&(added.counts.get(canonicalKey(residualAfter(app)))||0)>0&&exact(added,residualAfter(app)).length>0){
      residuals.push({native:{cmt:record.cmt,occurrence_index:app.native_occurrence_index},arity:app.root_syntactic_arity,
        arguments:app.supplied_some,after:take(added,residualAfter(app),'overapplication residual')});
    }
  }
  const leftovers=remaining(removed)+remaining(added);if(leftovers)fail(`unapproved candidate delta rows remain: ${leftovers}`);
  const witness={schema_version:'local-recursive-witness-v1',baseline_digest:provenance.baseline_digest,
    candidate_digest:provenance.candidate_digest,evidence_file:nativeFile,evidence_sha256:fileSha256(nativeFile),
    probe_sha256:fileSha256(path.join(__dirname,'recursive-witness.ml')),transitions,residuals};
  const stateAfter=b.state(),stateAfterSha256=sha256(JSON.stringify(stateAfter));
  if(stateBeforeSha256!==stateAfterSha256)fail('repository state changed during mechanical draft preparation');
  const report={review_required:true,kind:'mechanical-draft-NOT-human-review',draft_witness:output,
    candidate_directory:candidate,native_evidence:nativeFile,native_evidence_sha256:fileSha256(nativeFile),
    transition_count:transitions.length,residual_count:residuals.length,state_before_sha256:stateBeforeSha256,state_after_sha256:stateAfterSha256};
  fs.writeFileSync(output,JSON.stringify(witness,null,2)+'\n',{flag:'wx'});
  fs.writeFileSync(`${output}.report.json`,JSON.stringify(report,null,2)+'\n',{flag:'wx'});
  return report;
}
if(require.main===module){try{if(process.argv.length!==5)fail('usage: prepare-witness.js CANDIDATE_DIR ATTEMPT4_NATIVE_410_JSON OUTPUT_DRAFT');
  console.log(JSON.stringify(prepare(...process.argv.slice(2).map(value=>path.resolve(value))),null,2));
}catch(error){console.error(`PREPARE_WITNESS_REFUSED: ${error.stack||error}`);process.exitCode=2;}}
module.exports={prepare};
