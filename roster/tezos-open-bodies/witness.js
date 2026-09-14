'use strict';

const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const {ComparisonInputError, CANONICAL_FIELDS, POSITION_FIELDS, canonicalStrings} = require('./comparison.js');
const {probeRecords} = require('./run-probe.js');

const fail = message => { throw new ComparisonInputError(`open-body witness: ${message}`); };
const sha256 = value => crypto.createHash('sha256').update(value).digest('hex');
const fileSha256 = file => sha256(fs.readFileSync(file));
const allFields = [...CANONICAL_FIELDS, ...POSITION_FIELDS];

function positionKey(row) {
  canonicalStrings([row]);
  for (const field of POSITION_FIELDS) {
    if (!(field in row) || (row[field] !== null && !Number.isInteger(row[field])))
      fail(`invalid ${field}`);
  }
  return JSON.stringify(allFields.map(field => row[field]));
}

function validLoc(loc) {
  return loc && typeof loc === 'object' && Number.isInteger(loc.start_offset)
    && Number.isInteger(loc.end_offset) && loc.start_offset >= 0
    && loc.end_offset >= loc.start_offset && loc.start && loc.end
    && typeof loc.start.file === 'string' && loc.start.file === loc.end.file
    && Number.isInteger(loc.start.line) && Number.isInteger(loc.end.line)
    && Number.isInteger(loc.start.column) && Number.isInteger(loc.end.column);
}
const sameRange = (loc, row, prefix) => validLoc(loc)
  && loc.start.file === row[`${prefix}_path`]
  && loc.start.line === row[`${prefix}_line_start`]
  && loc.end.line === row[`${prefix}_line_end`];
const contains = (outer, inner) => validLoc(outer) && validLoc(inner)
  && outer.start.file === inner.start.file && outer.start_offset <= inner.start_offset
  && inner.end_offset <= outer.end_offset;

function expectedTarget(candidate) {
  const loc = candidate.root_function_loc;
  if (!validLoc(loc) || typeof candidate.binding_name !== 'string' || !candidate.binding_name)
    fail('candidate has malformed canonical identity');
  return `${candidate.binding_name}.<fun:${loc.start.line}:${loc.start.column + 1}>`;
}

function validateRecord(record) {
  if (!record || record.schema_version !== 'open-body-witness-v2'
    || record.artifact_digest_algorithm !== 'md5'
    || !/^[a-f0-9]{32}$/.test(record.artifact_digest || '')
    || !Array.isArray(record.structural_candidates)
    || !Array.isArray(record.native_function_owners)
    || !Array.isArray(record.all_application_occurrences)) fail('malformed native probe record');
}

function validateNativePair(record, locator, before, after) {
  validateRecord(record); positionKey(before); positionKey(after);
  if (before.target !== null || before.target_path !== null || before.kind !== 'MAY_TOP'
    || before.top_reason !== 'callback_param' || before.top_anchor !== before.call_site
    || before.edge_form !== null || after.kind !== 'MAY_ENUMERATED' || after.edge_form !== null
    || after.top_reason !== null || after.top_anchor !== null || after.target_path !== before.caller_path
    || after.target === null || after.callee_name !== after.target
    || ['caller_path','caller','call_site','caller_line_start','caller_line_end'].some(k => before[k] !== after[k]))
    fail('pair is not a same-site callback_param-to-body transition');
  const index = typeof locator === 'number' ? locator : locator?.native_occurrence_index;
  if (!Number.isInteger(index)) fail('missing native occurrence identity');
  const matches = record.all_application_occurrences.filter(x => x.native_occurrence_index === index);
  if (matches.length !== 1) fail('native occurrence identity is absent or ambiguous');
  const app = matches[0];
  if (app.classification !== 'eligible_unique' || app.matching_identity_candidate_count !== 1
    || !Array.isArray(app.matching_identity_candidates) || app.matching_identity_candidates.length !== 1)
    fail('native occurrence is not uniquely eligible');
  const candidate = app.matching_identity_candidates[0];
  if (candidate.actual_root_body_cardinality !== 1 || !Number.isInteger(candidate.actual_root_owner)
    || app.target_disposition !== `eligible_unique:body_function:${candidate.actual_root_owner}`)
    fail('root body owner is absent or ambiguous');
  const owners = record.native_function_owners.filter(x => x.native_function_index === candidate.actual_root_owner);
  if (owners.length !== 1 || !sameRange(candidate.root_function_loc, after, 'target')
    || !sameRange(owners[0].stored_owner_loc, after, 'target')
    || owners[0].canonical_owner_name !== expectedTarget(candidate)
    || owners[0].owner_kind !== 'promoted_open_body_root'
    || !owners[0].is_promoted_open_body_root || owners[0].matching_open_body_root_count !== 1
    || after.target !== expectedTarget(candidate))
    fail('stored target is not the exact canonical root body');
  if (!app.head || app.head.ident?.unique_name !== candidate.binder?.unique_name
    || app.head.ident?.name !== candidate.binder?.name || app.head.value_uid !== candidate.binder_uid
    || app.head.longident !== candidate.binder.name || before.callee_name !== app.head.ident.name)
    fail('application head and exact binder identity disagree');
  const head = app.head.head_loc, application = app.application_loc;
  if (!validLoc(head) || !validLoc(application) || !contains(application, head)
    || `${application.start.file}:${application.start.line}` !== before.call_site)
    fail('application/head offsets do not match the stored site');
  const callerMatches = record.native_function_owners.filter(owner =>
    sameRange(owner.stored_owner_loc, before, 'caller') && contains(owner.loc, application));
  if (app.caller) {
    if (app.caller_owner_cardinality !== 1 || !contains(app.caller.loc, application)
      || callerMatches.length !== 1
      || callerMatches[0].native_function_index !== app.caller.native_function_index
      || app.caller.canonical_owner_name !== before.caller
      || callerMatches[0].canonical_owner_name !== before.caller)
      fail('stored caller ownership/name/range is ambiguous');
  } else {
    const binding=app.enclosing_binding;
    if (app.caller_owner_cardinality !== 0 || callerMatches.length !== 0
      || !app.enclosing_structural_binding_available
      || !app.enclosing_binding_rhs_contains_application
      || !binding?.is_structure_binding || binding.name !== before.caller
      || !validLoc(binding.rhs_loc) || !contains(binding.rhs_loc, application)
      || !sameRange(binding.loc, before, 'caller'))
      fail('top-level structural caller ownership/name/range is ambiguous');
  }
  if (!Number.isInteger(app.supplied_some) || !Number.isInteger(candidate.root_function_arity)
    || app.supplied_some !== app.arguments.filter(x => x.supplied).length)
    fail('native arity/supplied count is malformed');
  const group = app.caller_site_head_group;
  const members = record.all_application_occurrences.filter(x => x.caller_site_head_group?.key === group?.key);
  if (!group || group.occurrence_count !== members.length || !group.unambiguous
    || members.some(x => x.classification !== 'eligible_unique'
      || x.target_disposition !== app.target_disposition
      || x.matching_identity_candidates?.[0]?.binding_name !== candidate.binding_name))
    fail('printed-head line group is incomplete or mixed');
  return {app, candidate, group_key:group.key, group_count:members.length,
    syntactic_arity:candidate.root_function_arity, supplied_some:app.supplied_some};
}

function manifestMap(manifest) {
  const records = manifest?.records;
  if (!Array.isArray(records)) fail('missing fixed410 manifest records');
  const map = new Map();
  for (const record of records) {
    if (!Array.isArray(record) || record.length !== 3 || !path.isAbsolute(record[2])
      || !/^[a-f0-9]{64}$/.test(record[1]) || map.has(record[2])) fail('malformed fixed410 manifest');
    map.set(record[2], record[1]);
  }
  return map;
}
const counted = rows => { const m=new Map(); for (const row of rows) {const k=positionKey(row);m.set(k,(m.get(k)||0)+1);} return m; };
const take = (m,k,label) => { if (!(m.get(k)>0)) fail(`${label} is absent or overused`);m.set(k,m.get(k)-1); };

function loadWitness(file, baseline, candidateSnapshot, manifest) {
  try {
    const raw = fs.readFileSync(file); const value = JSON.parse(raw);
    if (value.schema_version !== 1 || value.kind !== 'structural-open-body-invocation'
      || value.baseline_digest !== baseline?.digest || value.candidate_digest !== candidateSnapshot?.digest
      || !Array.isArray(value.transitions) || !Array.isArray(value.residuals)) fail('wrong class or snapshot digest');
    if (typeof value.evidence_file !== 'string' || !path.isAbsolute(value.evidence_file)
      || fileSha256(value.evidence_file) !== value.evidence_sha256
      || fileSha256(path.join(__dirname,'open-body-witness.ml')) !== value.probe_sha256)
      fail('native evidence/probe SHA-256 mismatch');
    const records=JSON.parse(fs.readFileSync(value.evidence_file));
    if (!Array.isArray(records)||records.length===0) fail('native evidence is empty');
    const pinned=manifestMap(manifest), seenFiles=new Set();
    for(const record of records){validateRecord(record);if(seenFiles.has(record.cmt))fail('duplicate native artifact');seenFiles.add(record.cmt);
      if(!pinned.has(record.cmt)||fileSha256(record.cmt)!==pinned.get(record.cmt))fail('native artifact is not the pinned fixed410 input');}
    if(JSON.stringify(probeRecords(records.map(x=>x.cmt)))!==JSON.stringify(records))fail('native evidence does not reproduce');
    const byCmt=new Map(records.map(x=>[x.cmt,x]));
    const before=counted(baseline.positioned_rows||[]), after=counted(candidateSnapshot.positioned_rows||[]);
    const consumed=new Set(), groups=new Map(), natives=[];
    const transitions=value.transitions.map(item=>{
      if (!item || ['reviewed_by','reviewed_at','source_evidence'].some(k => typeof item[k] !== 'string' || !item[k].trim()))
        fail('missing review/source provenance');
      const record=byCmt.get(item?.native?.cmt);if(!record)fail('missing native CMT reference');
      take(before,positionKey(item.before),'baseline positioned row');take(after,positionKey(item.after),'candidate positioned row');
      const id=item.native.occurrence_index,key=`${record.cmt}\0${id}`;if(consumed.has(key))fail('native occurrence reused');
      const native=validateNativePair(record,{native_occurrence_index:id},item.before,item.after);consumed.add(key);natives.push(native);
      const g=`${record.cmt}\0${native.group_key}`;groups.set(g,{expected:native.group_count,count:(groups.get(g)?.count||0)+1});
      return {before:item.before,after:item.after};
    });
    for(const {expected,count} of groups.values())if(count!==expected)fail('insufficient exact capacity for printed-head line group');
    const residualHeads=new Set();
    const residuals=value.residuals.map(item=>{if (!item || ['reviewed_by','reviewed_at','source_evidence'].some(k => typeof item[k] !== 'string' || !item[k].trim())) fail('missing residual review/source provenance');
      const i=item.head_index;if(!Number.isInteger(i)||i<0||i>=transitions.length)fail('residual head index');
      if(residualHeads.has(i))fail('residual head occurrence reused');
      residualHeads.add(i);
      const n=natives[i];if(n.supplied_some<=n.syntactic_arity||item.arity!==n.syntactic_arity||item.arguments!==n.supplied_some)fail('residual lacks exact native overapplication');
      take(after,positionKey(item.after),'candidate residual row');return {after:item.after,head:transitions[i],arity:item.arity,arguments:item.arguments};});
    return {transitions,residuals,sha256:sha256(raw)};
  } catch(error) {if(error instanceof ComparisonInputError)throw error;fail(error.message);}
}

module.exports={loadWitness,validateNativePair,positionKey,fileSha256};
