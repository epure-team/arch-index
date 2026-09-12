#!/usr/bin/env node
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const {spawnSync} = require('node:child_process');

const LIMIT = 16 * 1024 * 1024;
const TIMEOUT = 120000;
const FILES = ['gate.json', 'report.json', 'report.sarif', 'report.html', 'diagnostics.txt', 'run.json'];
const RULE = 'rule "self escaping assertion and division origins" forbid origin from file:lib/arch_index/** form:assert,division channel:exception allow-file:test/fixtures/origin-consumer/self.allow';

const sha256 = data => crypto.createHash('sha256').update(data).digest('hex');
const fileHash = file => sha256(fs.readFileSync(file));
const posix = value => value.split(path.sep).join('/');

function command(exe, args, options = {}) {
  const result = spawnSync(exe, args, {cwd: options.cwd, encoding: 'utf8', timeout: options.timeout || TIMEOUT,
    maxBuffer: options.maxBuffer || LIMIT, env: {...process.env, ...options.env}});
  if (result.error) throw new Error(`${path.basename(exe)} execution failed: ${result.error.message}`);
  if (result.signal) throw new Error(`${path.basename(exe)} terminated by ${result.signal}`);
  return {status: result.status, stdout: result.stdout || '', stderr: result.stderr || ''};
}

function walk(dir, suffixes, rejectSymlinks = false) {
  const found = [];
  for (const entry of fs.readdirSync(dir, {withFileTypes: true})) {
    const candidate = path.join(dir, entry.name);
    const stat = fs.lstatSync(candidate);
    if (rejectSymlinks && stat.isSymbolicLink()) {
      const relevantFile = suffixes.some(s => entry.name.endsWith(s));
      let targetDirectory = false; try { targetDirectory = fs.statSync(candidate).isDirectory(); } catch {}
      if (relevantFile || targetDirectory) throw new Error(`symlink in input tree: ${candidate}`);
    }
    if (entry.isDirectory()) found.push(...walk(candidate, suffixes, rejectSymlinks));
    else if (suffixes.some(s => entry.name.endsWith(s))) found.push(candidate);
  }
  return found.sort();
}

function contained(root, candidate) {
  const relative = path.relative(root, candidate);
  return relative === '' || (!relative.startsWith(`..${path.sep}`) && relative !== '..' && !path.isAbsolute(relative));
}

function inventory(files, base, rejectSymlinks = false, physicalRoot = base) {
  const canonical = new Set();
  const realRoot = fs.realpathSync(physicalRoot);
  return files.map(file => {
    const stat = fs.lstatSync(file);
    if (rejectSymlinks && stat.isSymbolicLink()) throw new Error(`symlinked CMT input: ${file}`);
    const real = fs.realpathSync(file);
    if (!contained(realRoot, real)) throw new Error(`input escapes fixed physical root: ${file}`);
    if (canonical.has(real)) throw new Error(`duplicate canonical input: ${file}`);
    canonical.add(real);
    const relative = posix(path.relative(base, file));
    if (!relative || relative.startsWith('../') || path.isAbsolute(relative)) throw new Error(`input outside fixed root: ${file}`);
    return {path: relative, sha256: fileHash(file)};
  }).sort((a, b) => a.path.localeCompare(b.path));
}

function validateReference(reference) {
  if (reference.version !== 1 || !Array.isArray(reference.modules) || !reference.totals || !Array.isArray(reference.origin_groups))
    throw new Error('invalid reference version/shape');
  const seenModules = new Set();
  for (const p of reference.modules) {
    if (typeof p !== 'string' || path.isAbsolute(p) || p.split('/').includes('..') || seenModules.has(p)) throw new Error('invalid/duplicate reference module');
    seenModules.add(p);
  }
  for (const key of ['modules', 'functions', 'calls', 'origins'])
    if (!Number.isSafeInteger(reference.totals[key]) || reference.totals[key] < 0) throw new Error(`invalid reference total ${key}`);
  if (reference.totals.modules !== reference.modules.length) throw new Error('reference module total disagrees with module paths');
  const groups = new Set(); let sum = 0;
  for (const g of reference.origin_groups) {
    const key = `${g.channel}\0${g.form}\0${g.escapes}`;
    if (typeof g.channel !== 'string' || !g.channel || typeof g.form !== 'string' || !g.form || groups.has(key) || ![0, 1].includes(g.escapes) || !Number.isSafeInteger(g.count) || g.count < 0) throw new Error('invalid/duplicate origin group');
    groups.add(key); sum += g.count;
  }
  if (sum !== reference.totals.origins) throw new Error('reference origin total disagrees with groups');
}

function sqlite(db, sql) {
  const r = command('sqlite3', ['-json', db, sql]);
  if (r.status !== 0) throw new Error(`sqlite3 failed: ${r.stderr}`);
  return JSON.parse(r.stdout || '[]');
}

function compareCoverage(current, reference, indexedModules, sourceModules) {
  const deltas = [];
  for (const key of ['modules', 'functions', 'calls', 'origins']) {
    const delta = current.totals[key] - reference.totals[key];
    if (delta !== 0) deltas.push({metric: key, reference: reference.totals[key], current: current.totals[key], delta});
  }
  const map = rows => new Map(rows.map(g => [`${g.channel}\0${g.form}\0${g.escapes}`, g.count]));
  const a = map(reference.origin_groups), b = map(current.origin_groups);
  for (const key of [...new Set([...a.keys(), ...b.keys()])].sort()) {
    const av = a.get(key) || 0, bv = b.get(key) || 0;
    if (av !== bv) { const [channel, form, escapes] = key.split('\0'); deltas.push({metric: 'origin_group', channel, form, escapes: Number(escapes), reference: av, current: bv, delta: bv-av}); }
  }
  const missing = reference.modules.filter(x => !indexedModules.includes(x));
  const extra = indexedModules.filter(x => !reference.modules.includes(x));
  if (missing.length || extra.length) deltas.push({metric: 'module_population', missing, extra});
  const sourceMissing = reference.modules.filter(x => !sourceModules.includes(x));
  const sourceExtra = sourceModules.filter(x => !reference.modules.includes(x));
  if (sourceMissing.length || sourceExtra.length) deltas.push({metric: 'source_module_population', missing: sourceMissing, extra: sourceExtra});
  return deltas;
}

function sharedResult(result) {
  const copy = {...result}; delete copy.evaluator; if (copy.exact === false) delete copy.exact; return copy;
}

function canonical(value) {
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === 'object') return Object.fromEntries(Object.keys(value).sort().map(k => [k, canonical(value[k])]));
  return value;
}

const same = (a, b) => JSON.stringify(canonical(a)) === JSON.stringify(canonical(b));

function validateEvidence(gate, report, sarif, html) {
  if (gate.computed !== true || gate.contract_ok !== true || !Array.isArray(gate.results) || gate.results.length !== 1) throw new Error('gate is not one computed contracted rule');
  const result = gate.results[0];
  if (result.ordinal !== 1 || result.rule !== 'self escaping assertion and division origins' || result.kind !== 'origin') throw new Error('unexpected gate rule identity');
  const valid = ['PASS', 'UNKNOWN', 'VIOLATION', 'POSSIBLE'];
  if (!valid.includes(result.verdict)) throw new Error(`ineligible verdict ${result.verdict}`);
  const census = gate.proved + gate.violations + gate.possible + gate.unknown_escaping + gate.unknown_no_contract + gate.vacuous + gate.not_computed;
  const expected = {proved:0, violations:0, possible:0, unknown_escaping:0, unknown_no_contract:0, vacuous:0, not_computed:0};
  const field = {PASS:'proved',VIOLATION:'violations',POSSIBLE:'possible',UNKNOWN:'unknown_escaping'}[result.verdict]; expected[field] = 1;
  const expectedFailed = ['VIOLATION','POSSIBLE'].includes(result.verdict) ? [result.rule] : [];
  if (census !== 1 || Object.entries(expected).some(([k,v]) => gate[k] !== v) || gate.unknown !== gate.unknown_escaping + gate.unknown_no_contract ||
      gate.failing !== expectedFailed.length || !same(gate.failed, expectedFailed) || gate.verdict !== (expectedFailed.length ? 'fail' : 'pass')) throw new Error('inconsistent gate census/policy');
  if (report.verdicts_status !== 'COMPUTED' || report.rule_results.length !== 1 || !same(sharedResult(report.rule_results[0]), sharedResult(result))) throw new Error('gate/report rule evidence diverges');
  const ruleRun = sarif.runs.find(run => run.properties && run.properties.category === 'arch-report/rules');
  const reportVerdicts = {PASS:expected.proved,VIOLATION:expected.violations,POSSIBLE:expected.possible,UNKNOWN:expected.unknown_escaping,
    UNKNOWN_NO_CONTRACT:expected.unknown_no_contract,NO_SOURCE:0,NO_TARGET:0,NOT_COMPUTED:expected.not_computed};
  if (!same(report.verdicts, reportVerdicts) || !ruleRun || ruleRun.properties.contract_ok !== true || ruleRun.properties.computed !== true ||
      sarif.properties.verdicts_status !== report.verdicts_status || !same(sarif.properties.verdicts, report.verdicts) || !same(sarif.properties.rule_results, report.rule_results)) throw new Error('report/SARIF rule evidence diverges');
  const expectedAlerts = report.rule_results.filter(r => r.verdict !== 'PASS').map(r => `${r.rule}#${r.ordinal}:${r.verdict}`).sort();
  const actualAlerts = (ruleRun.results || []).map(r => `${r.ruleId}:${r.properties.verdict}`).sort();
  if (!same(expectedAlerts, actualAlerts)) throw new Error('SARIF rule alerts diverge');
  if (!/<html[\s>]/i.test(html) || !/<\/html>/i.test(html) || !html.includes('self escaping assertion and division origins') || !html.includes(result.verdict)) throw new Error('HTML report incomplete');
  return result;
}

async function runConsumer(options) {
  const root = fs.realpathSync(options.root);
  const requested = path.resolve(options.out);
  const parent = fs.realpathSync(path.dirname(requested));
  const leaf = path.join(parent, path.basename(requested));
  if (fs.existsSync(leaf) || fs.lstatSync(path.dirname(leaf)) && (() => { try { fs.lstatSync(leaf); return true; } catch { return false; } })()) throw new Error(`output already exists: ${requested}`);
  fs.mkdirSync(leaf);
  let diagnostics = ''; let db; let reportStage;
  const config = options.config || {};
  const paths = {
    schema: path.resolve(root, config.schema || 'architecture-schema.sql'),
    rules: path.resolve(root, config.rules || 'test/fixtures/origin-consumer/self.rules'),
    allow: path.resolve(root, config.allow || 'test/fixtures/origin-consumer/self.allow'),
    reference: path.resolve(root, config.reference || 'test/fixtures/origin-consumer/reference.json'),
    indexer: path.resolve(root, config.indexer || '_build/default/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe'),
    rulesTool: path.resolve(root, config.rulesTool || '_build/default/bin/arch_rules/arch_rules.exe'),
    reportTool: path.resolve(root, config.reportTool || '_build/default/bin/arch_report/arch_report.exe')
  };
  const buildDir = path.resolve(root, config.buildDir || '_build/default/lib/arch_index');
  const sourceDir = path.resolve(root, config.sourceDir || 'lib/arch_index');
  const tracked = Object.values(paths);
  const errorsConfig = path.join(root, 'arch-errors.toml');
  const configPresence = fs.existsSync(errorsConfig); if (configPresence) tracked.push(errorsConfig);
  let before;
  const run = {version: 1, complete: false, status: 'error', policy: null, coverage: null, provenance: {}, artifacts: {}};
  let exit = 2; let gateValidated = false; let inputSnapshot = [];
  const faults = options.faults || {};
  const purgeReports = reason => {
    const errors = [];
    for (const name of ['report.json', 'report.sarif', 'report.html']) {
      try {
        if (faults.cleanupReport === name && fs.existsSync(path.join(leaf, name))) throw new Error(`injected ${name} cleanup failure`);
        fs.unlinkSync(path.join(leaf, name));
      } catch (error) { if (error.code !== 'ENOENT') { const message = `${reason}: cannot remove ${name}: ${error.message}`; errors.push(message); console.error(`origin-consumer: ${message}`); } }
    }
    return errors;
  };
  try {
    before = new Map(tracked.map(p => [p, fileHash(p)]));
    const normalized = fs.readFileSync(paths.rules, 'utf8').split(/\r?\n/).map(x => x.replace(/#.*/, '').trim()).filter(Boolean).join(' ');
    if (normalized !== (config.expectedRule || RULE)) throw new Error('rule declaration differs from bounded contract');
    const reference = JSON.parse(fs.readFileSync(paths.reference, 'utf8')); validateReference(reference);
    const gitRoot = command('git', ['rev-parse', '--show-toplevel'], {cwd: root});
    const revision = command('git', ['rev-parse', 'HEAD'], {cwd: root});
    if (gitRoot.status || revision.status || fs.realpathSync(gitRoot.stdout.trim()) !== root) throw new Error('root is not the resolved Git checkout');
    const dirty = command('git', ['status', '--porcelain=v1', '-uall'], {cwd: root}); if (dirty.status) throw new Error('cannot record git dirtiness');
    const branch = command('git', ['symbolic-ref', '-q', '--short', 'HEAD'], {cwd: root});
    if (![0, 1].includes(branch.status)) throw new Error('cannot determine Git attachment state');
    const realSourceDir = fs.realpathSync(sourceDir), realBuildDir = fs.realpathSync(buildDir);
    if (!contained(root, realSourceDir) || !contained(root, realBuildDir)) throw new Error('fixed source/build root escapes Git checkout');
    const sourceFiles = walk(sourceDir, ['.ml', '.mli']).filter(file => !file.startsWith(`${buildDir}${path.sep}`));
    const cmtFiles = walk(buildDir, ['.cmt', '.cmti'], true);
    if (!sourceFiles.length || !cmtFiles.length) throw new Error('empty source or CMT inventory');
    run.provenance = {revision: revision.stdout.trim(), git_root: root, detached: branch.status === 1,
      dirty: dirty.stdout.split(/\r?\n/).filter(Boolean), output: leaf,
      trusted_build_assumption: 'CMT inputs are trusted local build artifacts; this record does not certify source-to-CMT freshness.',
      sources: inventory(sourceFiles, root, false, sourceDir), cmts: inventory(cmtFiles, buildDir, true, buildDir),
      inputs: Object.fromEntries(tracked.map(p => [posix(path.relative(root, p)), before.get(p)])),
      errors_config: configPresence ? {path: 'arch-errors.toml', sha256: fileHash(errorsConfig)} : {path: null, sha256: null}};
    inputSnapshot = [...sourceFiles, ...cmtFiles].map(p => [p, fileHash(p)]);
    db = path.join(parent, `.origin-consumer-${process.pid}-${crypto.randomBytes(5).toString('hex')}.db`);
    const index = command(paths.indexer, [`--build-dir=${buildDir}`, `--db-path=${db}`, `--schema-path=${paths.schema}`], {cwd: root, ...options.commandOptions});
    diagnostics += index.stderr; if (index.status !== 0) throw new Error(`indexer exited ${index.status}`);
    const totalsRow = sqlite(db, 'select (select count(*) from modules) modules,(select count(*) from functions) functions,(select count(*) from calls) calls,(select count(*) from exn_origins) origins')[0];
    const groups = sqlite(db, 'select channel,form,escapes,count(*) count from exn_origins group by channel,form,escapes order by channel,form,escapes');
    const indexedModules = sqlite(db, 'select path from modules order by path').map(x => x.path);
    const sourceModules = sourceFiles.filter(x => x.endsWith('.ml')).map(x => posix(path.relative(root, x))).sort();
    if (!totalsRow.modules || !totalsRow.functions || !totalsRow.origins) throw new Error('incomplete index measurements');
    const current = {totals: totalsRow, origin_groups: groups};
    const deltas = compareCoverage(current, reference, indexedModules, sourceModules);
    run.coverage = {reference_revision: reference.revision, current, deltas, indexed_modules: indexedModules};
    const gate = command(paths.rulesTool, [db, paths.rules, '--format', 'json', '--on-possible', 'fail', '--on-unknown', 'warn', '--on-vacuous', 'fail', '--on-not-computed', 'fail'], {cwd: root, ...options.commandOptions});
    diagnostics += gate.stderr; let gateJson; try { gateJson = JSON.parse(gate.stdout); } catch { throw new Error('malformed gate JSON'); }
    fs.writeFileSync(path.join(leaf, 'gate.json'), `${JSON.stringify(gateJson, null, 2)}\n`);
    reportStage = fs.mkdtempSync(path.join(parent, '.origin-report-'));
    const reportCmd = command(paths.reportTool, [db, '--out', reportStage, '--rules', paths.rules], {cwd: root, ...options.commandOptions});
    diagnostics += reportCmd.stderr; if (reportCmd.status !== 0) throw new Error(`report exited ${reportCmd.status}`);
    const report = JSON.parse(fs.readFileSync(path.join(reportStage, 'report.json')));
    const sarif = JSON.parse(fs.readFileSync(path.join(reportStage, 'report.sarif')));
    const html = fs.readFileSync(path.join(reportStage, 'report.html'), 'utf8');
    run.provenance.database = {schema_version: report.schema_version, producers: report.producers};
    const result = validateEvidence(gateJson, report, sarif, html);
    gateValidated = true;
    const policyFailed = ['VIOLATION', 'POSSIBLE'].includes(result.verdict);
    if (gate.status !== (policyFailed ? 1 : 0)) throw new Error(`gate exit ${gate.status} inconsistent with ${result.verdict}`);
    run.policy = {verdict: result.verdict, failed: policyFailed, gate_exit: gate.status};
    run.status = policyFailed ? 'policy-failed' : deltas.length ? 'coverage-drift' : 'held';
    exit = policyFailed || deltas.length ? 1 : 0;
    for (const name of ['report.json', 'report.sarif', 'report.html']) fs.copyFileSync(path.join(reportStage, name), path.join(leaf, name));
    if (fs.existsSync(errorsConfig) !== configPresence) throw new Error('arch-errors.toml presence changed during run');
    for (const [p, hash] of before) if (fileHash(p) !== hash) throw new Error(`input mutated during run: ${p}`);
    for (const [p, hash] of inputSnapshot) if (!fs.existsSync(p) || fileHash(p) !== hash) throw new Error(`input mutated during run: ${p}`);
    const afterSources = walk(sourceDir, ['.ml', '.mli']).filter(file => !file.startsWith(`${buildDir}${path.sep}`));
    const afterCmts = walk(buildDir, ['.cmt', '.cmti'], true);
    if (!same(afterSources, sourceFiles) || !same(afterCmts, cmtFiles)) throw new Error('input population changed during run');
    for (const name of ['gate.json', 'report.json', 'report.sarif', 'report.html']) run.artifacts[name] = fileHash(path.join(leaf, name));
    run.complete = true;
  } catch (error) {
    diagnostics += `${error.message}\n`; run.status = 'error'; run.complete = false; exit = 2;
    for (const message of purgeReports('error publication cleanup')) diagnostics += `${message}\n`;
    if (!gateValidated) { try { fs.unlinkSync(path.join(leaf, 'gate.json')); } catch (cleanupError) { if (cleanupError.code !== 'ENOENT') { const message = `error publication cleanup: cannot remove gate.json: ${cleanupError.message}`; diagnostics += `${message}\n`; console.error(`origin-consumer: ${message}`); } } }
  } finally {
    const cleanupErrors = [];
    if (db) for (const suffix of ['', '-wal', '-shm', '-journal']) {
      try {
        if ((faults.cleanupDb && suffix === '') || faults.cleanupSuffix === suffix) throw new Error(`injected database${suffix || ' main'} cleanup failure`);
        fs.unlinkSync(db + suffix);
      } catch (error) { if (error.code !== 'ENOENT') cleanupErrors.push(`cleanup ${path.basename(db + suffix)}: ${error.message}`); }
    }
    if (reportStage) {
      try { if (faults.cleanupStage) throw new Error('injected report staging cleanup failure'); fs.rmSync(reportStage, {recursive: true, force: true}); }
      catch (error) { cleanupErrors.push(`cleanup report staging: ${error.message}`); }
    }
    if (cleanupErrors.length) {
      for (const message of cleanupErrors) console.error(`origin-consumer: ${message}`);
      diagnostics += `${cleanupErrors.join('\n')}\n`; exit = 2; run.status = 'error'; run.complete = false;
      for (const message of purgeReports('cleanup failure publication rollback')) diagnostics += `${message}\n`;
    }
    try {
      fs.writeFileSync(path.join(leaf, 'diagnostics.txt'), diagnostics);
      if (faults.finalRecord) throw new Error('injected final record write failure');
      fs.writeFileSync(path.join(leaf, 'run.json'), `${JSON.stringify(run, null, 2)}\n`);
    } catch (error) {
      exit = 2; run.status = 'error'; run.complete = false;
      const message = `origin-consumer: final record write failed: ${error.message}`;
      console.error(message);
      const rollbackErrors = purgeReports('final record failure publication rollback');
      try { fs.unlinkSync(path.join(leaf, 'run.json')); } catch (unlinkError) { if (unlinkError.code !== 'ENOENT') { const rollback = `cannot remove run.json: ${unlinkError.message}`; rollbackErrors.push(rollback); console.error(`origin-consumer: ${rollback}`); } }
      try { fs.appendFileSync(path.join(leaf, 'diagnostics.txt'), `${message}\n${rollbackErrors.join('\n')}\n`); }
      catch (diagnosticError) { console.error(`origin-consumer: cannot append final failure diagnostics: ${diagnosticError.message}`); }
    }
  }
  return {exit, out: leaf, run};
}

async function cli() {
  if (process.argv.length !== 4 || process.argv[2] !== '--out') throw new Error('usage: node scripts/origin-consumer.js --out <new-output-directory>');
  const result = await runConsumer({root: path.resolve(__dirname, '..'), out: process.argv[3]});
  console.error(`origin-consumer: ${result.run.status} -> ${result.out}`); process.exitCode = result.exit;
}

module.exports = {runConsumer, FILES, validateEvidence, validateReference};
if (require.main === module) cli().catch(error => { console.error(`origin-consumer: ${error.message}`); process.exitCode = 2; });
