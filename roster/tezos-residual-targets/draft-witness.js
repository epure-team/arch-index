#!/usr/bin/env node
'use strict';

// Produces an explicitly unreviewed draft. It cannot satisfy loadWitness's
// independent-review gate and is not evidence of acceptance.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const {CANONICAL_FIELDS} = require('./comparison.js');
const {validateNativePair, positionKey} = require('./witness.js');

const root = path.resolve(__dirname, '../..');
const reportDir = path.join(root, 'improvement/2026-09-14-tezos-resolution/attempt2-2026-09-14T08-35-50-576Z-3164680');
const evidenceFile = path.join(root, 'improvement/2026-09-14-tezos-resolution/attempt2-alias-native-v2.json');
const outputFile = path.join(root, 'improvement/2026-09-14-tezos-resolution/attempt2-draft-witness.json');
const probeFile = path.join(__dirname, 'alias-witness.ml');
const sha = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const canonicalKey = row => JSON.stringify(CANONICAL_FIELDS.map(field => row[field]));

function selectPositioned(positioned, canonicalRows, label) {
  const counts = new Map();
  for (const row of canonicalRows) counts.set(canonicalKey(row), (counts.get(canonicalKey(row)) || 0) + 1);
  const selected = [];
  for (const row of positioned) {
    const key = canonicalKey(row), count = counts.get(key) || 0;
    if (count > 0) { selected.push(row); counts.set(key, count - 1); }
  }
  const missing = [...counts.values()].reduce((a,b) => a+b, 0);
  if (missing) throw new Error(`${label}: ${missing} canonical facts lack positioned instances`);
  return selected;
}

function locators(record) {
  return [
    ...record.applications.map((_,index) => ({bucket:'applications',index})),
    ...record.identifiers.filter(x => x.callback_contexts.length).map(x =>
      ({bucket:'identifiers',index:record.identifiers.indexOf(x)})),
    ...record.letops.flatMap((x,index) => x.operators.map((_,operator_index) =>
      ({bucket:'letops',index,operator_index}))),
  ];
}

function main() {
  if (process.argv.length > 3 || (process.argv[2] && process.argv[2] !== '--check'))
    throw new Error('usage: draft-witness.js [--check]');
  const check = process.argv[2] === '--check';
  const changes = JSON.parse(fs.readFileSync(path.join(reportDir,'changes.json')));
  const report = JSON.parse(fs.readFileSync(path.join(reportDir,'report.json')));
  const records = JSON.parse(fs.readFileSync(evidenceFile));
  const removed = selectPositioned(changes.before_positioned, changes.removed, 'removed');
  const added = selectPositioned(changes.after_positioned, changes.added, 'added');
  if (removed.length !== 124 || added.length !== 124 || changes.residuals.length !== 0)
    throw new Error(`unexpected delta ${removed.length}/${added.length}/${changes.residuals.length}`);
  const bySource = new Map();
  for (const record of records) {
    bySource.set(record.source,record);
    bySource.set(record.source.replace(/\.pp\.ml$/,'.ml'),record);
    for (const binding of record.bindings) bySource.set(binding.binding_loc.file,record);
  }
  const availableAfter = new Set(added.map((_,index) => index));
  const consumedNative = new Set(), transitions = [];
  for (const before of removed) {
    const candidates = [...availableAfter].filter(index => {
      const after = added[index];
      return ['caller_path','caller','call_site','caller_line_start','caller_line_end']
        .every(field => before[field] === after[field]);
    });
    const record = bySource.get(before.caller_path);
    if (!record) throw new Error(`no native CMT for ${before.caller_path}`);
    const matches = [];
    for (const afterIndex of candidates) for (const locator of locators(record)) {
      const nativeKey = JSON.stringify([record.cmt,locator.bucket,locator.index,locator.operator_index ?? null]);
      if (consumedNative.has(nativeKey)) continue;
      try {
        const native = validateNativePair(record,locator,before,added[afterIndex]);
        matches.push({afterIndex,locator,native,nativeKey});
      } catch (_) { /* Candidate mismatch is expected during exact search. */ }
    }
    if (matches.length !== 1) {
      throw new Error(`transition ${positionKey(before)} has ${matches.length} exact native/after matches; examples=${JSON.stringify(matches.slice(0,3).map(x=>x.locator))}`);
    }
    const match = matches[0], after = added[match.afterIndex];
    availableAfter.delete(match.afterIndex); consumedNative.add(match.nativeKey);
    transitions.push({before,after,native:{cmt:record.cmt,locator:match.locator},
      reviewed_by:null,reviewed_at:null,
      source_evidence:JSON.stringify({occurrence_path:match.native.occurrence_path,
        occurrence_loc:match.native.occurrence_loc,alias_uid:match.native.alias_uid,
        alias_binding_loc:match.native.alias_binding_loc,body_uid:match.native.body_uid,
        body_loc:match.native.body_loc,syntactic_arity:match.native.syntactic_arity})});
  }
  if (availableAfter.size) throw new Error(`${availableAfter.size} added positioned facts remain unpaired`);
  const draft = {schema_version:2,kind:'local-value-alias-one-hop',
    baseline_digest:report.baseline_digest,candidate_digest:report.candidate_digest,
    evidence_file:evidenceFile,evidence_sha256:sha(evidenceFile),probe_sha256:sha(probeFile),
    transitions,residuals:[]};
  const encoded = `${JSON.stringify(draft,null,2)}\n`;
  if (check) {
    if (!fs.existsSync(outputFile) || fs.readFileSync(outputFile,'utf8') !== encoded)
      throw new Error('draft witness differs from reproducible output');
  } else fs.writeFileSync(outputFile, encoded, {flag:'wx'});
  console.log(`DRAFT ONLY: paired ${transitions.length} transitions; independent review fields intentionally null`);
}

try { main(); }
catch (error) { process.stderr.write(`DRAFT_WITNESS_SETUP: ${error.message}\n`); process.exitCode=2; }
