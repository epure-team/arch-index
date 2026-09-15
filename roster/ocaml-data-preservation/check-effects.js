#!/usr/bin/env node
'use strict';

const {execFileSync, spawnSync} = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const assert = require('node:assert/strict');

const root = path.resolve(__dirname, '../..');
const loader = path.join(root, '_build/default/bin/arch_effects_load/main.exe');
const producer = path.join(root, '_build/default/bin/arch_effects_ocaml/arch_effects_ocaml.exe');
const migration = path.join(root, 'effects-schema-migration.sql');
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'arch-effects-check-'));
const fail = message => assert.fail(`CHECK1 assertion: ${message}`);
const sql = (db, statement) => execFileSync('sqlite3', [db, statement], {encoding: 'utf8'}).trim();

try {
  for (const executable of [loader,producer])
    if (!fs.existsSync(executable)) throw new Error(`build the native executable first: ${executable}`);
  const db = path.join(tmp, 'main.db');
  sql(db, "CREATE TABLE modules(id INTEGER PRIMARY KEY,path TEXT); CREATE TABLE functions(id INTEGER PRIMARY KEY,module_id INTEGER,name TEXT); INSERT INTO modules VALUES(1,'src/a.ml'),(2,'src/b.ml'); INSERT INTO functions VALUES(11,1,'f'),(22,2,'f');");
  const input = [
    {type:'effect',function_name:'f',file_path:'src/./a.ml',value_kind:'HeapRef',target:null,soundness:'sound',producer:'check'},
    {type:'effect',function_name:'f',file_path:'src/b.ml',value_kind:'HeapRef',target:null,soundness:'candidate',producer:'check'},
    {type:'effect',function_name:'f',file_path:null,value_kind:'HeapRef',target:'',soundness:'sound',producer:'check'},
  ].map(JSON.stringify).join('\n') + '\n';
  const loaded = spawnSync(loader, [db, '--migration', migration], {input, encoding:'utf8'});
  if (loaded.status !== 0) fail(`loader failed: ${loaded.stderr}`);
  if (sql(db, "SELECT group_concat(x,'|') FROM (SELECT COALESCE(function_id,'NULL') x FROM function_effects ORDER BY id)") !== '11|22|NULL')
    fail('main-schema homonym/ambiguous associations differ');
  if (sql(db, 'SELECT count(*) FROM function_effects') !== '3') fail('NULL/empty or soundness payload was lost');
  assert.match(loaded.stderr,/ambiguous function f/,'unbound ambiguity is diagnosed');
  const reload = spawnSync(loader, [db], {input, encoding:'utf8'});
  if (reload.status !== 0 || !reload.stdout.includes('0 effects written, 3 skipped')) fail('duplicate accounting differs');

  const alt = path.join(tmp, 'alternative.db');
  sql(alt, "CREATE TABLE functions(id INTEGER PRIMARY KEY,name TEXT,file_path TEXT); INSERT INTO functions VALUES(7,'g','lib/./g.ml');");
  const altInput = JSON.stringify({type:'effect',function_name:'g',file_path:'lib/g.ml',value_kind:'HeapRef',target:null,soundness:'sound',producer:'check'}) + '\n';
  if (spawnSync(loader, [alt, '--migration', migration], {input:altInput, encoding:'utf8'}).status !== 0 || sql(alt, 'SELECT function_id FROM function_effects') !== '7')
    fail('alternative schema normalized association differs');
  const rowId=sql(alt,'SELECT id FROM function_effects');
  sql(alt,'UPDATE function_effects SET function_id=999');
  const repaired=spawnSync(loader,[alt],{input:altInput,encoding:'utf8'});
  assert.equal(repaired.status,0,repaired.stderr);
  assert.match(repaired.stdout,/1 effects written, 0 skipped/);
  assert.equal(sql(alt,'SELECT id FROM function_effects'),rowId);
  assert.equal(sql(alt,'SELECT function_id FROM function_effects'),'7');
  const repairedReload=spawnSync(loader,[alt],{input:altInput,encoding:'utf8'});
  assert.equal(repairedReload.status,0,repairedReload.stderr);
  assert.match(repairedReload.stdout,/0 effects written, 1 skipped/);

  const pathlessInput=JSON.stringify({...JSON.parse(altInput),file_path:null})+'\n';
  assert.equal(spawnSync(loader,[alt],{input:pathlessInput,encoding:'utf8'}).status,0);
  assert.equal(sql(alt,'SELECT function_id FROM function_effects WHERE file_path IS NULL'),'7');
  sql(alt,"INSERT INTO functions VALUES(8,'g','other.ml')");
  const ambiguous=spawnSync(loader,[alt],{input:pathlessInput,encoding:'utf8'});
  assert.equal(ambiguous.status,0,ambiguous.stderr);
  assert.match(ambiguous.stderr,/ambiguous function g/);
  assert.match(ambiguous.stdout,/1 effects written, 0 skipped/);
  assert.equal(sql(alt,'SELECT function_id IS NULL FROM function_effects WHERE file_path IS NULL'),'1');

  // Path spellings are preserved payload data, while association normalizes
  // both sides. Do not merge distinct raw payloads merely sharing a target.
  const spellingInput=JSON.stringify({...JSON.parse(altInput),file_path:'lib/./g.ml'})+'\n';
  assert.equal(spawnSync(loader,[alt],{input:spellingInput,encoding:'utf8'}).status,0);
  assert.equal(sql(alt,'SELECT count(*) FROM function_effects WHERE function_id=7'),'2');
  const flat = path.join(tmp, 'flat.db');
  sql(flat, 'CREATE TABLE functions(name TEXT,file_path TEXT);');
  if (spawnSync(loader, [flat, '--migration', migration], {input:altInput, encoding:'utf8'}).status !== 0 || sql(flat, 'SELECT function_id IS NULL FROM function_effects') !== '1')
    fail('flat schema fabricated an ID');

  const parents = path.join(tmp, 'parents.db');
  sql(parents, "CREATE TABLE functions(id INTEGER PRIMARY KEY,name TEXT,file_path TEXT); INSERT INTO functions VALUES(1,'f','safe.ml');");
  const parentInput = JSON.stringify({type:'effect',function_name:'f',file_path:'../../safe.ml',value_kind:'HeapRef',soundness:'sound',producer:'check'}) + '\n';
  const parentLoad = spawnSync(loader, [parents, '--migration', migration], {input:parentInput, encoding:'utf8'});
  if (parentLoad.status !== 0) throw new Error(`parent-path fixture failed: ${parentLoad.stderr}`);
  if (parentLoad.status !== 0 || sql(parents, 'SELECT function_id IS NULL FROM function_effects') !== '1')
    fail('unresolved parent segments must not alias a root-local source');
  assert.match(parentLoad.stderr,/unmatched function f at \.\.\/\.\.\/safe\.ml/);

  const payloads=path.join(tmp,'payloads.db');
  sql(payloads,'CREATE TABLE functions(name TEXT)');
  const same={type:'effect',function_name:'p',file_path:'p.ml',value_kind:'HeapRef',target:null,soundness:'sound',producer:'check'};
  const distinct=[same,{...same,target:''},{...same,soundness:'candidate'},{...same,file_path:null},{...same,file_path:''}].map(JSON.stringify).join('\n')+'\n';
  const distinctions=spawnSync(loader,[payloads,'--migration',migration],{input:distinct,encoding:'utf8'});
  assert.equal(distinctions.status,0,distinctions.stderr);
  assert.equal(sql(payloads,'SELECT count(*) FROM function_effects'),'5');
  const distinctionsReload=spawnSync(loader,[payloads],{input:distinct,encoding:'utf8'});
  assert.equal(distinctionsReload.status,0,distinctionsReload.stderr);
  assert.match(distinctionsReload.stdout,/0 effects written, 5 skipped/);

  const rollback = path.join(tmp, 'rollback.db');
  sql(rollback, "CREATE TABLE functions(name TEXT); CREATE TABLE function_effects(id INTEGER PRIMARY KEY,function_id INTEGER,function_name TEXT NOT NULL,file_path TEXT,value_kind TEXT NOT NULL,target TEXT,is_direct INTEGER NOT NULL DEFAULT 1,soundness TEXT NOT NULL,producer TEXT); CREATE TRIGGER reject_bad BEFORE INSERT ON function_effects WHEN NEW.function_name='bad' BEGIN SELECT RAISE(ABORT,'injected'); END;");
  const batch = ['good','bad'].map(function_name => JSON.stringify({type:'effect',function_name,value_kind:'HeapRef',soundness:'sound',producer:'check'})).join('\n') + '\n';
  const rejected = spawnSync(loader, [rollback], {input:batch, encoding:'utf8'});
  if (rejected.status === 0 || rejected.stdout.includes('effects written') || sql(rollback, 'SELECT count(*) FROM function_effects') !== '0')
    fail('failed batch was reported or partially committed');

  const malformed=spawnSync(loader,[rollback],{input:JSON.stringify(same)+'\nnot json\n',encoding:'utf8'});
  assert.notEqual(malformed.status,0); assert.doesNotMatch(malformed.stdout,/effects written/);
  assert.equal(sql(rollback,'SELECT count(*) FROM function_effects'),'0');
  const allowed=spawnSync(loader,[rollback,'--allow-skip'],{input:JSON.stringify(same)+'\nnot json\n',encoding:'utf8'});
  assert.equal(allowed.status,0,allowed.stderr); assert.match(allowed.stdout,/1 effects written, 1 skipped/);
  const inputFd=fs.openSync(tmp,'r');
  try {
    const ioFailure=spawnSync(loader,[rollback],{stdio:[inputFd,'pipe','pipe'],encoding:'utf8'});
    assert.notEqual(ioFailure.status,0); assert.match(ioFailure.stderr,/input read failed/);
    assert.doesNotMatch(ioFailure.stdout,/effects written/);
    assert.equal(sql(rollback,'SELECT count(*) FROM function_effects'),'1');
  } finally {fs.closeSync(inputFd);}

  sql(alt,"UPDATE function_effects SET function_id=999 WHERE file_path='lib/g.ml'; CREATE TRIGGER reject_repair BEFORE UPDATE ON function_effects BEGIN SELECT RAISE(ABORT,'injected repair failure'); END;");
  const oldRows=sql(alt,'SELECT json_group_array(json_object(\'id\',id,\'function_id\',function_id,\'file_path\',file_path)) FROM function_effects');
  const repairFailure=spawnSync(loader,[alt],{input:JSON.stringify(same)+'\n'+altInput,encoding:'utf8'});
  assert.notEqual(repairFailure.status,0); assert.doesNotMatch(repairFailure.stdout,/effects written/);
  assert.equal(sql(alt,'SELECT json_group_array(json_object(\'id\',id,\'function_id\',function_id,\'file_path\',file_path)) FROM function_effects'),oldRows);

  const incompatible = path.join(tmp, 'incompatible.db');
  sql(incompatible, "CREATE TABLE functions(name TEXT); CREATE TABLE function_effects(id INTEGER PRIMARY KEY,function_id INTEGER,function_name TEXT NOT NULL,file_path TEXT,value_kind TEXT NOT NULL,target TEXT,is_direct INTEGER NOT NULL DEFAULT 1,soundness TEXT NOT NULL,producer TEXT); INSERT INTO function_effects VALUES(1,NULL,'dup',NULL,'HeapRef',NULL,1,'sound','check'),(2,NULL,'dup',NULL,'HeapRef',NULL,1,'sound','check');");
  const refused = spawnSync(loader, [incompatible], {input:'', encoding:'utf8'});
  if (refused.status === 0 || sql(incompatible, 'SELECT count(*) FROM function_effects') !== '2')
    fail('incompatible legacy duplicates were deleted or accepted');

  const src = path.join(tmp, 'project');
  fs.mkdirSync(path.join(src, 'src'), {recursive:true});
  fs.mkdirSync(path.join(src, 'obj/deep'), {recursive:true});
  fs.writeFileSync(path.join(src, 'src/effect.ml'),
    'let f t = Hashtbl.replace t 1 2\nlet f t = Hashtbl.replace t 3 4\n');
  const ocamlc = execFileSync('opam', ['exec','--','which','ocamlc'], {cwd:root, encoding:'utf8'}).trim();
  execFileSync(ocamlc, ['-w','-32','-bin-annot','-c','src/effect.ml','-o','obj/deep/effect.cmo'], {cwd:src});
  const emitted = execFileSync(producer, ['--build-dir',path.join(src,'obj'),'--source-root',src], {encoding:'utf8'}).trim().split('\n').map(JSON.parse);
  if (emitted.map(x => x.function_name).join('|') !== 'f#1|f') fail('producer shadow identities differ');
  if (!emitted.every(x => x.file_path === 'src/effect.ml')) fail('producer explicit-root paths differ');

  execFileSync(ocamlc, ['-w','-32','-bin-annot','-c',path.join(src,'src/effect.ml'),'-o','obj/deep/effect.cmo'], {cwd:src});
  const absoluteEmitted = execFileSync(producer, ['--build-dir',path.join(src,'obj'),'--source-root','project'], {cwd:tmp,encoding:'utf8'}).trim().split('\n').map(JSON.parse);
  if (!absoluteEmitted.every(x=>x.file_path==='src/effect.ml'))
    fail('absolute metadata must relativize against an explicitly relative source root');

  execFileSync(ocamlc, ['-w','-32','-bin-annot','-c','../../src/effect.ml','-o','effect.cmo'], {cwd:path.join(src,'obj/deep')});
  const parentEmitted = execFileSync(producer, ['--build-dir',path.join(src,'obj'),'--source-root',src], {encoding:'utf8'}).trim().split('\n').map(JSON.parse);
  if (!parentEmitted.every(x => x.file_path === '../../src/effect.ml'))
    fail('producer must retain unresolved parent segments');

  if (!process.exitCode) console.log('CHECK1 PASS: effects association, payload, migration, rollback, legacy refusal, and producer identity');
} catch (error) {
  console.error(`CHECK1 setup: ${error.message}`);
  process.exitCode = error instanceof assert.AssertionError ? 1 : 2;
} finally {
  fs.rmSync(tmp, {recursive:true, force:true});
}
