#!/usr/bin/env node
'use strict';

/* A baseline-aware consumer for the intentionally narrow api-review report.
   It does not index, rebuild, query SQLite, or promote baselines. */
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const FILES = ['report.json', 'scope.json', 'delta.json', 'diagnostics.txt', 'run.json'];
const sha256 = text => crypto.createHash('sha256').update(text).digest('hex');
const canonical = value => {
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === 'object') return Object.fromEntries(Object.keys(value).sort().map(k => [k, canonical(value[k])]));
  return value;
};
const encoded = value => JSON.stringify(canonical(value));
const same = (a, b) => encoded(a) === encoded(b);
const readJson = file => JSON.parse(fs.readFileSync(file, 'utf8'));
const writeJson = (file, value) => fs.writeFileSync(file, `${JSON.stringify(value, null, 2)}\n`);
const producerIdentity = producers => producers.map(p => {
  if (!p || typeof p.producer !== 'string' || !p.producer || (p.producer_version !== null && typeof p.producer_version !== 'string') || typeof p.soundness_class !== 'string' || !p.soundness_class) fail('invalid producer provenance');
  return {producer: p.producer, producer_version: p.producer_version, soundness_class: p.soundness_class};
}).sort((a, b) => encoded(a).localeCompare(encoded(b)));

function fail(message) { throw new Error(message); }

function parse(argv) {
  const values = {};
  for (let i = 0; i < argv.length; i += 2) {
    const flag = argv[i], value = argv[i + 1];
    if (!['--report', '--scope', '--out', '--baseline'].includes(flag) || value === undefined || Object.hasOwn(values, flag)) fail('usage: node scripts/analysis-report-consumer.js --report CURRENT.json --scope SCOPE.json --out NEW_DIR [--baseline PREVIOUS_RUN.json]');
    values[flag] = value;
  }
  if (!values['--report'] || !values['--scope'] || !values['--out']) fail('usage: node scripts/analysis-report-consumer.js --report CURRENT.json --scope SCOPE.json --out NEW_DIR [--baseline PREVIOUS_RUN.json]');
  return values;
}

function reportContract(report) {
  if (!report || typeof report !== 'object' || Array.isArray(report)) fail('report is not a JSON object');
  if (report.profile !== 'api-review') fail('report profile must be api-review');
  if (typeof report.schema_version !== 'string' || !report.schema_version) fail('report has no schema_version');
  if (!Array.isArray(report.producers) || !Array.isArray(report.analysis_coverage) || !Array.isArray(report.sections)) fail('report lacks provenance/sections');
  const api = report.sections.filter(s => s && s.analysis === 'api_surface');
  if (api.length !== 1 || api[0].status !== 'covered' || !Array.isArray(api[0].findings)) fail('api_surface is absent or unavailable');
  const rows = new Map();
  for (const finding of api[0].findings) {
    if (!finding || finding.kind !== 'api_surface' || typeof finding.id !== 'string' || !finding.id.startsWith('api_surface|')) fail('invalid api_surface finding');
    const parts = finding.id.split('|');
    if (parts.length !== 3 || !parts[1] || !parts[2] || finding.subject !== parts[2]) fail(`invalid api identity: ${finding.id}`);
    const identity = `${parts[1]}:${parts[2]}`;
    if (rows.has(identity)) fail(`duplicate api identity: ${identity}`);
    rows.set(identity, {identity, location: finding.location === null ? null : finding.location, id: finding.id});
  }
  if (api[0].finding_count !== rows.size) fail('api_surface finding_count disagrees with findings');
  return {schema_version: report.schema_version, profile: report.profile, producers: report.producers, producer_identity: producerIdentity(report.producers),
    analysis_coverage: report.analysis_coverage, rows};
}

function scopeContract(scope) {
  if (!scope || typeof scope !== 'object' || Array.isArray(scope) || scope.version !== 1 || typeof scope.corpus !== 'string' || !scope.corpus || typeof scope.configuration !== 'string' || !scope.configuration) fail('scope must be a version-1 object with non-empty corpus and configuration');
  return {canonical: encoded(scope), sha256: sha256(encoded(scope))};
}

function delta(base, current) {
  const classify = kind => Array.from(kind).sort().map(identity => ({identity, baseline: base.rows.has(identity), current: current.rows.has(identity)}));
  const old = new Set(base.rows.keys()), now = new Set(current.rows.keys());
  const added = new Set([...now].filter(x => !old.has(x)));
  const unchanged = new Set([...now].filter(x => old.has(x)));
  const absent = new Set([...old].filter(x => !now.has(x)));
  return {version: 1, status: 'compared', identity: 'api_surface file:function',
    limitations: ['An absent API entry is not a correction or risk verdict.', 'MUST/MAY reachability and MAY_TOP frontiers are not compared by this consumer.'],
    summary: {baseline: old.size, current: now.size, new: added.size, unchanged: unchanged.size, absent: absent.size},
    new: classify(added), unchanged: classify(unchanged), absent: classify(absent)};
}

function compatible(base, current, baselineScope, scope) {
  if (base.schema_version !== current.schema_version) fail('baseline schema_version differs');
  if (base.profile !== current.profile) fail('baseline profile differs');
  if (!same(base.producer_identity, current.producer_identity)) fail('baseline producer identity differs');
  if (!same(base.analysis_coverage, current.analysis_coverage)) fail('baseline analysis coverage differs');
  if (baselineScope.sha256 !== scope.sha256) fail('baseline scope manifest differs');
}

function baselineContract(file) {
  const run = readJson(file);
  if (!run || run.version !== 1 || run.complete !== true || !['first-run', 'compared'].includes(run.status) || !run.scope || typeof run.scope.sha256 !== 'string' || !run.artifacts || typeof run.artifacts['report.json'] !== 'string') fail('baseline run is incomplete or invalid');
  const reportFile = path.join(path.dirname(path.resolve(file)), 'report.json');
  const scopeFile = path.join(path.dirname(path.resolve(file)), 'scope.json');
  if (!fs.existsSync(reportFile) || !fs.existsSync(scopeFile)) fail('baseline package lacks report.json or scope.json');
  const reportText = fs.readFileSync(reportFile, 'utf8');
  if (sha256(reportText) !== run.artifacts['report.json']) fail('baseline report hash differs from run.json');
  const scope = scopeContract(readJson(scopeFile));
  if (scope.sha256 !== run.scope.sha256) fail('baseline scope hash differs from run.json');
  return {report: reportContract(JSON.parse(reportText)), scope};
}

function runConsumer(options) {
  const requested = path.resolve(options.out);
  const parentName = path.dirname(requested);
  if (!fs.existsSync(parentName)) fail('output parent does not exist');
  const parent = fs.realpathSync(parentName);
  const out = path.join(parent, path.basename(requested));
  try { fs.lstatSync(out); fail(`output already exists: ${out}`); } catch (error) { if (error.code !== 'ENOENT') throw error; }
  fs.mkdirSync(out);
  let diagnostics = '', outcome = {version: 1, complete: false, status: 'error', artifacts: {}};
  let exit = 2;
  try {
    const reportText = fs.readFileSync(options.report, 'utf8');
    const current = reportContract(JSON.parse(reportText));
    const scopeValue = readJson(options.scope);
    const scope = scopeContract(scopeValue);
    let comparison;
    if (options.baseline) {
      const previous = baselineContract(options.baseline);
      compatible(previous.report, current, previous.scope, scope);
      comparison = delta(previous.report, current);
    } else {
      comparison = {version: 1, status: 'no_baseline', identity: 'api_surface file:function',
        limitations: ['No semantic comparison was requested.', 'Promote this completed package explicitly after review.'],
        summary: {baseline: null, current: current.rows.size, new: null, unchanged: null, absent: null}, new: [], unchanged: [], absent: []};
    }
    fs.writeFileSync(path.join(out, 'report.json'), reportText);
    writeJson(path.join(out, 'scope.json'), canonical(scopeValue));
    writeJson(path.join(out, 'delta.json'), comparison);
    outcome = {version: 1, complete: true, status: options.baseline ? 'compared' : 'first-run',
      report: {profile: current.profile, schema_version: current.schema_version, producers: current.producers}, scope: {sha256: scope.sha256},
      comparison: comparison.summary, artifacts: {}};
    fs.writeFileSync(path.join(out, 'diagnostics.txt'), diagnostics);
    for (const name of ['report.json', 'scope.json', 'delta.json', 'diagnostics.txt']) outcome.artifacts[name] = sha256(fs.readFileSync(path.join(out, name)));
    writeJson(path.join(out, 'run.json'), outcome);
    exit = 0;
  } catch (error) {
    diagnostics += `${error.message}\n`;
    outcome.diagnostics = error.message;
    try { fs.writeFileSync(path.join(out, 'diagnostics.txt'), diagnostics); writeJson(path.join(out, 'run.json'), outcome); } catch (writeError) { console.error(`analysis-report-consumer: unable to publish error record: ${writeError.message}`); }
  }
  return {exit, out, run: outcome};
}

function cli() {
  const options = parse(process.argv.slice(2));
  const result = runConsumer({report: path.resolve(options['--report']), scope: path.resolve(options['--scope']), out: options['--out'], baseline: options['--baseline'] && path.resolve(options['--baseline'])});
  console.error(`analysis-report-consumer: ${result.run.status} -> ${result.out}`);
  process.exitCode = result.exit;
}

module.exports = {FILES, canonical, delta, reportContract, runConsumer, scopeContract};
if (require.main === module) { try { cli(); } catch (error) { console.error(`analysis-report-consumer: ${error.message}`); process.exitCode = 2; } }
