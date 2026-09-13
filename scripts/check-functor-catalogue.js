#!/usr/bin/env node
'use strict';
/* Independent acceptance checker.  Its expected CMT census, SQL rows and
 * compatibility oracle are authored here/in versioned roster files, never read
 * from the collector or query implementation. */
const assert = require('node:assert/strict');
const cp = require('node:child_process');
const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const build = path.join(root, '_build/default');
const exe = (env, rel) => process.env[env] || path.join(build, rel);
const indexer = exe('ARCH_FUNCTOR_INDEXER', 'bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe');
const queryBinary = exe('ARCH_FUNCTOR_QUERY', 'bin/arch_query/arch_query.exe');
const typedtree = exe('ARCH_FUNCTOR_TYPEDTREE_PROBE', 'tezt/fixtures/functor_catalogue/typedtree_probe.exe');
const storage = exe('ARCH_FUNCTOR_STORAGE_PROBE', 'tezt/fixtures/functor_catalogue/storage_probe.exe');
const lifecycleProbe = exe('ARCH_FUNCTOR_LIFECYCLE_PROBE', 'tezt/fixtures/functor_catalogue/lifecycle_probe.exe');
const selection = exe('ARCH_FUNCTOR_SELECTION_PROBE', 'tezt/fixtures/functor_catalogue/selection_probe.exe');
const seed = process.env.ARCH_FUNCTOR_CATALOGUE_CMT || path.join(build, 'tezt/fixtures/functor_catalogue/.catalogue.objs/byte/catalogue.cmt');
const cap = 16 * 1024 * 1024;
const limitations = 'not_runtime_instances;not_closed_world;no_target_resolution;no_source_freshness_check;paths_are_artifact_selections';
const summaryHeaders = ['contract','selected_inputs','collected_inputs','total','returned','truncated','scope','limitations'];
const applicationHeaders = ['artifact','source','compiler_unit','ordinal','application_kind','location','head','argument','diagnostics'];

function run(command, args, options = {}) {
  const r = cp.spawnSync(command, args, {cwd: root, encoding: 'utf8', timeout: 120000, maxBuffer: cap, ...options});
  if (r.error || r.signal || r.status === null) throw new Error(`setup: ${command}: ${r.error || r.signal}`);
  return r;
}
function ok(command, args, options) { const r = run(command, args, options); if (r.status !== 0) throw new Error(`${command} exited ${r.status}: ${r.stderr}`); return r.stdout; }
function probeJson(command, args, options) { const r = run(command, args, options); if (r.status === 1) assert.fail(`${command} assertion failure: ${r.stderr}`); if (r.status !== 0) throw new Error(`${command} setup failure (${r.status}): ${r.stderr}`); return JSON.parse(r.stdout); }
function json(command, args, options) { return JSON.parse(ok(command, args, options)); }
function mustFile(p, label = p) { if (!fs.existsSync(p)) throw new Error(`setup: missing ${label}: ${p}`); return p; }
function sql(db, text) { return ok('sqlite3', [db], {input: text}); }
function rows(db, statement) { const text = ok('sqlite3', ['-json', db, statement]); return text.trim() ? JSON.parse(text) : []; }
function quote(s) { return `'${String(s).replaceAll("'", "''")}'`; }
function hash(p) { return crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex'); }
function temp(fn) { const d = fs.mkdtempSync(path.join(os.tmpdir(), 'functor-catalogue-')); try { return fn(d); } finally { fs.rmSync(d, {recursive: true, force: true}); } }
function indexDir(dir, db) { ok(indexer, ['--build-dir', dir, '--db-path', db, '--schema-path', path.join(root, 'architecture-schema.sql')]); }
function queryRun(db, extra = [], format = 'json') { return run(queryBinary, [db, 'functor-applications', ...extra], {env: {...process.env, ARCH_QUERY_FORMAT: format}}); }
function assertRefusal(r, token, status = 3) { assert.equal(r.status, status, r.stderr); assert.equal(r.stdout, ''); assert.match(r.stderr, new RegExp(token)); }
function assertSetupProbe(p) { mustFile(p); }
function assertCommand(name) { const r = run(name, ['--version']); if (r.status !== 0) throw new Error(`setup: ${name} unavailable`); }
function twoArrays(stdout) { const boundary = stdout.indexOf(']\n['); assert(boundary >= 0, `JSON output must contain summary-array then application-array: ${JSON.stringify(stdout)}`); assert.equal(stdout.indexOf(']\n[', boundary + 1), -1); return [JSON.parse(stdout.slice(0, boundary + 1)), JSON.parse(stdout.slice(boundary + 2))]; }

function closedLocation(value) {
  assert.deepEqual(Object.keys(value).sort(), ['end_col','end_line','file','ghost','start_col','start_line']);
  assert.equal(typeof value.ghost, 'boolean');
  const nulls = ['file','start_line','start_col','end_line','end_col'].every(k => value[k] === null);
  if (nulls) return false;
  assert.equal(typeof value.file, 'string'); assert(value.file.length > 0);
  for (const k of ['start_line','end_line']) assert(Number.isInteger(value[k]) && value[k] >= 1);
  for (const k of ['start_col','end_col']) assert(Number.isInteger(value[k]) && value[k] >= 0);
  assert(value.start_line < value.end_line || (value.start_line === value.end_line && value.start_col <= value.end_col));
  return true;
}
function descriptor(value, allowUnit = false) {
  assert.equal(typeof value, 'object'); assert.equal(typeof value.kind, 'string');
  const keys = Object.keys(value).sort();
  switch (value.kind) {
    case 'path': assert.deepEqual(keys, ['compiler','contains_apply','kind','source']); assert.equal(typeof value.compiler, 'string'); assert.equal(typeof value.source, 'string'); assert.equal(typeof value.contains_apply, 'boolean'); break;
    case 'structure': case 'unpack': assert.deepEqual(keys, ['kind']); break;
    case 'functor': assert.deepEqual(keys, ['kind','name','parameter']); assert(['unit','named'].includes(value.parameter)); assert(value.parameter === 'unit' ? value.name === null : value.name === null || typeof value.name === 'string'); break;
    case 'constraint': assert.deepEqual(keys, ['expression','kind']); descriptor(value.expression, false); break;
    case 'application': assert.deepEqual(keys, ['kind','ordinal']); assert(Number.isInteger(value.ordinal) && value.ordinal > 0); break;
    case 'unit': assert(allowUnit); assert.deepEqual(keys, ['kind']); break;
    default: assert.fail(`unknown descriptor kind ${value.kind}`);
  }
}
function stripConstraint(v) { while (v.kind === 'constraint') v = v.expression; return v; }
function validateApp(row, allOrdinals) {
  assert.deepEqual(Object.keys(row).sort(), applicationHeaders.slice().sort());
  assert(['apply','apply_unit'].includes(row.application_kind)); assert(Number.isInteger(row.ordinal) && row.ordinal > 0);
  const location = JSON.parse(row.location), head = JSON.parse(row.head), argument = JSON.parse(row.argument), diagnostics = JSON.parse(row.diagnostics);
  const valid = closedLocation(location); descriptor(head); descriptor(argument, row.application_kind === 'apply_unit');
  assert.equal(row.application_kind === 'apply_unit', stripConstraint(argument).kind === 'unit');
  assert(Array.isArray(diagnostics)); assert.deepEqual(diagnostics, [...new Set(diagnostics)].sort());
  const expected = [];
  if (!['path','application'].includes(stripConstraint(head).kind)) expected.push('opaque_functor_head');
  if (stripConstraint(argument).kind === 'structure') expected.push('anonymous_argument');
  if ([stripConstraint(head), stripConstraint(argument)].some(x => x.kind === 'unpack')) expected.push('unpacked_expression');
  if (!valid) expected.push('unusable_location');
  assert.deepEqual(diagnostics, expected.sort());
  for (const x of [head, argument]) { const y = stripConstraint(x); if (y.kind === 'application') assert(allOrdinals.has(y.ordinal) && y.ordinal > row.ordinal); }
}
function inventory() {
  [indexer, typedtree, storage, lifecycleProbe, selection, seed].forEach(assertSetupProbe);
  const census = probeJson(typedtree, ['census', '--input', seed]);
  assert.equal(census.ok, true); assert.equal(census.before.apply, 18); assert.equal(census.before.apply_unit, 1);
  for (const context of ['class','functorbody','localmodule','module-type-of','unpack']) assert(census.before.contexts[context] > 0, `native premise lacks ${context}`);
  temp(dir => {
    const db = path.join(dir, 'catalogue.db'); indexDir(path.dirname(seed), db);
    const apps = rows(db, `SELECT i.artifact,i.source,i.compiler_unit,a.ordinal,a.application_kind,a.location,a.head,a.argument,a.diagnostics FROM functor_applications a JOIN functor_catalogue_inputs i USING(producer_run_id,artifact) ORDER BY i.artifact,a.ordinal`);
    assert.equal(apps.length, 19); const ordinals = new Set(apps.map(x => x.ordinal)); assert.deepEqual([...ordinals], Array.from({length: 19}, (_, i) => i + 1)); apps.forEach(a => validateApp(a, ordinals));
    assert.equal(apps.filter(a => a.application_kind === 'apply_unit').length, 1);
    assert(apps.some(a => JSON.parse(a.argument).kind === 'structure'));
    assert(apps.some(a => JSON.parse(a.head).kind === 'application'));
    const operand = text => {
      const d = stripConstraint(JSON.parse(text));
      return d.kind === 'path' ? d.source : d.kind === 'application' ? `@${d.ordinal}` : d.kind;
    };
    // Written from the owned source, not from the collector's output: head
    // subtree precedes argument subtree even for chained/nested applications.
    assert.deepEqual(apps.map(a => [a.ordinal, operand(a.head), operand(a.argument)]), [
      [1,'F','A'], [2,'F','structure'], [3,'@4','B'], [4,'G','A'],
      [5,'H','@6'], [6,'F','A'], [7,'U','unit'], [8,'F','A'],
      [9,'functor','A'], [10,'functor','structure'], [11,'F','X'],
      [12,'F','A'], [13,'F','A'], [14,'F','X'], [15,'F','unpack'],
      [16,'F','A'], [17,'F','A'], [18,'F','A'], [19,'F','A']
    ]);
    for (const mode of ['papply','ghost-valid','invalid-location','same-position']) {
      const variant = path.join(dir, mode); fs.mkdirSync(variant); const output = path.join(variant, 'catalogue.cmt'); const evidence = probeJson(typedtree, [mode, '--input', seed, '--output', output]);
      assert.equal(evidence.ok, true); assert.equal(evidence.synthetic, true); assert(evidence.changed > 0);
      if (mode === 'papply') assert(evidence.after.papply_paths > evidence.before.papply_paths);
      if (mode === 'ghost-valid') assert(evidence.after.locations.some(x => x.valid && x.ghost));
      if (mode === 'invalid-location') assert(evidence.after.locations.some(x => !x.valid));
      if (mode === 'same-position') assert(evidence.after.locations.some(x => evidence.after.locations.filter(y => y.span === x.span).length >= 2));
      const variantDb = path.join(variant, 'catalogue.db'); indexDir(variant, variantDb);
      const variantApps = rows(variantDb, `SELECT i.artifact,i.source,i.compiler_unit,a.ordinal,a.application_kind,a.location,a.head,a.argument,a.diagnostics FROM functor_applications a JOIN functor_catalogue_inputs i USING(producer_run_id,artifact) ORDER BY a.ordinal`);
      assert.equal(variantApps.length, 19, `${mode}: selected synthetic CMT must be collected`);
      const variantOrdinals = new Set(variantApps.map(x => x.ordinal)); variantApps.forEach(a => validateApp(a, variantOrdinals));
      assert(variantApps.every(a => a.source && a.compiler_unit), `${mode}: source/unit provenance`);
      if (mode === 'papply') assert(variantApps.some(a => JSON.parse(a.argument).kind === 'path' && JSON.parse(a.argument).contains_apply), 'Papply must remain a path descriptor');
      if (mode === 'ghost-valid') assert(variantApps.some(a => JSON.parse(a.location).ghost && JSON.parse(a.location).file !== null), 'valid ghost location retained');
      if (mode === 'invalid-location') assert(variantApps.some(a => JSON.parse(a.location).file === null && JSON.parse(a.diagnostics).includes('unusable_location')), 'invalid location null diagnostic');
      if (mode === 'same-position') assert(new Set(variantApps.map(a => `${JSON.parse(a.location).file}:${JSON.parse(a.location).start_line}:${JSON.parse(a.location).start_col}`)).size < variantApps.length, 'same-position premise persisted');
    }
  });
  temp(dir => {
    const out = path.join(dir, '_build/default');
    const selected = path.join(out, 'selected');
    fs.mkdirSync(selected, {recursive:true});
    fs.writeFileSync(path.join(dir, 'external.ml'),
      'module type S = sig val n : int end\nmodule A = struct let n = 1 end\nmodule H (X:S) = X\nmodule F (X:S) = struct module Hidden = H(X) let n = Hidden.n end\n');
    fs.writeFileSync(path.join(dir, 'consumer.ml'),
      'module Used = External.F(External.A)\nmodule Left = struct module F(X:External.S) = X module M = F(External.A) end\nmodule Right = struct module F(X:External.S) = X module M = F(External.A) end\n');
    const compiler = process.env.ARCH_FUNCTOR_OCAMLC || 'ocamlc';
    ok(compiler, ['-bin-annot','-c','external.ml','-o','_build/default/external.cmo'], {cwd:dir});
    ok(compiler, ['-I','_build/default','-bin-annot','-c','consumer.ml','-o','_build/default/selected/consumer.cmo'], {cwd:dir});
    const externalCensus = probeJson(typedtree, ['census','--input',path.join(out,'external.cmt')]);
    const selectedCensus = probeJson(typedtree, ['census','--input',path.join(selected,'consumer.cmt')]);
    assert.equal(externalCensus.before.apply, 1, 'excluded external body really contains an application');
    assert.equal(selectedCensus.before.apply, 3, 'selected source has one external and two shadowed applications');
    const db = path.join(dir, 'selected.db');
    indexDir(selected, db);
    assert.equal(rows(db, 'SELECT count(*) n FROM functor_catalogue_inputs')[0].n, 1);
    const apps = rows(db, 'SELECT ordinal,head,argument FROM functor_applications ORDER BY ordinal');
    assert.deepEqual(apps.map(a => [a.ordinal, stripConstraint(JSON.parse(a.head)).source]),
      [[1,'External.F'], [2,'F'], [3,'F']]);
    assert(apps.every(a => stripConstraint(JSON.parse(a.argument)).source === 'External.A'));
  });
  return {native_census: '18 apply + 1 apply_unit', contexts: 5, external_and_shadowed: 3};
}
function lifecycle() {
  [storage, lifecycleProbe, selection, typedtree, indexer, seed].forEach(assertSetupProbe);
  const s = json(selection, []); assert.equal(s.ok, true); assert.deepEqual(s.selected, ['./same.cmt','link/same.cmt','z.cmt']);
  const rollback = json(storage, []); assert.equal(rollback.ok, true); assert.equal(rollback.catalogue_inputs, 0); assert.equal(rollback.functor_applications, 0); assert.equal(rollback.graph_facts, 1);
  const life = json(lifecycleProbe, []); assert.equal(life.ok, true); assert.equal(life.marker_before_finalize, 0); assert.equal(life.finalized, true); assert.equal(life.marker_after_finalize, 1);
  temp(dir => {
    for (const [mode, outcome] of [['unsupported-annotation','unsupported_annotation'], ['missing-source','missing_source']]) {
      const variant = path.join(dir, mode); fs.mkdirSync(variant); const cmt = path.join(variant, 'catalogue.cmt'); const evidence = probeJson(typedtree, [mode, '--input', seed, '--output', cmt]); assert.equal(evidence.ok, true); const db = path.join(variant, 'result.db'); indexDir(variant, db); const input = rows(db, 'SELECT outcome FROM functor_catalogue_inputs'); assert.deepEqual(input.map(x => x.outcome), [outcome]); assert.equal(rows(db, 'SELECT count(*) n FROM functor_applications')[0].n, 0); assert.equal(rows(db, "SELECT count(*) n FROM comment_db_meta WHERE key='functor_catalogue_contract'")[0].n, 0);
    }
  });
  const extended = require('../tezt/fixtures/functor_catalogue/lifecycle_checks.js').runLifecycleChecks({assert,fs,path,root,indexer,indexDir,queryRun,assertRefusal,twoArrays,rows,sql,quote,hash,temp,run,ok,probeJson,typedtree,storage,lifecycleProbe,selection,seed});
  return {selection: s.selected.length, rollback: true, extended};
}
function makeDb(db, mutate = '') {
  sql(db, fs.readFileSync(path.join(root, 'architecture-schema.sql'), 'utf8'));
  const loc = JSON.stringify({file:'a.ml',start_line:1,start_col:0,end_line:1,end_col:4,ghost:false});
  const head = JSON.stringify({kind:'path',compiler:'F',source:'F',contains_apply:false});
  const arg = JSON.stringify({kind:'path',compiler:'A',source:'A',contains_apply:false});
  sql(db, `INSERT INTO producer_runs(id,producer) VALUES(1,'arch_index_cmt'); INSERT INTO modules(id,path,lines) VALUES(1,'a.ml',1),(2,'b.ml',1); INSERT INTO functor_catalogue_runs VALUES(1,2); INSERT INTO functor_catalogue_inputs VALUES(1,'a.cmt','a.ml','A',1,'collected',2),(1,'b.cmt','b.ml','B',2,'collected',1); INSERT INTO functor_applications VALUES(1,'a.cmt',1,'apply',${quote(loc)},${quote(head)},${quote(arg)},'[]'),(1,'a.cmt',2,'apply',${quote(loc)},${quote(head)},${quote(arg)},'[]'),(1,'b.cmt',1,'apply',${quote(loc)},${quote(head)},${quote(arg)},'[]'); INSERT INTO comment_db_meta(key,value) VALUES('functor_catalogue_contract','v1'); PRAGMA foreign_keys=OFF; PRAGMA ignore_check_constraints=ON; ${mutate}`);
}
function query() {
  assertSetupProbe(queryBinary); assertCommand('sqlite3');
  temp(dir => {
    const db = path.join(dir, 'valid.db'); makeDb(db); const before = hash(db);
    const r = queryRun(db, ['2']); assert.equal(r.status, 0, r.stderr); const [summary, applications] = twoArrays(r.stdout);
    assert.deepEqual(Object.keys(summary[0]), summaryHeaders); assert.deepEqual(Object.keys(applications[0]), applicationHeaders); assert.deepEqual(summary, [{contract:'v1',selected_inputs:2,collected_inputs:2,total:3,returned:2,truncated:1,scope:'selected_cmt_syntax_only',limitations}]); assert.equal(applications.length, 2); assert.deepEqual(applications.map(x => [x.artifact,x.ordinal]), [['a.cmt',1],['a.cmt',2]]); assert.equal(hash(db), before);
    for (const f of ['box','list','json','csv','line','markdown']) { const x = queryRun(db, ['0'], f); assert.equal(x.status, 0, `${f}: ${x.stderr}`); assert.equal(hash(db), before); if (f === 'json') assert.deepEqual(twoArrays(x.stdout)[1], []); }
    for (const args of [['-1'],['+1'],['0x10'],['999999999999999999999999999999999999'],['2','extra']]) assertRefusal(queryRun('/does/not/exist.db', args), 'usage|limit|integer', 2);
    const faults = [
      "DELETE FROM functor_catalogue_runs", "INSERT INTO producer_runs(id,producer) VALUES(2,'x'); INSERT INTO functor_catalogue_runs VALUES(2,1)",
      "UPDATE functor_catalogue_runs SET selected_inputs=1", "UPDATE functor_catalogue_inputs SET expected_applications=9", "UPDATE functor_catalogue_inputs SET source=NULL", "UPDATE functor_catalogue_inputs SET compiler_unit=X'00'", "UPDATE functor_catalogue_inputs SET module_id=99",
      "UPDATE functor_applications SET ordinal=0 WHERE artifact='a.cmt' AND ordinal=2", "UPDATE functor_applications SET ordinal=4 WHERE artifact='a.cmt' AND ordinal=2", "UPDATE functor_applications SET application_kind='bogus' WHERE artifact='a.cmt' AND ordinal=1", "UPDATE functor_applications SET location=X'00' WHERE artifact='a.cmt' AND ordinal=1", "UPDATE functor_applications SET location='{\"file\":null,\"start_line\":1,\"start_col\":0,\"end_line\":1,\"end_col\":1,\"ghost\":false}' WHERE artifact='a.cmt' AND ordinal=1", "UPDATE functor_applications SET head='{}' WHERE artifact='a.cmt' AND ordinal=1", "UPDATE functor_applications SET head='{\"kind\":\"functor\",\"parameter\":\"unit\",\"name\":\"X\"}' WHERE artifact='a.cmt' AND ordinal=1", "UPDATE functor_applications SET head='{\"kind\":\"constraint\",\"expression\":{\"kind\":\"application\",\"ordinal\":1}}' WHERE artifact='a.cmt' AND ordinal=1", "UPDATE functor_applications SET argument='{\"kind\":\"unit\"}' WHERE artifact='a.cmt' AND ordinal=1", "UPDATE functor_applications SET diagnostics='[\"unusable_location\",\"unusable_location\"]' WHERE artifact='a.cmt' AND ordinal=1", "UPDATE functor_applications SET diagnostics='[\"opaque_functor_head\"]' WHERE artifact='a.cmt' AND ordinal=1", "INSERT INTO functor_applications VALUES(1,'orphan.cmt',1,'apply','{}','{}','{}','[]')"
    ];
    faults.forEach((fault, i) => { const bad = path.join(dir, `bad${i}.db`); makeDb(bad, fault); assertRefusal(queryRun(bad, ['0']), 'INCONSISTENT_CATALOGUE'); });
    const missing = path.join(dir, 'missing.db'); makeDb(missing, 'DROP TABLE functor_applications'); assertRefusal(queryRun(missing), 'UNSUPPORTED_SCHEMA');
    const unmarked = path.join(dir, 'unmarked.db'); makeDb(unmarked, "DELETE FROM comment_db_meta WHERE key='functor_catalogue_contract'"); assertRefusal(queryRun(unmarked), 'NOT_COLLECTED');
  });
  const extended = require('../tezt/fixtures/functor_catalogue/query_checks.js').runQueryChecks({assert,fs,path,root,queryBinary,queryRun,assertRefusal,twoArrays,makeDb,rows,sql,quote,hash,temp,summaryHeaders,applicationHeaders,limitations,run,ok});
  return {valid: 3, formats: 6, corruption: 19, extended};
}
function canonical(v) { if (Array.isArray(v)) return v.map(canonical).sort((a,b) => JSON.stringify(a).localeCompare(JSON.stringify(b))); if (v && typeof v === 'object') return Object.fromEntries(Object.keys(v).sort().map(k => [k, canonical(v[k])])); return v; }
function withoutRunMetadata(rows_) { return rows_.map(row => { const out = {...row}; for (const k of ['created_at','last_analyzed','producer_run_id']) delete out[k]; return out; }); }
function compatibility() {
  [indexer, queryBinary].forEach(assertSetupProbe); const expected = JSON.parse(fs.readFileSync(path.join(root, 'roster/functor-instance-resolution/compatibility-rich-baseline.json'), 'utf8'));
  const verdicts = [
    {args:['raises','execute'], stdout:'[{"verdict":"execute: UNBOUNDED (⊤): {}"},\n{"verdict":"  reason: may_top_edge fixture.ml:7"},\n{"verdict":"  reason: may_top_edge fixture.ml:8"}]\n'},
    {args:['unreachable','execute','check'], stdout:'[{"verdict":"REACHABLE (may-reach): execute -> check"}]\n'},
    {args:['may-fail','check','--channel','exception'], stdout:'[{"exception":"Helper.Failure","via":"-","how":"direct"}]\n[{"verdict":"check: UNBOUNDED (⊤): {Helper.Failure}"},\n{"verdict":"  reason: may_top_edge fixture.ml:7"}]\n'}
  ];
  temp(dir => {
    const rich = path.join(dir, 'rich');
    const out = path.join(rich, '_build/default');
    fs.mkdirSync(out, {recursive:true});
    fs.writeFileSync(path.join(rich, 'helper.ml'), 'let identity n = n\nexception Failure of int\n');
    fs.writeFileSync(path.join(rich, 'fixture.ml'), "open Helper\nmodule type S = sig val run : int -> int end\nmodule A = struct let run n = identity n + 1 end\nmodule F (X : S) = struct let run n = X.run n end\nmodule M = F (A)\nmodule Anonymous = F (struct let run n = n - 1 end)\nlet check n = if n < 0 then raise (Failure n) else A.run n\nlet execute n = try M.run (check n) with Failure _ -> 0\nlet dead n = if false then A.run n else identity n\nlet division d = 10 / d\n");
    ok(process.env.ARCH_FUNCTOR_OCAMLC || 'ocamlc', ['-bin-annot','-c','helper.ml','-o','_build/default/helper.cmo'], {cwd:rich});
    ok(process.env.ARCH_FUNCTOR_OCAMLC || 'ocamlc', ['-I','_build/default','-bin-annot','-c','fixture.ml','-o','_build/default/fixture.cmo'], {cwd:rich});
    const db = path.join(dir,'rich.db');
    let firstCatalogue;
    for (let pass = 0; pass < 2; pass++) {
      indexDir(out, db);
      for (const [key, baseline] of Object.entries(expected)) {
        const statement = key === 'contracts'
          ? "SELECT key,value FROM comment_db_meta WHERE key IN ('callgraph_contract','error_contract','exn_contract')"
          : `SELECT * FROM ${key}`;
        assert.deepEqual(canonical(withoutRunMetadata(rows(db, statement))), canonical(baseline), `${key}, reindex pass ${pass}`);
      }
      assert.equal(expected.conditions.length, 0, 'constant false is not a stored condition premise');
      assert(expected.calls.some(c => c.callee_name === 'X.run' && c.kind === 'MAY_TOP'));
      assert(expected.exn_origins.length > 0 && expected.call_exn_scopes.length > 0);
      const before = hash(db);
      for (const oracle of verdicts) {
        const result = run(queryBinary, [db, ...oracle.args], {env:{...process.env, ARCH_QUERY_FORMAT:'json'}});
        assert.equal(result.status, 0, result.stderr);
        assert.equal(result.stdout, oracle.stdout, oracle.args.join(' '));
        assert.equal(hash(db), before, 'legacy read changed DB bytes');
      }
      const catalogue = queryRun(db);
      assert.equal(catalogue.status, 0, catalogue.stderr);
      const [summary, applications] = twoArrays(catalogue.stdout);
      assert.equal(summary[0].total, 2);
      assert.equal(hash(db), before, 'catalogue read changed DB bytes');
      if (pass === 0) firstCatalogue = applications;
      else assert.deepEqual(applications, firstCatalogue, 'reindex catalogue identity/order changed');
    }
  });
  return {oracle: 'versioned rich baseline', semantic_tables_and_contracts: Object.keys(expected).length, legacy_queries: verdicts.length, indexing_passes: 2};
}
try { const mode = process.argv[2]; const groups = {inventory,lifecycle,query,compatibility}; if (!groups[mode]) throw new Error('usage: check-functor-catalogue.js inventory|lifecycle|query|compatibility'); console.log(JSON.stringify({mode, result: groups[mode]()})); } catch (e) { console.error(e.stack || String(e)); process.exitCode = e instanceof assert.AssertionError ? 1 : 2; }
