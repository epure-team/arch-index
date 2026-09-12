#!/usr/bin/env node
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const sha256 = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
function validate(dir) {
  const root = fs.realpathSync(dir);
  const runPath = path.join(root, 'run.json');
  const diagnostics = path.join(root, 'diagnostics.txt');
  if (!fs.existsSync(runPath) || !fs.existsSync(diagnostics)) throw new Error('run.json and diagnostics.txt are required');
  const run = JSON.parse(fs.readFileSync(runPath, 'utf8'));
  if (!['held','policy-failed','coverage-drift','error'].includes(run.status)) throw new Error(`unknown run status ${run.status}`);
  const complete = ['held', 'policy-failed', 'coverage-drift'].includes(run.status);
  if (complete !== (run.complete === true)) throw new Error('status/complete mismatch');
  const reports = ['gate.json', 'report.json', 'report.sarif', 'report.html'];
  if (complete) for (const name of reports) {
    const file = path.join(root, name); if (!fs.existsSync(file)) throw new Error(`missing ${name}`);
    if (run.artifacts[name] !== sha256(file)) throw new Error(`digest mismatch for ${name}`);
  }
  if (!complete) for (const name of ['report.json', 'report.sarif', 'report.html']) if (fs.existsSync(path.join(root, name))) throw new Error(`error package must not publish ${name}`);
  const unexpected = fs.readdirSync(root).filter(x => !['gate.json','report.json','report.sarif','report.html','diagnostics.txt','run.json'].includes(x));
  if (unexpected.length) throw new Error(`unexpected retained artifacts: ${unexpected.join(', ')}`);
  return run;
}
module.exports = {validate};
if (require.main === module) { try { if (process.argv.length !== 3) throw new Error('usage: origin-consumer-artifacts.js <directory>'); validate(process.argv[2]); } catch (e) { console.error(`origin-consumer-artifacts: ${e.message}`); process.exitCode = 1; } }
