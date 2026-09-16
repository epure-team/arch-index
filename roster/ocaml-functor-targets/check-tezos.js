#!/usr/bin/env node
'use strict';

const assert = require('node:assert/strict');
const cp = require('node:child_process');
const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {DatabaseSync} = require('node:sqlite');
const baseline = require('../tezos-residual-targets/baseline.js');
const comparison = require('../tezos-call-resolution/comparison.js');

const root = path.resolve(__dirname, '../..');
const args = process.argv.slice(2);
const frozenDirectory = path.join(root,
  'improvement/2026-09-16-ocaml-functor-targets/stage3-baseline');
const frozen = Object.freeze({
  archRevision: '0eb588720e6fc564e291280e376ed7678484dfcf',
  tezosRevision: '1727d7e192f2374edda7ad7adceef6f4ec51f71a',
  selected: 410,
  manifestSha256: '9e38880a52f855c58081b1a171af5879058cbaa2697aaa5694827cbd16f8ecd1',
  producerSha256: 'cae67d6906ddd595c3f3379eb70c0bd39e5338357451a55c3ee78015b9d8bbe4',
  schemaSha256: '1dd2d909e1feb2582e8a13f717ef165b7be9b73b908f73f47983920bded580d0',
  databaseSha256: '0961802f32ef152c1705ce3ad00c1ad830ed9fb62bb74544b34a49973453632e',
  rows: 45290,
  canonicalSha256: 'e1eca57522d24cbd62753bf6a490d650e1ca17d0de4f0d4e760949f5e4261bf2',
  relations: Object.freeze({irmin: 4921, protocol: 12441}),
});
const maxBuffer = 64 * 1024 * 1024;
class SetupError extends Error {}
const exitCode = error => error instanceof assert.AssertionError ? 1 : 2;
const sha256 = value => crypto.createHash('sha256').update(value).digest('hex');
const fileSha256 = file => sha256(fs.readFileSync(file));

function run(command, commandArgs, options = {}) {
  const result = cp.spawnSync(command, commandArgs, {
    cwd: root, encoding: 'utf8', timeout: 240000, maxBuffer, ...options,
  });
  if (result.error) throw new SetupError(`${command}: ${result.error.message}`);
  if (result.signal || result.status !== 0) {
    const detail = (result.stderr || result.stdout || '').trim();
    throw new SetupError(`${command} exited ${result.status ?? result.signal}${detail ? `: ${detail}` : ''}`);
  }
  return result.stdout;
}

function sourceState() {
  const bytes = (command, commandArgs, cwd) => {
    const result = cp.spawnSync(command, commandArgs, {cwd, encoding: null, maxBuffer});
    if (result.error || result.status !== 0) throw new SetupError(`${command} cannot capture source state`);
    return result.stdout;
  };
  return {
    arch_revision: run('git', ['rev-parse', 'HEAD']).trim(),
    tracked_diff_sha256: sha256(bytes('git', ['diff', '--binary', '--no-ext-diff', 'HEAD'], root)),
    tezos_revision: run('git', ['rev-parse', 'HEAD'], {cwd: baseline.TEZOS}).trim(),
    tezos_status_sha256: sha256(bytes('git', ['status', '--porcelain=v1', '--untracked-files=all'], baseline.TEZOS)),
    producer_sha256: fileSha256(baseline.CURRENT_PRODUCER),
    schema_sha256: fileSha256(baseline.CURRENT_SCHEMA),
  };
}

function sameState(left, right) {
  return Object.keys(left).every(key => left[key] === right[key]);
}

function relationKey(row) {
  return row.edge_form === 'value_alias' || row.target === null ? null :
    JSON.stringify([row.caller_path, row.caller, row.call_site, row.target_path, row.target]);
}

function relationSet(rows) {
  return new Set(rows.map(relationKey).filter(value => value !== null));
}

function relationChanges(before, after) {
  const oldSet = relationSet(before), newSet = relationSet(after);
  const subtract = (left, right) => [...left].filter(key => !right.has(key)).sort();
  return {losses: subtract(oldSet, newSet), gains: subtract(newSet, oldSet)};
}

function counted(rows) {
  const result = new Map();
  for (const row of rows) {
    const key = comparison.canonicalStrings([row])[0];
    result.set(key, (result.get(key) || 0) + 1);
  }
  return result;
}

function rowChanges(before, after) {
  const oldRows = counted(before), newRows = counted(after);
  const subtract = (left, right) => [...left].sort().flatMap(([key, count]) => {
    const difference = count - (right.get(key) || 0);
    return difference > 0 ? [{row: JSON.parse(key), count: difference}] : [];
  });
  return {removed: subtract(oldRows, newRows), added: subtract(newRows, oldRows)};
}

function sliceCounts(keys) {
  const result = {irmin: 0, protocol: 0, other: 0};
  for (const key of keys) {
    const [callerPath] = JSON.parse(key);
    if (callerPath.startsWith('irmin/')) result.irmin++;
    else if (callerPath.startsWith('src/proto_alpha/')) result.protocol++;
    else result.other++;
  }
  return result;
}

function validateFrozen(manifest) {
  const files = {
    db: path.join(frozenDirectory, 'baseline.db'),
    producer: path.join(frozenDirectory, 'producer.exe'),
    schema: path.join(frozenDirectory, 'architecture-schema.sql'),
  };
  for (const [name, file] of Object.entries(files))
    if (!fs.existsSync(file) || !fs.statSync(file).isFile()) throw new SetupError(`missing frozen Stage-3 ${name}: ${file}`);
  assert.equal(fileSha256(files.db), frozen.databaseSha256, 'frozen Stage-3 database hash');
  assert.equal(fileSha256(files.producer), frozen.producerSha256, 'frozen Stage-3 producer hash');
  assert.equal(fileSha256(files.schema), frozen.schemaSha256, 'frozen Stage-3 schema hash');
  const snapshot = comparison.snapshotDatabase(files.db,
    {expectedArtifactSuffixes: manifest.destinationSuffixes});
  assert.equal(snapshot.row_count, frozen.rows, 'frozen Stage-3 row count');
  assert.equal(snapshot.digest, frozen.canonicalSha256, 'frozen Stage-3 canonical digest');
  assert.deepEqual(baseline.relationMetrics(snapshot.rows), frozen.relations,
    'frozen Stage-3 slice relation counts');
  return {files, snapshot};
}

function validateWitnesses(dbPath) {
  const db = new DatabaseSync(dbPath, {readOnly: true});
  try {
    const scalar = (sql, ...params) => Number(Object.values(db.prepare(sql).get(...params))[0]);
    const marker = key => db.prepare('SELECT value FROM comment_db_meta WHERE key=?').get(key)?.value;
    for (const table of ['functor_target_inputs', 'functor_target_witnesses'])
      if (!db.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name=?").get(table))
        throw new SetupError(`candidate database lacks ${table}`);
    assert.equal(marker('functor_target_contract'), 'v1', 'target contract marker');
    assert.equal(scalar('SELECT count(*) FROM functor_target_inputs'), frozen.selected,
      'target input inventory');
    assert.equal(scalar("SELECT count(*) FROM functor_target_inputs WHERE outcome='collected'"),
      frozen.selected, 'collected target input inventory');
    const expected = scalar('SELECT coalesce(sum(expected_witnesses),0) FROM functor_target_inputs');
    const witnessCount = scalar('SELECT count(*) FROM functor_target_witnesses');
    assert.equal(witnessCount, expected, 'expected/stored target witness count');
    const rows = db.prepare(`SELECT w.producer_run_id,w.artifact,w.application_ordinal,
      w.declaration_key,w.formal_position,w.formal_key,w.actual_root_key,w.actual_path,
      w.member_path,w.caller_name,w.call_location,w.occurrence_ordinal,
      cm.path caller_path,cf.name caller,c.call_site,tm.path target_path,tf.name target,
      c.kind,c.edge_form,c.top_reason,c.top_anchor,b.status,b.formal_position binding_position,
      b.actual_root_key binding_actual_root,
      d.formals,c.producer_run_id call_run,tf.producer_run_id target_run,
      EXISTS(SELECT 1 FROM calls top WHERE top.caller_id=c.caller_id
        AND top.call_site IS c.call_site AND top.kind='MAY_TOP'
        AND top.top_reason='module_param') retained_top
      FROM functor_target_witnesses w
      JOIN functor_bindings b ON b.producer_run_id=w.producer_run_id
        AND b.artifact=w.artifact AND b.ordinal=w.application_ordinal
      JOIN functor_declarations d ON d.producer_run_id=w.producer_run_id
        AND d.artifact=w.artifact AND d.declaration_key=w.declaration_key
      JOIN calls c ON c.id=w.candidate_call_id
      JOIN functions cf ON cf.id=c.caller_id JOIN modules cm ON cm.id=cf.module_id
      JOIN functions tf ON tf.id=w.target_function_id AND tf.id=c.callee_id
      JOIN modules tm ON tm.id=tf.module_id ORDER BY w.artifact,w.application_ordinal,
        w.occurrence_ordinal,w.target_function_id`).all();
    assert.equal(rows.length, witnessCount, 'complete witness identity joins');
    const witnessed = new Map();
    for (const row of rows) {
      assert.equal(row.status, 'matched', 'witness binding status');
      assert.equal(Number(row.binding_position), Number(row.formal_position), 'witness formal position');
      assert.equal(row.binding_actual_root, row.actual_root_key, 'witness actual root');
      assert.equal(row.kind, 'MAY_ENUMERATED', 'witness candidate kind');
      assert.equal(Number(row.retained_top), 1, 'independent module-parameter TOP');
      for (const [name, value] of [['actual_path', row.actual_path], ['member_path', row.member_path]]) {
        let parsed;
        try { parsed = JSON.parse(value); } catch (_) { parsed = null; }
        assert(Array.isArray(parsed) && parsed.length > 0 && parsed.every(item => typeof item === 'string' && item),
          `${name} is a nonempty string array`);
      }
      let location;
      try { location = JSON.parse(row.call_location); } catch (_) { location = null; }
      assert(location && typeof location === 'object' && !Array.isArray(location), 'witness call location JSON');
      const formals = JSON.parse(row.formals);
      assert.equal(formals[Number(row.formal_position) - 1]?.binder_key, row.formal_key,
        'declaration contains witness formal at the authenticated slot');
      const key = JSON.stringify([row.caller_path, row.caller, row.call_site,
        row.target_path, row.target]);
      const ids = witnessed.get(key) || [];
      const artifactParts = row.artifact.split(/[\\/]/);
      const artifact = artifactParts.slice(-2).join('/');
      ids.push([artifact, Number(row.application_ordinal), Number(row.occurrence_ordinal)]);
      witnessed.set(key, ids);
    }
    return {witnessCount, expectedWitnesses: expected, witnessed};
  } finally { db.close(); }
}

function controlled(mode) {
  if (mode === 'pass') return;
  if (mode === 'assertion') throw new assert.AssertionError({message: 'injected Tezos assertion'});
  throw new SetupError('injected Tezos setup failure');
}

async function main() {
  const control = args[0]?.match(/^--test-control=(pass|assertion|setup)$/);
  if (args.length === 1 && control) return controlled(control[1]);
  if (args.length) throw new SetupError('usage: check-tezos.js [--test-control=pass|assertion|setup]');

  const manifest = baseline.readManifest({expected: {
    selected: frozen.selected, manifestSha256: frozen.manifestSha256,
  }});
  assert.equal(run('git', ['rev-parse', 'HEAD'], {cwd: baseline.TEZOS}).trim(),
    frozen.tezosRevision, 'fixed410 Tezos revision');
  const old = validateFrozen(manifest);
  run('opam', ['exec', '--', 'dune', 'build', '--root=.',
    'bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe']);
  const before = sourceState();
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'arch-index-functor-targets-check3-'));
  let report;
  try {
    const selection = baseline.makeSelection(temporary, manifest);
    const replayDb = path.join(temporary, 'stage3-replay.db');
    baseline.produce(old.files.producer, old.files.schema, replayDb, selection);
    const replay = comparison.snapshotDatabase(replayDb,
      {expectedArtifactSuffixes: manifest.destinationSuffixes});
    assert.equal(replay.digest, frozen.canonicalSha256, 'frozen Stage-3 replay digest');

    const producer = path.join(temporary, 'candidate-producer.exe');
    const schema = path.join(temporary, 'candidate-schema.sql');
    fs.copyFileSync(baseline.CURRENT_PRODUCER, producer);
    fs.copyFileSync(baseline.CURRENT_SCHEMA, schema);
    assert.equal(fileSha256(producer), before.producer_sha256, 'copied candidate producer');
    assert.equal(fileSha256(schema), before.schema_sha256, 'copied candidate schema');
    const candidateDb = path.join(temporary, 'candidate.db');
    const started = process.hrtime.bigint();
    baseline.produce(producer, schema, candidateDb, selection);
    const wallMs = Number(process.hrtime.bigint() - started) / 1e6;
    const current = comparison.snapshotDatabase(candidateDb,
      {expectedArtifactSuffixes: manifest.destinationSuffixes});
    const evidence = validateWitnesses(candidateDb);
    const relations = relationChanges(old.snapshot.rows, current.rows);
    const rows = rowChanges(old.snapshot.rows, current.rows);
    const addedMust = rows.added.filter(change => change.row.kind === 'MUST');
    const missingWitness = relations.gains.filter(key => !evidence.witnessed.has(key));
    assert.equal(relations.losses.length, 0, 'Stage-3 resolved relation losses');
    assert.equal(addedMust.length, 0, 'new or upgraded MUST rows');
    assert(relations.gains.length > 0, 'at least one witnessed Irmin/protocol gain');
    assert.equal(missingWitness.length, 0, 'candidate-only relations without an exact witness');
    const gainSlices = sliceCounts(relations.gains);
    assert(gainSlices.irmin + gainSlices.protocol > 0,
      'at least one witnessed gain belongs to Irmin or protocol');
    const after = sourceState();
    assert(sameState(before, after), 'producer/schema/source inputs remained stable');
    report = {
      check: 'CHECK3', ok: true, semantic_status: 'attributed_supported_subset',
      frozen_stage3: {arch_revision: frozen.archRevision, tezos_revision: frozen.tezosRevision,
        selected: frozen.selected, rows: frozen.rows, canonical_sha256: frozen.canonicalSha256,
        producer_sha256: frozen.producerSha256, schema_sha256: frozen.schemaSha256,
        database_sha256: frozen.databaseSha256, relations: frozen.relations},
      candidate: {rows: current.row_count, canonical_sha256: current.digest,
        producer_sha256: before.producer_sha256, schema_sha256: before.schema_sha256},
      rows: {added_count: rows.added.reduce((sum, item) => sum + item.count, 0),
        removed_count: rows.removed.reduce((sum, item) => sum + item.count, 0),
        added: rows.added, removed: rows.removed},
      relations: {gains: relations.gains.map(key => ({relation: JSON.parse(key),
          witnesses: evidence.witnessed.get(key)})), losses: [], gain_slices: gainSlices},
      witnesses: {stored: evidence.witnessCount, expected: evidence.expectedWitnesses,
        distinct_relations: evidence.witnessed.size},
      resources: {producer_wall_ms: wallMs, max_rss_kib: null,
        rss_observation: 'not sampled; no performance bound claimed'},
      stability: {inputs_unchanged: true, before, after},
      limitations: [
        'No whole-program or closed-world guarantee; the independent module-parameter TOP is retained.',
        'No completeness guarantee: Path.Papply, persistent/cross-unit actuals, unpack and Shapes/UID are outside this stage.',
        'No performance bound; resource values are observations only.',
      ],
    };
  } finally {
    if (path.dirname(temporary) !== os.tmpdir() ||
        !path.basename(temporary).startsWith('arch-index-functor-targets-check3-'))
      throw new SetupError('unsafe CHECK3 cleanup path');
    fs.rmSync(temporary, {recursive: true, force: true});
  }
  const reportDirectory = path.join(root, 'improvement/2026-09-16-ocaml-functor-targets');
  fs.mkdirSync(reportDirectory, {recursive: true});
  const reportPath = path.join(reportDirectory, `check3-${Date.now()}-${process.pid}.json`);
  report.report_path = reportPath;
  fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`);
  process.stdout.write(`${JSON.stringify(report)}\n`);
}

(async () => {
  try { await main(); }
  catch (error) {
    process.stderr.write(`${error instanceof assert.AssertionError ? 'CHECK3_ASSERTION' : 'CHECK3_SETUP'}: ${error.message}\n`);
    process.exitCode = exitCode(error);
  }
})();
