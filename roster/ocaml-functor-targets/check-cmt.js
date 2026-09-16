#!/usr/bin/env node
'use strict';

const cp = require('node:child_process');
const path = require('node:path');

const root = path.resolve(__dirname, '../..');
const args = process.argv.slice(2);
const titles = [
  'functor targets: direct local application resolves a formal member call',
  'functor targets: flat mode infers and persists no Stage 4 target or witness',
  'functor targets: 0-CFA unions actuals and preserves every witness',
  'functor targets: finalizer rejects a witness whose candidate lost its callee',
  'functor targets: rejected positive candidate prevents completion',
  'functor targets: curried slots nested members and refusals stay separated',
];

class SetupError extends Error {}
const exitCode = error => error instanceof require('node:assert').AssertionError ? 1 : 2;

function run(command, commandArgs, options = {}) {
  const result = cp.spawnSync(command, commandArgs, {
    cwd: root, encoding: 'utf8', timeout: 180000,
    maxBuffer: 64 * 1024 * 1024, ...options,
  });
  const output = `${result.stdout || ''}${result.stderr || ''}`;
  process.stdout.write(output);
  if (result.error) throw new SetupError(`${command}: ${result.error.message}`);
  if (result.signal) throw new SetupError(`${command} terminated by ${result.signal}`);
  return {result, output};
}

function controlled(mode) {
  if (mode === 'pass') return;
  if (mode === 'assertion')
    throw new (require('node:assert').AssertionError)({message: 'injected target assertion'});
  throw new SetupError('injected target setup failure');
}

function main() {
  const control = args[0]?.match(/^--test-control=(pass|assertion|setup)$/);
  if (args.length === 1 && control) return controlled(control[1]);
  if (args.length) throw new SetupError('usage: check-cmt.js [--test-control=pass|assertion|setup]');

  const build = run('opam', ['exec', '--', 'dune', 'build', '--root=.',
    'tezt/tests/main.exe', 'bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe',
    'bin/arch_index_cli/arch_index_cli.exe', 'bin/arch_query/arch_query.exe']);
  if (build.result.status !== 0) throw new SetupError(`native build exited ${build.result.status}`);

  const tezt = run('opam', ['exec', '--', 'dune', 'exec', '--root=.',
    'tezt/tests/main.exe', '--', '--file', 'tezt/tests/functor_bindings.ml',
    '--match', 'functor targets', '--keep-going']);
  if (tezt.result.status !== 0) {
    if (tezt.result.status === 1 && tezt.output.includes('[FAILURE]') &&
        /FUNCTOR_TARGET_(?:RED|FLAT|UNION|OCCURRENCE|VALIDATOR|LIFECYCLE|POSITION|NESTED|REFUSAL)/.test(tezt.output))
      throw new (require('node:assert').AssertionError)({message: 'authentic target fixture assertion failed'});
    throw new SetupError(`target Tezt execution exited ${tezt.result.status}`);
  }
  for (const title of titles)
    if (!tezt.output.includes('[SUCCESS]') || !tezt.output.includes(title))
      throw new SetupError(`successful output lacks required fixture: ${title}`);

  const copies = run('opam', ['exec', '--', 'node',
    'roster/ocaml-data-preservation/check-cmt-copies.js']);
  if (copies.result.status !== 0) {
    if (copies.result.status === 1) throw new (require('node:assert').AssertionError)({message: 'copy/variant assertion failed'});
    throw new SetupError(`copy/variant checker exited ${copies.result.status}`);
  }
  if (!copies.output.includes('CHECK2 PASS')) throw new SetupError('copy/variant checker emitted no proof marker');

  const lifecycle = run('opam', ['exec', '--', 'node',
    'scripts/check-functor-catalogue.js', 'lifecycle']);
  if (lifecycle.result.status !== 0) {
    if (lifecycle.result.status === 1) throw new (require('node:assert').AssertionError)({message: 'variant refusal assertion failed'});
    throw new SetupError(`variant lifecycle checker exited ${lifecycle.result.status}`);
  }
  let report;
  try { report = JSON.parse(lifecycle.output.trim()); }
  catch (error) { throw new SetupError(`variant lifecycle output is not JSON: ${error.message}`); }
  if (report.mode !== 'lifecycle' || !report.result?.extended?.checked_outcomes?.includes('dropped_module'))
    throw new SetupError('variant lifecycle output lacks the refusal proof');
  process.stdout.write('CHECK1_PASS: authentic targets, flat isolation, witnesses, copies and variant refusal passed\n');
}

try { main(); }
catch (error) {
  process.stderr.write(`${error instanceof require('node:assert').AssertionError ? 'CHECK1_ASSERTION' : 'CHECK1_SETUP'}: ${error.message}\n`);
  process.exitCode = exitCode(error);
}
