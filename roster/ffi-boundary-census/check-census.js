#!/usr/bin/env node
'use strict';

const cp = require('child_process');
const path = require('path');
const crypto = require('crypto');

const root = process.argv[2] || '/home/mathias/dev/tezos/tezos';
const script = path.join(__dirname, 'census.js');
function fail(message) { process.stderr.write(`CHECK1_ASSERTION: ${message}\n`); process.exit(1); }
function run(args) {
  const result = cp.spawnSync(process.execPath, [script, ...args], {
    encoding: 'utf8', maxBuffer: 64 * 1024 * 1024,
  });
  if (result.status !== 0) {
    process.stderr.write(result.stderr);
    process.stderr.write('CHECK1_SETUP: census launch failed\n');
    process.exit(2);
  }
  return result.stdout;
}

if (process.argv[3] === '--test-control=assertion') fail('injected assertion');
if (process.argv[3] === '--test-control=setup') { process.stderr.write('CHECK1_SETUP: injected setup failure\n'); process.exit(2); }

run(['--self-test']);
let value;
try { value = JSON.parse(run([root])); } catch (error) { process.stderr.write(`CHECK1_SETUP: invalid JSON: ${error.message}\n`); process.exit(2); }
if (value.schema_version !== 1 || value.analysis !== 'ffi_boundary_census') fail('wrong envelope');
if (path.resolve(value.root) !== path.resolve(root)) fail('root mismatch');
if (!Array.isArray(value.records) || !Number.isInteger(value.files_scanned)) fail('bad record collection');
const sorted = [...value.records].sort((a, b) => a.mechanism.localeCompare(b.mechanism) || a.path.localeCompare(b.path) || a.line - b.line || a.symbol.localeCompare(b.symbol));
if (JSON.stringify(sorted) !== JSON.stringify(value.records)) fail('records are not deterministic');
const actual = {};
for (const record of value.records) {
  if (!record.mechanism || !record.path || !Number.isInteger(record.line) || record.line < 1 || !record.symbol) fail('malformed record');
  if (record.path.startsWith('../') || path.isAbsolute(record.path) || record.symbol.startsWith('%')) fail('out-of-scope record');
  actual[record.mechanism] = (actual[record.mechanism] || 0) + 1;
}
if (JSON.stringify(actual) !== JSON.stringify(value.summary.by_mechanism)) fail('summary disagrees with records');
const digest = crypto.createHash('sha256').update(JSON.stringify(value.records)).digest('hex');
if (digest !== value.source_digest) fail('record digest mismatch');
process.stdout.write(`CHECK1_PASS: ${value.files_scanned} files, ${value.summary.records} source candidates; no FFI link inferred\n`);
