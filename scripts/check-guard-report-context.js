#!/usr/bin/env node
'use strict';
// Self-contained R1 regression: only this file is overlaid into the pre-fix archive.
const assert = require('node:assert/strict');
const cp = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const binary = path.join(root, '_build/default/bin/arch_guard/arch_guard.exe');
const cap = 16 * 1024 * 1024;
function success(command, args, cwd = root) {
  const result = cp.spawnSync(command, args, {cwd, encoding: 'utf8', timeout: 120000, maxBuffer: cap});
  if (result.error || result.signal || result.status !== 0)
    throw new Error(`execution: ${command}: ${result.error || result.signal || result.stderr || result.status}`);
  if (Buffer.byteLength(result.stdout) + Buffer.byteLength(result.stderr) > cap)
    throw new Error('execution: combined child output exceeds 16 MiB');
  return result.stdout;
}
function checkContext(json, text, compiler, bits, empty) {
  assert.equal(json.tool.compiler_version, compiler, 'linked compiler version');
  assert.equal(json.tool.int_bits, bits, 'linked compiler target int width');
  assert.ok([31, 63].includes(bits));
  assert.equal(json.outcome, empty ? 'empty_inventory' : 'classified');
  assert.equal(json.census.artifacts, 1);
  assert.equal(json.census.total_sites, empty ? 0 : 1);
  assert.match(text, /supplied accepted artifacts only/, 'text artifact scope');
  assert.ok(text.includes(`compiler_version: ${compiler}\n`), 'text linked compiler version');
  assert.ok(text.includes(`int_bits: ${bits}\n`), 'text int width');
  const requirements = [
    [json.analysis.assumptions, /same-compiler/, 'same compiler'],
    [json.analysis.assumptions, /same-target/, 'same target'],
    [json.analysis.assumptions, /artifact-only scope/, 'artifact-only scope'],
    [json.analysis.assumptions, /no source freshness certificate/, 'no source freshness'],
    [json.analysis.limitations, /no whole-program completeness/, 'no completeness'],
    [json.analysis.limitations, /no guaranteed execution or confirmed failure/, 'no execution/failure claim'],
    [json.analysis.limitations, /no machine-checked proof/, 'no proof'],
    [json.analysis.limitations, /no interprocedural or heap reasoning/, 'no interprocedural/heap reasoning'],
    [json.analysis.limitations, /^indirect operations are not covered$/, 'indirect operations excluded'],
    [json.analysis.limitations, /^omitted artifacts are not covered$/, 'omitted artifacts excluded'],
  ];
  for (const [values, pattern, label] of requirements) {
    assert.ok(Array.isArray(values) && values.some(value => typeof value === 'string' && pattern.test(value)), `JSON ${label}`);
    // The actual reported statement, not a separately invented text approximation.
    for (const value of values.filter(value => pattern.test(value)))
      assert.ok(text.includes(value), `text ${label}`);
  }
  assert.equal(json.analysis.mode, 'experimental-report-only');
  assert.match(text, /Report-only conditional facts/);
  if (empty) {
    assert.match(text, /No matching immediate primitive occurrences in supplied artifacts\./);
    assert.equal(json.sites.length, 0);
    for (const [name, value] of Object.entries(json.census))
      if (name !== 'artifacts') assert.equal(value, 0, `empty census ${name}`);
  } else {
    assert.equal(json.sites[0].status, 'MAY_ZERO');
    assert.deepEqual(json.sites[0].reasons, ['divisor_may_be_zero']);
  }
}
function main() {
  // Normal Tezt/full-build runs already supply this binary. Only a fresh archive
  // requires setup; do not inherit ARCH_GUARD pointing outside the archived tree.
  if (!fs.existsSync(binary)) success('dune', ['build', '--root', root, 'bin/arch_guard/arch_guard.exe']);
  const compiler = success('ocamlc', ['-version']).trim();
  const config = success('ocamlc', ['-config']);
  const match = config.match(/^word_size:\s*(32|64)$/m);
  if (!match) throw new Error('execution: compiler word_size unavailable');
  const bits = Number(match[1]) - 1;
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'guard-report-context-'));
  const failures = [];
  try {
    for (const [name, source, empty] of [
      ['empty', 'let value = 1\n', true],
      ['classified', 'let divide divisor = 10 / divisor\n', false],
    ]) {
      fs.writeFileSync(path.join(dir, `${name}.ml`), source);
      success('ocamlc', ['-bin-annot', '-c', `${name}.ml`], dir);
      const cmt = path.join(dir, `${name}.cmt`);
      const json = JSON.parse(success(binary, ['--cmt', cmt, '--format', 'json']));
      const text = success(binary, ['--cmt', cmt, '--format', 'text']);
      try { checkContext(json, text, compiler, bits, empty); }
      catch (error) {
        if (!(error instanceof assert.AssertionError)) throw error;
        failures.push(`${name}: ${error.message}`);
      }
    }
    assert.equal(failures.length, 0, failures.join('\n'));
    console.log('report context: empty/classified actual CLI JSON/text PASS');
  } finally { fs.rmSync(dir, {recursive: true, force: true}); }
}
try { main(); }
catch (error) {
  console.error(error.message);
  process.exitCode = error instanceof assert.AssertionError ? 1 : 2;
}
