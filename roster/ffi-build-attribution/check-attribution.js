#!/usr/bin/env node
'use strict';
const cp = require('child_process');
const crypto = require('crypto');
const path = require('path');
const root = process.argv[2] || '/home/mathias/dev/tezos/tezos';
const script = path.join(__dirname, 'attribution.js');
function assertion(m) { process.stderr.write(`CHECK2_ASSERTION: ${m}\n`); process.exit(1); }
function run(args) {
  const r = cp.spawnSync(process.execPath, [script, ...args], {encoding:'utf8', maxBuffer:64*1024*1024});
  if (r.status !== 0) { process.stderr.write(r.stderr); process.stderr.write('CHECK2_SETUP: attribution launch failed\n'); process.exit(2); }
  return r.stdout;
}
if (process.argv[3] === '--test-control=assertion') assertion('injected assertion');
if (process.argv[3] === '--test-control=setup') { process.stderr.write('CHECK2_SETUP: injected setup failure\n'); process.exit(2); }
run(['--self-test']);
let x; try { x=JSON.parse(run([root])); } catch (e) { process.stderr.write(`CHECK2_SETUP: invalid JSON: ${e.message}\n`); process.exit(2); }
if (x.schema_version !== 1 || x.analysis !== 'ffi_build_attribution' || !Array.isArray(x.records)) assertion('wrong envelope');
let attributed=0, unattributed=0;
for (const row of x.records) {
  if (!row.candidate || !Array.isArray(row.targets) || !['ATTRIBUTED','UNATTRIBUTED'].includes(row.availability)) assertion('bad candidate record');
  if (row.availability === 'ATTRIBUTED') { attributed++; if (!row.targets.length) assertion('empty attributed target set'); }
  else { unattributed++; if (row.targets.length) assertion('nonempty unattributed target set'); }
  for (const target of row.targets) {
    if (!target.dune_path || !Number.isInteger(target.stanza_line) || !['same_dune_directory','foreign_stub_source'].includes(target.ownership)) assertion('bad target evidence');
  }
}
if (attributed !== x.summary.attributed || unattributed !== x.summary.unattributed || attributed + unattributed !== x.summary.candidates) assertion('summary mismatch');
for (const target of x.rust_dependency_targets) if (target.evidence !== 'target dependency only; not a Rust symbol link') assertion('Rust dependency overclaim');
if (crypto.createHash('sha256').update(JSON.stringify(x.records)).digest('hex') !== x.record_digest) assertion('digest mismatch');
process.stdout.write(`CHECK2_PASS: ${attributed} attributed, ${unattributed} explicit unattributed; no symbol link inferred\n`);
