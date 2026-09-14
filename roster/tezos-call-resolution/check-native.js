#!/usr/bin/env node
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');
const root = path.resolve(__dirname, '../..');
const titles = [
  'local structured module: run resolves to its same-file Local.f body',
  'local structured modules: ownership, masks, arity and emission forms',
  'local structured module: rejected owned body remains dropped_node TOP',
  'local structured modules: CMT identities and flat attribution stay file-local',
  'local structured modules: labeled arity ratchet',
  'local structured modules: verifier refusal coverage',
];
function classify(status, output) {
  if (status === 0 && titles.every(title => output.split('\n').some(line =>
    line.includes('[SUCCESS]') && line.endsWith(title)))) return 'pass';
  if (status === 1 && !output.includes('LOCAL_MODULE_SETUP:') &&
    output.split('\n').some(line => line.includes('[error]') &&
      line.includes('LOCAL_MODULE_ASSERTION:'))) return 'assertion';
  return 'setup';
}
try {
  if (process.argv.includes('--self-test')) {
    const green = titles.map((t,i) => `[SUCCESS] (${i+1}/${titles.length}) ${t}`).join('\n');
    assert.equal(classify(0, green), 'pass');
    assert.equal(classify(0, ''), 'setup');
    assert.equal(classify(1, '[error] LOCAL_MODULE_ASSERTION: got 0 expected 1'), 'assertion');
    assert.equal(classify(1, '[error] LOCAL_MODULE_SETUP: fixture failed'), 'setup');
    assert.equal(classify(1, '[error] compiler failed'), 'setup');
    console.log('PASS native-wrapper classification (5 assertions)');
  } else {
    if (process.argv.length !== 2) throw new Error('usage: check-native.js [--self-test]');
    const binary = path.join(root, '_build/default/tezt/tests/main.exe');
    if (!fs.existsSync(binary)) throw new Error('build the current checkout before native checks');
    const result = cp.spawnSync('opam', ['exec', `--switch=${root}`, '--', binary,
      '--file', 'tezt/tests/local_module_targets.ml', '--keep-going'],
    {cwd: root, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024});
    if (result.error) throw result.error;
    const output = (result.stdout || '') + (result.stderr || '');
    process.stdout.write(output);
    const outcome = classify(result.status, output);
    if (outcome === 'assertion') process.exitCode = 1;
    else if (outcome !== 'pass') throw new Error('native setup failed or required tests were not executed');
  }
} catch (error) {
  process.stderr.write(`${error instanceof assert.AssertionError ? 'ASSERTION' : 'SETUP'}: ${error.message}\n`);
  process.exitCode = error instanceof assert.AssertionError ? 1 : 2;
}
