#!/usr/bin/env node
'use strict';

/* Independent real-producer regression for binding-side RAISE(ROLLBACK).
 * This deliberately imports no project helper: review overlays this one file
 * onto a pre-fix git archive. */
const assert = require('node:assert/strict');
const cp = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const root = path.resolve(__dirname, '../..');
const producer = path.join(root,
  '_build/default/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe');
const schema = path.join(root, 'architecture-schema.sql');
const cap = 32 * 1024 * 1024;

class InfrastructureError extends Error {}

function run(command, args, options = {}) {
  const result = cp.spawnSync(command, args, {
    cwd: root, encoding: 'utf8', timeout: 180000, maxBuffer: cap,
    env: process.env, ...options
  });
  if (result.error || result.signal || result.status === null) {
    throw new InfrastructureError(`${command}: ${result.error || result.signal}`);
  }
  return result;
}

function requireOk(command, args, options = {}) {
  const result = run(command, args, options);
  if (result.status !== 0) {
    throw new InfrastructureError(
      `${command} exited ${result.status}\n${result.stdout}${result.stderr}`);
  }
  return result.stdout;
}

function sql(db, statement) {
  return requireOk('sqlite3', [db], {input: statement});
}

function rows(db, statement) {
  const result = run('sqlite3', ['-json', db, statement]);
  if (result.status !== 0) {
    throw new InfrastructureError(`sqlite3 exited ${result.status}: ${result.stderr}`);
  }
  try {
    return result.stdout.trim() ? JSON.parse(result.stdout) : [];
  } catch (error) {
    throw new InfrastructureError(`invalid sqlite3 JSON: ${error.message}`);
  }
}

function quoteIdentifier(value) {
  return `"${String(value).replaceAll('"', '""')}"`;
}

function write(file, contents) {
  fs.writeFileSync(file, contents);
}

function buildProducer() {
  requireOk('dune', ['build', '--root', root,
    'bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe']);
  if (!fs.existsSync(producer)) {
    throw new InfrastructureError(`exact-checkout producer is missing: ${producer}`);
  }
}

function compileFixtures(dir, count) {
  const buildDir = path.join(dir, '_build/default');
  fs.mkdirSync(buildDir, {recursive: true});
  for (let index = 1; index <= count; index++) {
    const stem = `rollback_fixture_${index}`;
    write(path.join(dir, `${stem}.ml`), `
module type S = sig val value : int end
module F (X : S) = X
module A = struct let value = ${index * 2} end
module B = struct let value = ${index * 2 + 1} end
module First = F (A)
module Second = F (B)
`);
    requireOk('ocamlc', ['-bin-annot', '-c', `${stem}.ml`,
      '-o', `_build/default/${stem}.cmo`], {cwd: dir});
  }
  return buildDir;
}

function index(buildDir, db, schemaPath) {
  return run(producer, ['--build-dir', buildDir, '--db-path', db,
    '--schema-path', schemaPath]);
}

function tableSnapshot(db, table) {
  const columns = rows(db, `PRAGMA table_info(${quoteIdentifier(table)})`)
    .map(column => column.name);
  if (columns.length === 0) {
    throw new InfrastructureError(`cannot inspect table ${table}`);
  }
  const projection = columns.map(column => {
    const name = quoteIdentifier(column);
    // Producer invocation times are inherently different across independent DBs.
    return ['created_at', 'last_analyzed'].includes(column)
      ? `CASE WHEN ${name} IS NULL THEN NULL ELSE '<timestamp>' END AS ${name}`
      : name;
  }).join(',');
  const order = columns.map(quoteIdentifier).join(',');
  return rows(db, `SELECT ${projection} FROM ${quoteIdentifier(table)} ORDER BY ${order}`);
}

function oldSemanticSnapshot(db) {
  const excluded = new Set([
    'functor_binding_inputs', 'functor_declarations', 'functor_bindings'
  ]);
  const tables = rows(db, `SELECT name FROM sqlite_schema
    WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name`)
    .map(row => row.name).filter(name => !excluded.has(name));
  const result = {};
  for (const table of tables) {
    if (table === 'comment_db_meta') {
      result[table] = rows(db, `SELECT key,value FROM comment_db_meta
        WHERE key <> 'functor_binding_contract' ORDER BY key,value`);
    } else {
      result[table] = tableSnapshot(db, table);
    }
  }
  return result;
}

function bindingSnapshot(db) {
  return {
    inputs: rows(db, `SELECT producer_run_id,artifact,outcome,
        expected_declarations,expected_bindings
      FROM functor_binding_inputs ORDER BY artifact`),
    declarations: rows(db, `SELECT producer_run_id,artifact,declaration_key,name,
        location,formals
      FROM functor_declarations ORDER BY artifact,declaration_key`),
    bindings: rows(db, `SELECT producer_run_id,artifact,ordinal,status,reason,
        declaration_key,formal_position,head_application_ordinal,actual_root_key
      FROM functor_bindings ORDER BY artifact,ordinal`)
  };
}

function artifactBindingSnapshot(snapshot, artifact) {
  return {
    inputs: snapshot.inputs.filter(row => row.artifact === artifact),
    declarations: snapshot.declarations.filter(row => row.artifact === artifact),
    bindings: snapshot.bindings.filter(row => row.artifact === artifact)
  };
}

function assertHealthy(db, inputCount) {
  const catalogue = rows(db, `SELECT artifact,expected_applications
    FROM functor_catalogue_inputs WHERE outcome='collected' ORDER BY artifact`);
  assert.equal(catalogue.length, inputCount, 'healthy control did not collect every owned CMT');
  assert.ok(catalogue.every(row => row.expected_applications === 2),
    `healthy application premise differs: ${JSON.stringify(catalogue)}`);
  const bindings = rows(db, `SELECT artifact,count(*) AS n FROM functor_bindings
    GROUP BY artifact ORDER BY artifact`);
  assert.equal(bindings.length, inputCount, 'healthy control lacks an artifact binding set');
  assert.ok(bindings.every(row => row.n === 2),
    `healthy binding premise differs: ${JSON.stringify(bindings)}`);
  const inputs = rows(db, `SELECT artifact,outcome,expected_declarations,expected_bindings
    FROM functor_binding_inputs ORDER BY artifact`);
  assert.equal(inputs.length, inputCount);
  assert.ok(inputs.every(row => row.outcome === 'collected' &&
    row.expected_declarations === 1 && row.expected_bindings === 2),
  `healthy binding-input premise differs: ${JSON.stringify(inputs)}`);
  assert.deepEqual(rows(db, `SELECT value FROM comment_db_meta
    WHERE key='functor_catalogue_contract'`), [{value: 'v1'}]);
  assert.deepEqual(rows(db, `SELECT value FROM comment_db_meta
    WHERE key='functor_binding_contract'`), [{value: 'v1'}]);
}

function assertFault(db, healthyOld, healthyBindings, inputCount) {
  assert.deepEqual(oldSemanticSnapshot(db), healthyOld,
    'binding ROLLBACK changed old graph or catalogue semantics');
  const inputs = rows(db, `SELECT artifact,outcome,expected_declarations,expected_bindings
    FROM functor_binding_inputs ORDER BY artifact`);
  assert.equal(inputs.length, inputCount, 'fault run did not account for every input');
  const failed = inputs.filter(row => row.outcome === 'collection_failed');
  const collected = inputs.filter(row => row.outcome === 'collected');
  assert.equal(failed.length, 1, `expected exactly one failed input: ${JSON.stringify(inputs)}`);
  assert.deepEqual([failed[0].expected_declarations, failed[0].expected_bindings], [0, 0]);
  assert.equal(collected.length, inputCount - 1);
  for (const input of collected) {
    assert.equal(input.expected_declarations, 1);
    assert.equal(input.expected_bindings, 2);
  }
  const faultBindings = bindingSnapshot(db);
  for (const input of collected) {
    assert.deepEqual(
      artifactBindingSnapshot(faultBindings, input.artifact),
      artifactBindingSnapshot(healthyBindings, input.artifact),
      `${input.artifact}: successful binding rows changed under another input's fault`);
  }
  const entityCounts = rows(db, `SELECT i.artifact,i.outcome,
      (SELECT count(*) FROM functor_declarations d WHERE d.producer_run_id=i.producer_run_id
        AND d.artifact=i.artifact) AS declarations,
      (SELECT count(*) FROM functor_bindings b WHERE b.producer_run_id=i.producer_run_id
        AND b.artifact=i.artifact) AS bindings
    FROM functor_binding_inputs i ORDER BY i.artifact`);
  const failedEntities = entityCounts.find(row => row.artifact === failed[0].artifact);
  const healthyFailedInput = artifactBindingSnapshot(
    healthyBindings, failed[0].artifact).inputs;
  assert.equal(healthyFailedInput.length, 1,
    'healthy control lacked the artifact selected for the injected fault');
  assert.deepEqual(
    artifactBindingSnapshot(faultBindings, failed[0].artifact).inputs,
    [{...healthyFailedInput[0], outcome: 'collection_failed',
      expected_declarations: 0, expected_bindings: 0}],
    'failed input row was not the exact zero-count failure record');
  assert.deepEqual([failedEntities.declarations, failedEntities.bindings], [0, 0],
    'failed input retained partial child entities');
  assert.deepEqual(
    artifactBindingSnapshot(faultBindings, failed[0].artifact).declarations, [],
    'failed input retained declaration rows');
  assert.deepEqual(
    artifactBindingSnapshot(faultBindings, failed[0].artifact).bindings, [],
    'failed input retained binding-result rows');
  assert.ok(entityCounts.filter(row => row.outcome === 'collected')
    .every(row => row.declarations === 1 && row.bindings === 2),
  `successful binding entities were not intact: ${JSON.stringify(entityCounts)}`);
  assert.equal(rows(db, `SELECT count(*) AS n FROM comment_db_meta
    WHERE key='functor_binding_contract'`)[0].n, 0, 'fault run retained binding marker');
  return {failed: failed[0].artifact, collected: collected.map(row => row.artifact)};
}

function assertSingleInjectedWarning(result) {
  const warnings = result.stderr.match(/injected binding global rollback/g) || [];
  assert.equal(warnings.length, 1,
    `expected one actual injected fault warning, got ${warnings.length}: ${result.stderr}`);
}

function main() {
  buildProducer();
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'arch-global-rollback-'));
  try {
    const baseSchema = fs.readFileSync(schema, 'utf8');
    const schemaWithFault = `${baseSchema}\n
CREATE TRIGGER binding_global_rollback BEFORE INSERT ON functor_bindings
WHEN NEW.ordinal=2
 AND EXISTS (SELECT 1 FROM functor_bindings b
             WHERE b.producer_run_id=NEW.producer_run_id
               AND b.artifact=NEW.artifact AND b.ordinal=1)
 AND (SELECT count(*) FROM functor_declarations d
      WHERE d.producer_run_id=NEW.producer_run_id
        AND d.artifact=NEW.artifact)=1
 AND (SELECT count(*) FROM functor_bindings b
      WHERE b.producer_run_id=NEW.producer_run_id
        AND b.artifact<>NEW.artifact)=2
 AND NOT EXISTS (SELECT 1 FROM functor_binding_inputs i
                 WHERE i.outcome='collection_failed')
BEGIN
  SELECT RAISE(ROLLBACK,'injected binding global rollback');
END;
`;

    // The required two-input control and fault reproduction are deliberately separate.
    const twoDir = path.join(dir, 'two');
    fs.mkdirSync(twoDir);
    const twoBuild = compileFixtures(twoDir, 2);
    const twoDb = path.join(dir, 'two.db');
    const twoSchema = path.join(dir, 'two-schema.sql');
    write(twoSchema, baseSchema);
    const healthyRun = index(twoBuild, twoDb, twoSchema);
    assert.equal(healthyRun.status, 0, healthyRun.stderr);
    assertHealthy(twoDb, 2);
    const healthyTwoOld = oldSemanticSnapshot(twoDb);
    const healthyTwoBindings = bindingSnapshot(twoDb);

    fs.rmSync(twoDb);
    write(twoSchema, schemaWithFault);
    const faultTwoRun = index(twoBuild, twoDb, twoSchema);
    assert.equal(faultTwoRun.status, 0,
      `fault producer must recover and exit 0: ${faultTwoRun.stderr}`);
    assertSingleInjectedWarning(faultTwoRun);
    const twoOutcome = assertFault(twoDb, healthyTwoOld, healthyTwoBindings, 2);
    assert.equal(twoOutcome.collected.length, 1,
      'two-input case did not preserve the binding input stored before the fault');

    // Separate continuation proof: one earlier success, one fault, then one later
    // success because the trigger suppresses itself only after the failed row exists.
    const threeDir = path.join(dir, 'three');
    fs.mkdirSync(threeDir);
    const threeBuild = compileFixtures(threeDir, 3);
    const threeDb = path.join(dir, 'three.db');
    const threeSchema = path.join(dir, 'three-schema.sql');
    write(threeSchema, baseSchema);
    const healthyThreeRun = index(threeBuild, threeDb, threeSchema);
    assert.equal(healthyThreeRun.status, 0, healthyThreeRun.stderr);
    assertHealthy(threeDb, 3);
    const healthyThreeOld = oldSemanticSnapshot(threeDb);
    const healthyThreeBindings = bindingSnapshot(threeDb);
    fs.rmSync(threeDb);
    write(threeSchema, schemaWithFault);
    const faultThreeRun = index(threeBuild, threeDb, threeSchema);
    assert.equal(faultThreeRun.status, 0,
      `continuation producer must recover and exit 0: ${faultThreeRun.stderr}`);
    assertSingleInjectedWarning(faultThreeRun);
    const threeOutcome = assertFault(
      threeDb, healthyThreeOld, healthyThreeBindings, 3);
    assert.equal(threeOutcome.collected.length, 2,
      'later input did not survive after the single injected fault');

    process.stdout.write(JSON.stringify({
      ok: true,
      two_input: {applications_per_input: 2, earlier_binding_input_preserved: true},
      continuation: {inputs: 3, failed: 1, collected: 2, later_input_preserved: true},
      trigger: 'ordinal_2_after_distinct_artifact_once',
      old_graph_and_catalogue_semantics: 'equal',
      binding_marker_after_fault: 'absent'
    }) + '\n');
  } finally {
    fs.rmSync(dir, {recursive: true, force: true});
  }
}

try {
  main();
} catch (error) {
  process.stderr.write(`${error.stack || error}\n`);
  process.exitCode = error instanceof assert.AssertionError ? 1 : 2;
}
