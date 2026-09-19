#!/usr/bin/env node
'use strict';

/* A descriptive, baseline-aware consumer for arch-impact JSON. It never
   indexes, reparses Git, promotes a baseline, or turns a delta into a gate. */
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const FILES = ['impact.json', 'scope.json', 'delta.json', 'diagnostics.txt', 'run.json'];
const sha256 = x => crypto.createHash('sha256').update(x).digest('hex');
const canonical = x => Array.isArray(x) ? x.map(canonical) : x && typeof x === 'object' ? Object.fromEntries(Object.keys(x).sort().map(k => [k, canonical(x[k])])) : x;
const encoded = x => JSON.stringify(canonical(x));
const same = (a, b) => encoded(a) === encoded(b);
const fail = x => { throw new Error(x); };
const read = p => JSON.parse(fs.readFileSync(p, 'utf8'));
const write = (p, x) => fs.writeFileSync(p, `${JSON.stringify(x, null, 2)}\n`);

function parse(argv) {
  const values = {};
  for (let i = 0; i < argv.length; i += 2) {
    const k = argv[i], v = argv[i + 1];
    if (!['--impact', '--scope', '--out', '--baseline'].includes(k) || v === undefined || Object.hasOwn(values, k)) fail('usage: node scripts/change-review-consumer.js --impact CURRENT.json --scope SCOPE.json --out NEW_DIR [--baseline PREVIOUS_RUN.json]');
    values[k] = v;
  }
  if (!values['--impact'] || !values['--scope'] || !values['--out']) fail('usage: node scripts/change-review-consumer.js --impact CURRENT.json --scope SCOPE.json --out NEW_DIR [--baseline PREVIOUS_RUN.json]');
  return values;
}
function scopeContract(x) {
  if (!x || Array.isArray(x) || x.version !== 1 || typeof x.corpus !== 'string' || !x.corpus || typeof x.configuration !== 'string' || !x.configuration) fail('scope must be a version-1 object with non-empty corpus and configuration');
  return {value: canonical(x), sha256: sha256(encoded(x))};
}
function rows(values, kind, key) {
  if (!Array.isArray(values)) fail(`impact ${kind} is not an array`);
  const result = new Map();
  for (const v of values) { const id = key(v); if (!id || result.has(id)) fail(`invalid or duplicate ${kind} identity`); result.set(id, {identity: id, value: canonical(v)}); }
  return result;
}
function impactContract(x) {
  if (!x || Array.isArray(x) || x.computed !== true || x.contract_ok !== true || x.sound_reachability !== true) fail('impact is not a computed sound briefing');
  if (x.resolved_cone !== 'possible_bounded' || !same(x.resolved_edge_kinds, ['MUST', 'MAY_ENUMERATED'])) fail('impact bounded edge-kind contract differs');
  if (!x.impact_input || x.impact_input.version !== 1 || !['diff', 'files'].includes(x.impact_input.mode) || !Array.isArray(x.impact_input.changed_files)) fail('impact_input is unavailable or malformed');
  if (!x.index_provenance || x.index_provenance.version !== 1 || !Array.isArray(x.index_provenance.producers) || !Array.isArray(x.index_provenance.analysis_coverage)) fail('index_provenance is unavailable or malformed');
  if (!Array.isArray(x.files_unmatched) || !Array.isArray(x.files_file_granular)) fail('impact file mapping status is unavailable');
  if (x.files_unmatched.length || x.files_file_granular.length) fail('impact input is unmatched or file-granular');
  if (x.decision_analysis_available !== true || !x.findings || x.findings.computed !== true || !Array.isArray(x.findings.decisions)) fail('decision analysis is unavailable');
  const producerIdentity = x.index_provenance.producers.map(p => ({producer:p.producer, producer_version:p.producer_version, soundness_class:p.soundness_class})).sort((a,b) => encoded(a).localeCompare(encoded(b)));
  return {raw:x, input:canonical(x.impact_input), provenance:{schema_version:x.index_provenance.schema_version, producers:producerIdentity, coverage:canonical(x.index_provenance.analysis_coverage)}, rows:{
    touched:rows(x.touched, 'touched', v => typeof v.file === 'string' && typeof v.name === 'string' ? `${v.file}:${v.name}` : null),
    exports:rows(x.affected_exported, 'export', v => typeof v === 'string' ? v : null),
    tests:rows(x.tests_reaching, 'test', v => typeof v === 'string' ? v : null),
    frontier:rows(x.top_frontier, 'frontier', v => typeof v.function === 'string' && Number.isInteger(v.escapes) ? `${v.function}:${v.escapes}` : null),
    decisions:rows(x.findings.decisions, 'decision', v => typeof v.file === 'string' && Number.isInteger(v.line) && typeof v.form === 'string' ? `${v.file}:${v.line}:${v.form}` : null)
  }};
}
function delta(base, now) {
  const one = (name, a, b) => { const old = new Set(a.keys()), current = new Set(b.keys()); const mk = set => [...set].sort().map(identity => ({identity})); return {new:mk(new Set([...current].filter(x=>!old.has(x)))), unchanged:mk(new Set([...current].filter(x=>old.has(x)))), absent:mk(new Set([...old].filter(x=>!current.has(x))))}; };
  const surfaces = Object.fromEntries(Object.keys(now.rows).map(k => [k, one(k, base.rows[k], now.rows[k])]));
  return {version:1, status:'compared', limitations:['All bounded reachability is possible, not definite.','TOP rows are observed frontier holders, never hidden targets.','Absent rows are descriptive, not a correction, risk, or security verdict.'], surfaces};
}
function compatible(a,b,sa,sb) { if (!same(a.input,b.input)) fail('baseline impact input differs'); if (!same(a.provenance,b.provenance)) fail('baseline index provenance differs'); if (sa.sha256 !== sb.sha256) fail('baseline scope manifest differs'); }
function baseline(file) { const run=read(file); if (!run || run.version !== 1 || run.complete !== true || !['first-run','compared'].includes(run.status) || !run.scope || typeof run.scope.sha256 !== 'string' || !run.artifacts || typeof run.artifacts['impact.json'] !== 'string' || typeof run.artifacts['scope.json'] !== 'string') fail('baseline run is incomplete or invalid'); const dir=path.dirname(path.resolve(file)), text=fs.readFileSync(path.join(dir,'impact.json'),'utf8'), scopeText=fs.readFileSync(path.join(dir,'scope.json'),'utf8'); if (sha256(text)!==run.artifacts['impact.json']) fail('baseline impact hash differs from run.json'); if (sha256(scopeText)!==run.artifacts['scope.json']) fail('baseline scope hash differs from run.json'); const scope=scopeContract(JSON.parse(scopeText)); if(scope.sha256!==run.scope.sha256) fail('baseline scope manifest hash differs from run.json'); return {impact:impactContract(JSON.parse(text)),scope}; }
function runConsumer(o) { const parent=fs.realpathSync(path.dirname(path.resolve(o.out))), out=path.join(parent,path.basename(o.out)); if(fs.existsSync(out)) fail(`output already exists: ${out}`); fs.mkdirSync(out); let run={version:1,complete:false,status:'error',artifacts:{}}, exit=2; try { const text=fs.readFileSync(o.impact,'utf8'), current=impactContract(JSON.parse(text)), scope=scopeContract(read(o.scope)); const previous=o.baseline ? baseline(o.baseline) : null; const d=previous ? (compatible(previous.impact,current,previous.scope,scope),delta(previous.impact,current)) : {version:1,status:'no_baseline',limitations:['No semantic comparison was requested.'],surfaces:{}}; fs.writeFileSync(path.join(out,'impact.json'),text); write(path.join(out,'scope.json'),scope.value); write(path.join(out,'delta.json'),d); fs.writeFileSync(path.join(out,'diagnostics.txt'),''); run={version:1,complete:true,status:o.baseline?'compared':'first-run',scope:{sha256:scope.sha256},artifacts:{}}; for(const n of FILES.slice(0,4)) run.artifacts[n]=sha256(fs.readFileSync(path.join(out,n))); write(path.join(out,'run.json'),run); exit=0; } catch(e) { run.diagnostics=e.message; fs.writeFileSync(path.join(out,'diagnostics.txt'),`${e.message}\n`); write(path.join(out,'run.json'),run); } return {exit,out,run}; }
function cli(){const o=parse(process.argv.slice(2));const r=runConsumer({impact:path.resolve(o['--impact']),scope:path.resolve(o['--scope']),out:o['--out'],baseline:o['--baseline']&&path.resolve(o['--baseline'])});console.error(`change-review-consumer: ${r.run.status} -> ${r.out}`);process.exitCode=r.exit;}
module.exports={FILES,impactContract,runConsumer,scopeContract}; if(require.main===module){try{cli()}catch(e){console.error(`change-review-consumer: ${e.message}`);process.exitCode=2;}}
