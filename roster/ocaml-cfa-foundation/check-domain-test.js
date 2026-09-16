#!/usr/bin/env node
'use strict';

const assert = require('node:assert/strict');
const cp = require('node:child_process');
const path = require('node:path');
const {exitCode, runCheck, SetupError} = require('./check-domain.js');

const one = {
  label: 'injected one-cell oracle control',
  cells: 1,
  operations: [['target', 0, 'f'], ['reason', 0, 'opaque'], ['solve']],
};
const good = JSON.stringify([[{targets: ['f'], reasons: ['opaque']}]]);

assert.doesNotThrow(() => runCheck({cases: [one], runProbe: () => good}));
assert.throws(
  () => runCheck({cases: [one], runProbe: () => JSON.stringify([[{targets: [], reasons: []}]])}),
  assert.AssertionError,
);
assert.throws(() => runCheck({cases: [one], runProbe: () => '{}'}), SetupError);
assert.throws(() => runCheck({cases: [one], runProbe: () =>
  JSON.stringify([[{targets: ['f'], reasons: ['opaque'], extra: true}]])}), SetupError);
assert.throws(() => runCheck({cases: [one], runProbe: () =>
  JSON.stringify([[{targets: ['z', 'a'], reasons: ['opaque']}]])}), SetupError);
assert.throws(() => runCheck({cases: [], runProbe: () => good}), SetupError);
assert.equal(exitCode(new assert.AssertionError({message: 'oracle mismatch'})), 1);
assert.equal(exitCode(new SetupError('malformed probe')), 2);
for (const [control, status] of [['pass', 0], ['assertion', 1], ['setup', 2]]) {
  const result = cp.spawnSync(process.execPath, [path.join(__dirname, 'check-domain.js'), `--test-control=${control}`]);
  assert.equal(result.status, status, `CLI ${control} control exit`);
}
console.log('PASS domain checker injection controls (pass/assertion/setup)');
