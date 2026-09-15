'use strict';
// Preparation only: freeze/replay the PR108 producer, never admit a candidate.
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const assert = require('node:assert/strict');
const b = require('../tezos-residual-targets/baseline.js');
const {snapshotDatabase, compareSnapshots} = require('../tezos-call-resolution/comparison.js');
const directory = path.join(b.ROOT, 'improvement/2026-09-14-tezos-resolution/attempt5-baseline-v2');
const expected = Object.freeze({...b.EXPECTED,
  producerSha256:'48f1412002321dca745040a70f00f04c440fb4086d61bc2efb09482cc1af2136',
  digest:'082bdce92c6cab7b654f87a90db59ca9979d7004f45a42997a33718f6cd7c67a',
  relations:{irmin:4849,protocol:12157}});
const purpose = 'tezos-recursive-typed-bodies-pr108-sealed-predecessor-v2';
const phaseFiles = ['briefs/tezos-recursive-typed-bodies-state.json','briefs/tezos-recursive-typed-bodies-manifest.txt'];
const {DatabaseSync} = require('node:sqlite');
function sqlDigest(file) {
  const db = new DatabaseSync(file,{readOnly:true});
  try {
    const schema = db.prepare('SELECT type,name,tbl_name,sql FROM sqlite_schema ORDER BY type,name').all();
    const tables = db.prepare("SELECT name FROM sqlite_schema WHERE type='table' ORDER BY name").all();
    const rows = tables.map(({name}) => [name,
      db.prepare(`SELECT * FROM "${name.replaceAll('"','""')}"`).all()
        .map(row => JSON.stringify(row)).sort()]);
    return b.sha256(JSON.stringify({schema,rows}));
  } finally { db.close(); }
}
function assertSealed(file) {
  assert.equal(fs.existsSync(file+'-wal'),false,'frozen WAL sidecar forbidden');
  assert.equal(fs.existsSync(file+'-shm'),false,'frozen SHM sidecar forbidden');
  const header = fs.readFileSync(file).subarray(0,100);
  assert.equal(header[18],1,'frozen database must use rollback journal write mode');
  assert.equal(header[19],1,'frozen database must use rollback journal read mode');
}
function seal(file) {
  const before = sqlDigest(file);
  const db = new DatabaseSync(file);
  try {
    const checkpoint = db.prepare('PRAGMA wal_checkpoint(TRUNCATE)').get();
    assert.equal(checkpoint.busy,0,'staging checkpoint must not be busy');
    assert.equal(db.prepare('PRAGMA journal_mode=DELETE').get().journal_mode,'delete');
  } finally { db.close(); }
  assertSealed(file);
  const after = sqlDigest(file);
  assert.equal(after,before,'sealing must preserve every SQL table row and schema definition');
  return {journal_mode:'delete',sql_sha256:after,all_sql_preserved:true};
}
function validateState(s) {
  assert.ok(s && typeof s === 'object' && !Array.isArray(s));
  assert.deepEqual(Object.keys(s).sort(),['archRevision','archStatus','tezosRevision',
    'tezosStatus','activeTask','activeManifest','sourceFingerprint',...phaseFiles].sort());
  assert.match(s.sourceFingerprint,/^[a-f0-9]{64}$/);
  assert.match(s.archRevision,/^[a-f0-9]{40}$/);
  for (const key of ['archStatus','tezosStatus','activeTask','activeManifest'])
    assert.equal(typeof s[key],'string');
  assert.ok(s.activeTask === 'absent\0' || s.activeTask === 'present\0tezos-recursive-typed-bodies\n');
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
  const manifestPath = path.join(b.ROOT, phaseFiles[1]);
  s.activeManifest = fs.existsSync(manifestPath) ? `present\0${fs.readFileSync(manifestPath, 'utf8')}` : 'absent\0';
  const sourcePaths = require('node:child_process').execFileSync('git',
    ['ls-files', 'lib', 'tezt', 'architecture-schema.sql'], {cwd:b.ROOT, encoding:'utf8'})
    .trim().split('\n').filter(Boolean);
  for (const name of fs.readdirSync(__dirname)) {
    const file = path.join(__dirname, name);
    if (fs.statSync(file).isFile()) sourcePaths.push(path.relative(b.ROOT,file));
  }
  s.sourceFingerprint = b.sha256(JSON.stringify(sourcePaths.sort().map(file => [file,b.fileSha256(path.join(b.ROOT,file))])));
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
  assert.equal(r.sealing.journal_mode,'delete');
  assert.equal(r.sealing.all_sql_preserved,true);
  assert.match(r.sealing.sql_sha256,/^[a-f0-9]{64}$/);
  assert.equal(r.manifest,b.MANIFEST);
  validateState(r.state);
  assert.match(r.db_sha256,/^[a-f0-9]{64}$/);
}
function checkArtifacts(r) {
  assert.equal(b.fileSha256(r.producer),expected.producerSha256);
  assert.equal(b.fileSha256(r.schema),expected.schemaSha256);
  assert.equal(b.fileSha256(r.db),r.db_sha256);
  assertSealed(r.db);
  assert.equal(sqlDigest(r.db),r.sealing.sql_sha256);
}
function run(mode) {
  assert.ok(['--create','--check'].includes(mode),'usage: prepare-baseline.js --create|--check');
  const before = state(), manifest = b.readManifest({expected});
  if (mode === '--create') {
    assert.ok(!fs.existsSync(directory),'refusing to overwrite attempt5 baseline');
    assert.equal(b.fileSha256(b.CURRENT_PRODUCER),expected.producerSha256);
    assert.equal(b.fileSha256(b.CURRENT_SCHEMA),expected.schemaSha256);
  }
  const temp = fs.mkdtempSync(path.join(os.tmpdir(),'arch-index-attempt5-baseline-'));
  let staging;
  try {
    let record;
    if (mode === '--create') {
      staging = fs.mkdtempSync(path.join(path.dirname(directory),'.attempt5-baseline-'));
      fs.copyFileSync(b.CURRENT_PRODUCER,path.join(staging,'producer.exe'),fs.constants.COPYFILE_EXCL);
      fs.copyFileSync(b.CURRENT_SCHEMA,path.join(staging,'architecture-schema.sql'),fs.constants.COPYFILE_EXCL);
      record = {format_version:1,purpose,expected,manifest:b.MANIFEST,state:before,
        db:path.join(directory,'baseline.db'),producer:path.join(directory,'producer.exe'),
        schema:path.join(directory,'architecture-schema.sql'),
        source_status_unchanged:true,input_hashes_unchanged:true};
      b.produce(path.join(staging,'producer.exe'),path.join(staging,'architecture-schema.sql'),
        path.join(staging,'baseline.db'),b.makeSelection(temp,manifest));
      record.sealing = seal(path.join(staging,'baseline.db'));
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
    const readCopy = path.join(temp,'read-stability.db');
    fs.copyFileSync(actual.db,readCopy,fs.constants.COPYFILE_EXCL);
    const readHash = b.fileSha256(readCopy);
    const read = require('node:child_process').spawnSync('sqlite3',
      [readCopy,'SELECT count(*) FROM calls;'],{encoding:'utf8',timeout:30000});
    assert.equal(read.status,0,read.stderr);
    assert.equal(read.stdout.trim(),String(expected.rows));
    assert.equal(b.fileSha256(readCopy),readHash,'ordinary SELECT must preserve sealed copy bytes');
    assertSealed(readCopy);
    b.readManifest({expected}); checkArtifacts(actual); b.assertStateUnchanged(before,state());
    if (staging) {
      assert.equal(b.fileSha256(b.CURRENT_PRODUCER),expected.producerSha256);
      assert.equal(b.fileSha256(b.CURRENT_SCHEMA),expected.schemaSha256);
      fs.writeFileSync(path.join(staging,'provenance.json'),JSON.stringify(record,null,2)+'\n',{flag:'wx'});
      assert.ok(!fs.existsSync(directory)); fs.renameSync(staging,directory); staging = null;
    }
    console.log(`PASS ${mode}: ${replay.row_count}/${replay.digest}; Irmin4849/protocol12157; neutral, no gain`);
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
