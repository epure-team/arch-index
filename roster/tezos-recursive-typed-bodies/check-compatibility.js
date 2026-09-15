'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const cp=require('node:child_process'),os=require('node:os');
const b=require('./baseline.js');
const predecessor='4a952441fcd7648d20e68b5c6348de1b3fe85522';
const frozen={
  'lib/arch_index/arch_index_cmt.mli':'6834d0c154e0e354298df3ce7af8e73a1eb5a88559969891d9b773ce8fcbc424',
  'architecture-schema.sql':'1dd2d909e1feb2582e8a13f717ef165b7be9b73b908f73f47983920bded580d0',
  'lib/arch_index/call_graph_extractor.ml':'85d93403f0177f3fe66a85bc3847164280cefc8e4c237acae5f9e0d2143281cd',
};
const protectedPaths=['roster/tezos-call-resolution','roster/tezos-residual-targets',
  'roster/tezos-open-bodies','roster/tezos-local-recursion','scripts/recalibrate.sh',
  'tezt/tests/must_null_ceiling.ml','.github/workflows/ci.yml',
  'test/fixtures/self-index-stats.txt','test/fixtures/origin-consumer/reference.json',
  'test/fixtures/origin-consumer/self.allow','checks/origin-recurring-consumer.js'];
const allowedSource=new Set(['lib/arch_index/arch_index_cmt.ml',
  'tezt/tests/recursive_open_body_targets.ml','tezt/tests/main.ml','tezt/tests/dune']);
function run(command,args,options={}){
  const r=cp.spawnSync(command,args,{cwd:b.ROOT,encoding:'utf8',timeout:120000,maxBuffer:128*1024*1024,...options});
  if(r.error||r.signal||r.status===null)throw Error(`${command} setup: ${r.error||r.signal}`);
  return r;
}
function git(args){const r=run('git',args);if(r.status!==0)throw Error(`git setup ${r.status}: ${r.stderr}`);return r.stdout;}
function child(name){
  const r=run(process.execPath,[path.join(__dirname,name)]);
  if(r.status>=2)throw Error(`${name} setup: ${r.stderr}`);
  assert.equal(r.status,0,`${name} assertion: ${r.stdout}\n${r.stderr}`);
}
function selfSmoke(){
  const temp=fs.mkdtempSync(path.join(os.tmpdir(),'arch-index-open-recursive-self-'));
  try{
    const db=path.join(temp,'self.db');
    const produced=run(b.CURRENT_PRODUCER,['--build-dir',path.join(b.ROOT,'_build/default/lib/arch_index'),
      '--db-path',db,'--schema-path',b.CURRENT_SCHEMA]);
    if(produced.status!==0)throw Error(`self producer setup: ${produced.stderr}`);
    const r=run('sqlite3',[db,"SELECT 'modules: ' || count(*) FROM modules; SELECT 'functions: ' || count(*) FROM functions; SELECT 'calls: ' || count(*) FROM calls;"]);
    if(r.status!==0)throw Error(`self SQL setup: ${r.stderr}`);
    assert.equal(r.stdout,fs.readFileSync(path.join(b.ROOT,'test/fixtures/self-index-stats.txt'),'utf8'),
      'self-smoke mismatch requires pristine attribution and explicit path authorization, not automatic refresh');
  }finally{fs.rmSync(temp,{recursive:true});}
}
function main(){
  if(process.argv.length!==2)throw Error('usage: check-compatibility.js');
  const before=b.state(),producer=b.fileSha256(b.CURRENT_PRODUCER);
  assert.equal(git(['rev-parse',`${predecessor}^{commit}`]).trim(),predecessor);
  for(const [file,digest] of Object.entries(frozen)){
    assert.equal(b.fileSha256(path.join(b.ROOT,file)),digest,`${file} current boundary changed`);
    assert.equal(b.sha256(git(['show',`${predecessor}:${file}`])),digest,`${file} predecessor boundary changed`);
  }
  assert.equal(git(['diff','--name-only',predecessor,'--',...protectedPaths]),'',
    'historical checker/self-policy/CI changes are not authorized');
  const changed=git(['diff','--name-only',predecessor,'--','lib','bin','tezt','architecture-schema.sql']).split('\n').filter(Boolean);
  assert.ok(changed.every(file=>allowedSource.has(file)),'out-of-scope tracked source change');
  const untracked=git(['ls-files','--others','--exclude-standard','--','lib','bin','tezt']).split('\n').filter(Boolean);
  assert.ok(untracked.every(file=>allowedSource.has(file)||file==='tezt/tests/lsp_doc_comment_lines.ml'),
    'out-of-scope new source file');
  b.loadFrozen();
  child('check-native.js');
  selfSmoke();
  assert.equal(b.fileSha256(b.CURRENT_PRODUCER),producer,'producer changed during compatibility');
  b.assertStateUnchanged(before,b.state());
  console.log(JSON.stringify({verdict:'PASS',predecessor,public_schema_flat_unchanged:true,
    old_checkers_self_policy_unchanged:true,paired_native_preservation:true,retention_authorized:false,
    ci_verified:false}));
}
if(require.main===module){try{main();}catch(e){console.error(e.stack||e);process.exitCode=e instanceof assert.AssertionError?1:2;}}
module.exports={run:main};
