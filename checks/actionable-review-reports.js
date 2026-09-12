#!/usr/bin/env node
'use strict';
const A = require('node:assert/strict'), C = require('node:child_process'),
      F = require('node:fs'), O = require('node:os'), P = require('node:path');
class X extends Error {};
const modes = new Set([ 'rules', 'ordering', 'operands', 'compatibility' ]);
const need = (n, fallback) => {
  let v = process.env[n] || fallback;
  if (!v || !P.isAbsolute(v) || !F.existsSync(v))
    throw new X(`${n} must be an existing absolute path`);
  return v
};
function tool(n, fallback) {
  const v = process.env[n] || fallback;
  if (P.isAbsolute(v)) {
    if (F.existsSync(v))
      return v;
  } else
    for (const d of (process.env.PATH || '').split(P.delimiter)) {
      const candidate = P.join(d, v);
      try {
        if (F.statSync(candidate).isFile() &&
            (F.statSync(candidate).mode & 0o111))
          return candidate;
      } catch (_) {
      }
    }
  throw new X(`${n} / ${fallback} was not executable in PATH`);
}
function run(x, a, o) {
  let r = C.spawnSync(x, a, {encoding : 'utf8', ...(o || {})});
  if (r.error || r.signal || r.status === null)
    throw new X(`could not execute ${x}`);
  return r
}
function ok(s, x, a, o) {
  let r = run(x, a, o);
  if (r.status)
    throw new X(`${s}: ${r.status}: ${r.stderr || r.stdout}`);
  return r
}
const put = (f, s) => {
  F.mkdirSync(P.dirname(f), {recursive : true});
  F.writeFileSync(f, s)
};
const js = f => JSON.parse(F.readFileSync(f));
const sql = (p, d, s) => ok('sqlite', p.sqlite, [ d, s ]);
function graph(p, d, contract, top) {
  sql(p, d,
      "CREATE TABLE comment_db_meta(key TEXT,value TEXT);CREATE TABLE modules(id INTEGER PRIMARY KEY,path TEXT);CREATE TABLE functions(id INTEGER PRIMARY KEY,module_id INTEGER,name TEXT,exposed INTEGER,line_start INTEGER,line_end INTEGER);CREATE TABLE calls(id INTEGER PRIMARY KEY,caller_id INTEGER,callee_id INTEGER,callee_name TEXT,call_site TEXT,kind TEXT,top_reason TEXT);CREATE TABLE producer_runs(id INTEGER PRIMARY KEY,producer TEXT,producer_version TEXT,invocation_digest TEXT,soundness_class TEXT);" +
          (contract
               ? "INSERT INTO comment_db_meta VALUES('callgraph_contract','v1');"
               : "") +
          "INSERT INTO modules VALUES(1,NULL);INSERT INTO functions VALUES(1,1,'entry',0,1,1),(2,1,'same',0,2,2),(3,1,'same',0,3,3),(4,1,'target',0,4,4),(5,1,'isolated',0,5,5);INSERT INTO calls VALUES(1,1,2,'same','f:1','MUST',NULL),(2,2,3,'same','f:2','MUST',NULL),(3,3,4,'target','f:3','MUST',NULL)" +
          (top ? ",(4,2,NULL,'*TOP*','f:4','MAY_TOP','reflection')" : "") +
          ";INSERT INTO producer_runs VALUES(1,'arch-index-cmt','native',NULL,'sound_with_top'),(2,'newer-importer','foreign',NULL,'heuristic');")
}
const rep = (p, d, o, r) =>
    run(p.report, r ? [ d, '--out', o, '--rules', r ] : [ d, '--out', o ]);
function arts(o) {
  for (const f of ['report.json', 'report.sarif', 'report.html'])
    A.ok(F.existsSync(P.join(o, f)), `missing ${f}`);
  return {
    j: js(P.join(o, 'report.json')), s: js(P.join(o, 'report.sarif')),
        h: F.readFileSync(P.join(o, 'report.html'), 'utf8')
  }
}
const rr = (j, n) => {
  let r = j.rule_results.find(x => x.ordinal === n);
  A.ok(r, `missing ordinal ${n}`);
  return r
};
function rules(p, d) {
  let db = P.join(d, 'r.db'), rf = P.join(d, 'r');
  graph(p, db, true, true);
  put(rf,
      'rule "exact <html>"\n  forbid reach from fn:entry to fn:target\nrule "frontier"\n  forbid reach from fn:same to fn:isolated\n');
  let g = run(p.rules, [ db, rf, '--format', 'json' ]);
  A.equal(g.status, 1, g.stderr || g.stdout);
  let out = P.join(d, 'out');
  F.mkdirSync(out);
  let report = rep(p, db, out, rf);
  A.equal(report.status, 0, report.stderr || report.stdout);
  let a = arts(out), e = rr(a.j, 1);
  A.equal(a.j.verdicts_status, 'COMPUTED');
  let canonical = ({ordinal, evaluator, ...result}) =>
      ({...result, exact : result.exact || false});
  let gateResults = jsout(g).results;
  let reportResults = a.j.rule_results.map(canonical);
  A.deepEqual(reportResults, gateResults.map(canonical));
  A.deepEqual(e.witness, [ 'entry', 'same', 'same', 'target' ]);
  A.deepEqual(gateResults[0].witness, e.witness);
  A.deepEqual(a.s.properties.rule_results[0].witness, e.witness);
  let ruleRun = a.s.runs.find(run => run.tool.driver.name === 'arch-rules');
  A.ok(ruleRun);
  let flowLocations = ruleRun.results[0].codeFlows[0].threadFlows[0].locations;
  A.deepEqual(flowLocations.map(
                  step => step.location.logicalLocations[0].fullyQualifiedName),
              e.witness);
  A.ok(flowLocations.every(step => !step.location.physicalLocation));
  A.match(
      a.h,
      /<ol class="witness"><li>entry<\/li><li>same<\/li><li>same<\/li><li>target<\/li><\/ol>/);
  A.equal(rr(a.j, 2).verdict, 'UNKNOWN');
  A.match(a.h, /exact &lt;html&gt;/)
}
function jsout(r) {
  try {
    return JSON.parse(r.stdout)
  } catch (e) {
    throw new X('rules JSON parse')
  }
}
function ordering(p, d) {
  let db = P.join(d, 'o.db'), rf = P.join(d, 'r');
  graph(p, db, true, true);
  sql(p, db,
      "INSERT INTO functions VALUES(6,1,'maybe',0,6,6),(7,1,'maybe_target',0,7,7);INSERT INTO calls VALUES(5,6,7,'maybe_target','f:5','MAY_ENUMERATED',NULL);");
  put(rf,
      'rule "pass"\n  forbid reach from fn:isolated to fn:target\nrule "uncertain <tag>"\n  forbid reach from fn:same to fn:isolated\nrule "not computed"\n  forbid effect from fn:entry kind:GlobalVar\nrule "duplicate"\n  forbid reach from fn:entry to fn:target\nrule "possible"\n  forbid reach from fn:maybe to fn:maybe_target\nrule "duplicate"\n  forbid reach from fn:entry to fn:target\nrule "vacuous"\n  forbid reach from fn:entry to fn:missing\n');
  let out = P.join(d, 'out');
  F.mkdirSync(out);
  let report = rep(p, db, out, rf);
  A.equal(report.status, 0, report.stderr || report.stdout);
  let a = arts(out);
  A.deepEqual(a.j.rule_results.map(x => x.ordinal), [ 1, 2, 3, 4, 5, 6, 7 ]);
  A.deepEqual(a.j.rule_alerts.map(x => x.ordinal), [ 4, 6, 5, 2, 3, 7 ]);
  A.deepEqual(a.s.properties.rule_results.map(x => x.ordinal),
              [ 1, 2, 3, 4, 5, 6, 7 ]);
  A.equal(rr(a.j, 1).verdict, 'PASS');
  A.equal(rr(a.j, 2).verdict, 'UNKNOWN');
  A.equal(rr(a.j, 3).verdict, 'NOT_COMPUTED');
  A.equal(rr(a.j, 7).verdict, 'NO_TARGET');
  A.deepEqual(a.j.producers.map(x => x.producer),
              [ 'arch-index-cmt', 'newer-importer' ]);
  A.deepEqual(a.s.properties.index_producers.map(x => x.producer),
              [ 'arch-index-cmt', 'newer-importer' ]);
  let ruleRun = a.s.runs.find(run => run.tool.driver.name === 'arch-rules');
  A.ok(ruleRun);
  A.deepEqual(
      ruleRun.results.map(result => result.ruleId),
      a.j.rule_alerts.map(result => `${result.rule}#${result.ordinal}`));
  A.ok(a.j.rule_results.every(x => x.evaluator === 'arch-rules'));
  A.ok(!a.j.rule_alerts.some(x => x.verdict === 'PASS'));
  A.match(a.h, /uncertain &lt;tag&gt;/)
}
function compat(p, d) {
  let db = P.join(d, 'c.db'), out = P.join(d, 'out');
  graph(p, db, true, false);
  F.mkdirSync(out);
  A.equal(rep(p, db, out).status, 0);
  let a = arts(out), names = [ 'report.json', 'report.sarif', 'report.html' ],
      old = Object.fromEntries(
          names.map(n => [n, F.readFileSync(P.join(out, n))]));
  A.equal(a.j.verdicts_status, 'NOT_COMPUTED');
  for (const v
           of ['PASS', 'VIOLATION', 'POSSIBLE', 'UNKNOWN',
               'UNKNOWN_NO_CONTRACT', 'NO_SOURCE', 'NO_TARGET', 'NOT_COMPUTED'])
    A.equal(a.j.verdicts[v], 0);
  let empty = P.join(d, 'empty'), bad = P.join(d, 'bad'),
      missing = P.join(d, 'missing');
  put(empty, '');
  put(bad, 'not a rule\n');
  for (const rf of [empty, bad, missing]) {
    let failed = rep(p, db, out, rf);
    A.equal(failed.status, 2);
    A.doesNotMatch(failed.stdout, /historical finding/);
    for (const n of names)
      A.deepEqual(F.readFileSync(P.join(out, n)), old[n])
  }
  for (const args of [[ db, '--out', out, '--rules' ],
                      [ db, '--out', out, '--unknown' ],
                      [ db, '--out', out, 'trailing' ]])
    A.equal(run(p.report, args).status, 2);
  let valid = P.join(d, 'valid');
  put(valid, 'rule "v"\n  forbid reach from fn:entry to fn:target\n');
  let broken = P.join(d, 'broken');
  F.mkdirSync(broken);
  F.mkdirSync(P.join(broken, 'report.sarif'));
  let io = rep(p, db, broken, valid);
  A.equal(io.status, 2);
  A.doesNotMatch(io.stdout, /historical finding/);
  let nc = P.join(d, 'n.db'), rf = P.join(d, 'n');
  graph(p, nc, false, false);
  put(rf, 'rule "nc"\n  forbid reach from fn:entry to fn:isolated\n');
  let no = P.join(d, 'no');
  F.mkdirSync(no);
  A.equal(rep(p, nc, no, rf).status, 0);
  A.equal(rr(arts(no).j, 1).verdict, 'UNKNOWN_NO_CONTRACT');
}
function operands(p, d) {
  let root = P.join(d, 'fixture'), long = 'a'.repeat(257),
      same = Array.from({length : 201}, (_, i) => `(x / b${i})`).join(' + '),
      sites = Array.from({length : 201}, (_, i) => `let site_${i} x y = x / y`)
                  .join('\n');
  put(P.join(root, 'dune-project'),
      '(lang dune 3.0)\n(name ar_operand_fixture)\n');
  put(P.join(root, 'dune'),
      '(library (name ar_operand_fixture) (modules operands))\n');
  put(P.join(root, 'operands.ml'),
      `let kinds x y = x / 0 + x / 2 + x / (-2) + x / y + x / (y + 1) + x / (-y)\nlet i32 x y = Int32.rem x y\nlet i64 x y = Int64.rem x y\nlet ni x y = Nativeint.rem x y\nlet ${
          long} = 1\nlet over x = x / ${long}\nlet same x ${
          Array.from({length : 201}, (_, i) => 'b' + i).join(' ')} = ${same}\n${
          sites}\n`);
  ok('dune', p.dune, [ 'build', '--root', root ], {cwd : d});
  let db = P.join(d, 'x.db');
  ok('index', p.index, [
    '--build-dir', P.join(root, '_build/default'), '--db-path', db,
    '--schema-path', p.schema
  ]);
  let af = P.join(d, 'allow'), rf = P.join(d, 'r');
  put(af, '');
  put(rf,
      `rule "origin"\n  forbid origin from file:**/operands.ml form:division allow-file:${
          af}\n`);
  sql(p, db, "UPDATE exn_origins SET col=100000-id WHERE form='division'");
  let g = run(p.rules, [ db, rf, '--format', 'json' ]);
  A.equal(g.status, 1);
  let x = jsout(g).results[0];
  for (const c of ['integer_literal', 'identifier', 'other'])
    A.ok(x.origin_contexts.some(q => q.category === c));
  A.ok(x.origin_contexts.some(q => q.category === 'integer_literal' &&
                                   q.representation === '-2'));
  A.ok(x.origin_contexts.some(q => q.category === 'other' &&
                                   q.representation === null));
  for (const k of ['int32', 'int64', 'nativeint'])
    A.ok(x.origin_contexts.some(q => q.integer_kind === k));
  A.ok(x.origin_contexts.some(
      q => q.unavailable_reason &&
           q.unavailable_reason.includes('256 UTF-8 bytes')));
  A.ok(x.context_total > 200);
  A.equal(x.context_omitted, x.context_total - x.origin_contexts.length);
  let out = P.join(d, 'out');
  F.mkdirSync(out);
  A.equal(rep(p, db, out, rf).status, 0);
  A.deepEqual(rr(arts(out).j, 1).origin_contexts, x.origin_contexts);
  for (
      const [n, s, clone] of [
          [ 'slot', "operand_slot='bad'", false ],
          [ 'category', "operand_category='bogus'", true ],
          [ 'primitive', "operand_primitive='%bad'", false ],
          [
            'representation',
            "operand_category='identifier',operand_repr=NULL,operand_unavailable_reason=NULL",
            false
          ],
          [
            'kind',
            "operand_primitive='%int32_div',operand_integer_kind='int64'", false
          ]]) {
    let b = P.join(d, n + '.db');
    F.copyFileSync(db, b);
    if (clone)
      sql(p, b,
          'ALTER TABLE exn_origins RENAME TO eo_checked;CREATE TABLE exn_origins AS SELECT * FROM eo_checked;DROP TABLE eo_checked;');
    sql(p, b,
        `UPDATE exn_origins SET ${
            s} WHERE id=(SELECT min(id) FROM exn_origins)`);
    A.equal(run(p.rules, [ b, rf, '--format', 'json' ]).status, 2);
    let bo = P.join(d, n);
    F.mkdirSync(bo);
    A.equal(rep(p, b, bo, rf).status, 3)
  }
  let oldDb = P.join(d, 'old.db');
  F.copyFileSync(db, oldDb);
  sql(p, oldDb,
      'ALTER TABLE exn_origins RENAME TO eo_new;CREATE TABLE exn_origins AS SELECT id,function_id,scope_id,form,exn_path,escapes,line,col,channel FROM eo_new;DROP TABLE eo_new;');
  let oldOut = P.join(d, 'old');
  F.mkdirSync(oldOut);
  A.equal(rep(p, oldDb, oldOut, rf).status, 0);
  A.ok(rr(arts(oldOut).j, 1)
           .origin_contexts.every(q => q.availability === 'unavailable'));
  let nullDb = P.join(d, 'null.db');
  F.copyFileSync(db, nullDb);
  sql(p, nullDb,
      'UPDATE exn_origins SET operand_primitive=NULL,operand_slot=NULL,operand_category=NULL,operand_repr=NULL,operand_integer_kind=NULL,operand_unavailable_reason=NULL');
  let nullOut = P.join(d, 'null');
  F.mkdirSync(nullOut);
  A.equal(rep(p, nullDb, nullOut, rf).status, 0);
  A.ok(rr(arts(nullOut).j, 1)
           .origin_contexts.every(q => q.availability === 'unavailable'));
  for (
      const [n, set] of [[ 'empty', "operand_category=''" ], [
        'reason',
        "operand_primitive=NULL,operand_slot=NULL,operand_category=NULL,operand_repr=NULL,operand_integer_kind=NULL,operand_unavailable_reason='alone'"
      ]]) {
    let b = P.join(d, n + '-partial.db');
    F.copyFileSync(db, b);
    sql(p, b,
        'ALTER TABLE exn_origins RENAME TO eo_checked;CREATE TABLE exn_origins AS SELECT * FROM eo_checked;DROP TABLE eo_checked;');
    sql(p, b,
        `UPDATE exn_origins SET ${
            set} WHERE id=(SELECT min(id) FROM exn_origins)`);
    let bo = P.join(d, n + '-partial');
    F.mkdirSync(bo);
    A.equal(rep(p, b, bo, rf).status, 3)
  }
  put(P.join(root, 'operands.ml'), 'let source_changed = 0\n');
  let changed = P.join(d, 'changed.db');
  ok('retained CMT', p.index, [
    '--build-dir', P.join(root, '_build/default'), '--db-path', changed,
    '--schema-path', p.schema
  ]);
  let changedRun = run(p.rules, [ changed, rf, '--format', 'json' ]);
  A.equal(changedRun.status, 1);
  A.ok(jsout(changedRun)
           .results[0]
           .origin_contexts.some(q => q.category === 'identifier'))
}
function main() {
  let m = process.argv[2];
  if (!modes.has(m))
    throw new X('unknown mode ' + m);
  if (process.env.ACTIONABLE_REVIEW_REPORTS_CONTROL === 'assert')
    A.fail('controlled assertion');
  if (process.env.ACTIONABLE_REVIEW_REPORTS_CONTROL === 'execution')
    throw new X('controlled execution');
  let repo = P.resolve(__dirname, '..'),
      built = (...xs) => P.join(repo, '_build', 'default', ...xs);
  let p = {
    report :
        need('ARCH_REPORT', built('bin', 'arch_report', 'arch_report.exe')),
    rules : need('ARCH_RULES', built('bin', 'arch_rules', 'arch_rules.exe')),
    schema : need('ARCH_SCHEMA', P.join(repo, 'architecture-schema.sql')),
    sqlite : tool('SQLITE3', 'sqlite3')
  };
  if (m === 'operands') {
    p.index = need('ARCH_INDEX', built('bin', 'arch_callgraph_ocaml',
                                       'arch_callgraph_ocaml.exe'));
    p.dune = tool('DUNE', 'dune')
  }
  let d = F.mkdtempSync(P.join(O.tmpdir(), 'actionable-review-reports-'));
  try {
    ({rules, ordering, operands, compatibility : compat})[m](p, d)
  } finally {
    F.rmSync(d, {recursive : true, force : true})
  }
}
try {
  main()
} catch (e) {
  process.stderr.write(
      (e instanceof A.AssertionError ? 'assertion: ' : 'execution error: ') +
      (e.stack || e.message || e) + '\n');
  process.exit(e instanceof A.AssertionError ? 1 : 2)
}
