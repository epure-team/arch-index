#!/usr/bin/env node
'use strict';

const cp = require('node:child_process');
const path = require('node:path');

const root = path.resolve(__dirname, '../..');
const checker = path.join(root, 'roster/ocaml-cfa-foundation/check-cmt.js');
const args = process.argv.slice(2);
const result = cp.spawnSync(process.execPath, [checker, ...args], {
  cwd: root,
  encoding: 'utf8',
  timeout: 180000,
  maxBuffer: 32 * 1024 * 1024,
});
process.stdout.write(result.stdout || '');
process.stderr.write(result.stderr || '');
if (result.error || result.signal) {
  process.stderr.write(`CHECK2_SETUP: ${result.error?.message || result.signal}\n`);
  process.exitCode = 2;
} else {
  process.exitCode = result.status;
}
