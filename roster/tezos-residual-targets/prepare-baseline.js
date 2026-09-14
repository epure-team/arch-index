#!/usr/bin/env node
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const {
  TEZOS, MANIFEST, CURRENT_PRODUCER, CURRENT_SCHEMA, BASELINE_DIR, PURPOSE, EXPECTED,
  ComparisonInputError, sha256, fileSha256, readManifest, validateSnapshot,
  sourceState, validateActivePhase, assertStateUnchanged, validateProvenance, loadFrozen, makeSelection, produce, replayFrozen,
} = require('./baseline.js');
const {snapshotDatabase} = require('../tezos-call-resolution/comparison.js');

function usage() { throw new ComparisonInputError('usage: prepare-baseline.js (--create | --check)'); }

function checkPinnedSource(state) {
  if (state.tezosRevision !== EXPECTED.tezosRevision) throw new ComparisonInputError('Tezos revision differs from the fixed corpus provenance');
  for (const [file, digest, label] of [[CURRENT_PRODUCER, EXPECTED.producerSha256, 'current producer'], [CURRENT_SCHEMA, EXPECTED.schemaSha256, 'current schema']]) {
    if (!fs.existsSync(file) || !fs.statSync(file).isFile()) throw new ComparisonInputError(`missing ${label}`);
    if (fileSha256(file) !== digest) throw new ComparisonInputError(`${label} hash mismatch`);
  }
}

function create() {
  if (fs.existsSync(BASELINE_DIR)) throw new ComparisonInputError(`refusing to overwrite baseline directory: ${BASELINE_DIR}`);
  const parent = path.dirname(BASELINE_DIR);
  fs.mkdirSync(parent, {recursive: true});
  const staging = path.join(parent, `.attempt2-baseline-${process.pid}-${Date.now()}`);
  if (fs.existsSync(staging)) throw new ComparisonInputError('baseline staging collision');
  const before = sourceState();
  validateActivePhase(before);
  checkPinnedSource(before);
  const manifest = readManifest();
  fs.mkdirSync(staging);
  try {
    const producer = path.join(staging, 'producer.exe');
    const schema = path.join(staging, 'architecture-schema.sql');
    const db = path.join(staging, 'baseline.db');
    fs.copyFileSync(CURRENT_PRODUCER, producer, fs.constants.COPYFILE_EXCL);
    fs.chmodSync(producer, fs.statSync(CURRENT_PRODUCER).mode & 0o777);
    fs.copyFileSync(CURRENT_SCHEMA, schema, fs.constants.COPYFILE_EXCL);
    const selection = makeSelection(staging, manifest);
    produce(producer, schema, db, selection);
    fs.rmSync(selection, {recursive: true});
    const snapshot = snapshotDatabase(db, {expectedArtifactSuffixes: manifest.destinationSuffixes});
    const relations = validateSnapshot(snapshot);
    const finalProducer = path.join(BASELINE_DIR, 'producer.exe');
    const finalSchema = path.join(BASELINE_DIR, 'architecture-schema.sql');
    const finalDb = path.join(BASELINE_DIR, 'baseline.db');
    const provenance = {
      format_version: 1, purpose: PURPOSE,
      db: finalDb, producer: finalProducer, schema: finalSchema, manifest: MANIFEST,
      tezos_checkout: TEZOS, selected: EXPECTED.selected,
      manifest_sha256: EXPECTED.manifestSha256, producer_sha256: EXPECTED.producerSha256,
      schema_sha256: EXPECTED.schemaSha256, tezos_revision: EXPECTED.tezosRevision,
      canonical_rows: EXPECTED.rows, canonical_sha256: EXPECTED.digest, relations,
      arch_revision: before.archRevision, arch_status_sha256: sha256(before.archStatus),
      tezos_status_sha256: sha256(before.tezosStatus), source_status_unchanged: true,
      active_task_sha256: sha256(before.activeTask), active_manifest_sha256: sha256(before.activeManifest),
      input_hashes_unchanged: false,
    };
    if (fileSha256(producer) !== EXPECTED.producerSha256 || fileSha256(schema) !== EXPECTED.schemaSha256)
      throw new ComparisonInputError('frozen copy hash mismatch');
    // Prove the copied producer neutral while the directory is still staging.
    // No provenance marker is written until this succeeds, so interrupted or
    // failed setup cannot be mistaken for a usable baseline.
    replayFrozen({...provenance, db, producer, schema}, readManifest());
    const manifestAfter = readManifest();
    if (!manifest.raw.equals(manifestAfter.raw)) throw new ComparisonInputError('manifest changed during baseline production');
    assertStateUnchanged(before, sourceState());
    provenance.input_hashes_unchanged = true;
    validateProvenance(provenance);
    fs.writeFileSync(path.join(staging, 'provenance.json'), JSON.stringify(provenance, null, 2) + '\n', {flag: 'wx'});
    fs.renameSync(staging, BASELINE_DIR);
    process.stdout.write(`PASS created frozen attempt2 baseline (${EXPECTED.rows} rows; irmin ${relations.irmin}; protocol ${relations.protocol})\n`);
  } catch (error) {
    if (fs.existsSync(staging)) fs.rmSync(staging, {recursive: true});
    throw error;
  }
}

function check() {
  const before = sourceState();
  validateActivePhase(before, {allowInactive: true});
  if (before.tezosRevision !== EXPECTED.tezosRevision) throw new ComparisonInputError('Tezos revision differs from the fixed corpus provenance');
  const manifest = readManifest();
  const provenance = loadFrozen();
  const snapshot = snapshotDatabase(provenance.db, {expectedArtifactSuffixes: manifest.destinationSuffixes});
  const relations = validateSnapshot(snapshot);
  replayFrozen(provenance, manifest);
  const manifestAfter = readManifest();
  if (!manifest.raw.equals(manifestAfter.raw)) throw new ComparisonInputError('manifest changed during frozen replay');
  assertStateUnchanged(before, sourceState());
  if (sha256(before.tezosStatus) !== provenance.tezos_status_sha256)
    throw new ComparisonInputError('live Tezos status differs from frozen provenance');
  // The recorded task/manifest describe creation, not a permanent phase lock:
  // roster releases ACTIVE_TASK after implementation. The before/after check
  // above still rejects any concurrent phase or scope mutation during replay.
  process.stdout.write(`PASS frozen attempt2 baseline replay (${snapshot.row_count} rows; irmin ${relations.irmin}; protocol ${relations.protocol})\n`);
}

try {
  const args = process.argv.slice(2);
  if (args.length !== 1 || !['--create', '--check'].includes(args[0])) usage();
  if (args[0] === '--create') create(); else check();
} catch (error) {
  process.stderr.write(`SETUP FAILED: ${error.stack || error}\n`);
  process.exitCode = error instanceof ComparisonInputError ? 2 : 3;
}
