#!/usr/bin/env node
'use strict';

const assert = require('node:assert/strict');
const cp = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const root = path.resolve(__dirname, '../..');
const producer = path.join(root, '_build/default/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe');
const schema = path.join(root, 'architecture-schema.sql');

function run(command, args, options = {}) {
  const result = cp.spawnSync(command, args, {cwd:root, encoding:'utf8', timeout:120000, maxBuffer:32*1024*1024, ...options});
  if (result.error || result.signal || result.status === null) throw new Error(`${command}: ${result.error || result.signal}`);
  return result;
}
function ok(command, args, options) {
  const r = run(command, args, options);
  if (r.status !== 0) throw new Error(`${command} exited ${r.status}: ${r.stderr}`);
  return r.stdout;
}
function rows(db, sql) { return JSON.parse(ok('sqlite3', ['-json', db, sql]).trim() || '[]'); }
function marker(db, key) { return rows(db, `SELECT value FROM comment_db_meta WHERE key='${key}'`).length; }
function graph(db) {
  // Include every graph table, not just counts or resolved calls. Only the
  // explicitly per-artifact inventories and run metadata may differ.
  const tables = rows(db, "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
    .map(x => x.name).filter(x => !x.startsWith('sqlite_') && !x.startsWith('functor_') && !['producer_runs','comment_db_meta'].includes(x));
  return Object.fromEntries(tables.map(table => [table, rows(db, `SELECT * FROM "${table}"`).map(row => {
    for (const key of ['created_at','last_analyzed','producer_run_id']) delete row[key];
    return JSON.stringify(row);
  }).sort()]));
}
function main() {
  if (!fs.existsSync(producer)) throw new Error('build the native CMT producer first');
  const compiler = ok('opam', ['exec','--','which','ocamlc']).trim();
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'arch-cmt-copies-'));
  try {
    const build = path.join(temporary, '_build/default');
    const first = path.join(build, 'first'), second = path.join(build, 'second');
    fs.mkdirSync(first, {recursive:true}); fs.mkdirSync(second);
    fs.writeFileSync(path.join(temporary, 'fixture.ml'),
      'module type S = sig val run : int -> int end\nmodule A = struct let run x = x + 1 end\nmodule F(X:S) = struct let run x = X.run x end\nmodule M = F(A)\nlet target x = A.run x\nlet entry x = target x\n');
    ok(compiler, ['-bin-annot','-c','fixture.ml','-o','_build/default/first/fixture.cmo'], {cwd:temporary});
    const a = path.join(first,'fixture.cmt'), b = path.join(second,'fixture.cmt');
    const index = (db, selected=build, ddl=schema) => run(producer, ['--build-dir',selected,'--db-path',db,'--schema-path',ddl], {cwd:temporary});
    const single = path.join(temporary,'single.db');
    assert.equal(index(single).status, 0, 'single-artifact premise must index');
    const baseline = graph(single);
    assert(rows(single, 'SELECT * FROM calls').length > 0, 'nonempty graph premise');
    assert(rows(single, 'SELECT * FROM functor_bindings').length > 0, 'nonempty binding premise');
    fs.copyFileSync(a,b);
    assert(fs.readFileSync(a).equals(fs.readFileSync(b)), 'exact-byte copy premise');
    const copied = path.join(temporary,'copies.db');
    const result = index(copied);
    assert.equal(result.status, 0, `exact copies must succeed: ${result.stderr}`);
    assert.deepEqual(graph(copied), baseline, 'copies must preserve the complete single-artifact graph');
    const collected = db => {
      const inputs = rows(db, 'SELECT artifact,outcome,module_id FROM functor_catalogue_inputs ORDER BY artifact');
      assert.equal(inputs.length,2); assert(inputs.every(x => x.outcome === 'collected'));
      assert.equal(new Set(inputs.map(x=>x.module_id)).size,1);
      assert.deepEqual(rows(db,'SELECT outcome FROM functor_binding_inputs ORDER BY artifact'), [{outcome:'collected'},{outcome:'collected'}]);
      assert.deepEqual(rows(db,'SELECT outcome,expected_witnesses FROM functor_target_inputs ORDER BY artifact'), [{outcome:'collected',expected_witnesses:1},{outcome:'collected',expected_witnesses:1}]);
      assert.equal(marker(db,'functor_catalogue_contract'),1);
      assert.equal(marker(db,'functor_binding_contract'),1);
      assert.equal(marker(db,'functor_target_contract'),1);
      for (const table of ['functor_applications','functor_declarations','functor_bindings']) {
        const perArtifact = inputs.map(x => rows(db, `SELECT * FROM ${table} WHERE artifact='${x.artifact.replaceAll("'","''")}'`).map(row=> {
          delete row.artifact; delete row.producer_run_id; return JSON.stringify(row);
        }).sort());
        assert(perArtifact[0].length > 0, `${table} nonempty`);
        assert.deepEqual(perArtifact[0],perArtifact[1], `${table} must be collected independently per path`);
      }
      const witnessSets = inputs.map(x => rows(db, `SELECT * FROM functor_target_witnesses WHERE artifact='${x.artifact.replaceAll("'","''")}'`).map(row=> {
        delete row.artifact; delete row.producer_run_id; return JSON.stringify(row);
      }).sort());
      assert.equal(witnessSets[0].length,1,'functor target witness nonempty');
      assert.deepEqual(witnessSets[0],witnessSets[1],'exact copies retain independent provenance over one canonical call');
    };
    collected(copied);
    fs.unlinkSync(b); fs.symlinkSync(a,b);
    const linked=path.join(temporary,'symlinks.db');
    assert.equal(index(linked).status,0); collected(linked); assert.deepEqual(graph(linked),baseline);
    assert(rows(linked,'SELECT artifact FROM functor_catalogue_inputs').some(x=>x.artifact === b), 'selected symlink spelling retained');
    fs.unlinkSync(b);
    assert.equal(index(copied).status,0);
    assert.equal(rows(copied,'SELECT * FROM functor_catalogue_inputs').length,1,'reindex removes old copy');
    assert.deepEqual(graph(copied),baseline,'new run extracts a fresh graph');
    ok(compiler, ['-bin-annot','-c','fixture.ml','-o','_build/default/second/fixture.cmo'], {cwd:temporary});
    assert(!fs.readFileSync(a).equals(fs.readFileSync(b)), 'independently compiled negative premise');
    const conflict=path.join(temporary,'conflict.db');
    assert.equal(index(conflict).status,0,'unique same-source variant must reconcile');
    assert.deepEqual(graph(conflict),baseline,'same-source variants preserve one canonical graph');
    collected(conflict);
    const reversedRoot=path.join(temporary,'reversed');
    const reversedFirst=path.join(reversedRoot,'first');
    const reversedSecond=path.join(reversedRoot,'second');
    fs.mkdirSync(reversedFirst,{recursive:true}); fs.mkdirSync(reversedSecond,{recursive:true});
    fs.copyFileSync(b,path.join(reversedFirst,'fixture.cmt'));
    fs.copyFileSync(a,path.join(reversedSecond,'fixture.cmt'));
    const reversed=path.join(temporary,'reversed.db');
    assert.equal(index(reversed,reversedRoot).status,0,'reversed variant discovery must reconcile');
    assert.deepEqual(graph(reversed),baseline,'variant discovery order must not change canonical graph rows');
    collected(reversed);
    fs.copyFileSync(a,b);
    const failureSchema=path.join(temporary,'failed-graph.sql');
    fs.writeFileSync(failureSchema,fs.readFileSync(schema,'utf8')+"\nCREATE TRIGGER reject_target BEFORE INSERT ON functions WHEN NEW.name='target' BEGIN SELECT RAISE(ABORT,'injected graph failure'); END;\n");
    const failed=path.join(temporary,'failed.db');
    assert.equal(index(failed,build,failureSchema).status,1);
    assert(rows(failed,'SELECT outcome FROM functor_catalogue_inputs').some(x=>x.outcome==='dropped_module'), 'partial representative must not authorize reuse');
    assert.equal(marker(failed,'functor_catalogue_contract'),0);
    for (const which of ['first','second']) {
      const callbackSchema=path.join(temporary,`failed-${which}.sql`);
      fs.writeFileSync(callbackSchema,fs.readFileSync(schema,'utf8')+`\nCREATE TRIGGER reject_catalogue BEFORE INSERT ON functor_applications WHEN NEW.artifact LIKE '%/${which}/%' BEGIN SELECT RAISE(ABORT,'injected collection failure'); END;\n`);
      const failedCallback=path.join(temporary,`callback-${which}.db`);
      const r=index(failedCallback,build,callbackSchema);
      assert([0,1].includes(r.status),r.stderr);
      assert.deepEqual(rows(failedCallback,'SELECT outcome FROM functor_catalogue_inputs ORDER BY outcome'), [{outcome:'collected'},{outcome:'collection_failed'}]);
      assert.equal(marker(failedCallback,'functor_catalogue_contract'),0);
      assert.equal(marker(failedCallback,'functor_binding_contract'),0);
    }
    fs.writeFileSync(b,'not a cmt');
    const unreadable=path.join(temporary,'unreadable.db');
    index(unreadable);
    assert(rows(unreadable,'SELECT outcome FROM functor_catalogue_inputs').some(x=>x.outcome==='unreadable'));
    assert.equal(marker(unreadable,'functor_catalogue_contract'),0);
    const empty=path.join(temporary,'empty'); fs.mkdirSync(empty);
    const emptyDb=path.join(temporary,'empty.db');
    assert.equal(index(emptyDb,empty).status,0);
    assert.equal(rows(emptyDb,'SELECT * FROM functor_catalogue_inputs').length,0);
    assert.equal(marker(emptyDb,'functor_catalogue_contract'),0);
    console.log('CHECK2 PASS: exact copies, symlinks, graph equality, separate inventories, variants, order, failures and fresh runs');
  } finally { fs.rmSync(temporary,{recursive:true}); }
}
try { main(); }
catch (error) { console.error(error.stack); process.exitCode=error instanceof assert.AssertionError ? 1 : 2; }
