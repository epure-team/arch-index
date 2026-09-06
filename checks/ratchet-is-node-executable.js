#!/usr/bin/env node
// checks/ratchet-is-node-executable.js — runnable directly: `node <path> [root]`.
//
// Exit convention: 0 = passes · 1 = assertion fired · >=2 = error/setup failure.
//
// WHY THIS EXISTS. The review-convergence gate resolves a linked check as `node <path>`; its
// contract says so in words: "A check is always a node-runnable file path (invoked as
// `node <path>`); a spec-level CHECK-N id with no file is recorded for traceability but not
// red/green-executed." Nine of this campaign's checks are bash. `node checks/no-score-scans-
// sql-strings.sh` dies on line 2 of the file, so the gate recorded six `green-failure`
// violations ("check does not pass against the current tree") for six checks that all exit 0
// under bash — while independently marking those same six red_verified. The gate could neither
// green- nor red-verify any of them, and the round's ratchet links had to be demoted to
// traceability ids.
//
// The fix is one node-runnable path that runs the whole ratchet, rather than nine node shims
// wrapping nine bash scripts. This check pins that the path keeps that property, and it does so
// WITH ITS OWN POSITIVE CONTROL rather than by assertion: it runs `node` against a bash check
// and requires that to FAIL, then runs `node` against the entrypoint and requires that to
// succeed. If the first ever stopped failing, the second would prove nothing, and this check
// would be measuring the absence of a problem that had gone away — so both halves are asserted
// and a control that stops controlling is itself a failure.
//
// It asserts EXECUTABILITY, not the ratchet's verdict: `--list` is used, not a full run, so this
// stays fast and so a genuine ratchet regression is reported by run-ratchet.js under its own
// name rather than arriving here disguised as an interface problem.

'use strict';

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const root = process.argv[2] || path.resolve(__dirname, '..');
const entrypoint = path.join(root, 'checks', 'run-ratchet.js');

if (!fs.existsSync(entrypoint)) {
  console.error(`ratchet-is-node-executable: ${entrypoint} does not exist.`);
  console.error('  Without it the gate has no node-runnable path to the ratchet at all. That is the defect');
  console.error('  itself, but from here it is a missing fixture, so it is exit 2 rather than a silent pass.');
  process.exit(2);
}

const bashChecks = fs
  .readdirSync(path.join(root, 'checks'))
  .filter((f) => f.endsWith('.sh'))
  .sort();

const run = (args) => {
  const r = spawnSync(process.execPath, args, { cwd: root, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024, timeout: 120000 });
  return { code: r.status == null ? 2 : r.status, out: `${r.stdout || ''}${r.stderr || ''}` };
};

const problems = [];

// The control. A bash script handed to node must fail — that is WHY the entrypoint is needed.
if (bashChecks.length === 0) {
  console.log('  (no bash check remains under checks/, so the control below is not needed and not run)');
} else {
  const victim = path.join('checks', bashChecks[0]);
  const { code } = run([path.join(root, victim)]);
  if (code === 0) {
    problems.push(
      `the control did not control: \`node ${victim}\` exited 0, so a bash check IS node-runnable here ` +
        'and this check is no longer measuring anything. Re-derive it before trusting its next pass.'
    );
  } else {
    console.log(`  ok   control: \`node ${victim}\` exits ${code} — a bash check is not node-runnable`);
  }
}

// The assertion. The entrypoint must be node-runnable and must name a non-empty ratchet.
const { code, out } = run([entrypoint, '--list', root]);
const lines = out.split('\n').filter(Boolean);
if (code !== 0) {
  problems.push(`\`node checks/run-ratchet.js --list\` exited ${code}:\n${out.replace(/^/gm, '      ')}`);
} else if (lines.length === 0) {
  problems.push('`node checks/run-ratchet.js --list` succeeded and listed nothing. An entrypoint that reaches no check is not an entrypoint.');
} else {
  console.log(`  ok   \`node checks/run-ratchet.js --list\` exits 0 and names ${lines.length} check(s)`);
}

console.log(`ratchet-is-node-executable: ${bashChecks.length} bash check(s) under checks/, reached through one node path.`);

if (problems.length) {
  for (const p of problems) console.error(`  ${p}`);
  console.error('  The gate invokes a linked check as `node <path>`. A link it cannot execute is recorded as');
  console.error('  a failure against a check that passes, which is worse than no link: it makes the gate');
  console.error('  disagree with the tree and teaches a reader to discount it.');
  process.exit(1);
}

console.log('  The gate has a path it can execute. What it finds behind that path is run-ratchet.js\'s answer, not this one.');
process.exit(0);
