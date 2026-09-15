#!/usr/bin/env node
'use strict';

const assert = require('node:assert/strict');
const cp = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {ROOT,TEZOS,MANIFEST,CURRENT_PRODUCER,CURRENT_SCHEMA,fileSha256,readManifest,
  relationMetrics,sourceState,assertStateUnchanged,makeSelection,produce} = require('../tezos-residual-targets/baseline.js');
const {snapshotDatabase,canonicalStrings,digestStrings} = require('../tezos-call-resolution/comparison.js');
const baselineDir=path.join(ROOT,'improvement/2026-09-15-ocaml-cfa/stage1-baseline');
const expected={rows:45052,digest:'1799c07fd3eb87d4bca433b15b7daeb47f466f90cb098541372e1dd9dd7bac7a',
  relations:{irmin:4849,protocol:12171},producer:'1cb7943cefa15a56f0df39fd2c2e741832d1acefaeedb92d189eb643075e9593',
  schema:'1dd2d909e1feb2582e8a13f717ef165b7be9b73b908f73f47983920bded580d0'};
function run(executable,args,options={}) {
  const r=cp.spawnSync(executable,args,{cwd:ROOT,encoding:'utf8',timeout:120000,maxBuffer:64*1024*1024,...options});
  if(r.error||r.signal||r.status!==0) throw new Error(`${executable}: ${r.error||r.signal||r.stderr}`);
  return r.stdout;
}
function rows(db,sql) {return JSON.parse(run('sqlite3',['-readonly','-json',db,sql]).trim()||'[]');}
function main() {
  const before=sourceState(),manifest=readManifest();
  assert.equal(before.tezosRevision,'1727d7e192f2374edda7ad7adceef6f4ec51f71a');
  assert.equal(fileSha256(path.join(baselineDir,'producer.exe')),expected.producer);
  assert.equal(fileSha256(path.join(baselineDir,'architecture-schema.sql')),expected.schema);
  const baseline=JSON.parse(fs.readFileSync(path.join(baselineDir,'snapshot.json'),'utf8'));
  // Check the logical frozen snapshot itself. Never repin from the new run or
  // rely on a possibly checkpointed SQLite WAL as the baseline authority.
  assert.equal(baseline.rows.length,expected.rows);
  assert.equal(digestStrings(canonicalStrings(baseline.rows)),expected.digest);
  assert.deepEqual(relationMetrics(baseline.rows),expected.relations);
  const temporary=fs.mkdtempSync(path.join(os.tmpdir(),'arch-data-tezos-'));
  try {
    const selection=makeSelection(temporary,manifest),db=path.join(temporary,'result.db');
    const started=Date.now(); produce(CURRENT_PRODUCER,CURRENT_SCHEMA,db,selection);
    const snapshot=snapshotDatabase(db,{expectedArtifactSuffixes:manifest.destinationSuffixes});
    assert.equal(snapshot.row_count,expected.rows);
    assert.equal(snapshot.digest,expected.digest,'fixed410 canonical graph changed');
    assert.deepEqual(relationMetrics(snapshot.rows),expected.relations);
    const emitted=run(path.join(ROOT,'_build/default/bin/arch_effects_ocaml/arch_effects_ocaml.exe'),
      ['--build-dir',selection,'--source-root',TEZOS],{cwd:TEZOS}).trim();
    const effects=emitted ? emitted.split('\n').map(JSON.parse) : [];
    assert(effects.length>0,'effect observation must be non-vacuous');
    const summary=run(path.join(ROOT,'_build/default/bin/arch_effects_load/main.exe'),
      [db,'--migration',path.join(ROOT,'effects-schema-migration.sql')],{input:emitted+'\n'}).trim();
    const stored=rows(db,'SELECT e.*,f.name AS bound_name,m.path AS bound_path FROM function_effects e LEFT JOIN functions f ON f.id=e.function_id LEFT JOIN modules m ON m.id=f.module_id');
    const payload=e=>JSON.stringify([e.function_name,e.file_path??null,e.value_kind,e.target??null,e.producer,e.soundness]);
    assert.equal(stored.length,new Set(effects.map(payload)).size,'distinct emitted effect payloads lost');
    let bound=0;
    for(const e of stored) if(e.function_id!==null) {
      bound++; assert.equal(e.bound_name,e.function_name);
      assert.equal(path.posix.normalize(e.bound_path),path.posix.normalize(e.file_path));
    }
    assert(bound>0,'bound effect observation must be non-vacuous');
    readManifest(); assertStateUnchanged(before,sourceState());
    const report={check:'CHECK3',ok:true,manifest:MANIFEST,selected:manifest.records.length,
      canonical_rows:snapshot.row_count,canonical_sha256:snapshot.digest,relations:expected.relations,
      effects:{emitted:effects.length,distinct_stored:stored.length,bound,unbound:stored.length-bound,summary},
      duration_ms:Date.now()-started,inputs_unchanged:true,source_status_unchanged:true,
      limitation:'fixed corpus non-regression and post-change effect observations, not completeness or an effect-resolution gain measurement'};
    if(process.env.ARCH_DATA_REPORT) fs.writeFileSync(process.env.ARCH_DATA_REPORT,JSON.stringify(report,null,2)+'\n');
    console.log(JSON.stringify(report));
  } finally {fs.rmSync(temporary,{recursive:true});}
}
try {main();} catch(error) {console.error(error.stack);process.exitCode=error instanceof assert.AssertionError?1:2;}
