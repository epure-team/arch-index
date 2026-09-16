#!/usr/bin/env node
'use strict';

const assert = require('node:assert/strict');
const cp = require('node:child_process');
const path = require('node:path');
const {SetupError, exitCode, measurementReport, multisetDelta, relationDelta, sliceRelationCounts, newMustRows} = require('./check-tezos.js');

function row(overrides = {}) {
  return {
    caller_path: 'irmin/lib_irmin/a.ml', caller: 'caller', call_site: 'a.ml:1',
    target_path: 'irmin/lib_irmin/a.ml', target: 'target', callee_name: 'target',
    kind: 'MAY_ENUMERATED', edge_form: null, top_reason: null, top_anchor: null,
    ...overrides,
  };
}

const a = row();
const b = row({call_site: 'a.ml:2', target: 'old', callee_name: 'old'});
const c = row({call_site: 'a.ml:3', target: 'new', callee_name: 'new'});
const sameRelationDifferentDisplay = row({callee_name: 'display-only'});
const rows = multisetDelta([a, a, b], [a, c, c]);
assert.deepEqual(rows.removed.map(change => [change.row.call_site, change.count]), [['a.ml:1', 1], ['a.ml:2', 1]]);
assert.deepEqual(rows.added.map(change => [change.row.call_site, change.count]), [['a.ml:3', 2]]);

const relations = relationDelta([a, b], [sameRelationDifferentDisplay, c]);
assert.equal(relations.losses.length, 1, 'old distinct relation is retained only by its five-field relation key');
assert.equal(relations.gains.length, 1, 'display-only row change is not a relation gain');
assert.deepEqual(sliceRelationCounts([a, b]), {irmin: 2, protocol: 0});
assert.deepEqual(sliceRelationCounts([row({caller_path: 'src/proto_alpha/lib_protocol/a.ml'})]), {irmin: 0, protocol: 1});
assert.deepEqual(newMustRows([a, row({kind: 'MUST', call_site: 'a.ml:4'})]).map(value => value.call_site), ['a.ml:4']);
const report = measurementReport([a], {rows: [c, c], row_count: 2, digest: 'current'},
  {arch_revision: 'before', tezos_revision: 'tezos', producer_sha256: 'producer', schema_sha256: 'schema'},
  {arch_revision: 'before', tezos_revision: 'tezos', producer_sha256: 'producer', schema_sha256: 'schema'},
  {records: Array(410)}, {producer_wall_ms: 1, max_rss_kib: null, rss_observation: 'unavailable'});
assert.equal(report.semantic_status, 'not_proven');
assert.equal(report.rows.removed_count, 1);
assert.equal(report.rows.added_count, 2, 'report preserves multiset multiplicity rather than a set count');
assert.equal(exitCode(new assert.AssertionError({message: 'delta mismatch'})), 1);
assert.equal(exitCode(new SetupError('missing corpus')), 2);
for (const [control, status] of [['pass', 0], ['assertion', 1], ['setup', 2]]) {
  const result = cp.spawnSync(process.execPath, [path.join(__dirname, 'check-tezos.js'), `--test-control=${control}`]);
  assert.equal(result.status, status, `CLI ${control} control exit`);
}
console.log('PASS CHECK3 pure multiset/relation/exit controls');
