#!/usr/bin/env node
'use strict';

// CHECK-3 is structural accounting, not a semantic refinement proof.  In
// particular, source positions in canonical rows do not identify a physical
// CMT occurrence and cannot certify a one-to-many callback expansion.
const assert = require('node:assert/strict');
const cp = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const {
  ROOT, TEZOS, CURRENT_PRODUCER, CURRENT_SCHEMA, fileSha256, readManifest,
  makeSelection,
} = require('../tezos-residual-targets/baseline.js');
const {canonicalStrings, digestStrings, snapshotDatabase} = require('../tezos-call-resolution/comparison.js');

const frozenDirectory = path.join(ROOT, 'improvement/2026-09-15-ocaml-cfa/stage1-baseline');
const frozen = Object.freeze({
  rows: 45052,
  digest: '1799c07fd3eb87d4bca433b15b7daeb47f466f90cb098541372e1dd9dd7bac7a',
  relations: Object.freeze({irmin: 4849, protocol: 12171}),
  manifest: '9e38880a52f855c58081b1a171af5879058cbaa2697aaa5694827cbd16f8ecd1',
  producer: '1cb7943cefa15a56f0df39fd2c2e741832d1acefaeedb92d189eb643075e9593',
  schema: '1dd2d909e1feb2582e8a13f717ef165b7be9b73b908f73f47983920bded580d0',
});
const maxBuffer = 64 * 1024 * 1024;

class SetupError extends Error {}
function exitCode(error) { return error instanceof assert.AssertionError ? 1 : 2; }

function canonical(row) { return JSON.parse(canonicalStrings([row])[0]); }

function counted(rows) {
  const result = new Map();
  for (const raw of rows) {
    const row = canonical(raw), key = JSON.stringify(row);
    const value = result.get(key) || {row, count: 0};
    value.count++;
    result.set(key, value);
  }
  return result;
}

function multisetDelta(oldRows, newRows) {
  const oldCounts = counted(oldRows), newCounts = counted(newRows);
  const subtract = (left, right) => [...left].sort().flatMap(([key, value]) => {
    const count = value.count - (right.get(key)?.count || 0);
    return count > 0 ? [{row: value.row, count}] : [];
  });
  return {removed: subtract(oldCounts, newCounts), added: subtract(newCounts, oldCounts)};
}

function relationKey(row) {
  const value = canonical(row);
  return value.edge_form === 'value_alias' || value.target === null ? null :
    JSON.stringify([value.caller_path, value.caller, value.call_site, value.target_path, value.target]);
}

function relationSet(rows) {
  const result = new Set();
  for (const row of rows) { const key = relationKey(row); if (key !== null) result.add(key); }
  return result;
}

function relationDelta(oldRows, newRows) {
  const oldSet = relationSet(oldRows), newSet = relationSet(newRows);
  const changes = (left, right) => [...left].filter(key => !right.has(key)).sort()
    .map(key => ({key, relation: JSON.parse(key)}));
  return {losses: changes(oldSet, newSet), gains: changes(newSet, oldSet)};
}

function sliceRelationCounts(rows) {
  const counts = {irmin: 0, protocol: 0};
  for (const key of relationSet(rows)) {
    const [callerPath] = JSON.parse(key);
    if (callerPath.startsWith('irmin/')) counts.irmin++;
    else if (callerPath.startsWith('src/proto_alpha/')) counts.protocol++;
  }
  return counts;
}

function newMustRows(rows) { return rows.filter(row => canonical(row).kind === 'MUST').map(canonical); }

function run(command, args, options = {}) {
  const result = cp.spawnSync(command, args, {cwd: ROOT, encoding: 'utf8', timeout: 180000, maxBuffer, ...options});
  if (result.error) throw new SetupError(`${command}: ${result.error.message}`);
  if (result.signal || result.status !== 0) {
    const detail = (result.stderr || result.stdout || '').trim();
    throw new SetupError(`${command} exited ${result.status || result.signal}${detail ? `: ${detail}` : ''}`);
  }
  return result.stdout;
}

function commandBytes(command, args, cwd) {
  const result = cp.spawnSync(command, args, {cwd, encoding: null, maxBuffer});
  if (result.error || result.status !== 0) throw new SetupError(`${command} cannot capture source state`);
  return result.stdout;
}

function contentHash(parts) {
  const hash = crypto.createHash('sha256');
  for (const part of parts) { hash.update(part); hash.update('\0'); }
  return hash.digest('hex');
}

// Only untracked files that can affect this producer are inventoried.  Roster
// notes, manifests, and other agents' untracked work are deliberately outside
// the producer input boundary and cannot make this replay spuriously fail.
function producerUntrackedHash() {
  const names = commandBytes('git', ['ls-files', '--others', '--exclude-standard', '-z'], ROOT)
    .toString('utf8').split('\0').filter(name => name &&
      (name.startsWith('lib/arch_index/') || name.startsWith('bin/arch_callgraph_ocaml/') || name === 'architecture-schema.sql'))
    .sort();
  const parts = [];
  for (const name of names) {
    const full = path.join(ROOT, name);
    if (!fs.statSync(full).isFile()) throw new SetupError(`untracked producer input is not a file: ${name}`);
    parts.push(name, fs.readFileSync(full));
  }
  return contentHash(parts);
}

function localSourceState() {
  return {
    arch_revision: run('git', ['rev-parse', 'HEAD']).trim(),
    arch_status: run('git', ['status', '--porcelain=v1', '--untracked-files=all']),
    tracked_diff_sha256: contentHash([commandBytes('git', ['diff', '--binary', '--no-ext-diff', 'HEAD'], ROOT)]),
    producer_untracked_sha256: producerUntrackedHash(),
    tezos_revision: run('git', ['rev-parse', 'HEAD'], {cwd: TEZOS}).trim(),
    tezos_status: run('git', ['status', '--porcelain=v1', '--untracked-files=all'], {cwd: TEZOS}),
    producer_sha256: fileSha256(CURRENT_PRODUCER),
    schema_sha256: fileSha256(CURRENT_SCHEMA),
  };
}

function equalState(before, after) { return Object.keys(before).every(key => before[key] === after[key]); }
function inputsUnchanged(before, after) {
  return ['arch_revision', 'tracked_diff_sha256', 'producer_untracked_sha256', 'tezos_revision', 'tezos_status',
    'producer_sha256', 'schema_sha256'].every(key => before[key] === after[key]);
}
function readStage2Manifest() { return readManifest({expected: {selected: 410, manifestSha256: frozen.manifest}}); }
function frozenByteState() {
  return {
    snapshot_sha256: fileSha256(path.join(frozenDirectory, 'snapshot.json')),
    producer_sha256: fileSha256(path.join(frozenDirectory, 'producer.exe')),
    schema_sha256: fileSha256(path.join(frozenDirectory, 'architecture-schema.sql')),
  };
}

function validateFrozen() {
  const snapshotFile = path.join(frozenDirectory, 'snapshot.json');
  const baselineProducer = path.join(frozenDirectory, 'producer.exe');
  const baselineSchema = path.join(frozenDirectory, 'architecture-schema.sql');
  let snapshot;
  try { snapshot = JSON.parse(fs.readFileSync(snapshotFile, 'utf8')); }
  catch (error) { throw new SetupError(`frozen snapshot: ${error.message}`); }
  if (!snapshot || !Array.isArray(snapshot.rows)) throw new SetupError('frozen snapshot has no row array');
  assert.equal(snapshot.rows.length, frozen.rows, 'frozen stage1 row count');
  assert.equal(digestStrings(canonicalStrings(snapshot.rows)), frozen.digest, 'frozen stage1 digest');
  assert.deepEqual(sliceRelationCounts(snapshot.rows), frozen.relations, 'frozen stage1 slice relation counts');
  assert.equal(fileSha256(baselineProducer), frozen.producer, 'frozen stage1 producer hash');
  assert.equal(fileSha256(baselineSchema), frozen.schema, 'frozen stage1 schema hash');
  return snapshot.rows.map(canonical);
}

function buildCurrentProducer() { run('opam', ['exec', '--', 'dune', 'build', 'bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe']); }

function copyCurrentInputs(temporary, state) {
  const producer = path.join(temporary, 'producer.exe');
  const schema = path.join(temporary, 'architecture-schema.sql');
  fs.copyFileSync(CURRENT_PRODUCER, producer);
  fs.copyFileSync(CURRENT_SCHEMA, schema);
  if (fileSha256(producer) !== state.producer_sha256 || fileSha256(schema) !== state.schema_sha256)
    throw new SetupError('copied producer/schema hash does not match pre-replay input');
  return {producer, schema};
}

function sampledRss(pid) {
  try {
    const status = fs.readFileSync(`/proc/${pid}/status`, 'utf8');
    const match = status.match(/^Vm(?:HWM|RSS):\s+(\d+)\s+kB$/m);
    return match ? Number(match[1]) : null;
  } catch (_) { return null; }
}

function produceMeasured(producer, schema, db, selection) {
  return new Promise((resolve, reject) => {
    const started = process.hrtime.bigint();
    const child = cp.spawn(producer, ['--build-dir', selection, '--db-path', db, '--schema-path', schema],
      {cwd: TEZOS, stdio: ['ignore', 'pipe', 'pipe']});
    let stdout = '', stderr = '', maxRss = null, timedOut = false, outputOverflow = false;
    let killTimer = null;
    const append = (current, chunk) => {
      if (current.length + chunk.length > maxBuffer) { outputOverflow = true; child.kill('SIGTERM'); return current; }
      return current + chunk;
    };
    const sample = () => {
      if (!child.pid) return;
      const rss = sampledRss(child.pid);
      if (rss !== null) maxRss = Math.max(maxRss || 0, rss);
    };
    sample();
    const timer = setInterval(sample, 20);
    const timeout = setTimeout(() => {
      timedOut = true;
      child.kill('SIGTERM');
      killTimer = setTimeout(() => child.kill('SIGKILL'), 5000);
    }, 180000);
    child.stdout.on('data', chunk => { stdout = append(stdout, chunk.toString()); });
    child.stderr.on('data', chunk => { stderr = append(stderr, chunk.toString()); });
    child.on('error', error => { clearInterval(timer); clearTimeout(timeout); if (killTimer) clearTimeout(killTimer); reject(new SetupError(`producer: ${error.message}`)); });
    child.on('close', (status, signal) => {
      clearInterval(timer); clearTimeout(timeout); if (killTimer) clearTimeout(killTimer);
      const resource = {producer_wall_ms: Number(process.hrtime.bigint() - started) / 1e6,
        max_rss_kib: maxRss, rss_observation: maxRss === null ? 'unavailable: no Linux /proc sample' : 'Linux /proc VmHWM/VmRSS sample'};
      if (outputOverflow) reject(new SetupError('producer output exceeded bounded capture'));
      else if (timedOut || signal || status !== 0) {
        const detail = (stderr || stdout).trim();
        reject(new SetupError(`producer exited ${timedOut ? 'timeout' : status || signal}${detail ? `: ${detail}` : ''}`));
      } else resolve(resource);
    });
  });
}

function measurementReport(oldRows, snapshot, before, after, manifest, resource) {
  const rows = multisetDelta(oldRows, snapshot.rows);
  const relations = relationDelta(oldRows, snapshot.rows);
  const must = rows.added.filter(change => change.row.kind === 'MUST');
  return {
    check: 'CHECK3', status: 'measured', semantic_status: 'not_proven',
    frozen_stage1: {row_count: frozen.rows, canonical_sha256: frozen.digest, relations: frozen.relations,
      producer_sha256: frozen.producer, schema_sha256: frozen.schema},
    current: {row_count: snapshot.row_count, canonical_sha256: snapshot.digest,
      producer_sha256: before.producer_sha256, schema_sha256: before.schema_sha256,
      manifest_sha256: frozen.manifest, selected: manifest.records.length,
      cmt_hashes_reverified: true, arch_revision: before.arch_revision, tezos_revision: before.tezos_revision},
    rows: {removed: rows.removed, added: rows.added, removed_count: rows.removed.reduce((n, item) => n + item.count, 0),
      added_count: rows.added.reduce((n, item) => n + item.count, 0)},
    relations: {before: sliceRelationCounts(oldRows), after: sliceRelationCounts(snapshot.rows),
      gains: relations.gains, losses: relations.losses},
    new_must_rows: must, new_must_count: must.reduce((count, change) => count + change.count, 0),
    stability: {inputs_unchanged: inputsUnchanged(before, after), before, after},
    resources: resource,
    limitations: ['Exact canonical row-multiset and relation-set accounting only.',
      'No physical CMT occurrence identity or semantic one-to-many refinement proof.',
      'No soundness, completeness, stage3, or stage4 conclusion.'],
  };
}

async function main(argv) {
  const control = argv[0] && argv[0].match(/^--test-control=(pass|assertion|setup)$/);
  if (argv.length === 1 && control) {
    if (control[1] === 'assertion') throw new assert.AssertionError({message: 'injected assertion'});
    if (control[1] === 'setup') throw new SetupError('injected setup');
    return;
  }
  if (argv.length !== 0) throw new SetupError('usage: check-tezos.js');
  const oldRows = validateFrozen();
  const baselineBefore = frozenByteState();
  buildCurrentProducer();
  const before = localSourceState();
  assert.equal(before.tezos_revision, '1727d7e192f2374edda7ad7adceef6f4ec51f71a', 'fixed410 Tezos revision');
  const manifest = readStage2Manifest();
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'arch-index-cfa-check3-'));
  let report, failure = null, assertionFailure = null;
  try {
    const selection = makeSelection(temporary, manifest);
    const db = path.join(temporary, 'current.db');
    const copied = copyCurrentInputs(temporary, before);
    const resource = await produceMeasured(copied.producer, copied.schema, db, selection);
    resource.executed_producer_sha256 = fileSha256(copied.producer);
    resource.executed_schema_sha256 = fileSha256(copied.schema);
    const snapshot = snapshotDatabase(db, {expectedArtifactSuffixes: manifest.destinationSuffixes});
    const baselineAfter = frozenByteState();
    try { readStage2Manifest(); }
    catch (error) { throw new assert.AssertionError({message: `selected CMT/manifest drift: ${error.message}`}); }
    const after = localSourceState();
    report = measurementReport(oldRows, snapshot, before, after, manifest, resource);
    report.stability.baseline_unchanged = equalState(baselineBefore, baselineAfter);
    const assertionMessages = [];
    if (!report.stability.inputs_unchanged) assertionMessages.push('producer, schema, source or selected inputs changed during measurement');
    if (!report.stability.baseline_unchanged) assertionMessages.push('frozen stage1 artifacts changed during measurement');
    if (report.relations.losses.length) assertionMessages.push(`existing relation losses: ${report.relations.losses.length}`);
    if (report.new_must_count) assertionMessages.push(`new MUST rows: ${report.new_must_count}`);
    report.ok = assertionMessages.length === 0;
    report.assertions = assertionMessages;
    if (assertionMessages.length) assertionFailure = new assert.AssertionError({message: assertionMessages.join('; ')});
  } catch (error) {
    failure = error;
  } finally {
    try { fs.rmSync(temporary, {recursive: true, force: true}); }
    catch (error) { failure = new SetupError(`temporary cleanup failed: ${error.message}`); }
  }
  if (failure) throw failure;
  const reportDirectory = path.join(ROOT, 'improvement/2026-09-15-ocaml-cfa');
  const reportFile = path.join(reportDirectory, `check3-${Date.now()}-${process.pid}.json`);
  try {
    fs.mkdirSync(reportDirectory, {recursive: true});
    report.report_path = reportFile;
    fs.writeFileSync(reportFile, `${JSON.stringify(report, null, 2)}\n`);
  } catch (error) { throw new SetupError(`report write failed: ${error.message}`); }
  process.stdout.write(`${JSON.stringify(report)}\n`);
  if (assertionFailure) throw assertionFailure;
}

module.exports = {SetupError, exitCode, multisetDelta, relationDelta, sliceRelationCounts, newMustRows,
  measurementReport, validateFrozen};

if (require.main === module) (async () => {
  try { await main(process.argv.slice(2)); }
  catch (error) {
    process.stderr.write(`${error instanceof assert.AssertionError ? 'CHECK3_ASSERTION' : 'CHECK3_SETUP'}: ${error.message}\n`);
    process.exitCode = exitCode(error);
  }
})();
