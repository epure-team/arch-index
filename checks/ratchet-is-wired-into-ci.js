#!/usr/bin/env node
// checks/ratchet-is-wired-into-ci.js — runnable directly: `node <path> [root]`.
//
// Exit convention: 0 = passes · 1 = assertion fired · >=2 = error/setup failure.
//
// WHY THIS EXISTS. Eleven ratchet checks were wired into nothing. CI ran `dune build` and
// `dune test`; no workflow step, no dune rule and no script referenced `checks/` or
// `scripts/check-*`. Measured, not assumed: `grep -n 'scripts/check' .github/workflows/ci.yml`
// returned nothing, `grep -rn checks --include=dune .` returned nothing, and
// `git diff --stat origin/main...HEAD -- .github/` was empty. So every check written in this
// campaign to stop a regression was a file a person had to remember to run — which is exactly
// the state a ratchet exists to leave, and it had been that way for three review rounds.
//
// WHAT IS ASSERTED, and why it is not "a step mentions the word checks". Two things, because
// the wiring can rot from either end:
//
//   1. Some CI step actually invokes the runner. A commented-out step, or a mention in prose,
//      is not an invocation, so the step's `run:` body is what is searched — not the file.
//   2. THE RUNNER STILL COVERS EVERY CHECK. This is the half that rots silently: a new check
//      added under checks/ that the runner does not discover is a check CI does not run, and
//      nothing anywhere would say so. `--list` is asked what it would run, and the answer is
//      compared against the directory. A runner that had quietly stopped discovering a tier —
//      or the whole directory — is caught by the same comparison.
//
// It deliberately does NOT assert which runner, or that the step is named "Ratchet checks":
// those are decisions, not invariants, and pinning them would make an ordinary rename a
// failure. What must hold is that the files exist, that something in CI runs them, and that
// what runs them runs all of them.

'use strict';

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const root = process.argv[2] || path.resolve(__dirname, '..');
const workflowDir = path.join(root, '.github', 'workflows');
const runner = path.join('checks', 'run-ratchet.js');
const runnerAbs = path.join(root, runner);

if (!fs.existsSync(workflowDir)) {
  console.error(`ratchet-is-wired-into-ci: ${workflowDir} does not exist — nothing measured, nothing asserted.`);
  process.exit(2);
}
if (!fs.existsSync(runnerAbs)) {
  console.error(`ratchet-is-wired-into-ci: ${runnerAbs} does not exist. Refusing rather than passing:`);
  console.error('  a missing runner is the strongest form of "the ratchet is wired into nothing", but it is');
  console.error('  also a setup failure from this check\'s point of view, so it is exit 2 and not a silent 0.');
  process.exit(2);
}

// Every `run:` body in every workflow, flattened. YAML is not parsed: a dependency for one
// grep is a dependency this check would then have to install in CI to check CI.
const runBodies = [];
const workflows = fs.readdirSync(workflowDir).filter((f) => /\.ya?ml$/.test(f)).sort();
for (const wf of workflows) {
  const text = fs.readFileSync(path.join(workflowDir, wf), 'utf8');
  const lines = text.split('\n');
  for (let i = 0; i < lines.length; i++) {
    const m = /^(\s*)-?\s*run:\s*(.*)$/.exec(lines[i]);
    if (!m) continue;
    const indent = m[1].length;
    let body = m[2] === '|' || m[2] === '>' || m[2] === '' ? '' : m[2];
    for (let j = i + 1; j < lines.length; j++) {
      const l = lines[j];
      if (l.trim() === '') { body += '\n'; continue; }
      const li = l.length - l.replace(/^\s*/, '').length;
      if (li <= indent) break;
      body += `\n${l.trim()}`;
    }
    runBodies.push({ wf, line: i + 1, body });
  }
}

if (runBodies.length === 0) {
  console.error(`ratchet-is-wired-into-ci: no \`run:\` step found in ${workflows.join(', ') || '(no workflows)'}.`);
  process.exit(2);
}

// A comment line is not an invocation.
const invokes = runBodies.filter((s) =>
  s.body
    .split('\n')
    .some((l) => !/^\s*#/.test(l) && l.includes(runner))
);

const listed = spawnSync(process.execPath, [runnerAbs, '--list', root], { encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 });
if (listed.status !== 0) {
  console.error(`ratchet-is-wired-into-ci: \`node ${runner} --list\` exited ${listed.status}:`);
  console.error(`${listed.stdout || ''}${listed.stderr || ''}`.replace(/^/gm, '    '));
  process.exit(2);
}
const covered = new Set(
  (listed.stdout || '')
    .split('\n')
    .filter(Boolean)
    .map((l) => l.split('\t')[1])
);

const expected = [
  ...fs.readdirSync(path.join(root, 'checks')).filter((f) => /\.(sh|js)$/.test(f) && f !== 'run-ratchet.js').map((f) => `checks/${f}`),
  ...fs.readdirSync(path.join(root, 'scripts')).filter((f) => /^check-.*\.(sh|js)$/.test(f)).map((f) => `scripts/${f}`),
].sort();

const uncovered = expected.filter((f) => !covered.has(f));

console.log(
  `ratchet-is-wired-into-ci: ${workflows.length} workflow file(s), ${runBodies.length} run step(s); ` +
    `${expected.length} check file(s) on disk, ${covered.size} claimed by the runner.`
);
for (const s of invokes) console.log(`  invoked from ${s.wf}:${s.line}`);

let failed = false;
if (invokes.length === 0) {
  console.error(`  NO CI step invokes ${runner}.`);
  console.error('  The ratchet is then a set of files someone must remember to run, which is the state it');
  console.error('  exists to leave: a regression it would have caught reaches main with CI green.');
  failed = true;
}
if (uncovered.length) {
  console.error(`  ${uncovered.length} check file(s) exist that the runner does not run:`);
  for (const f of uncovered) console.error(`    - ${f}`);
  console.error('  A check CI never invokes is not weaker than no check; it is worse, because the ratchet');
  console.error('  table counts it as coverage.');
  failed = true;
}
if (failed) process.exit(1);

console.log('  Every check on disk is claimed by the runner, and CI invokes the runner. Running is not passing:');
console.log('  this asserts only that nothing in the ratchet is unreachable from CI.');
process.exit(0);
