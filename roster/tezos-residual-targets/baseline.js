'use strict';

const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const cp = require('node:child_process');
const {
  ComparisonInputError,
  snapshotDatabase,
  compareSnapshots,
} = require('../tezos-call-resolution/comparison.js');

const ROOT = path.resolve(__dirname, '../..');
const TEZOS = '/home/mathias/dev/tezos/tezos';
const MANIFEST = path.join(ROOT, 'roster/functor-instance-resolution/tezos-irmin-candidate/manifest-410.tsv');
const CURRENT_PRODUCER = path.join(ROOT, '_build/default/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe');
const CURRENT_SCHEMA = path.join(ROOT, 'architecture-schema.sql');
const BASELINE_DIR = path.join(ROOT, 'improvement/2026-09-14-tezos-resolution/attempt2-baseline');
const ACTIVE_TASK = path.join(ROOT, 'briefs/ACTIVE_TASK');
const ACTIVE_MANIFEST = path.join(ROOT, 'briefs/tezos-residual-targets-manifest.txt');
const PURPOSE = 'tezos-residual-targets-pr105-frozen-predecessor';
const EXPECTED = Object.freeze({
  selected: 410,
  manifestSha256: '9e38880a52f855c58081b1a171af5879058cbaa2697aaa5694827cbd16f8ecd1',
  producerSha256: 'c953970a15b64d026f7b502ba5d61be537c3ab5b51e219435b4a3483d57764b8',
  schemaSha256: '1dd2d909e1feb2582e8a13f717ef165b7be9b73b908f73f47983920bded580d0',
  tezosRevision: '1727d7e192f2374edda7ad7adceef6f4ec51f71a',
  rows: 45052,
  digest: '90e76d6b40b2d7f108fcc25523f85de1cb533a98565a8a7d6d284c1654939d4b',
  relations: Object.freeze({irmin: 4772, protocol: 11615}),
});

const sha256 = value => crypto.createHash('sha256').update(value).digest('hex');
const fileSha256 = file => sha256(fs.readFileSync(file));
const fail = message => { throw new ComparisonInputError(message); };

function requireAbsoluteFile(file, label) {
  if (typeof file !== 'string' || !path.isAbsolute(file) || path.normalize(file) !== file)
    fail(`${label} path must be absolute and normalized`);
  if (!fs.existsSync(file) || !fs.statSync(file).isFile()) fail(`missing ${label}: ${file}`);
}

function run(command, args, cwd) {
  const result = cp.spawnSync(command, args, {cwd, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024});
  if (result.error) fail(`${command}: ${result.error.message}`);
  if (result.status !== 0) fail(`${command} exited ${result.status}\n${result.stdout || ''}\n${result.stderr || ''}`);
  return result.stdout;
}

function readManifest(options = {}) {
  const manifestFile = options.manifestFile || MANIFEST;
  const expected = options.expected || EXPECTED;
  requireAbsoluteFile(path.resolve(manifestFile), 'manifest');
  const raw = fs.readFileSync(manifestFile);
  if (sha256(raw) !== expected.manifestSha256) fail('fixed410 manifest digest mismatch');
  const records = raw.toString('utf8').split('\n').filter(line => line && !line.startsWith('#')).map(line => line.split('\t'));
  if (records.length !== expected.selected || records.some(record => record.length !== 3)) fail('fixed410 manifest is incomplete or malformed');
  const destinations = new Set();
  for (const [slice, digest, artifact] of records) {
    if (!/^[a-z0-9-]+$/.test(slice) || !/^[a-f0-9]{64}$/.test(digest) || !path.isAbsolute(artifact) || path.extname(artifact) !== '.cmt')
      fail('malformed fixed410 manifest record');
    requireAbsoluteFile(artifact, 'manifest artifact');
    if (fileSha256(artifact) !== digest) fail(`fixed410 input hash mismatch: ${artifact}`);
    const destination = `${slice}/${path.basename(artifact)}`;
    if (destinations.has(destination)) fail(`selection collision: ${destination}`);
    destinations.add(destination);
  }
  return {raw, records, destinationSuffixes: [...destinations].sort()};
}

function relationMetrics(rows) {
  const sets = {irmin: new Set(), protocol: new Set()};
  for (const row of rows) {
    if (row.edge_form === 'value_alias' || row.target === null) continue;
    const slice = row.caller_path.startsWith('irmin/') ? 'irmin' : row.caller_path.startsWith('src/proto_alpha/') ? 'protocol' : null;
    if (slice) sets[slice].add(JSON.stringify([row.caller_path, row.caller, row.call_site, row.target_path, row.target]));
  }
  return {irmin: sets.irmin.size, protocol: sets.protocol.size};
}

function validateSnapshot(snapshot, expected = EXPECTED) {
  if (snapshot.row_count !== expected.rows || snapshot.digest !== expected.digest)
    fail(`baseline canonical mismatch: ${snapshot.row_count}/${snapshot.digest}`);
  const relations = relationMetrics(snapshot.rows);
  if (relations.irmin !== expected.relations.irmin || relations.protocol !== expected.relations.protocol)
    fail(`baseline relation mismatch: ${relations.irmin}/${relations.protocol}`);
  return relations;
}

function sourceState() {
  const optionalFile = file => fs.existsSync(file)
    ? `present\0${fs.readFileSync(file, 'utf8')}`
    : 'absent\0';
  return {
    archRevision: run('git', ['rev-parse', 'HEAD'], ROOT).trim(),
    archStatus: run('git', ['status', '--porcelain=v1', '--untracked-files=all'], ROOT),
    tezosRevision: run('git', ['rev-parse', 'HEAD'], TEZOS).trim(),
    tezosStatus: run('git', ['status', '--porcelain=v1', '--untracked-files=all'], TEZOS),
    activeTask: optionalFile(ACTIVE_TASK),
    activeManifest: optionalFile(ACTIVE_MANIFEST),
  };
}

function validateActivePhase(state, {allowInactive = false} = {}) {
  // Review/QA run after roster-implement has released its slot. A foreign
  // active task is never accepted; absence alone is legitimate at those gates.
  if (allowInactive && state.activeTask === 'absent\0') return;
  if (state.activeTask !== 'present\0tezos-residual-targets\n'
    && state.activeTask !== 'present\0tezos-residual-targets')
    fail('ACTIVE_TASK is absent or does not select tezos-residual-targets');
  if (!state.activeManifest.startsWith('present\0')) fail('tezos-residual-targets active manifest is absent');
  for (const required of ['roster/tezos-residual-targets/', 'improvement/'])
    if (!state.activeManifest.includes(required)) fail(`active scope manifest lacks ${required}`);
}

function assertStateUnchanged(before, after) {
  for (const key of Object.keys(before)) if (before[key] !== after[key]) fail(`source snapshot changed during setup: ${key}`);
}

function validateProvenance(value, options = {}) {
  const expected = options.expected || EXPECTED;
  const directory = options.directory || BASELINE_DIR;
  if (!value || typeof value !== 'object' || Array.isArray(value)) fail('malformed provenance record');
  if (value.format_version !== 1 || value.purpose !== PURPOSE) fail('provenance format or purpose mismatch');
  const exactPaths = {
    db: path.join(directory, 'baseline.db'),
    producer: path.join(directory, 'producer.exe'),
    schema: path.join(directory, 'architecture-schema.sql'),
    manifest: MANIFEST,
    tezos_checkout: TEZOS,
  };
  for (const [key, wanted] of Object.entries(exactPaths)) {
    if (value[key] !== wanted || !path.isAbsolute(value[key])) fail(`provenance ${key} path mismatch`);
  }
  const pins = {
    selected: expected.selected, manifest_sha256: expected.manifestSha256,
    producer_sha256: expected.producerSha256, schema_sha256: expected.schemaSha256,
    tezos_revision: expected.tezosRevision, canonical_rows: expected.rows,
    canonical_sha256: expected.digest,
  };
  for (const [key, wanted] of Object.entries(pins)) if (value[key] !== wanted) fail(`provenance ${key} mismatch`);
  if (value.relations?.irmin !== expected.relations.irmin || value.relations?.protocol !== expected.relations.protocol)
    fail('provenance relation metrics mismatch');
  if (typeof value.arch_revision !== 'string' || !/^[a-f0-9]{40}$/.test(value.arch_revision)
    || typeof value.arch_status_sha256 !== 'string' || !/^[a-f0-9]{64}$/.test(value.arch_status_sha256)
    || typeof value.tezos_status_sha256 !== 'string' || !/^[a-f0-9]{64}$/.test(value.tezos_status_sha256)
    || typeof value.active_task_sha256 !== 'string' || !/^[a-f0-9]{64}$/.test(value.active_task_sha256)
    || typeof value.active_manifest_sha256 !== 'string' || !/^[a-f0-9]{64}$/.test(value.active_manifest_sha256)
    || value.source_status_unchanged !== true || value.input_hashes_unchanged !== true)
    fail('provenance source snapshot is malformed or incomplete');
  return value;
}

function loadFrozen(directory = BASELINE_DIR, options = {}) {
  const provenanceFile = path.join(directory, 'provenance.json');
  requireAbsoluteFile(provenanceFile, 'provenance');
  let provenance;
  try { provenance = JSON.parse(fs.readFileSync(provenanceFile, 'utf8')); }
  catch (error) { fail(`invalid provenance JSON: ${error.message}`); }
  validateProvenance(provenance, {...options, directory});
  for (const [key, digest] of [['producer', provenance.producer_sha256], ['schema', provenance.schema_sha256]]) {
    requireAbsoluteFile(provenance[key], `frozen ${key}`);
    if (fileSha256(provenance[key]) !== digest) fail(`frozen ${key} hash mismatch`);
  }
  requireAbsoluteFile(provenance.db, 'baseline database');
  return provenance;
}

function makeSelection(parent, manifestData) {
  const selection = path.join(parent, 'selection');
  fs.mkdirSync(selection);
  for (const [slice, , artifact] of manifestData.records) {
    const dir = path.join(selection, slice);
    fs.mkdirSync(dir, {recursive: true});
    fs.symlinkSync(artifact, path.join(dir, path.basename(artifact)));
  }
  return selection;
}

function produce(producer, schema, db, selection) {
  run(producer, ['--build-dir', selection, '--db-path', db, '--schema-path', schema], TEZOS);
}

function replayFrozen(provenance, manifestData, expected = EXPECTED) {
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'arch-index-attempt2-replay-'));
  try {
    const selection = makeSelection(temporary, manifestData);
    const db = path.join(temporary, 'replay.db');
    produce(provenance.producer, provenance.schema, db, selection);
    const snapshot = snapshotDatabase(db, {expectedArtifactSuffixes: manifestData.destinationSuffixes});
    validateSnapshot(snapshot, expected);
    const frozen = snapshotDatabase(provenance.db, {expectedArtifactSuffixes: manifestData.destinationSuffixes});
    validateSnapshot(frozen, expected);
    const comparison = compareSnapshots(frozen, snapshot);
    if (!comparison.ok || !comparison.neutral) fail('frozen producer replay is not canonical-multiset neutral');
    return snapshot;
  } finally {
    if (path.dirname(temporary) !== os.tmpdir() || !path.basename(temporary).startsWith('arch-index-attempt2-replay-'))
      fail('unsafe replay cleanup path');
    fs.rmSync(temporary, {recursive: true});
  }
}

module.exports = {
  ROOT, TEZOS, MANIFEST, CURRENT_PRODUCER, CURRENT_SCHEMA, BASELINE_DIR,
  ACTIVE_TASK, ACTIVE_MANIFEST, PURPOSE, EXPECTED,
  ComparisonInputError, sha256, fileSha256, readManifest, relationMetrics,
  validateSnapshot, sourceState, validateActivePhase, assertStateUnchanged, validateProvenance,
  loadFrozen, makeSelection, produce, replayFrozen,
};
