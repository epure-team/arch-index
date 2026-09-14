#!/usr/bin/env node
'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {DatabaseSync} = require('node:sqlite');
const {compareSnapshots, snapshotDatabase} = require('./comparison.js');

let assertions = 0;
function check(test, message) {
  assert.ok(test, message);
  assertions += 1;
}

const baseRows = [
  {caller_path:'irmin/a.ml', caller:'run', call_site:'irmin/a.ml:10', target_path:'irmin/a.ml', target:'M.f', callee_name:'M.f', kind:'MAY_ENUMERATED', edge_form:null, top_reason:null, top_anchor:null},
  {caller_path:'irmin/a.ml', caller:'run', call_site:'irmin/a.ml:10', target_path:null, target:null, callee_name:'P.g', kind:'MAY_TOP', edge_form:null, top_reason:'module_param', top_anchor:'irmin/a.ml:10'},
  {caller_path:'irmin/a.ml', caller:'run', call_site:'irmin/a.ml:11', target_path:null, target:null, callee_name:'Stdlib.+', kind:'MUST', edge_form:null, top_reason:null, top_anchor:null},
  {caller_path:'src/proto_alpha/p.ml', caller:'go', call_site:'src/proto_alpha/p.ml:4', target_path:null, target:null, callee_name:'cb', kind:'MAY_TOP', edge_form:null, top_reason:'callback_param', top_anchor:'src/proto_alpha/p.ml:4'},
];

function clone(rows) { return rows.map(row => ({...row})); }
function compare(rows, options) { return compareSnapshots({rows:baseRows}, {rows}, options); }

try {
  check(compare(clone(baseRows).reverse()).ok, 'reordering identical rows must be neutral');

  const duplicate = [...clone(baseRows), {...baseRows[0]}];
  check(!compareSnapshots({rows:duplicate}, {rows:baseRows}).ok, 'deleting one duplicate must fail');

  const swapped = clone(baseRows);
  swapped[0].target = 'M.other';
  check(!compare(swapped).ok, 'swapping a target must fail');

  const kind = clone(baseRows);
  kind[0].kind = 'MUST';
  check(!compare(kind).ok, 'kind mutation and new MUST must fail');

  const permitted = clone(baseRows);
  permitted[1] = {...permitted[1], target_path:'irmin/a.ml', target:'P.g', kind:'MAY_ENUMERATED', top_reason:null, top_anchor:null};
  check(!compare(permitted).ok, 'same-file shape without an exact source witness must remain pending');
  const gain = compare(permitted, {approvedTransitions:[{before:baseRows[1],after:permitted[1]}]});
  check(gain.ok && gain.summary.relation_gains === 1, 'one exact same-file module_param transition must pass');
  check(gain.slices.irmin.relation_gains === 1, 'gain must be partitioned by slice');

  const unrelatedSameFile = clone(baseRows);
  unrelatedSameFile[1] = {...unrelatedSameFile[1], target_path:'irmin/a.ml', target:'Unrelated.f', kind:'MAY_ENUMERATED', top_reason:null, top_anchor:null};
  check(!compare(unrelatedSameFile).ok, 'an unrelated same-file target must not be blessed by structural shape');

  const crossFile = clone(permitted);
  crossFile[1].target_path = 'irmin/other.ml';
  check(!compare(crossFile).ok, 'cross-file resolution must fail');

  const callback = clone(baseRows);
  callback[3] = {...callback[3], target_path:'src/proto_alpha/p.ml', target:'cb', kind:'MAY_ENUMERATED', top_reason:null, top_anchor:null};
  check(!compare(callback).ok, 'blanket TOP-to-target resolution must fail');

  const ambiguousBase = [...clone(baseRows), {...baseRows[1]}];
  const ambiguousNew = clone(ambiguousBase);
  ambiguousNew[1] = {...ambiguousNew[1], target_path:'irmin/a.ml', target:'P.g', kind:'MAY_ENUMERATED', top_reason:null, top_anchor:null};
  check(!compareSnapshots({rows:ambiguousBase}, {rows:ambiguousNew}).ok, 'same-line residual mixtures must refuse');

  assert.throws(()=>compare([{...baseRows[0],kind:'UNKNOWN'}]), /invalid kind/); assertions++;
  assert.throws(()=>compare([{...baseRows[0],call_site:12}]), /invalid call_site/); assertions++;
  const malformed={...baseRows[0]}; delete malformed.top_anchor;
  assert.throws(()=>compare([malformed]), /lacks top_anchor/); assertions++;

  const aliasOld = {...baseRows[1], edge_form:'value_alias'};
  const aliasNew = {...aliasOld, target_path:'irmin/a.ml', target:'P.g', kind:'MAY_ENUMERATED', top_reason:null, top_anchor:null};
  const aliasResult = compareSnapshots({rows:[aliasOld]}, {rows:[aliasNew]}, {approvedTransitions:[{before:aliasOld,after:aliasNew}]});
  check(aliasResult.ok && aliasResult.summary.relation_gains === 0, 'value_alias transition stays in multiset checks but not the primary metric');

  const qualified = {...permitted[1], callee_name:'Make.P.g', target:'Make.P.g'};
  const qualifiedPair = {before:baseRows[1], after:qualified};
  check(compareSnapshots({rows:[baseRows[1]]}, {rows:[qualified]},
    {approvedTransitions:[qualifiedPair]}).ok,
    'exact reviewed identity may correct a short display to its stored qualified name');
  const duplicates = compareSnapshots({rows:[baseRows[1],baseRows[1]]},
    {rows:[qualified,qualified]}, {approvedTransitions:[qualifiedPair,qualifiedPair]});
  check(duplicates.ok && duplicates.summary.relation_gains === 1,
    'two exactly accounted identical transitions preserve multiplicity and yield one relation');
  check(!compareSnapshots({rows:[baseRows[1],baseRows[1]]}, {rows:[qualified,qualified]},
    {approvedTransitions:[qualifiedPair]}).ok, 'one witness cannot authorize two changed occurrences');
  check(!compareSnapshots({rows:[baseRows[1]]}, {rows:[qualified]},
    {approvedTransitions:[qualifiedPair,qualifiedPair]}).ok, 'unused duplicate witness must refuse');
  const residual = {...baseRows[1],callee_name:'*TOP*',top_reason:'callback_param'};
  const residualWitness = {after:residual,head:qualifiedPair,arity:1,arguments:2};
  check(compareSnapshots({rows:[baseRows[1]]}, {rows:[qualified,residual]},
    {approvedTransitions:[qualifiedPair],approvedResiduals:[residualWitness]}).ok,
    'exact reviewed overapplication adds its single computed-return residual');
  check(!compareSnapshots({rows:[baseRows[1]]}, {rows:[qualified,residual]},
    {approvedTransitions:[qualifiedPair],approvedResiduals:[{...residualWitness,arguments:1}]}).ok,
    'saturated application cannot justify a return residual');
  check(!compareSnapshots({rows:[baseRows[1]]}, {rows:[qualified,residual,residual]},
    {approvedTransitions:[qualifiedPair],approvedResiduals:[residualWitness,residualWitness]}).ok,
    'one reviewed head cannot justify two residual occurrences');

  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'arch-index-comparison-check-'));
  try {
    const dbPath = path.join(temporary, 'fixture.db');
    const db = new DatabaseSync(dbPath);
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
      INSERT INTO functor_catalogue_runs VALUES(1,410);`);
    const catalogue=db.prepare('INSERT INTO functor_catalogue_inputs VALUES(?,?,?,?)'),bindings=db.prepare('INSERT INTO functor_binding_inputs VALUES(?,?,?)');
    for(let i=0;i<410;i++){catalogue.run(1,`a${i}`,'collected',1);bindings.run(1,`a${i}`,'collected');}
    db.close();
    const snap = snapshotDatabase(dbPath);
    check(snap.rows.length === 1 && snap.rows[0].target === 'M.f', 'DB snapshot must join caller and target identities');
    check(snap.positioned_rows[0].target_line_start === 2, 'DB snapshot must retain target positions');
    check(typeof snap.digest === 'string' && snap.digest.length === 64, 'DB snapshot must have a canonical digest');
    assert.throws(()=>snapshotDatabase(path.join(temporary,'missing.db')), /missing database/); assertions++;
    const wrongPath=path.join(temporary,'wrong.db'),wrong=new DatabaseSync(wrongPath);wrong.exec('CREATE TABLE unrelated(id INTEGER)');wrong.close();
    assert.throws(()=>snapshotDatabase(wrongPath), /missing table/); assertions++;
    const orphanPath=path.join(temporary,'orphan.db'),orphan=new DatabaseSync(orphanPath);
    orphan.exec(`CREATE TABLE modules(id INTEGER PRIMARY KEY,path TEXT);CREATE TABLE functions(id INTEGER PRIMARY KEY,module_id INTEGER,name TEXT,line_start INTEGER,line_end INTEGER);
      CREATE TABLE calls(id INTEGER PRIMARY KEY,caller_id INTEGER,callee_id INTEGER,callee_name TEXT,call_site TEXT,kind TEXT,edge_form TEXT,top_reason TEXT,top_anchor TEXT);
      INSERT INTO calls VALUES(1,999,NULL,'lost','x.ml:1','MAY_TOP',NULL,'module_param','x.ml:1')`);orphan.close();
    assert.throws(()=>snapshotDatabase(orphanPath), /missing caller or target/); assertions++;
  } finally {
    fs.rmSync(temporary, {recursive:true});
  }

  process.stdout.write(`PASS comparison checker (${assertions} assertions)\n`);
} catch (error) {
  if (error instanceof assert.AssertionError) {
    process.stderr.write(`ASSERTION FAILED: ${error.message}\n`);
    process.exitCode = 1;
  } else {
    process.stderr.write(`SETUP FAILED: ${error.stack || error}\n`);
    process.exitCode = 2;
  }
}
