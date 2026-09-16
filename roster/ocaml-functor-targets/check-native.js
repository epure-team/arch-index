#!/usr/bin/env node
'use strict';

const assert = require('node:assert/strict');
const cp = require('node:child_process');
const path = require('node:path');

const root = path.resolve(__dirname, '../..');
const args = process.argv.slice(2);
class SetupError extends Error {}
const exitCode = error => error instanceof assert.AssertionError ? 1 : 2;

function run(command, commandArgs, timeout = 300000) {
  const result = cp.spawnSync(command, commandArgs, {
    cwd: root, encoding: 'utf8', timeout, maxBuffer: 64 * 1024 * 1024,
  });
  const output = `${result.stdout || ''}${result.stderr || ''}`;
  process.stdout.write(output);
  if (result.error) throw new SetupError(`${command}: ${result.error.message}`);
  if (result.signal) throw new SetupError(`${command} terminated by ${result.signal}`);
  return {result, output};
}

function controlled(mode) {
  if (mode === 'pass') return;
  if (mode === 'assertion') throw new assert.AssertionError({message: 'injected native assertion'});
  throw new SetupError('injected native setup failure');
}

function main() {
  const control = args[0]?.match(/^--test-control=(pass|assertion|setup)$/);
  if (args.length === 1 && control) return controlled(control[1]);
  if (args.length) throw new SetupError('usage: check-native.js [--test-control=pass|assertion|setup]');

  const build = run('opam', ['exec', '--', 'dune', 'build', '--root=.', 'tezt/tests/main.exe']);
  if (build.result.status !== 0) throw new SetupError(`native build exited ${build.result.status}`);
  for (const mode of ['inventory', 'lifecycle', 'query', 'compatibility']) {
    const checked = run('opam', ['exec', '--', 'node', 'scripts/check-functor-bindings.js', mode]);
    if (checked.result.status !== 0) {
      if (checked.result.status === 1) throw new assert.AssertionError({message: `binding ${mode} assertion failed`});
      throw new SetupError(`binding ${mode} exited ${checked.result.status}`);
    }
    let value;
    try { value = JSON.parse(checked.output.trim()); }
    catch (error) { throw new SetupError(`binding ${mode} output is not JSON: ${error.message}`); }
    if (value.mode !== mode || !value.result) throw new SetupError(`binding ${mode} output lacks its complete result`);
  }
  const suite = run('opam', ['exec', '--', 'dune', 'exec', '--root=.',
    'tezt/tests/main.exe', '--', '--job-count', '1'], 600000);
  if (suite.result.status !== 0) {
    if (suite.result.status === 1 && suite.output.includes('[FAILURE]'))
      throw new assert.AssertionError({message: 'full native suite assertion failed'});
    throw new SetupError(`full native suite exited ${suite.result.status}`);
  }
  if (!suite.output.includes('[SUCCESS]') || suite.output.includes('[FAILURE]'))
    throw new SetupError('full native suite emitted no trustworthy success summary');
  process.stdout.write('CHECK2_PASS: full native suite and four independent binding modes passed\n');
}

try { main(); }
catch (error) {
  process.stderr.write(`${error instanceof assert.AssertionError ? 'CHECK2_ASSERTION' : 'CHECK2_SETUP'}: ${error.message}\n`);
  process.exitCode = exitCode(error);
}
