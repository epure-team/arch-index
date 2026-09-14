'use strict';
// Preparation only: freeze/replay the PR106 producer, never admit a candidate.
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const assert = require('node:assert/strict');
const b = require('../tezos-residual-targets/baseline.js');
const {snapshotDatabase, compareSnapshots} = require('../tezos-call-resolution/comparison.js');
const directory = path.join(b.ROOT, 'improvement/2026-09-14-tezos-resolution/attempt3-baseline');
const expected = Object.freeze({...b.EXPECTED,
  producerSha256:'416e52cd88a0770a0a40f01f4f7cab20305f9591051442832abcbde5ace3158e',
  digest:'00f1769d6db7f6ee91ee51becabccd7b4ce13975acb6610c95ace69a7f620e9b',
  relations:{irmin:4781,protocol:11730}});
const purpose = 'tezos-open-bodies-pr106-frozen-predecessor';
const phaseFiles = ['briefs/tezos-open-bodies-state.json','briefs/tezos-open-bodies-manifest.txt'];
function validateState(s) {
  assert.ok(s && typeof s === 'object' && !Array.isArray(s));
  assert.deepEqual(Object.keys(s).sort(),['archRevision','archStatus','tezosRevision',
    'tezosStatus','activeTask','activeManifest',...phaseFiles].sort());
  assert.match(s.archRevision,/^[a-f0-9]{40}$/);
  for (const key of ['archStatus','tezosStatus','activeTask','activeManifest'])
    assert.equal(typeof s[key],'string');
  assert.ok(s.activeTask === 'absent\0' || s.activeTask === 'present\0tezos-open-bodies\n');
  assert.ok(s.activeManifest === 'absent\0' || s.activeManifest.startsWith('present\0'));
  for (const file of phaseFiles) {
    assert.equal(typeof s[file],'string');
    assert.ok(s[file] === 'absent' || /^[a-f0-9]{64}$/.test(s[file]));
  }
  assert.equal(s.tezosRevision,expected.tezosRevision);
  assert.equal(b.sha256(s.tezosStatus),'4abd1eead282f1bb0197d0e764dbd99c3d2203c62b0ad3f602e9e4c73875188d');
}
function state() {
  const s = b.sourceState();
  for (const file of phaseFiles) {
    const absolute = path.join(b.ROOT,file);
    s[file] = fs.existsSync(absolute) ? b.fileSha256(absolute) : 'absent';
  }
  validateState(s);
  return s;
}
function snapshot(db, manifest) {
  const s = snapshotDatabase(db,{expectedArtifactSuffixes:manifest.destinationSuffixes});
  b.validateSnapshot(s,expected);
  return s;
}
function validateRecord(r) {
  assert.equal(r.format_version,1); assert.equal(r.purpose,purpose);
  assert.deepEqual(r.expected,expected);
  for (const [key,name] of [['db','baseline.db'],['producer','producer.exe'],['schema','architecture-schema.sql']])
    assert.equal(r[key],path.join(directory,name));
  assert.equal(r.source_status_unchanged,true); assert.equal(r.input_hashes_unchanged,true);
  assert.equal(r.manifest,b.MANIFEST);
  validateState(r.state);
  assert.match(r.db_sha256,/^[a-f0-9]{64}$/);
}
function checkArtifacts(r) {
  assert.equal(b.fileSha256(r.producer),expected.producerSha256);
  assert.equal(b.fileSha256(r.schema),expected.schemaSha256);
  assert.equal(b.fileSha256(r.db),r.db_sha256);
}
function run(mode) {
  assert.ok(['--create','--check'].includes(mode),'usage: prepare-baseline.js --create|--check');
  const before = state(), manifest = b.readManifest();
  if (mode === '--create') {
    assert.ok(!fs.existsSync(directory),'refusing to overwrite attempt3 baseline');
    assert.equal(b.fileSha256(b.CURRENT_PRODUCER),expected.producerSha256);
    assert.equal(b.fileSha256(b.CURRENT_SCHEMA),expected.schemaSha256);
  }
  const temp = fs.mkdtempSync(path.join(os.tmpdir(),'arch-index-attempt3-baseline-'));
  let staging;
  try {
    let record;
    if (mode === '--create') {
      staging = fs.mkdtempSync(path.join(path.dirname(directory),'.attempt3-baseline-'));
      fs.copyFileSync(b.CURRENT_PRODUCER,path.join(staging,'producer.exe'),fs.constants.COPYFILE_EXCL);
      fs.copyFileSync(b.CURRENT_SCHEMA,path.join(staging,'architecture-schema.sql'),fs.constants.COPYFILE_EXCL);
      record = {format_version:1,purpose,expected,manifest:b.MANIFEST,state:before,
        db:path.join(directory,'baseline.db'),producer:path.join(directory,'producer.exe'),
        schema:path.join(directory,'architecture-schema.sql'),
        source_status_unchanged:true,input_hashes_unchanged:true};
      b.produce(path.join(staging,'producer.exe'),path.join(staging,'architecture-schema.sql'),
        path.join(staging,'baseline.db'),b.makeSelection(temp,manifest));
      record.db_sha256 = b.fileSha256(path.join(staging,'baseline.db'));
    } else record = JSON.parse(fs.readFileSync(path.join(directory,'provenance.json')));
    validateRecord(record);
    const actual = staging ? {...record,db:path.join(staging,'baseline.db'),
      producer:path.join(staging,'producer.exe'),schema:path.join(staging,'architecture-schema.sql')} : record;
    checkArtifacts(actual);
    const original = snapshot(actual.db,manifest);
    const replayDir = path.join(temp,'replay'); fs.mkdirSync(replayDir);
    const replayDb = path.join(replayDir,'replay.db');
    b.produce(actual.producer,actual.schema,replayDb,b.makeSelection(replayDir,manifest));
    const replay = snapshot(replayDb,manifest);
    const comparison = compareSnapshots(original,replay);
    assert.ok(comparison.ok && comparison.neutral,'frozen replay must be exactly neutral');
    b.readManifest(); checkArtifacts(actual); b.assertStateUnchanged(before,state());
    if (staging) {
      assert.equal(b.fileSha256(b.CURRENT_PRODUCER),expected.producerSha256);
      assert.equal(b.fileSha256(b.CURRENT_SCHEMA),expected.schemaSha256);
      fs.writeFileSync(path.join(staging,'provenance.json'),JSON.stringify(record,null,2)+'\n',{flag:'wx'});
      assert.ok(!fs.existsSync(directory)); fs.renameSync(staging,directory); staging = null;
    }
    console.log(`PASS ${mode}: ${replay.row_count}/${replay.digest}; Irmin4781/protocol11730; neutral, no gain`);
  } finally {
    fs.rmSync(temp,{recursive:true});
    if(staging) fs.rmSync(staging,{recursive:true});
  }
}
if(require.main === module) {
  try { assert.equal(process.argv.length,3); run(process.argv[2]); }
  catch(e) { console.error('SETUP FAILED:',e.stack); process.exitCode=2; }
}
module.exports={expected,directory,purpose,validateRecord,checkArtifacts,state,validateState};
