#!/usr/bin/env node
'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {spawnSync} = require('node:child_process');
const {runConsumer} = require('../scripts/origin-consumer.js');
const {validate} = require('../scripts/origin-consumer-artifacts.js');

const root = path.resolve(__dirname, '..');

function exec(exe, args, cwd) {
  const r = spawnSync(exe, args, {cwd, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024});
  if (r.error || r.signal || r.status !== 0) throw new Error(`${exe} failed (${r.status}): ${r.error || r.signal || r.stderr}`);
  return r.stdout;
}

function write(file, contents) { fs.writeFileSync(file, contents); }

function fixture(source = 'let allowed d = 10 / d\n', mutateReference) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'origin-consumer-check-'));
  try {
  write(path.join(dir, 'consumer.ml'), source);
  write(path.join(dir, 'dune-project'), '(lang dune 3.0)\n');
  write(path.join(dir, 'dune'), '(library (name consumer) (wrapped false))\n');
  fs.copyFileSync(path.join(root, 'architecture-schema.sql'), path.join(dir, 'architecture-schema.sql'));
  write(path.join(dir, 'fixture.allow'), 'allowed | consumer.ml:1 | division | Division_by_zero | x1\n');
  const declaration = `rule "self escaping assertion and division origins"\n  forbid origin from file:consumer.ml form:assert,division channel:exception allow-file:${path.join(dir, 'fixture.allow')}\n`;
  write(path.join(dir, 'fixture.rules'), declaration);
  const reference = {version: 1, revision: 'fixture', modules: ['consumer.ml'], totals: {modules:1,functions:1,calls:1,origins:1},
    origin_groups: [{channel:'exception',form:'division',escapes:1,count:1}]};
  if (mutateReference) mutateReference(reference);
  write(path.join(dir, 'reference.json'), `${JSON.stringify(reference)}\n`);
  exec('git', ['init', '-q'], dir); exec('git', ['add', '.'], dir);
  exec('git', ['-c','user.name=fixture','-c','user.email=fixture@example.invalid','commit','-qm','fixture'], dir);
  exec('dune', ['build','--root',dir], dir);
  const normalized = declaration.split(/\r?\n/).map(x => x.trim()).filter(Boolean).join(' ');
  return {dir, config: {sourceDir: '.', buildDir: '_build/default', schema: 'architecture-schema.sql', rules: 'fixture.rules', allow: 'fixture.allow', reference: 'reference.json',
    indexer: path.join(root, '_build/default/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe'), rulesTool: path.join(root, '_build/default/bin/arch_rules/arch_rules.exe'),
    reportTool: path.join(root, '_build/default/bin/arch_report/arch_report.exe'), expectedRule: normalized}};
  } catch (error) { fs.rmSync(dir,{recursive:true,force:true}); throw error; }
}

function tool(f, name, body) {
  const file = path.join(f.dir, name); write(file, `#!/bin/sh\nset -eu\n${body}\n`); fs.chmodSync(file, 0o755); return file;
}

async function authentic() {
  const productionParent=fs.mkdtempSync(path.join(os.tmpdir(),'origin-consumer-production-'));
  try {
    const production=await runConsumer({root,out:path.join(productionParent,'output')});
    assert.equal(production.exit,0); assert.equal(production.run.status,'held');
    assert.deepEqual(production.run.coverage.current.totals,{modules:23,functions:828,calls:5223,origins:491});
    assert.deepEqual(production.run.coverage.deltas,[]);
    const allowed=fs.readFileSync(path.join(root,'test/fixtures/origin-consumer/self.allow'),'utf8').split(/\r?\n/).filter(x=>x&&!x.startsWith('#'));
    assert.deepEqual(allowed,['collect_calls_from_expr.<fun:1374:21>.<fun:1385:36> | lib/arch_index/arch_index_cmt.ml:1388 | assert | Assert_failure | x1']);
  } finally { fs.rmSync(productionParent,{recursive:true,force:true}); }
  const f = fixture();
  try {
    const out = path.join(f.dir, 'artifacts');
    const result = await runConsumer({root: f.dir, out, config: f.config});
    assert.equal(result.exit, 0, `clean authentic consumer held: ${JSON.stringify(result.run)}\n${fs.readFileSync(path.join(out, 'diagnostics.txt'), 'utf8')}`);
    assert.equal(result.run.status, 'held'); assert.equal(result.run.complete, true);
    assert.equal(result.run.provenance.sources.some(x => x.path === 'consumer.ml'), true);
    assert.equal(result.run.provenance.cmts.some(x => x.path.endsWith('consumer.cmt')), true);
    assert.deepEqual(fs.readdirSync(out).sort(), ['diagnostics.txt','gate.json','report.html','report.json','report.sarif','run.json']);
    assert.equal(validate(out).status, 'held');
  } finally { fs.rmSync(f.dir, {recursive:true, force:true}); }
  await policyCase('let allowed d = 10 / d\nlet fresh d = 20 / d\n', 'fresh | consumer.ml:2 | division | Division_by_zero | ×1');
  await policyCase('let allowed d = (10 / d) + (20 / d)\n', 'allowed | consumer.ml:1 | division | Division_by_zero | ×2');
}

async function policyCase(source, expectedNeedle) {
  const f = fixture(source);
  try {
    const out = path.join(f.dir, 'artifacts'); const result = await runConsumer({root:f.dir,out,config:f.config});
    assert.equal(result.exit, 1); assert.equal(result.run.status, 'policy-failed');
    assert.ok(result.run.coverage.deltas.length > 0, 'policy failure outranks simultaneous reference drift');
    const gate = JSON.parse(fs.readFileSync(path.join(out, 'gate.json')));
    assert.equal(gate.results[0].verdict, 'VIOLATION');
    assert.ok(gate.results[0].detail.some(x => x.includes(expectedNeedle)), `missing detail ${expectedNeedle}`);
    assert.equal(validate(out).status, 'policy-failed');
    const reference=JSON.parse(fs.readFileSync(path.join(f.dir,'reference.json')));
    reference.totals=result.run.coverage.current.totals; reference.origin_groups=result.run.coverage.current.origin_groups;
    fs.writeFileSync(path.join(f.dir,'reference.json'),`${JSON.stringify(reference)}\n`);
    const matched=await runConsumer({root:f.dir,out:path.join(f.dir,'matched-reference'),config:f.config});
    assert.equal(matched.exit,1); assert.equal(matched.run.status,'policy-failed'); assert.deepEqual(matched.run.coverage.deltas,[],
      'matching updated observation cannot exempt the uncovered origin');
  } finally { fs.rmSync(f.dir,{recursive:true,force:true}); }
}

async function failures() {
  let f = fixture();
  try {
    const occupied=path.join(f.dir,'occupied'); fs.mkdirSync(occupied);
    await assert.rejects(() => runConsumer({root:f.dir,out:occupied,config:f.config}), /output already exists/);
    const occupiedFile=path.join(f.dir,'occupied-file'); write(occupiedFile,'preserve');
    await assert.rejects(() => runConsumer({root:f.dir,out:occupiedFile,config:f.config}),/output already exists/); assert.equal(fs.readFileSync(occupiedFile,'utf8'),'preserve');
    const dangling=path.join(f.dir,'dangling'); fs.symlinkSync(path.join(f.dir,'absent'),dangling);
    await assert.rejects(() => runConsumer({root:f.dir,out:dangling,config:f.config}),/output already exists/); assert.equal(fs.lstatSync(dangling).isSymbolicLink(),true);
  } finally { fs.rmSync(f.dir,{recursive:true,force:true}); }

  f = fixture();
  try {
    const physical=path.join(f.dir,'physical'); fs.mkdirSync(physical); const alias=path.join(f.dir,'alias'); fs.symlinkSync(physical,alias);
    const r=await runConsumer({root:f.dir,out:path.join(alias,'leaf'),config:f.config}); assert.equal(r.exit,0); assert.equal(r.out,path.join(physical,'leaf'));
  } finally { fs.rmSync(f.dir,{recursive:true,force:true}); }

  f = fixture();
  try {
    exec('git',['checkout','--detach','-q'],f.dir); const out=path.join(f.dir,'detached');
    const r=await runConsumer({root:f.dir,out,config:f.config}); assert.equal(r.exit,0); assert.equal(r.run.provenance.detached,true);
    assert.equal(r.run.provenance.git_root,f.dir); assert.equal(r.run.provenance.output,out); assert.match(r.run.provenance.trusted_build_assumption,/does not certify/);
  } finally { fs.rmSync(f.dir,{recursive:true,force:true}); }

  f = fixture();
  let escaped;
  try {
    escaped=fs.mkdtempSync(path.join(os.tmpdir(),'origin-consumer-escaped-')); write(path.join(escaped,'escaped.ml'),'let escaped = 1\n');
    fs.symlinkSync(path.join(escaped,'escaped.ml'),path.join(f.dir,'escaped.ml'));
    const out=path.join(f.dir,'escaped-output'); const r=await runConsumer({root:f.dir,out,config:f.config}); assert.equal(r.exit,2);
    assert.match(fs.readFileSync(path.join(out,'diagnostics.txt'),'utf8'),/escapes fixed physical root/);
  } finally { fs.rmSync(f.dir,{recursive:true,force:true}); if (escaped) fs.rmSync(escaped,{recursive:true,force:true}); }

  f = fixture(undefined, ref => { ref.totals.calls = 2; });
  try { const r=await runConsumer({root:f.dir,out:path.join(f.dir,'drift'),config:f.config}); assert.equal(r.exit,1); assert.equal(r.run.status,'coverage-drift'); assert.ok(r.run.coverage.deltas.some(x=>x.metric==='calls'&&x.delta===-1)); }
  finally { fs.rmSync(f.dir,{recursive:true,force:true}); }

  f = fixture(undefined, ref => { ref.modules.push('missing.ml'); ref.totals.modules = 2; });
  try { const r=await runConsumer({root:f.dir,out:path.join(f.dir,'module-drift'),config:f.config}); assert.equal(r.exit,1); assert.equal(r.run.status,'coverage-drift'); assert.ok(r.run.coverage.deltas.some(x=>x.metric==='module_population')); }
  finally { fs.rmSync(f.dir,{recursive:true,force:true}); }

  f = fixture(undefined, ref => { ref.origin_groups[0].form='assert'; });
  try { const r=await runConsumer({root:f.dir,out:path.join(f.dir,'group-drift'),config:f.config}); assert.equal(r.exit,1); assert.equal(r.run.status,'coverage-drift'); assert.equal(r.run.coverage.deltas.filter(x=>x.metric==='origin_group').length,2); }
  finally { fs.rmSync(f.dir,{recursive:true,force:true}); }

  f = fixture();
  try {
    f.config.rulesTool=tool(f,'bad-rules','printf "{}\\n"');
    const r=await runConsumer({root:f.dir,out:path.join(f.dir,'bad'),config:f.config}); assert.equal(r.exit,2,'malformed gate must error'); assert.equal(r.run.status,'error');
    assert.deepEqual(fs.readdirSync(path.join(f.dir,'bad')).sort(),['diagnostics.txt','run.json']); validate(path.join(f.dir,'bad'));
  } finally { fs.rmSync(f.dir,{recursive:true,force:true}); }

  f = fixture();
  try {
    const out=path.join(f.dir,'stage-cleanup-failure');
    const r=await runConsumer({root:f.dir,out,config:f.config,faults:{cleanupStage:true}});
    assert.equal(r.exit,2,'report staging cleanup failure must error');
    assert.equal(r.run.policy.verdict,'PASS'); assert.equal(r.run.complete,false);
    assert.deepEqual(fs.readdirSync(out).sort(),['diagnostics.txt','gate.json','run.json']);
    assert.match(fs.readFileSync(path.join(out,'diagnostics.txt'),'utf8'),/cleanup report staging.*injected/i);
  } finally { fs.rmSync(f.dir,{recursive:true,force:true}); }

  f = fixture();
  try {
    f.config.indexer=tool(f,'empty-index',`db=''; schema=''\nfor arg in "$@"; do case "$arg" in --db-path=*) db=\${arg#*=};; --schema-path=*) schema=\${arg#*=};; esac; done\nsqlite3 "$db" < "$schema"`);
    const out=path.join(f.dir,'empty'); const r=await runConsumer({root:f.dir,out,config:f.config}); assert.equal(r.exit,2); assert.match(fs.readFileSync(path.join(out,'diagnostics.txt'),'utf8'),/incomplete index measurements/);
  } finally { fs.rmSync(f.dir,{recursive:true,force:true}); }

  f = fixture();
  try {
    fs.rmSync(path.join(f.dir,'.git'),{recursive:true,force:true}); const out=path.join(f.dir,'not-git'); const r=await runConsumer({root:f.dir,out,config:f.config}); assert.equal(r.exit,2); assert.match(fs.readFileSync(path.join(out,'diagnostics.txt'),'utf8'),/Git checkout/);
  } finally { fs.rmSync(f.dir,{recursive:true,force:true}); }

  f = fixture();
  try {
    const real=f.config.reportTool;
    f.config.reportTool=tool(f,'bad-report',`"${real}" "$@"\nsed -i '0,/self escaping assertion and division origins/s//tampered rule/' "$3/report.json"`);
    const out=path.join(f.dir,'parity'); const r=await runConsumer({root:f.dir,out,config:f.config});
    assert.equal(r.exit,2,'report parity fault must error'); assert.deepEqual(fs.readdirSync(out).sort(),['diagnostics.txt','run.json']);
  } finally { fs.rmSync(f.dir,{recursive:true,force:true}); }

  f = fixture();
  try {
    const real=f.config.reportTool;
    f.config.reportTool=tool(f,'missing-report',`"${real}" "$@"\nrm "$3/report.html"`);
    const out=path.join(f.dir,'publication'); const r=await runConsumer({root:f.dir,out,config:f.config});
    assert.equal(r.exit,2,'incomplete publication must error'); assert.deepEqual(fs.readdirSync(out).sort(),['diagnostics.txt','run.json']);
  } finally { fs.rmSync(f.dir,{recursive:true,force:true}); }

  f = fixture();
  try {
    const real=f.config.rulesTool;
    f.config.rulesTool=tool(f,'config-appears',`touch "${path.join(f.dir,'arch-errors.toml')}"\nexec "${real}" "$@"`);
    const out=path.join(f.dir,'config-change'); const r=await runConsumer({root:f.dir,out,config:f.config});
    assert.equal(r.exit,2,'config presence mutation must error'); assert.match(fs.readFileSync(path.join(out,'diagnostics.txt'),'utf8'),/presence changed/);
  } finally { fs.rmSync(f.dir,{recursive:true,force:true}); }

  f = fixture();
  try {
    const target=path.join(f.dir,'cmt-alias-target'); fs.mkdirSync(target); fs.symlinkSync(target,path.join(f.dir,'_build/default/cmt-alias'));
    const out=path.join(f.dir,'symlink'); const r=await runConsumer({root:f.dir,out,config:f.config}); assert.equal(r.exit,2); assert.match(fs.readFileSync(path.join(out,'diagnostics.txt'),'utf8'),/symlink in input tree/);
  } finally { fs.rmSync(f.dir,{recursive:true,force:true}); }

  f = fixture();
  try {
    const real=f.config.rulesTool; f.config.rulesTool=tool(f,'mutate',`printf '\\n' >> "${path.join(f.dir,'consumer.ml')}"\nexec "${real}" "$@"`);
    const r=await runConsumer({root:f.dir,out:path.join(f.dir,'mutated'),config:f.config}); assert.equal(r.exit,2,'input mutation must error'); assert.match(fs.readFileSync(path.join(f.dir,'mutated','diagnostics.txt'),'utf8'),/input mutated/);
  } finally { fs.rmSync(f.dir,{recursive:true,force:true}); }

  f = fixture();
  try {
    f.config.rulesTool=tool(f,'slow','sleep 2');
    const r=await runConsumer({root:f.dir,out:path.join(f.dir,'slow-out'),config:f.config,commandOptions:{timeout:25}}); assert.equal(r.exit,2,'timeout must error'); assert.match(fs.readFileSync(path.join(f.dir,'slow-out','diagnostics.txt'),'utf8'),/timed out|ETIMEDOUT/i);
  } finally { fs.rmSync(f.dir,{recursive:true,force:true}); }

  f = fixture();
  try {
    f.config.rulesTool=tool(f,'overflow',"yes X | head -c 17000000");
    const r=await runConsumer({root:f.dir,out:path.join(f.dir,'overflow-out'),config:f.config}); assert.equal(r.exit,2,'overflow must error'); assert.match(fs.readFileSync(path.join(f.dir,'overflow-out','diagnostics.txt'),'utf8'),/maxBuffer|ENOBUFS/i);
  } finally { fs.rmSync(f.dir,{recursive:true,force:true}); }

  f = fixture();
  try {
    const out=path.join(f.dir,'cleanup-failure');
    const logged=[]; const originalError=console.error; console.error=(...parts)=>logged.push(parts.join(' '));
    let r; try { r=await runConsumer({root:f.dir,out,config:f.config,faults:{cleanupDb:true}}); } finally { console.error=originalError; }
    assert.equal(r.exit,2,'cleanup failure must outrank a validated held policy');
    assert.equal(r.run.status,'error'); assert.equal(r.run.complete,false);
    assert.equal(r.run.policy.verdict,'PASS','validated policy survives later cleanup failure');
    assert.deepEqual(fs.readdirSync(out).sort(),['diagnostics.txt','gate.json','run.json']);
    assert.match(fs.readFileSync(path.join(out,'diagnostics.txt'),'utf8'),/cleanup.*injected/i);
    assert.ok(logged.some(line=>/cleanup.*injected/i.test(line)),'cleanup failure is also visible on stderr');
  } finally { fs.rmSync(f.dir,{recursive:true,force:true}); }

  f = fixture();
  try {
    const out=path.join(f.dir,'record-failure');
    const r=await runConsumer({root:f.dir,out,config:f.config,faults:{finalRecord:true}});
    assert.equal(r.exit,2,'final record write failure must error');
    assert.equal(fs.existsSync(path.join(out,'run.json')),false,'failed final record cannot claim complete');
    for (const name of ['report.json','report.sarif','report.html']) assert.equal(fs.existsSync(path.join(out,name)),false,`record failure removes ${name}`);
  } finally { fs.rmSync(f.dir,{recursive:true,force:true}); }
}

async function packageChecks() {
  const f=fixture();
  try {
    const out=path.join(f.dir,'package'); const r=await runConsumer({root:f.dir,out,config:f.config}); assert.equal(r.exit,0); validate(out);
    const original=fs.readFileSync(path.join(out,'report.json')); fs.appendFileSync(path.join(out,'report.json'),' '); assert.throws(()=>validate(out),/digest mismatch/);
    fs.writeFileSync(path.join(out,'report.json'),original); fs.unlinkSync(path.join(out,'report.html')); assert.throws(()=>validate(out),/missing report.html/);
    fs.writeFileSync(path.join(out,'report.html'),'<html></html>');
    const run=JSON.parse(fs.readFileSync(path.join(out,'run.json'))); run.status='invented'; run.complete=false; fs.writeFileSync(path.join(out,'run.json'),JSON.stringify(run));
    assert.throws(()=>validate(out),/unknown run status/);
  } finally { fs.rmSync(f.dir,{recursive:true,force:true}); }
  const ci=fs.readFileSync(path.join(root,'.github/workflows/ci.yml'),'utf8');
  for (const needle of ['id: origin_consumer','actions/upload-artifact@v7','retention-days: 14','if-no-files-found: error',
    'origin-consumer/gate.json','origin-consumer/report.json','origin-consumer/report.sarif','origin-consumer/report.html','origin-consumer/diagnostics.txt','origin-consumer/run.json']) assert.ok(ci.includes(needle),`CI retention missing ${needle}`);
  const consumerBlock=ci.slice(ci.indexOf('id: origin_consumer'),ci.indexOf('- name: Validate escaping origin evidence package'));
  assert.equal(consumerBlock.includes('continue-on-error'),false,'consumer failure must remain visible');
}

async function main() {
  const mode = process.argv[2];
  if (!['authentic', 'failures', 'package'].includes(mode)) {
    throw new Error('usage: origin-recurring-consumer.js authentic|failures|package');
  }
  if (process.env.ORIGIN_CONSUMER_CHECK_CONTROL === 'assert') assert.fail('deliberate checker assertion');
  if (process.env.ORIGIN_CONSUMER_CHECK_CONTROL === 'execution') throw new Error('deliberate checker execution error');
  if (mode === 'authentic') await authentic();
  else if (mode === 'failures') await failures();
  else await packageChecks();
}

main().catch(error => {
  if (error instanceof assert.AssertionError) {
    console.error(`ASSERTION: ${error.message}`);
    process.exitCode = 1;
  } else {
    console.error(`EXECUTION: ${error.stack || error}`);
    process.exitCode = 2;
  }
});
