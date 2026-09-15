'use strict';
const fs=require('node:fs');
const path=require('node:path');
const crypto=require('node:crypto');
const {ComparisonInputError}=require('./comparison.js');
const {probeRecords}=require('./run-probe.js');

const fileSha256=file=>crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const stable=value=>{
  if(Array.isArray(value))return `[${value.map(stable).join(',')}]`;
  if(value&&typeof value==='object')return `{${Object.keys(value).sort().map(k=>`${JSON.stringify(k)}:${stable(value[k])}`).join(',')}}`;
  return JSON.stringify(value);
};
const positionKey=row=>stable({caller_path:row?.caller_path,caller:row?.caller,call_site:row?.call_site,
  target_path:row?.target_path,target:row?.target,callee_name:row?.callee_name,kind:row?.kind,
  edge_form:row?.edge_form,top_reason:row?.top_reason,top_anchor:row?.top_anchor,
  caller_line_start:row?.caller_line_start,caller_line_end:row?.caller_line_end,
  target_line_start:row?.target_line_start,target_line_end:row?.target_line_end});
const fail=message=>{throw new ComparisonInputError(message);};
function validLoc(loc){return !!(loc&&typeof loc==='object'&&Number.isInteger(loc.start_offset)
  &&Number.isInteger(loc.end_offset)&&loc.start_offset>=0&&loc.end_offset>=loc.start_offset
  &&loc.start&&loc.end&&typeof loc.start.file==='string'&&loc.start.file.length>0
  &&loc.start.file===loc.end.file&&Number.isInteger(loc.start.line)&&Number.isInteger(loc.end.line)
  &&Number.isInteger(loc.start.column)&&Number.isInteger(loc.end.column));}
/* Compiler-generated owners can legitimately carry [Location.none].  It is
   accepted only while checking that a complete record is well-formed; every
   location which authorizes a recursive transition still goes through
   [validLoc] below and must be an ordinary source range. */
function compilerNoneLoc(loc){return !!(loc&&typeof loc==='object'&&loc.ghost===true
  &&loc.start_offset===-1&&loc.end_offset===-1&&loc.start&&loc.end
  &&loc.start.file==='_none_'&&loc.end.file==='_none_'&&loc.start.line===0&&loc.end.line===0
  &&loc.start.column===-1&&loc.end.column===-1);}
const contains=(outer,inner)=>validLoc(outer)&&validLoc(inner)&&outer.start.file===inner.start.file
  &&outer.start_offset<=inner.start_offset&&inner.end_offset<=outer.end_offset;
const sameLoc=(a,b)=>validLoc(a)&&validLoc(b)&&a.start.file===b.start.file&&a.end.file===b.end.file
  &&a.start_offset===b.start_offset&&a.end_offset===b.end_offset;
const canonicalRootName=root=>root.allocation_ordinal===1?`${root.allocation_base}>`:`${root.allocation_base}#${root.allocation_ordinal}>`;
function validateRecord(record){
  if(!record||record.schema_version!=='recursive-witness-v1'||record.artifact_digest_algorithm!=='md5'
    ||!/^[a-f0-9]{32}$/.test(record.artifact_digest||'')||!path.isAbsolute(record.cmt||'')
    ||!Array.isArray(record.native_function_owners)||!Array.isArray(record.all_application_occurrences))fail('malformed native probe record');
  const ownerIds=new Set(),appIds=new Set();
  for(const owner of record.native_function_owners){
    if(!Number.isInteger(owner?.native_owner_index)||ownerIds.has(owner.native_owner_index)||typeof owner.name!=='string'
      ||!owner.name||typeof owner.kind!=='string'||(!validLoc(owner.loc)&&!compilerNoneLoc(owner.loc)))fail('malformed or duplicate native owner');
    ownerIds.add(owner.native_owner_index);
  }
  for(const app of record.all_application_occurrences){
    if(!Number.isInteger(app?.native_occurrence_index)||appIds.has(app.native_occurrence_index)
      ||(!validLoc(app.application_loc)&&!compilerNoneLoc(app.application_loc)))fail('malformed or duplicate native occurrence');
    appIds.add(app.native_occurrence_index);
  }
}
function locate(record,locator){
  validateRecord(record);
  if(!locator||!Number.isInteger(locator.native_occurrence_index))fail('native occurrence index required');
  const app=(record.all_application_occurrences||[]).find(x=>x.native_occurrence_index===locator.native_occurrence_index);
  if(!app)fail('native occurrence missing');
  return app;
}
function appSite(app){return `${app.application_loc.start.file}:${app.application_loc.start.line}`;}
function validateNativePair(record,locator,before,after){
  const app=locate(record,locator),scope=app.matching_recursive_scope,root=scope?.actual_root;
  if(app.classification!=='native_self_head_requires_storage_confirmation')fail('native occurrence is not an admitted singleton self-head');
  if(!scope||scope.group_size!==1||scope.direct_tfunction_rhs!==true)fail('singleton direct-function evidence missing');
  if(!root||scope.root_observation_count!==1||root.kind!=='recursive_root_literal'||!validLoc(scope.rhs_loc)
    ||!validLoc(root.loc)||!sameLoc(scope.rhs_loc,root.loc)
    ||!contains(scope.binding_loc,scope.rhs_loc))fail('unique physical root observation missing');
  if(!Number.isInteger(root.native_owner_index)||!Number.isInteger(root.allocation_ordinal)||root.allocation_ordinal<1
    ||typeof root.allocation_base!=='string'||!root.allocation_base.includes('<fun:')||root.name!==canonicalRootName(root))fail('actual root allocation evidence missing');
  const roots=record.native_function_owners.filter(owner=>owner.native_owner_index===root.native_owner_index);
  if(roots.length!==1||roots[0].kind!=='recursive_root_literal'||roots[0].name!==root.name
    ||!sameLoc(roots[0].loc,root.loc)||roots[0].allocation_base!==root.allocation_base
    ||roots[0].allocation_ordinal!==root.allocation_ordinal)fail('actual root owner link mismatch');
  const group=app.caller_site_group;
  if(!group||group.unambiguous!==true||!Array.isArray(group.member_occurrence_indices)
    ||group.member_occurrence_indices.length!==group.occurrence_count)fail('same-printed-head group is ambiguous or incomplete');
  if(!app.head?.ident?.unique_name||app.head.ident.unique_name!==scope.binder?.unique_name
    ||app.head.ident.name!==scope.binder?.name||app.head.longident!==scope.binder?.name
    ||app.head.value_uid!==scope.binder_uid)fail('head/binder identity mismatch');
  if(!validLoc(app.head.head_loc)||!validLoc(app.head.name_loc)||!contains(app.application_loc,app.head.head_loc)
    ||!contains(app.application_loc,app.head.name_loc)||!contains(scope.rhs_loc,app.application_loc)
    ||!contains(root.loc,app.application_loc))fail('head/application/RHS containment mismatch');
  if(!app.caller||!Number.isInteger(app.caller.native_owner_index)||typeof app.caller.name!=='string'
    ||!validLoc(app.caller.loc)||!contains(app.caller.loc,app.application_loc))fail('native caller ownership missing');
  const callers=record.native_function_owners.filter(owner=>contains(owner.loc,app.application_loc));
  const deepest=callers.filter(owner=>!callers.some(other=>other!==owner&&contains(owner.loc,other.loc)&&!sameLoc(owner.loc,other.loc)));
  if(deepest.length!==1||deepest[0].native_owner_index!==app.caller.native_owner_index
    ||deepest[0].name!==app.caller.name||!sameLoc(deepest[0].loc,app.caller.loc))fail('native caller is not the deepest actual owner');
  const storage=locator.storage;
  if(!storage||storage.stored!==true||storage.cmt!==record.cmt||storage.callee_name!==root.name
    ||storage.callee_path!==after?.target_path||storage.ordinal!==root.allocation_ordinal)fail('independent storage confirmation mismatch');
  const site=appSite(app),callerLoc=app.caller.loc,targetLoc=root.loc;
  if(!before||before.caller_path!==app.application_loc.start.file||before.caller!==app.caller.name
    ||before.call_site!==site||before.callee_name!==app.head.ident.name||before.target!==null
    ||before.target_path!==null||before.kind!=='MAY_TOP'||before.top_reason!=='callback_param'
    ||before.top_anchor!==site||before.edge_form!==null)fail('before positioned TOP does not match native occurrence');
  if(!after||after.caller_path!==before.caller_path||after.caller!==before.caller||after.call_site!==site
    ||after.target_path!==before.caller_path||after.target!==root.name||after.callee_name!==root.name
    ||after.kind!=='MAY_ENUMERATED'||after.top_reason!==null||after.top_anchor!==null||after.edge_form!==null)fail('after positioned bounded target does not match native root');
  if(before.caller_line_start!==callerLoc.start.line||before.caller_line_end!==callerLoc.end.line
    ||after.caller_line_start!==callerLoc.start.line||after.caller_line_end!==callerLoc.end.line
    ||after.target_line_start!==targetLoc.start.line||after.target_line_end!==targetLoc.end.line)fail('caller or root range mismatch');
  if(!Number.isInteger(app.root_syntactic_arity)||app.root_syntactic_arity!==root.arity
    ||!Number.isInteger(app.supplied_some)||app.supplied_some<0
    ||!Array.isArray(app.arguments)||app.arguments.filter(x=>x.supplied).length!==app.supplied_some)fail('native arity/supplied-slot evidence malformed');
  const members=record.all_application_occurrences.filter(x=>x.caller_site_group?.key===group.key);
  const listed=[...group.member_occurrence_indices].sort((a,b)=>a-b),actual=members.map(x=>x.native_occurrence_index).sort((a,b)=>a-b);
  if(group.occurrence_count!==members.length||listed.length!==new Set(listed).size||listed.join(',')!==actual.join(',')
    ||members.some(x=>x.classification!=='native_self_head_requires_storage_confirmation'
      ||x.target_disposition!==app.target_disposition||x.head?.longident!==app.head.longident
      ||x.head?.ident?.unique_name!==scope.binder.unique_name))fail('same-printed-head group members are not exactly admitted');
  return {record,app,scope,root,storage,syntactic_arity:app.root_syntactic_arity,
    supplied_some:app.supplied_some,position_key:positionKey(before),group_key:group.key};
}
function recordsFromEvidence(file){
  const parsed=JSON.parse(fs.readFileSync(file,'utf8'));
  if(!Array.isArray(parsed))fail('native evidence must be a record array');
  return parsed;
}
function manifestEntry(manifest,cmt){
  const records=manifest?.records;
  if(!Array.isArray(records))fail('manifest records required');
  const entry=records.find(record=>Array.isArray(record)&&record.length===3&&record[2]===cmt);
  if(!entry)fail('CMT is absent from concrete fixed410 manifest');
  const [slice,digest,artifact]=entry;
  if(!/^[a-z0-9-]+$/.test(slice)||!/^[a-f0-9]{64}$/.test(digest)||!path.isAbsolute(artifact)||path.extname(artifact)!=='.cmt')
    fail('malformed fixed410 manifest record');
  return entry;
}
function manifestContains(manifest,cmt){
  const entry=manifestEntry(manifest,cmt);
  if(!fs.existsSync(cmt))return false;
  return entry[1]===fileSha256(cmt);
}
function rowCapacity(rows){
  if(!Array.isArray(rows))fail('positioned rows required');
  const result=new Map();
  for(const row of rows){const key=positionKey(row);result.set(key,(result.get(key)||0)+1);}
  return result;
}
function consume(capacity,row,label){
  const key=positionKey(row),n=capacity.get(key)||0;
  if(n<1)fail(`${label} lacks exact positioned-row capacity`);
  capacity.set(key,n-1);
}
function loadWitness(file,baseline,candidateSnapshot,manifest){
 try{
  const raw=fs.readFileSync(file);
  const witness=JSON.parse(raw);
  if(witness?.schema_version!=='local-recursive-witness-v1')fail('witness schema refused');
  if(witness.baseline_digest!==baseline?.digest||witness.candidate_digest!==candidateSnapshot?.digest)fail('snapshot digest mismatch');
  if(typeof witness.evidence_file!=='string'||typeof witness.evidence_sha256!=='string')fail('native evidence provenance missing');
  const evidenceFile=path.resolve(path.dirname(file),witness.evidence_file);
  if(!fs.existsSync(evidenceFile)||fileSha256(evidenceFile)!==witness.evidence_sha256)fail('native evidence hash mismatch');
  const probeFile=path.resolve(__dirname,'recursive-witness.ml');
  if(typeof witness.probe_sha256!=='string'||fileSha256(probeFile)!==witness.probe_sha256)fail('native probe hash mismatch');
  const records=recordsFromEvidence(evidenceFile),cmts=records.map(record=>record?.cmt);
  if(cmts.some(cmt=>typeof cmt!=='string'||!path.isAbsolute(cmt)||path.extname(cmt)!=='.cmt')||new Set(cmts).size!==cmts.length)
    fail('native evidence must contain unique absolute CMT records');
  for(const record of records){
    if(!manifestContains(manifest,record.cmt))fail('native artifact absent from fixed410 manifest/hash binding');
    const md5=crypto.createHash('md5').update(fs.readFileSync(record.cmt)).digest('hex');
    if(record.artifact_digest!==md5)fail('native MD5 artifact identity mismatch');
  }
  /* Evidence bytes may be edited together with their witness hash.  Replay the
     compiler-only oracle over the exact pinned CMTs and require byte-for-byte
     semantic JSON equality, so a forged record cannot authorize a target. */
  let replayed;
  try{replayed=probeRecords(cmts);}catch(error){fail(`native CMT replay failed: ${error.message}`);}
  if(!Array.isArray(replayed)||replayed.length!==records.length)fail('native CMT replay cardinality mismatch');
  for(let i=0;i<records.length;i++)if(stable(records[i])!==stable(replayed[i]))fail('native evidence does not reproduce from pinned CMT');
  const byCmt=new Map(records.map(record=>[record.cmt,record]));
  const beforeCapacity=rowCapacity(baseline.positioned_rows),afterCapacity=rowCapacity(candidateSnapshot.positioned_rows);
  const transitions=Array.isArray(witness.transitions)?witness.transitions:fail('transition list required');
  const residuals=Array.isArray(witness.residuals)?witness.residuals:fail('residual list required');
  const headUse=new Set(),residualUse=new Set(),approved=new Map(),coveredGroups=new Map(),canonicalTransitions=[];
  for(const transition of transitions){
    if(!transition?.native||typeof transition.reviewed_by!=='string'||!transition.reviewed_by
      ||typeof transition.reviewed_at!=='string'||!transition.reviewed_at)fail('reviewed native transition metadata missing');
    const record=byCmt.get(transition.native.cmt);
    if(!record)fail('native artifact absent from replayed evidence');
    const key=`${record.cmt}#${transition.native.occurrence_index}`;
    if(headUse.has(key))fail('native head occurrence reused');
    const native=validateNativePair(record,{native_occurrence_index:transition.native.occurrence_index,storage:transition.native.storage},transition.before,transition.after);
    consume(beforeCapacity,transition.before,'baseline');consume(afterCapacity,transition.after,'candidate');
    headUse.add(key);approved.set(key,{transition,native});
    canonicalTransitions.push({before:transition.before,after:transition.after});
    const groupKey=`${record.cmt}\n${native.group_key}`,set=coveredGroups.get(groupKey)||new Set();
    set.add(transition.native.occurrence_index);coveredGroups.set(groupKey,set);
  }
  for(const {native} of approved.values()){
    const {record,app,scope}=native;
    const groupKey=`${record.cmt}\n${app.caller_site_group.key}`,covered=coveredGroups.get(groupKey)||new Set();
    for(const occurrence of app.caller_site_group.member_occurrence_indices)
      if(!covered.has(occurrence))fail('insufficient exact capacity for same-printed-head group');
    if(scope.storage!=='unconfirmed_native_oracle_only')fail('native storage status changed');
  }
  const canonicalResiduals=[];
  for(const residual of residuals){
    if(!residual?.native)fail('native residual metadata missing');
    const record=byCmt.get(residual.native.cmt),key=`${residual.native.cmt}#${residual.native.occurrence_index}`;
    if(!record||!approved.has(key))fail('residual lacks independently approved head');
    if(residualUse.has(key))fail('native residual occurrence reused');
    const native=approved.get(key).native;
    if(!(native.supplied_some>native.syntactic_arity))fail('residual is not an overapplied native head');
    if(residual.arity!==native.syntactic_arity||residual.arguments!==native.supplied_some)
      fail('residual arity/argument evidence mismatch');
    const after=residual.after,site=appSite(native.app);
    if(!after||after.caller_path!==approved.get(key).transition.after.caller_path||after.caller!==native.app.caller.name
      ||after.call_site!==site||after.target!==null||after.target_path!==null||after.callee_name!=='*TOP*'
      ||after.kind!=='MAY_TOP'||after.top_reason!=='callback_param'||after.top_anchor!==site||after.edge_form!==null)fail('returned-call residual does not match native overapplication');
    consume(afterCapacity,after,'candidate residual');residualUse.add(key);
    const head=approved.get(key).transition;
    canonicalResiduals.push({after,head:{before:head.before,after:head.after},arity:residual.arity,arguments:residual.arguments});
  }
  return {transitions:canonicalTransitions,residuals:canonicalResiduals,sha256:fileSha256(file),
    head_capacity:[...headUse],residual_capacity:[...residualUse]};
 }catch(error){if(error instanceof ComparisonInputError)throw error;fail(error.message);}
}
module.exports={ComparisonInputError,fileSha256,positionKey,validateNativePair,loadWitness};
