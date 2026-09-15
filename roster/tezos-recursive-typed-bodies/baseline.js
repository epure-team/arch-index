'use strict';

// Immutable acceptance boundary. Preparation can create a package; acceptance
// can only consume the separately pinned PR108 package, never recreate it.
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const cp = require('node:child_process');
const assert = require('node:assert/strict');
const b = require('../tezos-residual-targets/baseline.js');
const preparation = require('./prepare-baseline.js');
const {snapshotDatabase, compareSnapshots} = require('../tezos-call-resolution/comparison.js');
const TASK = 'tezos-recursive-typed-bodies';
const DIRECTORY = preparation.directory;
const EXPECTED = preparation.expected;
const PURPOSE = preparation.purpose;
const PROVENANCE_SHA256 = 'd05dc367bd0ad8db2c1f63939cb85431a19830caa6cf04caa332a6e1b2f97182';
const DATABASE_SHA256 = 'c45f4d08cafaaa764b32fc092609ad7d44b52edd2bc7bc17fae1e27fd4754198';
const SQL_SHA256 = '7fb1c78d1dadd672d31890fccfdc2555690cbb63557ceac1b32d49539b0b7be7';
const PHASE_FILES = [`briefs/${TASK}-state.json`, `briefs/${TASK}-manifest.txt`];
const fail = message => { throw new b.ComparisonInputError(message); };
function inputValidation(fn) {
  try { return fn(); }
  catch (error) {
    if (error instanceof b.ComparisonInputError) throw error;
    fail(error.message);
  }
}
function validateRecord(record) {
  return inputValidation(() => {
    assert.ok(record && typeof record === 'object' && !Array.isArray(record));
    assert.deepEqual(Object.keys(record).sort(), ['format_version','purpose',
      'expected','manifest','state','db','producer','schema','db_sha256',
      'source_status_unchanged','input_hashes_unchanged','sealing'].sort());
    preparation.validateRecord(record);
    assert.equal(record.db_sha256, DATABASE_SHA256);
    assert.deepEqual(record.sealing, {journal_mode:'delete',
      sql_sha256:SQL_SHA256, all_sql_preserved:true});
    return record;
  });
}
function checkArtifacts(record) {
  return inputValidation(() => {
    validateRecord(record);
    preparation.checkArtifacts(record);
  });
}
function loadFrozen() {
  return inputValidation(() => {
    const file = path.join(DIRECTORY, 'provenance.json');
    if (b.fileSha256(file) !== PROVENANCE_SHA256) fail('immutable PR108 provenance changed');
    const record = validateRecord(JSON.parse(fs.readFileSync(file, 'utf8')));
    checkArtifacts(record);
    return record;
  });
}
function sourceHashes() {
  // Include untracked task tests as well as tracked sources. Git status alone
  // does not detect content changes in an already-dirty file.
  const output = cp.execFileSync('git', ['ls-files','--cached','--others',
    '--exclude-standard','-z','--','lib','tezt','architecture-schema.sql',
    `roster/${TASK}`,`specs/${TASK}.md`,
    'roster/tezos-residual-targets', 'roster/tezos-call-resolution',
    'roster/tezos-open-bodies', 'roster/tezos-local-recursion'], {cwd:b.ROOT,encoding:'utf8'});
  return Object.fromEntries([...new Set(output.split('\0').filter(Boolean))].sort()
    .map(file => [file, b.fileSha256(path.join(b.ROOT, file))]));
}
function state() {
  return inputValidation(() => {
    const result = preparation.state();
    if (result.activeTask !== 'absent\0'
      && (!result.activeManifest.startsWith('present\0base=')
        || !result.activeManifest.includes(`\nroster/${TASK}/\n`)))
      fail('active task scope manifest missing');
    result.sourceFingerprint = b.sha256(JSON.stringify(sourceHashes()));
    return result;
  });
}
function frozenSnapshot(record, manifest) {
  const snapshot = snapshotDatabase(record.db,
    {expectedArtifactSuffixes:manifest.destinationSuffixes});
  b.validateSnapshot(snapshot, EXPECTED);
  return snapshot;
}
function assertNoOverwrite() {
  if (fs.existsSync(DIRECTORY)) fail('refusing to overwrite attempt5 baseline');
  fail('immutable attempt5 predecessor missing; restoration required');
}
function assertReplay(snapshot, original) {
  // Successful production with wrong semantic output is assertion RED, unlike
  // missing/malformed inputs or a failed producer process (setup exit2).
  assert.equal(snapshot.row_count, EXPECTED.rows, 'replay row count');
  assert.equal(snapshot.digest, EXPECTED.digest, 'replay canonical digest');
  assert.deepEqual(b.relationMetrics(snapshot.rows), EXPECTED.relations, 'replay relations');
  const comparison = compareSnapshots(original, snapshot);
  assert.ok(comparison.ok && comparison.neutral, 'PR108 replay must be exactly neutral');
}
function replay() {
  const before = state(), record = loadFrozen();
  const manifest = b.readManifest({expected:EXPECTED});
  const original = frozenSnapshot(record, manifest);
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(),'arch-index-attempt5-replay-'));
  try {
    const producer = path.join(temporary,'producer.exe');
    fs.copyFileSync(record.producer,producer,fs.constants.COPYFILE_EXCL);
    if (b.fileSha256(producer) !== EXPECTED.producerSha256) fail('copied predecessor changed');
    const db = path.join(temporary,'replay.db');
    b.produce(producer,record.schema,db,b.makeSelection(temporary,manifest));
    const snapshot = snapshotDatabase(db,{expectedArtifactSuffixes:manifest.destinationSuffixes});
    assertReplay(snapshot, original);
    b.readManifest({expected:EXPECTED});
    loadFrozen();
    b.assertStateUnchanged(before, state());
    return {rows:snapshot.row_count, digest:snapshot.digest,
      relations:b.relationMetrics(snapshot.rows), neutral:true};
  } finally { fs.rmSync(temporary,{recursive:true}); }
}
module.exports = {...b, DIRECTORY, EXPECTED, PURPOSE, PROVENANCE_SHA256,
  DATABASE_SHA256, SQL_SHA256, PHASE_FILES, validateRecord, checkArtifacts,
  loadFrozen, sourceHashes, state, frozenSnapshot, assertNoOverwrite, assertReplay, replay};
if (require.main === module) {
  try {
    if (process.argv.length !== 3 || process.argv[2] !== '--create')
      fail('usage: baseline.js --create (immutable predecessor cannot be recreated)');
    assertNoOverwrite();
  } catch (error) { console.error('BASELINE_INPUT:', error.message); process.exitCode = 2; }
}
