'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const cp = require('node:child_process');
const b = require('./baseline.js');

function run() {
  if (process.argv.length !== 2) throw new Error('usage: check-baseline.js');
  const before = b.state(), record = b.loadFrozen();
  let refusals = 0;
  const reject = mutate => {
    const bad = structuredClone(record); mutate(bad);
    assert.throws(() => b.validateRecord(bad), b.ComparisonInputError);
    refusals++;
  };
  for (const key of Object.keys(record)) reject(bad => { delete bad[key]; });
  for (const key of Object.keys(record.state)) reject(bad => { delete bad.state[key]; });
  for (const [key, value] of [['purpose','wrong'],['db','relative.db'],
    ['db_sha256','0'.repeat(64)],['source_status_unchanged',false],
    ['input_hashes_unchanged',false],['created_at','invalid']]) reject(bad => { bad[key] = value; });
  reject(bad => { bad.expected.producerSha256 = '0'.repeat(64); });
  reject(bad => { bad.expected.schemaSha256 = '0'.repeat(64); });
  reject(bad => { bad.expected.manifestSha256 = '0'.repeat(64); });
  reject(bad => { bad.state.archRevision = 'bad'; });
  reject(bad => { bad.state.activeTask = 'present\0foreign\n'; });
  reject(bad => { bad.state.tezosStatus += '\n'; });
  reject(bad => { bad.state[b.PHASE_FILES[0]] = 'bad'; });
  const recreate = cp.spawnSync(process.execPath, [path.join(__dirname,'baseline.js'),'--create'],
    {cwd:os.tmpdir(), encoding:'utf8'});
  if (recreate.error || recreate.signal) throw recreate.error || Error(recreate.signal);
  assert.equal(recreate.status, 2);
  assert.match(recreate.stderr, /refusing to overwrite attempt4 baseline/);
  const originalCwd = process.cwd();
  try { process.chdir(os.tmpdir()); assert.deepEqual(b.state(), before); }
  finally { process.chdir(originalCwd); }
  const replay = b.replay();
  b.assertStateUnchanged(before, b.state());
  assert.equal(b.fileSha256(path.join(b.DIRECTORY,'provenance.json')), b.PROVENANCE_SHA256);
  console.log(JSON.stringify({verdict:'PASS',record_refusals:refusals,
    overwrite_refused:true,cwd_independent:true,immutable_predecessor:true,replay}));
}
if (require.main === module) {
  try { run(); }
  catch (error) {
    console.error(error.stack || error);
    process.exitCode = error instanceof assert.AssertionError ? 1 : 2;
  }
}
module.exports = {run};
