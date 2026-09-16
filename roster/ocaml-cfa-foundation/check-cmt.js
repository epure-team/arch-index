#!/usr/bin/env node
'use strict';

const cp = require('node:child_process');
const path = require('node:path');

const root = path.resolve(__dirname, '../..');
const args = process.argv.slice(2);

function assertion(message) {
  process.stderr.write(`CHECK2_ASSERTION: ${message}\n`);
  process.exit(1);
}

function setup(message) {
  process.stderr.write(`CHECK2_SETUP: ${message}\n`);
  process.exit(2);
}

const title = 'OCaml CFA: a same-CMT alias chain reaches its actual target';
const assertionMarkers = [
  'OCAML_CFA_ASSERTION:', 'OCAML_CFA_RED:', 'OCAML_CFA_LITERAL_',
  'OCAML_CFA_METADATA', 'OCAML_CFA_ARITY', 'OCAML_CFA_RESIDUAL',
  'OCAML_CFA_CHANNELS', 'OCAML_CFA_CONSUMER_ASSERTION:',
  'OCAML_CFA_IDENTITY_ASSERTION:'
];

function classifyResult(result) {
  const output = `${result.stdout || ''}${result.stderr || ''}`;
  if (result.error || result.signal || output.includes('OCAML_CFA_SETUP:')) return 2;
  if (result.status === 0)
    return output.includes('[SUCCESS]') && output.includes(title) ? 0 : 2;
  const authenticFailure = result.status === 1 && output.includes('[FAILURE]') &&
    output.includes(title) && assertionMarkers.some(marker => output.includes(marker));
  return authenticFailure ? 1 : 2;
}

const selftests = {
  '--selftest-assertion': {
    status: 1, stdout: `[error] OCAML_CFA_CONSUMER_ASSERTION: controlled\n[FAILURE] ${title}\n`
  },
  '--selftest-setup': {
    status: 1, stdout: `OCAML_CFA_SETUP: controlled\n[FAILURE] ${title}\n`
  },
  '--selftest-compiler-marker': {
    status: 1, stderr: 'compiler excerpt: OCAML_CFA_ASSERTION: is source text\n'
  },
  '--selftest-empty-success': {status: 0, stdout: ''}
};
if (args.length === 1 && Object.hasOwn(selftests, args[0])) {
  const code = classifyResult(selftests[args[0]]);
  process.stderr.write(`CHECK2_SELFTEST: ${args[0]} classified ${code}\n`);
  process.exit(code);
}
if (args.length !== 0)
  setup('usage: check-cmt.js [--selftest-assertion|--selftest-setup|--selftest-compiler-marker|--selftest-empty-success]');

const build = cp.spawnSync(
  'opam',
  ['exec', '--', 'dune', 'build', '--root=.',
   'tezt/tests/main.exe',
   'bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe',
   'bin/arch_index_cli/arch_index_cli.exe',
   'bin/arch_query/arch_query.exe'],
  {cwd: root, encoding: 'utf8', timeout: 180000, maxBuffer: 32 * 1024 * 1024}
);
process.stdout.write(`${build.stdout || ''}${build.stderr || ''}`);
if (build.error) setup(`native build could not start: ${build.error.message}`);
if (build.signal) setup(`native build terminated by ${build.signal}`);
if (build.status !== 0) setup(`native build failed (exit ${build.status})`);

const result = cp.spawnSync(
  'opam',
  ['exec', '--', 'dune', 'exec', 'tezt/tests/main.exe', '--',
   '--file', 'tezt/tests/ocaml_cfa_foundation.ml', '--keep-going'],
  {cwd: root, encoding: 'utf8', timeout: 180000, maxBuffer: 32 * 1024 * 1024}
);

const output = `${result.stdout || ''}${result.stderr || ''}`;
process.stdout.write(output);
const classification = classifyResult(result);
if (classification === 0) {
  process.stdout.write('CHECK2_PASS: authentic main, flat, metadata, identity and consumer controls passed\n');
  process.exit(0);
}
if (classification === 1)
  assertion('native CFA assertion failed');
setup(`native Tezt setup/build/load failed or lacked proof markers (exit ${result.status})`);
