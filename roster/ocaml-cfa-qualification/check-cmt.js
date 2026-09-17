#!/usr/bin/env node
'use strict';

/* Stage 5 useful-query qualification.  The two native tests compile and index
 * authentic CMT input: the CFA fixture proves MUST-only / bounded-MAY / TOP
 * query distinctions, while impact proves the human and JSON wording.  The
 * pinned replay below supplies separate corpus/resource evidence. */
const assert = require('node:assert/strict');
const cp = require('node:child_process');
const path = require('node:path');

const root = path.resolve(__dirname, '../..');
const args = process.argv.slice(2);
class SetupError extends Error {}
const exitCode = error => error instanceof assert.AssertionError ? 1 : 2;

function run(command, commandArgs, timeout = 600000) {
  const result = cp.spawnSync(command, commandArgs, {
    cwd: root, encoding: 'utf8', timeout, maxBuffer: 64 * 1024 * 1024,
  });
  const output = `${result.stdout || ''}${result.stderr || ''}`;
  process.stdout.write(output);
  if (result.error) throw new SetupError(`${command}: ${result.error.message}`);
  if (result.signal) throw new SetupError(`${command} terminated by ${result.signal}`);
  return {result, output};
}

function checked(command, commandArgs, label) {
  const runResult = run(command, commandArgs);
  if (runResult.result.status === 0) return;
  if (runResult.result.status === 1 && runResult.output.includes('[FAILURE]'))
    throw new assert.AssertionError({message: `${label} assertion failed`});
  throw new SetupError(`${label} exited ${runResult.result.status}`);
}

function main() {
  const control = args[0]?.match(/^--test-control=(pass|assertion|setup)$/);
  if (args.length === 1 && control) {
    if (control[1] === 'assertion') throw new assert.AssertionError({message: 'injected qualification assertion'});
    if (control[1] === 'setup') throw new SetupError('injected qualification setup failure');
    return;
  }
  if (args.length) throw new SetupError('usage: check-cmt.js [--test-control=pass|assertion|setup]');

  checked('opam', ['exec', '--', 'dune', 'build', '--root=.', 'tezt/tests/main.exe'], 'native build');
  checked('opam', ['exec', '--', 'dune', 'exec', '--root=.', 'tezt/tests/main.exe', '--',
    '--job-count', '1', '--match', 'OCaml CFA: a same-CMT alias chain reaches its actual target|impact:'],
  'authentic useful-query suite');
  checked('opam', ['exec', '--', 'node', 'roster/ocaml-functor-targets/check-tezos.js'],
    'pinned semantic/resource replay');
  process.stdout.write('CHECK1_PASS: authentic CMT query semantics, impact labels, and pinned qualification passed\n');
}

try { main(); }
catch (error) {
  process.stderr.write(`${error instanceof assert.AssertionError ? 'CHECK1_ASSERTION' : 'CHECK1_SETUP'}: ${error.message}\n`);
  process.exitCode = exitCode(error);
}
