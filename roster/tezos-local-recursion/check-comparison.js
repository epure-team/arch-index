#!/usr/bin/env node
'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');
const {compareSnapshots} = require('./comparison.js');

const root = path.resolve(__dirname, '../..');
const reviewedWitness = path.join(root,
  'improvement/2026-09-14-tezos-resolution/attempt4-reviewed-witness.json');

const before = {caller_path:'irmin/src/io.ml', caller:'run.<fun:32:5>',
  call_site:'irmin/src/io.ml:44', target_path:null, target:null,
  callee_name:'aux', kind:'MAY_TOP', edge_form:null,
  top_reason:'callback_param', top_anchor:'irmin/src/io.ml:44'};
const after = {...before, target_path:before.caller_path,
  target:'run.<fun:32:5>', callee_name:'run.<fun:32:5>',
  kind:'MAY_ENUMERATED', top_reason:null, top_anchor:null};
const residual = {...before, callee_name:'*TOP*'};
const compare = (oldRows, newRows, transitions=[], residuals=[]) =>
  compareSnapshots({rows:oldRows}, {rows:newRows},
    {approvedTransitions:transitions, approvedResiduals:residuals});

function child(script, args=[]) {
  const result = cp.spawnSync(process.execPath, [path.join(__dirname, script), ...args],
    {cwd:root, encoding:'utf8', timeout:20*60*1000, maxBuffer:128*1024*1024});
  if (result.error || result.signal || result.status === null || result.status >= 2)
    throw new Error(`${script} setup failed (${result.status}): ${result.error || result.signal || result.stderr}`);
  assert.equal(result.status, 0, `${script} assertion failed:\n${result.stdout}\n${result.stderr}`);
  return result.stdout;
}

function run() {
  if (process.argv.length !== 2) throw new Error('usage: check-comparison.js');
  const pair = {before, after};
  const positive = compare([before], [after], [pair]);
  assert.equal(positive.ok, true);
  assert.equal(positive.summary.relation_gains, 1);
  assert.equal(positive.summary.relation_losses, 0);
  assert.equal(positive.slices.irmin.relation_gains, 1);
  assert.equal(compare([before], [before]).neutral, true);
  assert.equal(compare([before], [after]).ok, false, 'no implicit recursive transition');
  assert.equal(compare([before,before], [after,after], [pair]).ok, false,
    'duplicate recursive heads require separate capacity');
  assert.equal(compare([before,before], [after,after], [pair,pair]).ok, true);
  for (const change of [{kind:'MUST'}, {target_path:'other.ml'},
    {target:'guessed.<fun:32:5>'}, {callee_name:'aux'}, {caller:'outer'},
    {call_site:'irmin/src/io.ml:45'}, {edge_form:'value_alias'},
    {top_reason:'callback_param'}, {top_anchor:before.call_site}]) {
    const altered = {...after, ...change};
    assert.equal(compare([before], [altered], [{before,after:altered}]).ok, false,
      `forbidden admitted-head mutation ${JSON.stringify(change)}`);
  }
  const returned = {after:residual, head:pair, arity:1, arguments:2};
  assert.equal(compare([before], [after,residual], [pair], [returned]).ok, true);
  assert.equal(compare([before], [after,residual], [pair]).ok, false,
    'returned-call residual requires independent approval');
  assert.equal(compare([before], [after,residual,residual], [pair], [returned,returned]).ok,
    false, 'one head cannot authorize two residuals');
  const retained = {...after, caller:'retained', call_site:'irmin/src/io.ml:8'};
  assert.equal(compare([before,retained], [after], [pair]).ok, false,
    'count gain cannot conceal an old relation loss');
  const pointFree = {...retained, edge_form:'value_alias', call_site:null};
  assert.equal(compare([before,pointFree], [after], [pair]).ok, false,
    'point-free deletion cannot be approved as recursive resolution');

  child('check-baseline.js');
  child('check-witness-inputs.js');
  child('check-native.js');
  assert.ok(fs.existsSync(reviewedWitness),
    `reviewed fixed410 witness missing: ${reviewedWitness}`);
  assert.ok(fs.existsSync(path.join(__dirname,'verify.js')),
    'candidate verifier missing');
  const output = child('verify.js', ['--witness', reviewedWitness]);
  let report;
  try { report = JSON.parse(output); }
  catch (error) { throw new Error(`candidate verifier did not emit JSON: ${error.message}`); }
  assert.equal(report.verdict, 'PASS');
  assert.equal(report.classification, 'candidate');
  assert.ok(report.summary?.relation_gains > 0, 'candidate gain must be positive');
  assert.equal(report.summary?.relation_losses, 0);
  assert.equal(report.retention_authorized, false,
    'comparison cannot independently authorize retention');
  console.log(JSON.stringify({verdict:'PASS', comparison_controls:true,
    baseline:true, native:true, witnessed_candidate:true,
    relation_gains:report.summary.relation_gains}));
}

if (require.main === module) {
  try { run(); }
  catch (error) {
    const assertion = error instanceof assert.AssertionError;
    console.error(`${assertion ? 'LOCAL_RECURSION_COMPARISON_ASSERTION' : 'LOCAL_RECURSION_COMPARISON_SETUP'}: ${error.stack || error}`);
    process.exitCode = assertion ? 1 : 2;
  }
}

module.exports = {run};
