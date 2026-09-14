#!/usr/bin/env node
'use strict';

const assert = require('node:assert/strict');
const cp = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {DatabaseSync} = require('node:sqlite');
const {compareSnapshots, snapshotDatabase} = require('./comparison.js');
const {PURPOSE, sha256, readManifest, validateSnapshot, validateProvenance, loadFrozen} = require('./baseline.js');

let assertions = 0;
function check(value, message) { assert.ok(value, message); assertions++; }
function rejects(fn, pattern) { assert.throws(fn, pattern); assertions++; }
function writeFixtureDb(file, artifacts, options = {}) {
  const db = new DatabaseSync(file);
  db.exec(`PRAGMA foreign_keys=ON;
    CREATE TABLE modules(id INTEGER PRIMARY KEY,path TEXT NOT NULL);
    CREATE TABLE functions(id INTEGER PRIMARY KEY,module_id INTEGER NOT NULL REFERENCES modules(id),name TEXT NOT NULL,line_start INTEGER,line_end INTEGER);
    CREATE TABLE calls(id INTEGER PRIMARY KEY,caller_id INTEGER NOT NULL REFERENCES functions(id),callee_id INTEGER REFERENCES functions(id),callee_name TEXT NOT NULL,call_site TEXT,kind TEXT,edge_form TEXT,top_reason TEXT,top_anchor TEXT);
    CREATE TABLE functor_catalogue_runs(producer_run_id INTEGER,selected_inputs INTEGER);
    CREATE TABLE functor_catalogue_inputs(producer_run_id INTEGER,artifact TEXT,outcome TEXT,module_id INTEGER);
    CREATE TABLE functor_binding_inputs(producer_run_id INTEGER,artifact TEXT,outcome TEXT);
    INSERT INTO modules VALUES(1,'irmin/a.ml'),(2,'src/proto_alpha/p.ml');
    INSERT INTO functions VALUES(1,1,'run',1,3),(2,1,'M.f',4,5),(3,2,'go',1,3),(4,2,'P.f',4,5);
    INSERT INTO calls VALUES(1,1,2,'M.f','irmin/a.ml:2','MAY_ENUMERATED',NULL,NULL,NULL),(2,3,4,'P.f','src/proto_alpha/p.ml:2','MAY_ENUMERATED',NULL,NULL,NULL);
    INSERT INTO functor_catalogue_runs VALUES(7,${options.selected ?? artifacts.length});`);
  const catalogue = db.prepare('INSERT INTO functor_catalogue_inputs VALUES(?,?,?,?)');
  const binding = db.prepare('INSERT INTO functor_binding_inputs VALUES(?,?,?)');
  for (let i = 0; i < artifacts.length; i++) {
    const run = options.foreignIndex === i ? 8 : 7;
    catalogue.run(run, artifacts[i], 'collected', 1);
    if (options.missingBinding !== i) binding.run(run, artifacts[i], 'collected');
    if (options.duplicateBinding === i) binding.run(run, artifacts[i], 'collected');
  }
  db.close();
}

const row = {caller_path:'irmin/a.ml',caller:'run',call_site:'irmin/a.ml:9',target_path:'irmin/a.ml',target:'M.f',callee_name:'M.f',kind:'MAY_ENUMERATED',edge_form:null,top_reason:null,top_anchor:null};
const pointFree = {...row, call_site:null, edge_form:'value_alias'};
const expectedProvenance = {
  selected:2, manifestSha256:'a'.repeat(64), producerSha256:'b'.repeat(64), schemaSha256:'c'.repeat(64),
  tezosRevision:'d'.repeat(40), rows:2, digest:'e'.repeat(64), relations:{irmin:1,protocol:1},
};

try {
  const {validateActivePhase} = require('./baseline.js');
  const inactive = {activeTask: 'absent\0', activeManifest: 'absent\0'};
  rejects(() => validateActivePhase(inactive), /ACTIVE_TASK/);
  validateActivePhase(inactive, {allowInactive: true});
  check(true, 'released roster slot permits read-only review replay');
  rejects(() => validateActivePhase({...inactive, activeTask: 'present\0foreign'}, {allowInactive: true}), /ACTIVE_TASK/);
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'arch-index-attempt2-controls-'));
  try {
    const inputs = path.join(temporary, 'inputs'); fs.mkdirSync(inputs);
    const artifacts = [];
    for (let i=0;i<2;i++) { const file=path.join(inputs, `a${i}.cmt`); fs.writeFileSync(file, `cmt${i}`); artifacts.push(file); }
    const records = artifacts.map((file,i)=>`slice${i}\t${sha256(fs.readFileSync(file))}\t${file}`).join('\n')+'\n';
    const manifestFile=path.join(temporary,'manifest.tsv');fs.writeFileSync(manifestFile,records);
    const manifestExpected={...expectedProvenance,manifestSha256:sha256(Buffer.from(records))};
    const manifest=readManifest({manifestFile,expected:manifestExpected});
    check(manifest.records.length===2, 'synthetic manifest positive control');
    fs.appendFileSync(manifestFile,'malformed\n');
    rejects(()=>readManifest({manifestFile,expected:{...manifestExpected,manifestSha256:sha256(fs.readFileSync(manifestFile))}}),/incomplete or malformed/);
    fs.writeFileSync(manifestFile,records);
    fs.writeFileSync(artifacts[0],'changed');
    rejects(()=>readManifest({manifestFile,expected:manifestExpected}),/input hash mismatch/);
    fs.writeFileSync(artifacts[0],'cmt0');

    const suffixes=Array.from({length:410},(_,i)=>`slice${i}/a${i}.cmt`);
    const dbFile=path.join(temporary,'good.db');writeFixtureDb(dbFile,suffixes);
    const snapshot=snapshotDatabase(dbFile,{expectedArtifactSuffixes:suffixes});
    const syntheticExpected={...expectedProvenance,digest:snapshot.digest};
    check(validateSnapshot(snapshot,syntheticExpected).irmin===1,'canonical/slice positive control');
    rejects(()=>validateSnapshot(snapshot,{...syntheticExpected,digest:'0'.repeat(64)}),/canonical mismatch/);
    rejects(()=>validateSnapshot(snapshot,{...syntheticExpected,relations:{irmin:2,protocol:1}}),/relation mismatch/);
    rejects(()=>snapshotDatabase(dbFile,{expectedArtifactSuffixes:['foreign/a.cmt',...suffixes.slice(1)]}),/artifact set differs/);
    for (const [name,options,pattern] of [
      ['missing.db',{missingBinding:0},/incomplete/], ['duplicate.db',{duplicateBinding:0},/incomplete/],
      ['foreign.db',{foreignIndex:0},/incomplete|join/], ['selected.db',{selected:1},/exactly 410 selected inputs/],
    ]) {
      const file=path.join(temporary,name);writeFixtureDb(file,suffixes,options);
      // DB run validation remains fixed at 410 in the imported comparator.
      rejects(()=>snapshotDatabase(file,{expectedArtifactSuffixes:suffixes}),pattern);
    }

    const directory=path.join(temporary,'baseline');fs.mkdirSync(directory);
    for(const name of ['baseline.db','producer.exe','architecture-schema.sql']) fs.writeFileSync(path.join(directory,name),'x');
    const provenance={format_version:1,purpose:PURPOSE,db:path.join(directory,'baseline.db'),producer:path.join(directory,'producer.exe'),schema:path.join(directory,'architecture-schema.sql'),
      manifest:require('./baseline.js').MANIFEST,tezos_checkout:require('./baseline.js').TEZOS,selected:2,manifest_sha256:'a'.repeat(64),producer_sha256:'b'.repeat(64),schema_sha256:'c'.repeat(64),
      tezos_revision:'d'.repeat(40),canonical_rows:2,canonical_sha256:'e'.repeat(64),relations:{irmin:1,protocol:1},arch_revision:'f'.repeat(40),arch_status_sha256:'1'.repeat(64),tezos_status_sha256:'2'.repeat(64),active_task_sha256:'3'.repeat(64),active_manifest_sha256:'4'.repeat(64),source_status_unchanged:true,input_hashes_unchanged:true};
    check(validateProvenance(provenance,{directory,expected:expectedProvenance})===provenance,'provenance positive control');
    for(const [field,value,pattern] of [['producer_sha256','0'.repeat(64),/producer_sha256/],['schema_sha256','0'.repeat(64),/schema_sha256/],['canonical_sha256','0'.repeat(64),/canonical_sha256/],['db','relative.db',/db path/]]) {
      rejects(()=>validateProvenance({...provenance,[field]:value},{directory,expected:expectedProvenance}),pattern);
    }
    rejects(()=>validateProvenance({...provenance,format_version:2},{directory,expected:expectedProvenance}),/format or purpose/);
    rejects(()=>validateProvenance({...provenance,purpose:'other'},{directory,expected:expectedProvenance}),/format or purpose/);
    const fileDigest=sha256(Buffer.from('x'));
    const frozenExpected={...expectedProvenance,producerSha256:fileDigest,schemaSha256:fileDigest};
    const frozenProvenance={...provenance,producer_sha256:fileDigest,schema_sha256:fileDigest};
    fs.writeFileSync(path.join(directory,'provenance.json'),JSON.stringify(frozenProvenance));
    check(loadFrozen(directory,{expected:frozenExpected}).db===path.join(directory,'baseline.db'),'frozen artifact positive control');
    fs.writeFileSync(path.join(directory,'producer.exe'),'wrong');
    rejects(()=>loadFrozen(directory,{expected:frozenExpected}),/frozen producer hash mismatch/);
    fs.writeFileSync(path.join(directory,'producer.exe'),'x');
    fs.writeFileSync(path.join(directory,'architecture-schema.sql'),'wrong');
    rejects(()=>loadFrozen(directory,{expected:frozenExpected}),/frozen schema hash mismatch/);
  } finally { fs.rmSync(temporary,{recursive:true}); }

  const neutral=compareSnapshots({rows:[row,pointFree,pointFree]},{rows:[pointFree,row,pointFree]});
  check(neutral.ok&&neutral.neutral,'neutral reordered multiset must pass');
  check(!compareSnapshots({rows:[row,pointFree,pointFree]},{rows:[row,pointFree]}).ok,'duplicate point-free deletion must fail');
  const moved={...pointFree,target:'M.other'};
  check(!compareSnapshots({rows:[pointFree]},{rows:[moved]}).ok,'point-free movement must fail');
  const newMust={...row,kind:'MUST'};
  check(!compareSnapshots({rows:[row]},{rows:[newMust]}).ok,'new MUST must fail');
  rejects(()=>compareSnapshots({rows:[{...row,target_path:null}]},{rows:[]}),/partial target identity/);
  const top = {...row, target_path:null, target:null, callee_name:'Owned.alias',
    kind:'MAY_TOP', top_reason:'module_param', top_anchor:row.call_site};
  const pair = {before:top, after:row};
  const gained = compareSnapshots({rows:[top]}, {rows:[row]}, {approvedTransitions:[pair]});
  check(gained.ok && gained.summary.relation_gains === 1 && gained.slices.irmin.relation_gains === 1,
    'one exact reviewed ordinary pair permits one relation gain');
  check(!compareSnapshots({rows:[top,top]}, {rows:[row,row]}, {approvedTransitions:[pair]}).ok,
    'one witness cannot account for two duplicate occurrences');
  check(compareSnapshots({rows:[top,top]}, {rows:[row,row]}, {approvedTransitions:[pair,pair]}).ok,
    'two exact witnesses account for two occurrences');
  const aliasTop = {...top, edge_form:'value_alias'};
  const aliasTarget = {...row, edge_form:'value_alias'};
  check(!compareSnapshots({rows:[aliasTop]}, {rows:[aliasTarget]},
    {approvedTransitions:[{before:aliasTop,after:aliasTarget}]}).ok,
    'even a historical approved witness cannot authorize point-free movement');
  const residual = {...top, callee_name:'*TOP*', top_reason:'callback_param'};
  const returnWitness = {after:residual, head:pair, arity:1, arguments:2};
  check(compareSnapshots({rows:[top]}, {rows:[row,residual]},
    {approvedTransitions:[pair], approvedResiduals:[returnWitness]}).ok,
    'one separately witnessed overapplication residual is permitted');
  check(!compareSnapshots({rows:[top]}, {rows:[row,residual,residual]},
    {approvedTransitions:[pair], approvedResiduals:[returnWitness,returnWitness]}).ok,
    'one head cannot authorize two return residuals');
  const badArg=cp.spawnSync(process.execPath,[path.join(__dirname,'prepare-baseline.js'),'--invalid'],{encoding:'utf8'});
  check(badArg.status===2&&badArg.stderr.startsWith('SETUP FAILED:'),'invalid argv must exit as setup failure');
  const native=cp.spawnSync(process.execPath,[path.join(__dirname,'check-witness-inputs.js')],{encoding:'utf8',timeout:120000,maxBuffer:8*1024*1024});
  if(native.error||native.signal||native.status>=2||native.status===null) throw new Error(`native witness setup: ${native.error||native.signal||native.stderr}`);
  check(native.status===0,`native witness controls: ${native.stdout}\n${native.stderr}`);
  check(native.stdout.includes('PASS alias witness native inputs'),'native witness controls must actually execute');
  process.stdout.write(native.stdout);
  process.stdout.write(`PASS attempt2 preparation and multiset controls (${assertions} assertions)\n`);
} catch (error) {
  if (error instanceof assert.AssertionError) {
    process.stderr.write(`ASSERTION FAILED: ${error.message}\n`); process.exitCode=1;
  } else {
    process.stderr.write(`SETUP FAILED: ${error.stack || error}\n`); process.exitCode=2;
  }
}
