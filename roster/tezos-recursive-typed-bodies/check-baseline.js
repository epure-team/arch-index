'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const cp = require('node:child_process');
const {DatabaseSync} = require('node:sqlite');
const b = require('./baseline.js');

function run() {
  if (process.argv.length !== 2) throw new Error('usage: check-baseline.js');
  const before = b.state(), record = b.loadFrozen();
  const original = b.frozenSnapshot(record,b.readManifest({expected:b.EXPECTED}));
  assert.throws(() => b.assertReplay({...original,row_count:0},original),assert.AssertionError);
  assert.throws(() => b.assertReplay({...original,digest:'0'.repeat(64)},original),assert.AssertionError);
  assert.throws(() => b.assertReplay({...original,rows:[]},original),assert.AssertionError);
  let refusals = 0;
  const reject = mutate => {
    const bad = structuredClone(record); mutate(bad);
    assert.throws(() => b.validateRecord(bad), b.ComparisonInputError);
    refusals++;
  };
  for (const key of Object.keys(record)) reject(bad => { delete bad[key]; });
  for (const key of Object.keys(record.state)) reject(bad => { delete bad.state[key]; });
  for (const key of Object.keys(record.sealing)) reject(bad => { delete bad.sealing[key]; });
  reject(bad => { bad.extra = true; });
  reject(bad => { bad.state.extra = true; });
  reject(bad => { bad.sealing.extra = true; });
  for (const [key,value] of [['purpose','wrong'],['db','relative.db'],
    ['db_sha256','0'.repeat(64)],['source_status_unchanged',false],
    ['input_hashes_unchanged',false]]) reject(bad => { bad[key] = value; });
  reject(bad => { bad.expected.producerSha256 = '0'.repeat(64); });
  reject(bad => { bad.expected.schemaSha256 = '0'.repeat(64); });
  reject(bad => { bad.expected.manifestSha256 = '0'.repeat(64); });
  reject(bad => { bad.state.archRevision = 'bad'; });
  reject(bad => { bad.state.activeTask = 'present\0foreign\n'; });
  reject(bad => { bad.state.tezosStatus += '\n'; });
  reject(bad => { bad.state[b.PHASE_FILES[0]] = 'bad'; });
  reject(bad => { bad.sealing.sql_sha256 = '0'.repeat(64); });
  reject(bad => { bad.sealing.journal_mode = 'wal'; });
  reject(bad => { bad.sealing.all_sql_preserved = false; });
  reject(bad => { bad.db = bad.db.replace('attempt5-baseline-v2','attempt5-baseline'); });
  for (const program of ['baseline.js','prepare-baseline.js']) {
    const result = cp.spawnSync(process.execPath,[path.join(__dirname,program),'--create'],
      {cwd:os.tmpdir(),encoding:'utf8',timeout:60000});
    if (result.error || result.signal) throw result.error || Error(result.signal);
    assert.equal(result.status,2);
    assert.match(result.stderr,/refusing to overwrite attempt5 baseline/);
  }
  const originalCwd = process.cwd();
  try { process.chdir(os.tmpdir()); assert.deepEqual(b.state(),before); }
  finally { process.chdir(originalCwd); }
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(),'arch-index-attempt5-read-control-'));
  try {
    const copy = path.join(temporary,'sealed-copy.db');
    fs.copyFileSync(record.db,copy,fs.constants.COPYFILE_EXCL);
    const digest = b.fileSha256(copy);
    const db = new DatabaseSync(copy); // Intentionally writable, COPY ONLY.
    try {
      assert.equal(db.prepare('PRAGMA journal_mode').get().journal_mode,'delete');
      assert.equal(db.prepare('SELECT count(*) AS n FROM calls').get().n,b.EXPECTED.rows);
    } finally { db.close(); }
    const sqlite = cp.spawnSync('sqlite3',[copy,'SELECT count(*) FROM calls;'],
      {encoding:'utf8',timeout:30000});
    if (sqlite.error || sqlite.signal) throw sqlite.error || Error(sqlite.signal);
    if (sqlite.status !== 0) throw new Error(`sqlite3 setup failure: ${sqlite.stderr}`);
    assert.equal(sqlite.stdout.trim(),String(b.EXPECTED.rows));
    assert.equal(b.fileSha256(copy),digest);
    assert.equal(fs.existsSync(copy+'-wal'),false);
    assert.equal(fs.existsSync(copy+'-shm'),false);
  } finally { fs.rmSync(temporary,{recursive:true}); }
  const replay = b.replay();
  b.loadFrozen(); b.assertStateUnchanged(before,b.state());
  console.log(JSON.stringify({verdict:'PASS',record_refusals:refusals,
    overwrite_refused:true,cwd_independent:true,sealed_copy_read_stable:true,
    immutable_predecessor:true,semantic_failure_controls:3,replay}));
}
if (require.main === module) {
  try { run(); }
  catch (error) {
    console.error(error.stack || error);
    process.exitCode = error instanceof assert.AssertionError ? 1 : 2;
  }
}
module.exports = {run};
