#!/usr/bin/env node
'use strict';

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {
  ROOT, BASELINE_DIR, CURRENT_PRODUCER, CURRENT_SCHEMA, EXPECTED, ComparisonInputError,
  sha256, fileSha256, readManifest, validateSnapshot, sourceState,
  validateActivePhase, assertStateUnchanged, loadFrozen, makeSelection, produce,
} = require('./baseline.js');
const {snapshotDatabase, compareSnapshots} = require('./comparison.js');

// Preparation-only neutral mode always exercises the unchanged producer.
function self() {
  const before = sourceState();
  validateActivePhase(before, {allowInactive: true});
  const frozen = loadFrozen();
  if (before.tezosRevision !== frozen.tezos_revision
      || sha256(before.tezosStatus) !== frozen.tezos_status_sha256)
    throw new ComparisonInputError('Tezos checkout differs from frozen provenance');
  const producerHash = fileSha256(CURRENT_PRODUCER);
  const schemaHash = fileSha256(CURRENT_SCHEMA);
  if (producerHash !== EXPECTED.producerSha256 || schemaHash !== EXPECTED.schemaSha256)
    throw new ComparisonInputError('neutral preparation requires unchanged predecessor producer/schema');
  const manifest = readManifest();
  const baseline = snapshotDatabase(frozen.db, {expectedArtifactSuffixes: manifest.destinationSuffixes});
  validateSnapshot(baseline);
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'arch-index-attempt2-self-'));
  try {
    const selection = makeSelection(temporary, manifest);
    const db = path.join(temporary, 'candidate.db');
    produce(CURRENT_PRODUCER, CURRENT_SCHEMA, db, selection);
    const candidate = snapshotDatabase(db, {expectedArtifactSuffixes: manifest.destinationSuffixes});
    validateSnapshot(candidate);
    const comparison = compareSnapshots(baseline, candidate);
    if (!comparison.ok || !comparison.neutral)
      throw new ComparisonInputError('preparation self comparison is not neutral');
    readManifest();
    if (fileSha256(CURRENT_PRODUCER) !== producerHash || fileSha256(CURRENT_SCHEMA) !== schemaHash)
      throw new ComparisonInputError('producer/schema changed during self comparison');
    assertStateUnchanged(before, sourceState());
    process.stdout.write(`PASS preparation self: ${candidate.row_count} rows, ${candidate.digest}; neutral, no retained gain\n`);
  } finally {
    fs.rmSync(temporary, {recursive: true});
  }
}

function candidate(witnessFile) {
  const before = sourceState();
  validateActivePhase(before, {allowInactive: true});
  const frozen = loadFrozen();
  const frozenRecordHash = fileSha256(path.join(BASELINE_DIR, 'provenance.json'));
  if (before.tezosRevision !== frozen.tezos_revision
      || sha256(before.tezosStatus) !== frozen.tezos_status_sha256)
    throw new ComparisonInputError('Tezos checkout differs from frozen provenance');
  const producerHash = fileSha256(CURRENT_PRODUCER);
  const schemaHash = fileSha256(CURRENT_SCHEMA);
  if (schemaHash !== EXPECTED.schemaSha256)
    throw new ComparisonInputError('candidate schema change is outside attempt2');
  const manifest = readManifest();
  const baseline = snapshotDatabase(frozen.db, {expectedArtifactSuffixes: manifest.destinationSuffixes});
  validateSnapshot(baseline);
  const output = path.join(ROOT, 'improvement/2026-09-14-tezos-resolution',
    `attempt2-${new Date().toISOString().replace(/[:.]/g, '-')}-${process.pid}`);
  fs.mkdirSync(output);
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'arch-index-attempt2-candidate-'));
  try {
    const selection = makeSelection(temporary, manifest);
    const db = path.join(temporary, 'candidate.db');
    produce(CURRENT_PRODUCER, CURRENT_SCHEMA, db, selection);
    const next = snapshotDatabase(db, {expectedArtifactSuffixes: manifest.destinationSuffixes});
    // A missing admission implementation is a setup error, never permission to
    // accept a claimed witness. No witness permits only a genuinely neutral run.
    const witness = witnessFile
      ? require('./witness.js').loadWitness(witnessFile, baseline, next, manifest)
      : {transitions:[], residuals:[], sha256:null};
    const result = compareSnapshots(baseline, next, {
      approvedTransitions:witness.transitions, approvedResiduals:witness.residuals,
    });
    readManifest();
    loadFrozen();
    if (fileSha256(path.join(BASELINE_DIR, 'provenance.json')) !== frozenRecordHash
      || fileSha256(CURRENT_PRODUCER) !== producerHash || fileSha256(CURRENT_SCHEMA) !== schemaHash)
      throw new ComparisonInputError('producer/schema/frozen provenance changed during comparison');
    validateSnapshot(snapshotDatabase(frozen.db, {expectedArtifactSuffixes: manifest.destinationSuffixes}));
    assertStateUnchanged(before, sourceState());
    const changedSites = new Set([...result.changes.removed, ...result.changes.added]
      .map(row => JSON.stringify([row.caller_path,row.caller,row.call_site])));
    const changed = rows => rows.filter(row => changedSites.has(JSON.stringify([row.caller_path,row.caller,row.call_site])));
    fs.writeFileSync(path.join(output, 'changes.json'), JSON.stringify({
      ...result.changes, before_positioned:changed(baseline.positioned_rows),
      after_positioned:changed(next.positioned_rows),
    }, null, 2) + '\n', {flag:'wx'});
    fs.writeFileSync(path.join(output, 'provenance.json'), JSON.stringify({
      created_at:new Date().toISOString(), baseline_db:frozen.db,
      baseline_provenance_sha256:frozenRecordHash, baseline_digest:baseline.digest,
      candidate_digest:next.digest, candidate_rows:next.row_count,
      producer_sha256:producerHash, schema_sha256:schemaHash,
      manifest_sha256:EXPECTED.manifestSha256, selected:EXPECTED.selected,
      arch_revision:before.archRevision, arch_status_sha256:sha256(before.archStatus),
      tezos_revision:before.tezosRevision, tezos_status_sha256:sha256(before.tezosStatus),
      active_task_sha256:sha256(before.activeTask), active_manifest_sha256:sha256(before.activeManifest),
      witness_file:witnessFile, witness_sha256:witness.sha256,
      source_status_unchanged:true, input_hashes_unchanged:true,
    }, null, 2) + '\n', {flag:'wx'});
    const report = {verdict:result.ok?'PASS':'REFUSE', retention_authorized:false,
      classification:result.neutral?'neutral':'candidate', summary:result.summary,
      slices:result.slices, errors:result.errors, baseline_digest:baseline.digest,
      candidate_digest:next.digest, output};
    fs.writeFileSync(path.join(output, 'report.json'), JSON.stringify(report, null, 2) + '\n', {flag:'wx'});
    console.log(JSON.stringify({...report, errors:result.errors.slice(0, 5)}, null, 2));
    if (!result.ok) process.exitCode = 1;
  } finally {
    fs.rmSync(temporary, {recursive:true});
  }
}

try {
  const args = process.argv.slice(2);
  if (args.length === 1 && args[0] === '--self') self();
  else if (args.length === 0) candidate(null);
  else if (args.length === 2 && args[0] === '--witness') candidate(path.resolve(args[1]));
  else throw new ComparisonInputError('usage: verify.js [--self | --witness FILE]');
} catch (error) {
  process.stderr.write(`SETUP FAILED: ${error.stack || error}\n`);
  process.exitCode = error instanceof ComparisonInputError ? 2 : 3;
}
