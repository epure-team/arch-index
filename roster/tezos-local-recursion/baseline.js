'use strict';

// This attempt consumes the already established PR107 baseline. Historical
// producers, manifests and checker modules are read-only inputs, never refreshed.
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const cp = require('node:child_process');
const assert = require('node:assert/strict');
const b = require('../tezos-residual-targets/baseline.js');
const {snapshotDatabase, compareSnapshots, ComparisonInputError} =
  require('../tezos-call-resolution/comparison.js');

const ROOT = b.ROOT;
const DIRECTORY = path.join(ROOT, 'improvement/2026-09-14-tezos-resolution/attempt4-baseline');
const PURPOSE = 'tezos-local-recursion-pr107-frozen-predecessor';
const PROVENANCE_SHA256 = '30779a741f5c8f40653eaab7017c6ca53030698d2328decfdf267228004e0084';
const DATABASE_SHA256 = 'c85df8f4ed6847f822ee79dbb8061f8779c5cd009bb25d6512c0e7d36daf2f01';
const EXPECTED = Object.freeze({...b.EXPECTED,
  producerSha256: '992f4b252fb14d62cc64616bc88292883b7706a87e39ca9927bd498d0f1c5391',
  digest: '9ab4e0b13457247fb93dc83bf80323fcc5cec67866a18f56995ac0ec4a20867e',
  relations: Object.freeze({irmin: 4781, protocol: 12046})});
const TASK = 'tezos-local-recursion';
const PHASE_FILES = [`briefs/${TASK}-state.json`, `briefs/${TASK}-manifest.txt`];
const TEZOS_STATUS_SHA256 = '4abd1eead282f1bb0197d0e764dbd99c3d2203c62b0ad3f602e9e4c73875188d';
const fail = message => { throw new ComparisonInputError(message); };
const optional = file => fs.existsSync(file) ? `present\0${fs.readFileSync(file, 'utf8')}` : 'absent\0';

function inputValidation(fn) {
  try { return fn(); }
  catch (error) {
    if (error instanceof ComparisonInputError) throw error;
    fail(error.message);
  }
}

function validateRecord(record) {
  return inputValidation(() => {
    assert.ok(record && typeof record === 'object' && !Array.isArray(record));
    assert.deepEqual(Object.keys(record).sort(), ['format_version','purpose','created_at',
      'expected','manifest','state','db','producer','schema','db_sha256',
      'source_status_unchanged','input_hashes_unchanged'].sort());
    assert.equal(record.format_version, 1);
    assert.equal(record.purpose, PURPOSE);
    assert.equal(typeof record.created_at, 'string');
    assert.ok(Number.isFinite(Date.parse(record.created_at)));
    assert.deepEqual(record.expected, EXPECTED);
    assert.equal(record.manifest, b.MANIFEST);
    for (const [key, name] of [['db','baseline.db'],['producer','producer.exe'],
      ['schema','architecture-schema.sql']]) assert.equal(record[key], path.join(DIRECTORY, name));
    assert.equal(record.db_sha256, DATABASE_SHA256);
    assert.equal(record.source_status_unchanged, true);
    assert.equal(record.input_hashes_unchanged, true);
    const state = record.state;
    assert.ok(state && typeof state === 'object' && !Array.isArray(state));
    assert.deepEqual(Object.keys(state).sort(), ['archRevision','archStatus',
      'tezosRevision','tezosStatus','activeTask','activeManifest',...PHASE_FILES].sort());
    assert.match(state.archRevision, /^[a-f0-9]{40}$/);
    for (const key of ['archStatus','tezosStatus','activeTask','activeManifest'])
      assert.equal(typeof state[key], 'string');
    assert.equal(state.tezosRevision, EXPECTED.tezosRevision);
    assert.equal(b.sha256(state.tezosStatus), TEZOS_STATUS_SHA256);
    assert.ok(['absent\0', `present\0${TASK}\n`].includes(state.activeTask));
    assert.ok(state.activeManifest === 'absent\0' || state.activeManifest.startsWith('present\0'));
    for (const file of PHASE_FILES)
      assert.ok(state[file] === 'absent' || /^[a-f0-9]{64}$/.test(state[file]));
    return record;
  });
}

function loadFrozen() {
  return inputValidation(() => {
    const provenance = path.join(DIRECTORY, 'provenance.json');
    if (b.fileSha256(provenance) !== PROVENANCE_SHA256) fail('immutable PR107 provenance changed');
    const record = validateRecord(JSON.parse(fs.readFileSync(provenance, 'utf8')));
    checkArtifacts(record);
    return record;
  });
}

function checkArtifacts(record) {
  return inputValidation(() => {
    for (const [key, wanted] of [['producer',EXPECTED.producerSha256],
      ['schema',EXPECTED.schemaSha256],['db',DATABASE_SHA256]])
      if (b.fileSha256(record[key]) !== wanted) fail(`frozen ${key} changed`);
  });
}

function sourceHashes() {
  const files = ['lib/arch_index/arch_index_cmt.ml',
    'lib/arch_index/arch_index_cmt.mli','lib/arch_index/call_graph_extractor.ml',
    'architecture-schema.sql','tezt/tests/local_recursion_targets.ml',
    'tezt/tests/main.ml','tezt/tests/dune',`specs/${TASK}.md`];
  function walk(directory) {
    for (const entry of fs.readdirSync(path.join(ROOT, directory), {withFileTypes:true})) {
      const relative = `${directory}/${entry.name}`;
      if (entry.isDirectory()) walk(relative);
      else if (entry.isFile()) files.push(relative);
      else fail(`unexpected non-regular task source: ${relative}`);
    }
  }
  walk(`roster/${TASK}`);
  return Object.fromEntries(files.sort().map(file => [file,
    fs.existsSync(path.join(ROOT, file)) ? b.fileSha256(path.join(ROOT, file)) : null]));
}

function state() {
  const result = b.sourceState();
  // The predecessor helper's ACTIVE_MANIFEST points to attempt2. Override it;
  // retaining that old slot here would leave this attempt's scope unchecked.
  result.activeManifest = optional(path.join(ROOT, PHASE_FILES[1]));
  for (const file of PHASE_FILES) result[file] = fs.existsSync(path.join(ROOT, file))
    ? b.fileSha256(path.join(ROOT, file)) : 'absent';
  if (result.tezosRevision !== EXPECTED.tezosRevision
    || b.sha256(result.tezosStatus) !== TEZOS_STATUS_SHA256) fail('protected Tezos source state changed');
  if (!['absent\0', `present\0${TASK}\n`, `present\0${TASK}`].includes(result.activeTask))
    fail('foreign ACTIVE_TASK');
  if (result.activeTask !== 'absent\0'
    && (!result.activeManifest.startsWith('present\0base=')
      || !result.activeManifest.includes(`\nroster/${TASK}/\n`))) fail('active task scope manifest missing');
  result.sourceFingerprint = JSON.stringify(sourceHashes());
  return result;
}

function frozenSnapshot(record, manifest) {
  const snapshot = snapshotDatabase(record.db,
    {expectedArtifactSuffixes:manifest.destinationSuffixes});
  b.validateSnapshot(snapshot, EXPECTED);
  return snapshot;
}

function assertNoOverwrite(directory = DIRECTORY) {
  if (fs.existsSync(directory)) fail('refusing to overwrite attempt4 baseline');
  // A missing immutable predecessor is not a request to rebuild it with the
  // current candidate. Restore the original evidence, never silently replace it.
  fail('immutable attempt4 predecessor missing; restoration required');
}

function replay() {
  const before = state(), record = loadFrozen();
  const manifest = b.readManifest({expected:EXPECTED});
  const original = frozenSnapshot(record, manifest);
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'arch-index-recursive-baseline-'));
  try {
    const producer = path.join(temporary, 'producer.exe');
    fs.copyFileSync(record.producer, producer, fs.constants.COPYFILE_EXCL);
    if (b.fileSha256(producer) !== EXPECTED.producerSha256) fail('copied predecessor changed');
    const db = path.join(temporary, 'replay.db');
    b.produce(producer, record.schema, db, b.makeSelection(temporary, manifest));
    const repeated = snapshotDatabase(db, {expectedArtifactSuffixes:manifest.destinationSuffixes});
    b.validateSnapshot(repeated, EXPECTED);
    const comparison = compareSnapshots(original, repeated);
    if (!comparison.ok || !comparison.neutral) fail('PR107 copied-binary replay not neutral');
    b.readManifest({expected:EXPECTED}); loadFrozen();
    b.assertStateUnchanged(before, state());
    return {rows:repeated.row_count, digest:repeated.digest,
      relations:b.relationMetrics(repeated.rows), neutral:true};
  } finally { fs.rmSync(temporary, {recursive:true}); }
}

module.exports = {...b, ROOT, DIRECTORY, PURPOSE, PROVENANCE_SHA256, DATABASE_SHA256,
  EXPECTED, PHASE_FILES, validateRecord, loadFrozen, checkArtifacts, state,
  sourceHashes, frozenSnapshot, assertNoOverwrite, replay};

if (require.main === module) {
  try {
    if (process.argv.length !== 3 || process.argv[2] !== '--create')
      fail('usage: baseline.js --create (immutable predecessor cannot be overwritten)');
    assertNoOverwrite();
  } catch (error) { console.error('BASELINE_INPUT:', error.message); process.exitCode = 2; }
}
