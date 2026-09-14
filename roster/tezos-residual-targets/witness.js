'use strict';

const fs = require('node:fs');
const path = require('node:path');
const {
  ComparisonInputError, CANONICAL_FIELDS, POSITION_FIELDS, canonicalStrings,
} = require('./comparison.js');
const {fileSha256, sha256} = require('./baseline.js');
const {validateOneHop} = require('./check-witness.js');
const {probeRecords} = require('./run-probe.js');
const fail = message => { throw new ComparisonInputError(`paired witness: ${message}`); };
const positionKey = row => {
  canonicalStrings([row]);
  for (const field of POSITION_FIELDS)
    if (!(field in row) || (row[field] !== null && !Number.isInteger(row[field]))) fail(`invalid ${field}`);
  return JSON.stringify([...CANONICAL_FIELDS, ...POSITION_FIELDS].map(field => row[field]));
};
const span = (loc, row, prefix) => loc.file === row[`${prefix}_path`]
  && loc.start_line === row[`${prefix}_line_start`] && loc.end_line === row[`${prefix}_line_end`];
const within = (inner, outer) => inner.file === outer.file
  && inner.start_offset >= outer.start_offset && inner.end_offset <= outer.end_offset;

function validateNativePair(record, locator, before, after) {
  positionKey(before); positionKey(after);
  if (before.edge_form !== null || after.edge_form !== null
    || before.kind !== 'MAY_TOP' || before.top_reason !== 'module_param' || before.target !== null
    || after.kind !== 'MAY_ENUMERATED' || after.target_path !== before.caller_path
    || after.top_reason !== null || after.top_anchor !== null || after.callee_name !== after.target
    || ['caller_path','caller','call_site','caller_line_start','caller_line_end'].some(k => before[k] !== after[k]))
    fail('pair is not an ordinary same-site module_param-to-body transition');
  const native = validateOneHop(record, locator);
  if (native.occurrence_path !== before.callee_name) fail('native path differs from unresolved head');
  const targetBodies = record.bindings.filter(b => b.rhs_is_function
    && (span(b.binding_loc, after, 'target') || span(b.body_loc, after, 'target')));
  if (new Set(targetBodies.map(b => b.binding_uid)).size !== 1
    || targetBodies[0]?.binding_uid !== native.body_uid
    || targetBodies[0]?.name !== after.target.split('.').at(-1).replace(/#\d+$/, ''))
    fail('stored target span has absent or competing native body identity');
  const callerSpans = [
    ...record.bindings.filter(b => span(b.binding_loc,before,'caller') || span(b.body_loc,before,'caller'))
      .map(b => b.body_loc),
    ...record.functions.filter(loc => span(loc,before,'caller')),
  ];
  const locations = native.consumer_context.kind === 'callback'
    ? native.consumer_context.contexts.map(c => c.application_loc) : [native.occurrence_loc];
  const matchingLocations = locations.filter(loc => `${loc.file}:${loc.start_line}` === before.call_site
    && callerSpans.some(caller => within(loc, caller)));
  if (matchingLocations.length !== 1) fail('native invocation does not uniquely belong to stored caller/site');
  return native;
}

function loadWitness(file, baseline, candidate, manifest) {
  try {
    const raw = fs.readFileSync(file);
    const value = JSON.parse(raw);
    if (value.schema_version !== 2 || value.kind !== 'local-value-alias-one-hop'
      || value.baseline_digest !== baseline.digest || value.candidate_digest !== candidate.digest
      || !Array.isArray(value.transitions) || !Array.isArray(value.residuals))
      fail('wrong witness class or snapshot binding');
    if (typeof value.evidence_file !== 'string' || !path.isAbsolute(value.evidence_file)
      || fileSha256(value.evidence_file) !== value.evidence_sha256
      || fileSha256(path.join(__dirname,'alias-witness.ml')) !== value.probe_sha256)
      fail('native evidence/probe hash mismatch');
    const records = JSON.parse(fs.readFileSync(value.evidence_file));
    if (!Array.isArray(records) || records.length === 0) fail('native evidence is empty');
    const pinned = new Map(manifest.records.map(([,hash,cmt]) => [cmt,hash]));
    const files = records.map(r => r.cmt);
    if (new Set(files).size !== files.length) fail('duplicate CMT evidence');
    for (const cmt of files)
      if (!pinned.has(cmt) || fileSha256(cmt) !== pinned.get(cmt)) fail('evidence CMT is not a pinned input');
    // Hashes bind artifacts but are not proof of how JSON was produced. Repeat
    // the independent native probe and require byte-equivalent parsed records.
    const replayed = probeRecords(files);
    if (JSON.stringify(replayed) !== JSON.stringify(records)) fail('native evidence does not reproduce');
    const byCmt = new Map(records.map(r => [r.cmt,r]));
    const beforePositions = new Set(baseline.positioned_rows.map(positionKey));
    const afterPositions = new Set(candidate.positioned_rows.map(positionKey));
    const consumed = new Set();
    const review = item => {
      if (!item || ['reviewed_by','reviewed_at','source_evidence'].some(k => typeof item[k] !== 'string' || !item[k].trim()))
        fail('missing independent review/source annotation');
    };
    const natives = [];
    const transitions = value.transitions.map(item => {
      review(item);
      if (!beforePositions.has(positionKey(item.before)) || !afterPositions.has(positionKey(item.after)))
        fail('paired positioned facts are absent from snapshots');
      const reference = item.native;
      const record = reference && byCmt.get(reference.cmt);
      if (!record) fail('missing native CMT reference');
      const locator = reference.locator;
      const key = JSON.stringify([reference.cmt,locator?.bucket,locator?.index,locator?.operator_index ?? null]);
      if (consumed.has(key)) fail('native occurrence reference reused');
      const native = validateNativePair(record,locator,item.before,item.after);
      consumed.add(key); natives.push(native);
      return {before:item.before,after:item.after};
    });
    const residuals = value.residuals.map(item => {
      review(item);
      const index = item.head_index;
      if (!Number.isInteger(index) || index < 0 || index >= transitions.length
        || !afterPositions.has(positionKey(item.after))) fail('residual lacks exact head/return position');
      const native = natives[index];
      if (native.locator.bucket !== 'applications' || native.supplied_some <= native.syntactic_arity)
        fail('residual has no native overapplication premise');
      if (item.arity !== native.syntactic_arity || item.arguments !== native.supplied_some)
        fail('residual arity/argument metadata differs from native evidence');
      return {after:item.after,head:transitions[index],arity:item.arity,arguments:item.arguments};
    });
    return {transitions,residuals,sha256:sha256(raw)};
  } catch (error) {
    if (error instanceof ComparisonInputError) throw error;
    fail(error.message);
  }
}

module.exports = {loadWitness, validateNativePair, positionKey};
