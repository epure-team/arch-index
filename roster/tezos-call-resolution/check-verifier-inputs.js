#!/usr/bin/env node
'use strict';

const assert=require('node:assert/strict');
const crypto=require('node:crypto');
const cp=require('node:child_process');
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
const {DatabaseSync}=require('node:sqlite');
const {ComparisonInputError,snapshotDatabase}=require('./comparison.js');
const {loadProvenance,readManifest,loadWitness}=require('./verify.js');

const sha=data=>crypto.createHash('sha256').update(data).digest('hex');
let assertions=0;
const check=(condition,message)=>{assert.ok(condition,message);assertions++;};
const refuses=(fn,pattern,message,{inputError=true}={})=>{
  let error=null;
  try {fn();} catch(caught) {error=caught;}
  assert.ok(error,`${message}: expected refusal`);
  assert.match(String(error.message),pattern,`${message}: refusal message`);
  if(inputError) assert.ok(error instanceof ComparisonInputError,`${message}: input error class`);
  assertions++;
};

function writeDatabase(file,{catalogueCount=410,bindingCount=catalogueCount,run=1,
  catalogueRun=run,bindingRun=run,selected=410,catalogueOutcome='collected',bindingOutcome='collected',
  duplicateArtifact=false,dropColumn=null}={}) {
  const db=new DatabaseSync(file);
  db.exec(`PRAGMA foreign_keys=ON;
    CREATE TABLE modules(id INTEGER PRIMARY KEY,path TEXT NOT NULL UNIQUE);
    CREATE TABLE functions(id INTEGER PRIMARY KEY,module_id INTEGER NOT NULL REFERENCES modules(id),name TEXT NOT NULL,line_start INTEGER,line_end INTEGER);
    CREATE TABLE calls(id INTEGER PRIMARY KEY,caller_id INTEGER NOT NULL REFERENCES functions(id),callee_id INTEGER REFERENCES functions(id),callee_name TEXT NOT NULL,call_site TEXT,kind TEXT,edge_form TEXT,top_reason TEXT,top_anchor TEXT);
    CREATE TABLE functor_catalogue_runs(producer_run_id INTEGER,selected_inputs INTEGER);
    CREATE TABLE functor_catalogue_inputs(producer_run_id INTEGER,artifact TEXT,outcome TEXT,module_id INTEGER);
    CREATE TABLE functor_binding_inputs(producer_run_id INTEGER,artifact TEXT,outcome TEXT);
    INSERT INTO modules VALUES(1,'irmin/a.ml');
    INSERT INTO functions VALUES(1,1,'run',1,20),(2,1,'M.f',2,3);
    INSERT INTO calls VALUES(1,1,2,'M.f','irmin/a.ml:10','MAY_ENUMERATED',NULL,NULL,NULL);
    INSERT INTO functor_catalogue_runs VALUES(${run},${selected});`);
  const catalogue=db.prepare('INSERT INTO functor_catalogue_inputs VALUES(?,?,?,?)');
  const bindings=db.prepare('INSERT INTO functor_binding_inputs VALUES(?,?,?)');
  for(let i=0;i<catalogueCount;i++) catalogue.run(catalogueRun,duplicateArtifact&&i===catalogueCount-1?'a0':`a${i}`,catalogueOutcome,1);
  for(let i=0;i<bindingCount;i++) bindings.run(bindingRun,duplicateArtifact&&i===bindingCount-1?'a0':`a${i}`,bindingOutcome);
  if(dropColumn) db.exec(`ALTER TABLE ${dropColumn[0]} DROP COLUMN ${dropColumn[1]}`);
  db.close();
}

function positioned(row) {
  return {...row,caller_line_start:1,caller_line_end:20,target_line_start:2,target_line_end:3};
}

function main() {
  if(process.argv.includes('--assertion-control')) assert.fail('controlled assertion');
  if(process.argv.includes('--setup-control')) throw new Error('controlled setup failure');
  const temporary=fs.mkdtempSync(path.join(os.tmpdir(),'arch-index-verifier-inputs-'));
  try {
    const artifacts=path.join(temporary,'artifacts');fs.mkdirSync(artifacts);
    const lines=[];
    for(let i=0;i<410;i++) {
      const file=path.join(artifacts,`a${i}.cmt`),bytes=Buffer.from(`artifact-${i}`);
      fs.writeFileSync(file,bytes);lines.push(`irmin\t${sha(bytes)}\t${file}`);
    }
    const manifestFile=path.join(temporary,'manifest.tsv');
    const writeManifest=rows=>{const content=Buffer.from(rows.join('\n')+'\n');fs.writeFileSync(manifestFile,content);return {manifest:sha(content)};};
    let expected=writeManifest(lines);
    check(readManifest({manifestFile,expected}).entries.length===410,'valid isolated manifest control');
    refuses(()=>readManifest({manifestFile:path.join(temporary,'missing.tsv'),expected}),/ENOENT/,'missing manifest',{inputError:false});
    refuses(()=>readManifest({manifestFile,expected:{manifest:'0'.repeat(64)}}),/manifest digest mismatch/,'changed manifest digest');
    fs.writeFileSync(path.join(artifacts,'a0.cmt'),'changed');
    refuses(()=>readManifest({manifestFile,expected}),/fixed410 input mismatch/,'changed artifact digest');
    fs.writeFileSync(path.join(artifacts,'a0.cmt'),'artifact-0');
    fs.renameSync(path.join(artifacts,'a1.cmt'),path.join(artifacts,'a1.missing'));
    refuses(()=>readManifest({manifestFile,expected}),/fixed410 input mismatch/,'missing artifact');
    fs.renameSync(path.join(artifacts,'a1.missing'),path.join(artifacts,'a1.cmt'));
    expected=writeManifest(lines.slice(0,409));
    refuses(()=>readManifest({manifestFile,expected}),/incomplete or malformed/,'409-row manifest');
    expected=writeManifest([...lines.slice(0,409),lines[0]]);
    refuses(()=>readManifest({manifestFile,expected}),/selection collision/,'duplicate selection');
    expected=writeManifest([...lines.slice(0,409),'malformed\trow']);
    refuses(()=>readManifest({manifestFile,expected}),/incomplete or malformed/,'malformed manifest row');
    expected=writeManifest(lines);

    const baseline=path.join(temporary,'baseline.db');writeDatabase(baseline);
    const provenance={db:baseline,manifest_sha256:'manifest',producer_sha256:'producer',revision:'revision',checkout:'checkout',selected:410,source_status_unchanged:true,input_hashes_unchanged:true};
    const provenanceFile=path.join(temporary,'provenance.json');fs.writeFileSync(provenanceFile,JSON.stringify(provenance));
    const provenanceExpected={manifest:'manifest',baselineProducer:'producer',tezosRevision:'revision',checkout:'checkout'};
    check(loadProvenance(baseline,{expected:provenanceExpected}).value.selected===410,'valid isolated provenance control');
    fs.renameSync(provenanceFile,`${provenanceFile}.saved`);
    refuses(()=>loadProvenance(baseline,{expected:provenanceExpected}),/lacks sibling provenance/,'missing provenance');
    fs.renameSync(`${provenanceFile}.saved`,provenanceFile);
    refuses(()=>loadProvenance(baseline,{expected:{...provenanceExpected,manifest:'changed'}}),/pinned producer\/corpus\/source record/,'changed provenance');
    fs.writeFileSync(provenanceFile,'{');
    refuses(()=>loadProvenance(baseline,{expected:provenanceExpected}),/invalid provenance/,'malformed provenance JSON');
    for(const [label,change] of [
      ['provenance DB path',{db:path.join(temporary,'other.db')}],
      ['source unchanged flag',{source_status_unchanged:false}],
      ['input hashes unchanged flag',{input_hashes_unchanged:false}]]) {
      fs.writeFileSync(provenanceFile,JSON.stringify({...provenance,...change}));
      refuses(()=>loadProvenance(baseline,{expected:provenanceExpected}),label==='provenance DB path'?/does not bind/:/pinned producer\/corpus\/source record/,label);
    }
    fs.writeFileSync(provenanceFile,JSON.stringify(provenance));

    check(snapshotDatabase(baseline).row_count===1,'valid isolated database control');
    for(const [label,options,pattern] of [
      ['zero collection',{catalogueCount:0,bindingCount:0},/incomplete/],
      ['409 catalogue',{catalogueCount:409},/incomplete/],
      ['409 binding',{bindingCount:409},/incomplete/],
      ['wrong catalogue marker',{catalogueOutcome:'failed'},/incomplete/],
      ['wrong binding marker',{bindingOutcome:'failed'},/incomplete/],
      ['both inputs use undeclared run',{catalogueRun:2,bindingRun:2},/incomplete/],
      ['catalogue run mismatch',{catalogueRun:2},/incomplete/],
      ['binding run mismatch',{bindingRun:2},/incomplete/],
      ['wrong declared selected count',{selected:409},/exactly 410/],
      ['duplicate artifact',{duplicateArtifact:true},/incomplete/],
      ['missing provenance column',{dropColumn:['functor_binding_inputs','outcome']},/missing column/]]) {
      const file=path.join(temporary,`${label.replaceAll(' ','-')}.db`);writeDatabase(file,options);
      refuses(()=>snapshotDatabase(file),pattern,label);
    }

    const before={caller_path:'irmin/a.ml',caller:'run',call_site:'irmin/a.ml:10',target_path:null,target:null,callee_name:'M.f',kind:'MAY_TOP',edge_form:null,top_reason:'module_param',top_anchor:'irmin/a.ml:10'};
    const after={...before,target_path:'irmin/a.ml',target:'M.f',kind:'MAY_ENUMERATED',top_reason:null,top_anchor:null};
    const baselineSnapshot={digest:'before',positioned_rows:[positioned(before)]};
    const residual={...after,target_path:null,target:null,callee_name:'*TOP*',kind:'MAY_TOP',top_reason:'callback_param',top_anchor:after.call_site};
    const candidateSnapshot={digest:'after',positioned_rows:[positioned(after),positioned(residual)]};
    const witness={baseline_digest:'before',candidate_digest:'after',transitions:[{before:positioned(before),after:positioned(after),reviewed_by:'test',reviewed_at:'now',source_evidence:'isolated'}]};
    const witnessFile=path.join(temporary,'witness.json');fs.writeFileSync(witnessFile,JSON.stringify(witness));
    check(loadWitness(witnessFile,baselineSnapshot,candidateSnapshot).transitions.length===1,'valid positioned witness control');
    fs.writeFileSync(witnessFile,JSON.stringify({...witness,candidate_digest:'wrong'}));
    refuses(()=>loadWitness(witnessFile,baselineSnapshot,candidateSnapshot),/not bound to these exact snapshots/,'wrong witness digest');
    const wrongPosition=structuredClone(witness);wrongPosition.transitions[0].after.target_line_start=99;
    fs.writeFileSync(witnessFile,JSON.stringify(wrongPosition));
    refuses(()=>loadWitness(witnessFile,baselineSnapshot,candidateSnapshot),/does not contain exact facts and positions/,'wrong positioned witness');
    for(const [label,mutate,pattern] of [
      ['missing review evidence',x=>{delete x.transitions[0].reviewed_by;},/lacks review\/source evidence/],
      ['missing paired fact',x=>{delete x.transitions[0].before;},/lacks paired facts/]]) {
      const value=structuredClone(witness);mutate(value);fs.writeFileSync(witnessFile,JSON.stringify(value));
      refuses(()=>loadWitness(witnessFile,baselineSnapshot,candidateSnapshot),pattern,label);
    }
    const residualItem={after:positioned(residual),head:{before:positioned(before),after:positioned(after)},arity:1,arguments:2,
      reviewed_by:'test',reviewed_at:'now',source_evidence:'isolated'};
    const residualWitness={...witness,residuals:[residualItem]};
    fs.writeFileSync(witnessFile,JSON.stringify(residualWitness));
    check(loadWitness(witnessFile,baselineSnapshot,candidateSnapshot).residuals.length===1,'valid positioned residual control');
    fs.writeFileSync(witnessFile,JSON.stringify({...residualWitness,candidate_digest:'wrong'}));
    refuses(()=>loadWitness(witnessFile,baselineSnapshot,candidateSnapshot),/not bound to these exact snapshots/,'wrong residual witness digest');
    const residualWrongPosition=structuredClone(residualWitness);residualWrongPosition.residuals[0].after.caller_line_start=99;
    fs.writeFileSync(witnessFile,JSON.stringify(residualWrongPosition));
    refuses(()=>loadWitness(witnessFile,baselineSnapshot,candidateSnapshot),/lacks exact positioned head\/return facts/,'wrong residual position');
    const residualMissingReview=structuredClone(residualWitness);delete residualMissingReview.residuals[0].source_evidence;
    fs.writeFileSync(witnessFile,JSON.stringify(residualMissingReview));
    refuses(()=>loadWitness(witnessFile,baselineSnapshot,candidateSnapshot),/lacks review\/source evidence/,'missing residual review evidence');

    for(const [flag,status] of [['--assertion-control',1],['--setup-control',2]]) {
      const result=cp.spawnSync(process.execPath,[__filename,flag],{encoding:'utf8'});
      check(result.status===status,`${flag} exits ${status}`);
    }
  } finally {
    fs.rmSync(temporary,{recursive:true});
    check(!fs.existsSync(temporary),'owned temporary directory cleaned');
  }
  process.stdout.write(`PASS verifier inputs (${assertions} assertions)\n`);
}

try {main();} catch(error) {
  process.stderr.write(`${error instanceof assert.AssertionError?'ASSERTION FAILED':'SETUP FAILED'}: ${error.stack||error}\n`);
  process.exitCode=error instanceof assert.AssertionError?1:2;
}
