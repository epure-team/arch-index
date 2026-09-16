#!/usr/bin/env node
'use strict';

const cp = require('node:child_process');
const path = require('node:path');

const root = path.resolve(__dirname, '../..');
const cmtChecker = path.join(__dirname, 'check-cmt.js');

function run(label, command, args, expectedStatus) {
  const result = cp.spawnSync(command, args, {
    cwd: root,
    encoding: 'utf8',
    timeout: 240000,
    maxBuffer: 32 * 1024 * 1024,
  });
  process.stdout.write(result.stdout || '');
  process.stderr.write(result.stderr || '');
  if (result.error || result.signal) {
    process.stderr.write(
      `REVIEW_FIXES_SETUP: ${label}: ${result.error?.message || result.signal}\n`,
    );
    process.exit(2);
  }
  if (result.status !== expectedStatus) {
    process.stderr.write(
      `REVIEW_FIXES_ASSERTION: ${label}: expected exit ${expectedStatus}, got ${result.status}\n`,
    );
    process.exit(1);
  }
}

run(
  'iterative watcher and residual domain regressions',
  'opam',
  ['exec', '--', 'dune', 'exec', '--root', '.', 'test/test_cfa.exe'],
  0,
);
run('authentic CMT regressions', process.execPath, [cmtChecker], 0);
for (const marker of ['propagation', 'recursion', 'capture']) {
  run(
    `CHECK-2 ${marker} assertion classification`,
    process.execPath,
    [cmtChecker, `--selftest-${marker}`],
    1,
  );
}
run(
  'CHECK-2 setup classification',
  process.execPath,
  [cmtChecker, '--selftest-setup'],
  2,
);

process.stdout.write('REVIEW_FIXES_PASS: all round-1 findings are ratcheted\n');
