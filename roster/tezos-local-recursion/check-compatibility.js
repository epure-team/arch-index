#!/usr/bin/env node
'use strict';

const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');
const os = require('node:os');
const baseline = require('./baseline.js');

const root = path.resolve(__dirname, '../..');
const predecessor = '05e4a8a';
const authorizationFile='roster/tezos-local-recursion/reference-refresh-authorization.json';
const authorizationSha256='7d6676ee3a6441ec7253e1630539b8341976c49d9dd3d38c91d40e2270a30039';
const frozen = new Map([
  ['lib/arch_index/arch_index_cmt.mli', '6834d0c154e0e354298df3ce7af8e73a1eb5a88559969891d9b773ce8fcbc424'],
  ['architecture-schema.sql', '1dd2d909e1feb2582e8a13f717ef165b7be9b73b908f73f47983920bded580d0'],
  ['lib/arch_index/call_graph_extractor.ml', '85d93403f0177f3fe66a85bc3847164280cefc8e4c237acae5f9e0d2143281cd'],
]);
const amendedPaths = [
  'test/fixtures/self-index-stats.txt',
  'test/fixtures/origin-consumer/reference.json',
  'test/fixtures/origin-consumer/self.allow',
  'checks/origin-recurring-consumer.js',
];
const protectedPaths = [
  'roster/tezos-call-resolution',
  'roster/tezos-residual-targets',
  'roster/tezos-open-bodies',
  'scripts/recalibrate.sh',
  'tezt/tests/must_null_ceiling.ml',
  '.github/workflows/ci.yml',
];
const measuredSourcePaths=['lib','bin','tezt','architecture-schema.sql','dune','dune-project','dune-workspace'];
const userSourceException='tezt/tests/lsp_doc_comment_lines.ml';

function digest(file) {
  return crypto.createHash('sha256').update(fs.readFileSync(path.join(root,file))).digest('hex');
}
function git(args) {
  const result = cp.spawnSync('git', args, {cwd:root, encoding:'utf8'});
  if (result.error || result.signal || result.status === null || result.status >= 2)
    throw new Error(`git setup failed (${result.status}): ${result.error || result.signal || result.stderr}`);
  return result;
}
function json(file){return JSON.parse(fs.readFileSync(path.join(root,file),'utf8'));}
function names(result){return result.stdout.split(/\r?\n/).filter(Boolean).sort();}
function equal(a,b,message){assert.deepEqual(a,b,message);}
function query(db,sql){
  const result=cp.spawnSync('sqlite3',['-json',db,sql],{cwd:root,encoding:'utf8'});
  if(result.error||result.signal||result.status!==0)throw Error(`sqlite evidence query failed: ${result.error||result.signal||result.stderr}`);
  return JSON.parse(result.stdout||'[]');
}
function parseCalibration(raw){
  const {parseLog,validCell}=require('../tezos-open-bodies/check-self.js');
  const parsed=parseLog(raw),cells=parsed.cells;
  assert.ok(parsed.builtBase&&parsed.builtHead&&parsed.sourceOnly.golden&&parsed.sourceOnly.ceiling,'calibration is not source-only');
  for(const metric of ['golden','ceiling'])for(const cell of ['A','B','C','D'])assert.ok(validCell(metric,cells[metric]?.[cell]||''),'malformed calibration cell');
  return {parsed,cells};
}
function sourceStatusPaths(){
  return git(['status','--porcelain=v1','-uall']).stdout.split(/\r?\n/).filter(Boolean).map(line=>line.slice(3)).filter(file=>
    measuredSourcePaths.some(prefix=>file===prefix||file.startsWith(`${prefix}/`)));
}
function validateRefresh(){
  assert.equal(digest(authorizationFile),authorizationSha256,'refresh authorization changed after recording');
  const auth=json(authorizationFile),evidence=auth.evidence;
  assert.equal(auth.version,1);assert.equal(auth.base,'05e4a8a7ba2d64ff08a15e268005f800e06ea4d7');
  assert.match(auth.candidate,/^[a-f0-9]{40}$/);assert.deepEqual(Object.keys(auth.references).sort(),amendedPaths.slice().sort());
  for(const [file,hash] of Object.entries(evidence)){assert.match(hash,/^[a-f0-9]{64}$/);assert.equal(digest(file),hash,`evidence hash changed: ${file}`);}
  for(const file of amendedPaths){const hashes=auth.references[file];assert.equal(crypto.createHash('sha256').update(git(['show',`${auth.base}:${file}`]).stdout).digest('hex'),hashes.before,`unauthorized pre-change hash: ${file}`);assert.equal(digest(file),hashes.after,`unauthorized post-change hash: ${file}`);}
  equal(names(git(['diff','--name-only',auth.base,'--',...amendedPaths])),amendedPaths.slice().sort(),'reference refresh scope changed');
  const selfPath='improvement/2026-09-14-tezos-resolution/attempt4-self-reference-N1yBlb';
  const self=json(`${selfPath}/provenance.json`),raw=fs.readFileSync(path.join(root,selfPath,'recalibrate-explain.log'));
  assert.equal(self.base,auth.base);assert.equal(self.candidate_commit,auth.candidate);assert.equal(self.recalibrate_exit,0);assert.equal(self.cleanup_verified,true);
  const calibration=parseCalibration(raw),golden=auth.golden,ceiling=auth.ceiling;
  const goldenCell=cell=>`modules: ${golden[cell][0]} functions: ${golden[cell][1]} calls: ${golden[cell][2]}`;
  for(const cell of ['A','B','C','D']){assert.equal(calibration.cells.golden[cell],goldenCell(cell));assert.equal(calibration.cells.ceiling[cell],String(ceiling[cell]));}
  assert.deepEqual(golden.A,golden.B);assert.deepEqual(golden.C,golden.D);assert.equal(ceiling.A,ceiling.B);assert.equal(ceiling.C,ceiling.D);assert.equal(ceiling.pin,524);assert.equal(ceiling.headroom,25);
  const selected=Object.keys(self.selected_sha256).sort(),snapshot=self.root_head;
  assert.match(snapshot,/^[a-f0-9]{40}$/);assert.equal(git(['rev-parse',`${auth.candidate}^`]).stdout.trim(),snapshot,'ephemeral candidate parent mismatch');
  equal(names(git(['diff','--name-only',auth.base,snapshot,'--',...measuredSourcePaths])),[],'base-to-snapshot measured source scope changed');
  equal(names(git(['diff','--name-only',snapshot,auth.candidate,'--',...measuredSourcePaths])),selected,'snapshot-to-ephemeral measured source scope changed');
  const trackedSelected=selected.filter(file=>git(['ls-files','--error-unmatch','--',file]).status===0);
  equal(names(git(['diff','--name-only',snapshot,'--',...measuredSourcePaths])),trackedSelected,'snapshot-to-current tracked measured source scope changed');
  const sourceStatus=sourceStatusPaths().filter(file=>file!==userSourceException).sort();
  // Committing the measured files must not invalidate the same calibration.
  // The snapshot diff and blob hashes bind their contents; status detects extras.
  assert.ok(sourceStatus.every(file=>selected.includes(file)),'new unmeasured current source status');
  const userSourceHash=fs.existsSync(path.join(root,userSourceException))?digest(userSourceException):null;
  for(const file of selected){const blob=cp.spawnSync('git',['show',`${auth.candidate}:${file}`],{cwd:root,encoding:null});assert.equal(blob.status,0,`candidate blob unavailable: ${file}`);const expected=self.selected_sha256[file];assert.equal(crypto.createHash('sha256').update(blob.stdout).digest('hex'),expected,`ephemeral selected blob mismatch: ${file}`);assert.equal(digest(file),expected,`current selected source changed: ${file}`);}
  const originPath='improvement/2026-09-14-tezos-resolution/attempt4-origin-attribution-wSBKDP',origin=json(`${originPath}/provenance.json`),observed=json(`${originPath}/observations.json`);
  assert.equal(origin.input_provenance_sha256,evidence[`${selfPath}/provenance.json`]);assert.equal(origin.base,auth.base);assert.equal(origin.candidate,auth.candidate);assert.equal(origin.cleanup_verified,true);
  equal(origin.source_before,origin.source_after,'origin measurement source changed while building');
  for(const cell of ['A','B','C','D']){const meta=origin.cells[cell],db=path.join(root,originPath,meta.database);assert.equal(digest(path.relative(root,db)),meta.database_sha256,`origin DB hash mismatch: ${cell}`);const totals=query(db,'select (select count(*) from modules) modules,(select count(*) from functions) functions,(select count(*) from calls) calls,(select count(*) from exn_origins) origins')[0];equal(totals,observed[cell].totals,`origin DB totals mismatch: ${cell}`);equal(query(db,'select channel,form,escapes,count(*) count from exn_origins group by channel,form,escapes order by channel,form,escapes'),observed[cell].origin_groups,`origin DB groups mismatch: ${cell}`);const assertion=query(db,`select m.path source_path,f.name function_name,o.channel,o.form,o.exn_path,o.escapes,o.line,o.col,o.operand_primitive,o.operand_slot,o.operand_category,o.operand_repr,o.operand_integer_kind,o.operand_unavailable_reason from exn_origins o join functions f on f.id=o.function_id join modules m on m.id=f.module_id where o.form='assert' order by m.path,f.name,o.line,o.col`);equal(assertion,[observed[cell].sole_assert],`origin DB assertion mismatch: ${cell}`);}
  equal(observed.A,observed.B,'origin A/B is not source-only');equal(observed.C,observed.D,'origin C/D is not source-only');
  for(const cell of ['A','B','C','D'])assert.equal(observed[cell].totals.origins,auth.origins[cell],`origin calibration mismatch: ${cell}`);
  return {userSourceHash};
}
function assertUserSourceUnchanged(refresh){
  const after=fs.existsSync(path.join(root,userSourceException))?digest(userSourceException):null;
  assert.equal(after,refresh.userSourceHash,'unmeasured user source changed during compatibility gate');
}
function child(script) {
  const result = cp.spawnSync(process.execPath, [path.join(__dirname,script)],
    {cwd:root, encoding:'utf8', timeout:20*60*1000, maxBuffer:128*1024*1024});
  if (result.error || result.signal || result.status === null || result.status >= 2)
    throw new Error(`${script} setup failed (${result.status}): ${result.error || result.signal || result.stderr}`);
  assert.equal(result.status, 0, `${script} assertion failed:\n${result.stdout}\n${result.stderr}`);
  return result.stdout;
}

function selfSmoke() {
  const temporary=fs.mkdtempSync(path.join(os.tmpdir(),'arch-index-recursive-self-'));
  try {
    const db=path.join(temporary,'self.db');
    const args=[baseline.CURRENT_PRODUCER,'--build-dir',path.join(root,'_build/default/lib/arch_index'),
      '--db-path',db,'--schema-path',baseline.CURRENT_SCHEMA];
    const localSwitch=fs.existsSync(path.join(root,'_opam'));
    const produced=cp.spawnSync(localSwitch?'opam':args[0],
      localSwitch?['exec',`--switch=${root}`,'--',...args]:args.slice(1),
      {cwd:root,encoding:'utf8',timeout:120000,maxBuffer:64*1024*1024});
    if(produced.error||produced.signal||produced.status!==0)
      throw Error(`self producer failed: ${produced.error||produced.signal||produced.stderr}`);
    const query="SELECT 'modules: ' || count(*) FROM modules; " +
      "SELECT 'functions: ' || count(*) FROM functions; " +
      "SELECT 'calls: ' || count(*) FROM calls;";
    const result=cp.spawnSync('sqlite3',[db,query],{cwd:root,encoding:'utf8',timeout:120000});
    if(result.error||result.signal||result.status!==0)
      throw Error(`self-smoke query failed: ${result.error||result.signal||result.stderr}`);
    assert.equal(result.stdout,fs.readFileSync(path.join(root,'test/fixtures/self-index-stats.txt'),'utf8'),
      'self-smoke differs: require pristine crossed attribution before any reference amendment');
  } finally {fs.rmSync(temporary,{recursive:true});}
}

function run() {
  if (process.argv.length !== 2) throw new Error('usage: check-compatibility.js');
  assert.match(git(['rev-parse','--verify',`${predecessor}^{commit}`]).stdout.trim(), /^[a-f0-9]{40}$/,
    'exact predecessor commit must be available');
  for (const [file, expected] of frozen) {
    assert.equal(digest(file), expected, `${file} changed from exact predecessor boundary`);
    const old = git(['show',`${predecessor}:${file}`]);
    const oldDigest = crypto.createHash('sha256').update(old.stdout).digest('hex');
    assert.equal(oldDigest, expected, `${file} predecessor identity mismatch`);
  }
  const protectedDiff = git(['diff','--quiet',predecessor,'--',...protectedPaths]);
  assert.equal(protectedDiff.status, 0,
    `old frozen checker/baseline policy changed: ${protectedPaths.join(', ')}`);
  const refresh=validateRefresh();
  baseline.loadFrozen();
  child('check-native.js');
  selfSmoke();
  assertUserSourceUnchanged(refresh);
  console.log(JSON.stringify({verdict:'PASS', predecessor,
    public_mli_unchanged:true, schema_unchanged:true, flat_consumer_unchanged:true,
    old_checkers_unchanged:true, frozen_baseline:true, paired_native_preservation:true,
    retention_authorized:false}));
}

if (require.main === module) {
  try { run(); }
  catch (error) {
    const assertion = error instanceof assert.AssertionError;
    console.error(`${assertion ? 'LOCAL_RECURSION_COMPAT_ASSERTION' : 'LOCAL_RECURSION_COMPAT_SETUP'}: ${error.stack || error}`);
    process.exitCode = assertion ? 1 : 2;
  }
}

module.exports = {run};
