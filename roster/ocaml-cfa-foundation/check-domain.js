#!/usr/bin/env node
'use strict';

// CHECK-1: an independent, deliberately simple repeated-scan oracle for the
// finite CFA domain.  It talks only to the test-only native probe.
const assert = require('node:assert/strict');
const cp = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '../..');
const probe = path.join(root, '_build/default/test/test_cfa.exe');
const maxBuffer = 64 * 1024 * 1024;

class SetupError extends Error {}

function add(set, value) {
  const next = new Set(set);
  next.add(value);
  return next;
}

function union(left, right) {
  return new Set([...left, ...right]);
}

function normalized(set) {
  return [...set].sort();
}

// This is intentionally not a worklist: every pass scans every copy
// constraint until no destination product changes.
function oracle(cells, operations) {
  const targets = Array.from({length: cells}, () => new Set());
  const reasons = Array.from({length: cells}, () => new Set());
  const snapshots = [];
  const copies = [];
  for (const operation of operations) {
    const [kind, left, right] = operation;
    if (kind === 'target') targets[left] = add(targets[left], right);
    else if (kind === 'reason') reasons[left] = add(reasons[left], right);
    else if (kind === 'copy') {
      copies.push(operation);
    } else if (kind === 'solve') {
      let changed = true;
      while (changed) {
        changed = false;
        for (const [, src, dst] of copies) {
          const nextTargets = union(targets[dst], targets[src]);
          const nextReasons = union(reasons[dst], reasons[src]);
          if (nextTargets.size !== targets[dst].size || nextReasons.size !== reasons[dst].size)
            changed = true;
          targets[dst] = nextTargets;
          reasons[dst] = nextReasons;
        }
      }
      snapshots.push(targets.map((set, index) => ({
        targets: normalized(set), reasons: normalized(reasons[index]),
      })));
    } else {
      throw new SetupError(`unknown oracle operation ${String(kind)}`);
    }
  }
  return snapshots;
}

function validateSnapshot(value, cells, caseLabel) {
  if (!Array.isArray(value) || value.length !== cells)
    throw new SetupError(`${caseLabel}: snapshot must contain exactly ${cells} cells`);
  return value.map((cell, index) => {
    if (!cell || typeof cell !== 'object' || Array.isArray(cell) ||
        Object.keys(cell).sort().join(',') !== 'reasons,targets')
      throw new SetupError(`${caseLabel}: cell ${index} has the wrong schema`);
    for (const field of ['targets', 'reasons']) {
      if (!Array.isArray(cell[field]) || cell[field].some(value => typeof value !== 'string'))
        throw new SetupError(`${caseLabel}: cell ${index} ${field} must be a string array`);
      const sorted = [...cell[field]].sort();
      if (cell[field].some((value, position) => value !== sorted[position]) ||
          new Set(cell[field]).size !== cell[field].length)
        throw new SetupError(`${caseLabel}: cell ${index} ${field} is not sorted and unique`);
    }
    return {targets: cell.targets, reasons: cell.reasons};
  });
}

function parseProbeOutput(text, testCase) {
  if (typeof text !== 'string') throw new SetupError(`${testCase.label}: probe output is not text`);
  let value;
  try { value = JSON.parse(text); }
  catch (error) { throw new SetupError(`${testCase.label}: malformed probe JSON: ${error.message}`); }
  if (!Array.isArray(value)) throw new SetupError(`${testCase.label}: probe result must be an array`);
  const expectedSolves = testCase.operations.filter(operation => operation[0] === 'solve').length;
  if (value.length !== expectedSolves)
    throw new SetupError(`${testCase.label}: expected ${expectedSolves} snapshots, got ${value.length}`);
  return value.map(snapshot => validateSnapshot(snapshot, testCase.cells, testCase.label));
}

function nativeProbe(testCase) {
  if (!fs.existsSync(probe)) throw new SetupError(`missing native probe: ${probe}`);
  const result = cp.spawnSync(probe, ['--probe'], {
    cwd: root, input: JSON.stringify({cells: testCase.cells, operations: testCase.operations}),
    encoding: 'utf8', timeout: 120000, maxBuffer,
  });
  if (result.error) throw new SetupError(`native probe: ${result.error.message}`);
  if (result.signal || result.status !== 0) {
    const detail = (result.stderr || result.stdout || '').trim();
    throw new SetupError(`native probe exited ${result.status || result.signal}${detail ? `: ${detail}` : ''}`);
  }
  return result.stdout;
}

// The normal checker always refreshes the copied private-kernel test binary;
// existence alone would permit a stale `_build` result to pass.
function buildProbe() {
  const result = cp.spawnSync('opam', ['exec', '--', 'dune', 'build', 'test/test_cfa.exe'], {
    cwd: root, encoding: 'utf8', timeout: 120000, maxBuffer,
  });
  if (result.error) throw new SetupError(`probe build: ${result.error.message}`);
  if (result.signal || result.status !== 0) {
    const detail = (result.stderr || result.stdout || '').trim();
    throw new SetupError(`probe build exited ${result.status || result.signal}${detail ? `: ${detail}` : ''}`);
  }
}

function graphCase(mask) {
  const edges = [];
  for (let src = 0; src < 3; src++) for (let dst = 0; dst < 3; dst++)
    if (mask & (1 << (3 * src + dst))) edges.push(['copy', src, dst]);
  const offset = (base, operation) => operation[0] === 'copy'
    ? ['copy', operation[1] + base, operation[2] + base]
    : [operation[0], operation[1] + base, operation[2]];
  const forward = [['target', 0, 'f'], ['reason', 2, 'callback_param'], ...edges];
  const reversed = [...edges].reverse().map(operation => offset(3, operation))
    .concat([['reason', 5, 'callback_param'], ['target', 3, 'f']]);
  const duplicated = [['target', 6, 'f'], ['reason', 8, 'callback_param'],
    ...edges.map(operation => offset(6, operation)), ...edges.map(operation => offset(6, operation))];
  return {label: `three-node graph ${mask} (forward/reordered/duplicate)`, cells: 9,
    operations: [...forward, ['solve'], ...reversed, ['solve'], ...duplicated, ['solve']]};
}

function cases() {
  const result = Array.from({length: 512}, (_, mask) => graphCase(mask));
  result.push(
    {label: 'mixed known and unknown chain', cells: 3, operations: [
      ['target', 0, 'f'], ['reason', 1, 'opaque'], ['copy', 0, 1], ['copy', 1, 2], ['solve'],
    ]},
    {label: 'bottom cycle and unknown-only cell', cells: 3, operations: [
      ['copy', 0, 1], ['copy', 1, 0], ['reason', 2, 'callback_param'], ['reason', 2, 'callback_param'], ['solve'],
    ]},
    {label: 'seeded cycle', cells: 2, operations: [
      ['copy', 0, 1], ['copy', 1, 0], ['target', 0, 'f'], ['solve'],
    ]},
    {label: 'late seeds, copies, and repeated solve', cells: 4, operations: [
      ['copy', 0, 1], ['copy', 1, 0], ['solve'],
      ['target', 0, 'f'], ['solve'], ['reason', 1, 'dropped_node'], ['solve'],
      ['copy', 1, 2], ['copy', 2, 3], ['solve'],
      ['target', 3, 'g'], ['copy', 3, 0], ['copy', 3, 0], ['solve'], ['solve'],
    ]},
    {label: 'long chain', cells: 2000, operations: [
      ['target', 0, 'f'], ['reason', 0, 'opaque'],
      ...Array.from({length: 1999}, (_, index) => ['copy', index, index + 1]), ['solve'],
    ]},
  );
  return result;
}

function runCheck({runProbe = nativeProbe, cases: selectedCases = cases()} = {}) {
  if (!Array.isArray(selectedCases) || selectedCases.length === 0)
    throw new SetupError('CHECK1 requires a nonempty case list');
  for (const testCase of selectedCases) {
    const expected = oracle(testCase.cells, testCase.operations);
    const actual = parseProbeOutput(runProbe(testCase), testCase);
    assert.deepStrictEqual(actual, expected, `${testCase.label}: native product differs from repeated-scan oracle`);
  }
  return {cases: selectedCases.length};
}

function main(argv) {
  const control = argv[0] && argv[0].match(/^--test-control=(pass|assertion|setup)$/);
  if (argv.length === 1 && control) {
    // Explicit test-only path for exercising the CLI's own 0/1/2 mapping.
    // It is never read from environment or selected by the normal invocation.
    const one = {label: 'CLI test control', cells: 1,
      operations: [['target', 0, 'f'], ['reason', 0, 'opaque'], ['solve']]};
    if (control[1] === 'setup') throw new SetupError('injected setup failure');
    const output = control[1] === 'pass'
      ? JSON.stringify([[{targets: ['f'], reasons: ['opaque']}]])
      : JSON.stringify([[{targets: [], reasons: []}]]);
    runCheck({cases: [one], runProbe: () => output});
    return;
  }
  if (argv.length !== 0) throw new SetupError('usage: check-domain.js');
  buildProbe();
  const result = runCheck();
  process.stdout.write(`PASS CHECK1 independent finite-domain oracle (${result.cases} cases)\n`);
}

function exitCode(error) {
  return error instanceof assert.AssertionError ? 1 : 2;
}

module.exports = {SetupError, buildProbe, cases, exitCode, nativeProbe, oracle, parseProbeOutput, runCheck};

if (require.main === module) {
  try { main(process.argv.slice(2)); }
  catch (error) {
    process.stderr.write(`${error instanceof assert.AssertionError ? 'ASSERTION' : 'SETUP'}: ${error.message}\n`);
    process.exitCode = exitCode(error);
  }
}
