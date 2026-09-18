#!/usr/bin/env node
'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {runConsumer} = require('./analysis-report-consumer.js');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'analysis-report-consumer-'));
const put = (name, value) => { const p = path.join(root, name); fs.writeFileSync(p, `${JSON.stringify(value, null, 2)}\n`); return p; };
const report = rows => ({profile: 'api-review', schema_version: '1.12', producers: [{producer: 'arch-index', producer_version: '1', soundness_class: 'sound_with_top', invocation_digest: 'abc'}], analysis_coverage: [], sections: [{analysis: 'api_surface', status: 'covered', finding_count: rows.length, findings: rows.map(([file, name, line]) => ({id: `api_surface|${file}|${name}`, kind: 'api_surface', subject: name, location: `${file}:${line}`}))}]});
const scope = put('scope.json', {version: 1, corpus: 'fixture-corpus@1', configuration: 'api-review'});
const baseReport = put('base.json', report([['a.ml', 'f', 1], ['b.ml', 'g', 2]]));
const base = runConsumer({report: baseReport, scope, out: path.join(root, 'base')});
assert.equal(base.exit, 0, 'first run must succeed');
const currentReport = put('current.json', report([['b.ml', 'g', 99], ['c.ml', 'h', 3]]));
const compared = runConsumer({report: currentReport, scope, baseline: path.join(root, 'base', 'run.json'), out: path.join(root, 'current')});
assert.equal(compared.exit, 0, 'comparison must succeed');
const delta = JSON.parse(fs.readFileSync(path.join(root, 'current', 'delta.json')));
assert.deepEqual(delta.summary, {baseline: 2, current: 2, new: 1, unchanged: 1, absent: 1});
assert.deepEqual(delta.new.map(x => x.identity), ['c.ml:h']);
assert.deepEqual(delta.unchanged.map(x => x.identity), ['b.ml:g'], 'line changes do not change semantic identity');
assert.deepEqual(delta.absent.map(x => x.identity), ['a.ml:f']);
const changedScope = put('scope-other.json', {version: 1, corpus: 'fixture-corpus@2', configuration: 'api-review'});
const refused = runConsumer({report: currentReport, scope: changedScope, baseline: path.join(root, 'base', 'run.json'), out: path.join(root, 'refused')});
assert.equal(refused.exit, 2, 'scope drift must refuse');
const refusedRun = JSON.parse(fs.readFileSync(path.join(root, 'refused', 'run.json')));
assert.equal(refusedRun.complete, false, 'refusal cannot publish completion');
assert.equal(fs.existsSync(path.join(root, 'refused', 'delta.json')), false, 'refusal cannot publish delta');
const duplicate = put('duplicate.json', report([['a.ml', 'f', 1], ['a.ml', 'f', 2]]));
const duplicateResult = runConsumer({report: duplicate, scope, out: path.join(root, 'duplicate')});
assert.equal(duplicateResult.exit, 2, 'duplicate semantic identity must refuse');
fs.rmSync(root, {recursive: true, force: true});
process.stdout.write('analysis-report-consumer checks: PASS\n');
