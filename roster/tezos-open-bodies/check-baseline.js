'use strict';
const fs=require('node:fs');
const assert=require('node:assert/strict');
const p=require('./prepare-baseline.js');
try {
  const args=process.argv.slice(2);
  if(args.length>1 || (args.length===1 && args[0]!=='--replay'))
    throw Error('usage: check-baseline.js [--replay]');
  const frozenRecord=fs.readFileSync(p.directory+'/provenance.json');
  const r=JSON.parse(frozenRecord);
  p.validateRecord(r); p.checkArtifacts(r);
  let count=0;
  for(const key of Object.keys(r.state)) {
    const bad=structuredClone(r); delete bad.state[key];
    assert.throws(()=>p.validateRecord(bad)); count++;
  }
  for(const [key,value] of [['archRevision','bad'],['archStatus',null],
    ['activeTask','present\0foreign\n'],['briefs/tezos-open-bodies-state.json','bad']]) {
    const bad=structuredClone(r); bad.state[key]=value;
    assert.throws(()=>p.validateRecord(bad)); count++;
  }
  for(const [key,value] of [['purpose','wrong'],['db','relative.db'],
    ['db_sha256','bad'],['source_status_unchanged',false],['input_hashes_unchanged',false]]) {
    const bad=structuredClone(r); bad[key]=value;
    assert.throws(()=>p.validateRecord(bad)); count++;
  }
  const before=p.state(); process.chdir(require('node:os').tmpdir());
  assert.deepEqual(p.state(),before);
  const recreate=require('node:child_process').spawnSync(process.execPath,
    [require('node:path').join(__dirname,'prepare-baseline.js'),'--create'],{encoding:'utf8'});
  if(recreate.error) throw recreate.error;
  assert.equal(recreate.status,2);
  assert.match(recreate.stderr,/refusing to overwrite attempt3 baseline/);
  if(args[0]==='--replay') {
    const replay=require('node:child_process').spawnSync(process.execPath,
      [require('node:path').join(__dirname,'prepare-baseline.js'),'--check'],
      {encoding:'utf8',maxBuffer:16*1024*1024});
    if(replay.error || replay.status!==0)
      throw Error(`frozen replay setup failed: ${replay.error || replay.stderr}`);
    process.stdout.write(replay.stdout);
  }
  assert.deepEqual(fs.readFileSync(p.directory+'/provenance.json'),frozenRecord);
  p.checkArtifacts(r);
  console.log(`PASS baseline: positive frozen artifacts, ${count} record refusals, recreate refusal, cwd independence, unchanged frozen bytes`);
} catch(e) {
  console.error(e.stack);
  process.exitCode=e.code==='ERR_ASSERTION'?1:2;
}
