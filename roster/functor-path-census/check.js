#!/usr/bin/env node
'use strict';

const assert = require('node:assert/strict');
const cp = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const root = path.resolve(__dirname, '../..');
const cap = 16 * 1024 * 1024;

function run(command, args, options = {}) {
  const result = cp.spawnSync(command, args, {encoding: 'utf8', maxBuffer: cap, ...options});
  if (result.error || result.signal || result.status === null) {
    throw new Error(`setup: ${command}: ${result.error || result.signal}`);
  }
  return result;
}

function main() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'functor-path-census-red-'));
  try {
    const fixture = path.join(root, 'roster/functor-path-census/fixture.ml');
    const fixtureCopy = path.join(dir, 'fixture.ml');
    fs.copyFileSync(fixture, fixtureCopy);
    let result = run('ocamlc', ['-bin-annot', '-c', fixtureCopy], {cwd: dir});
    if (result.status !== 0) throw new Error(`fixture compilation (${result.status}): ${result.stderr}`);
    const probeCopy = path.join(dir, 'probe.ml');
    fs.copyFileSync(path.join(root, 'roster/functor-path-census/probe.ml'), probeCopy);
    const executable = path.join(dir, 'probe.exe');
    const staging = path.join(root, '_build/install/default/lib');
    const env = {...process.env, OCAMLPATH: process.env.OCAMLPATH
      ? `${staging}${path.delimiter}${process.env.OCAMLPATH}` : staging};
    result = run('ocamlfind', ['ocamlopt', '-package', 'arch-index', '-linkpkg', probeCopy,
      '-o', executable], {cwd: dir, env});
    if (result.status !== 0) throw new Error(`probe compilation (${result.status}): ${result.stderr}`);
    result = run(executable, [path.join(dir, 'fixture.cmt')], {cwd: dir});
    if (result.status !== 0) throw new Error(`probe execution (${result.status}): ${result.stderr}`);
    const report = JSON.parse(result.stdout);
    assert.equal(report.applications.length, 10,
      'fixture must retain the independently authored ten application occurrences');
    assert.deepEqual(report.applications.map(row => row.ordinal), [1,2,3,4,5,6,7,8,9,10]);
    const unsupported = report.applications.filter(row => row.reason === 'unsupported_path');
    assert.equal(unsupported.length, 9);
    assert.equal(report.applications.filter(row => row.status === 'matched').length, 1);
    assert.deepEqual(Object.fromEntries([...new Set(unsupported.map(row => row.root_category))]
      .sort().map(category => [category, unsupported.filter(row => row.root_category === category).length])), {
      bound_rhs_alias: 3, bound_rhs_structure: 4, named_functor_parameter: 1, persistent_unit: 1
    });
    assert.equal(new Set(unsupported.map(row => row.path_identity_class)).size, 7);
    assert.equal(new Set(unsupported.map(row => row.terminal_path.display)).size, 6);

    const digest = require('node:crypto').createHash('sha256')
      .update(fs.readFileSync(path.join(dir, 'fixture.cmt'))).digest('hex');
    const manifest = path.join(dir, 'manifest.tsv');
    fs.writeFileSync(manifest, `native\t${digest}\t${path.join(dir, 'fixture.cmt')}\n`);
    const {buildReport, parseManifest, publishReport} = require('./run.js');
    const first = buildReport(manifest);
    const second = buildReport(manifest);
    assert.equal(first.totals.applications, 10);
    assert.equal(first.totals.unsupported_path, 9);
    const semantic = value => ({totals: value.totals, unit_inventory: value.unit_inventory,
      artifacts: value.artifacts});
    assert.deepEqual(semantic(first), semantic(second), 'semantic replay differs');
    fs.writeFileSync(manifest, `native\t${'0'.repeat(64)}\t${path.join(dir, 'fixture.cmt')}\n`);
    assert.throws(() => parseManifest(manifest), /digest mismatch/);
    fs.writeFileSync(manifest, `native\t${digest}\t${path.join(dir, 'fixture.cmt')}\nother\t${digest}\t${path.join(dir, 'fixture.cmt')}\n`);
    assert.throws(() => parseManifest(manifest), /duplicate artifact/);

    // Publication must not expose a partially written report on an I/O failure.
    assert.equal(typeof publishReport, 'function', 'atomic publication helper required');
    const output = path.join(dir, 'report.json');
    const write = fs.writeFileSync;
    try {
      fs.writeFileSync = function(file, data, options) {
        write(file, String(data).slice(0, 5), options);
        throw new Error('injected write failure');
      };
      assert.throws(() => publishReport(output, first), /injected write failure/);
    } finally { fs.writeFileSync = write; }
    assert.equal(fs.existsSync(output), false, 'partial output was published');
    assert.equal(fs.readdirSync(dir).some(name => name.startsWith('.census-publish-')), false);
    publishReport(output, first);
    const saved = fs.readFileSync(output, 'utf8');
    assert.deepEqual(JSON.parse(saved), first);
    assert.throws(() => publishReport(output, second), /EEXIST/);
    assert.equal(fs.readFileSync(output, 'utf8'), saved, 'existing report was overwritten');

    for (const [contents, expected] of [
      ['', /no inputs/],
      ['only-one-column\n', /three nonempty columns/],
      [`native\tbad\t${fixtureCopy}\n`, /invalid sha256/],
      [`native\t${digest}\trelative.cmt\n`, /not absolute/],
      [`native\t${digest}\t${dir}\n`, /not a regular file/]
    ]) {
      fs.writeFileSync(manifest, contents);
      assert.throws(() => parseManifest(manifest), expected);
    }
    const cli = path.join(__dirname, 'run.js');
    result = run(process.execPath, [cli, '--manifest', manifest, '--out', output]);
    assert.equal(result.status, 2);
    assert.equal(result.stdout, '');
    assert.equal(fs.readFileSync(output, 'utf8'), saved);
    const absent = path.join(dir, 'absent-report.json');
    result = run(process.execPath, [cli, '--manifest', manifest, '--out', absent]);
    assert.equal(result.status, 2);
    assert.equal(fs.existsSync(absent), false);
  } finally {
    fs.rmSync(dir, {recursive: true, force: true});
  }
}

try { main(); }
catch (error) {
  if (error instanceof assert.AssertionError) {
    process.stderr.write(`assertion: ${error.message}\n`);
    process.exit(1);
  }
  process.stderr.write(`setup: ${error.stack || error}\n`);
  process.exit(2);
}
