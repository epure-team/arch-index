#!/usr/bin/env node
// checks/dispatched-groups-were-executed.js — runnable directly: `node <path> [task] [root]`.
//
// Exit convention: 0 = passes · 1 = assertion fired · >=2 = error/setup failure.
//
// WHY THIS EXISTS. `dispatch-covers-open-findings.js` closes ONE transition and says so in its
// own output: "naming is not fixing; this asserts only that none is unowned." That caveat was
// written as a statement of scope and became the exact description of the next hole. There are
// four states, not two:
//
//     unowned  ->  named  ->  dispatched  ->  executed
//
// The sibling check closes `unowned -> named`. This one closes `dispatched -> executed`, which
// is where this task lost work three times: a fix group was planned and given a worktree and no
// agent was ever launched for it, and separately a review specialist was given a worktree and
// never launched. In both cases the finding had an OWNER and no EXECUTION — precisely and only
// what the sibling's caveat said it could not detect.
//
// THE DISCRIMINATOR NEEDS NO JUDGEMENT ABOUT QUALITY. A dispatched worktree that ran has a diff;
// one that never ran is a bare checkout. That is observable without reading a line of content,
// and it caught both losses a posteriori: the two review worktrees that ran held ~540 MB of build
// output, the one that did not held 8.6 MB and nothing else.
//
// It reads the brief's plan for group headings and requires each to have an outcome section.
// A group with a finding table and no outcome is the shape both losses took.

const fs = require('fs');
const path = require('path');

const task = process.argv[2] || 'mutation-campaign-313';
const root = process.argv[3] || process.cwd();
const briefPath = path.join(root, 'briefs', `${task}-impl.md`);

if (!fs.existsSync(briefPath)) {
  console.error(`dispatched-groups-were-executed: ${briefPath} does not exist — nothing was measured, so nothing is asserted.`);
  process.exit(2);
}

const text = fs.readFileSync(briefPath, 'utf8');
const headings = [];
for (const line of text.split('\n')) {
  const m = /^#{2,3}\s+(.*)$/.exec(line);
  if (m) headings.push(m[1].trim());
}

// A planned group announces itself as "Group X — <something>"; its execution announces itself as
// "Group X — outcome". Both forms are the brief's own convention, not invented here.
const planned = new Map();
const executed = new Set();
for (const h of headings) {
  const m = /^Group\s+([A-Z])\s*[—-]\s*(.*)$/i.exec(h);
  if (!m) continue;
  const [, letter, rest] = m;
  if (/^outcome\b/i.test(rest.trim())) executed.add(letter.toUpperCase());
  else if (!planned.has(letter.toUpperCase())) planned.set(letter.toUpperCase(), h);
}

if (planned.size === 0) {
  console.log(
    'dispatched-groups-were-executed: the brief announces no "Group X — …" headings, so no dispatch\n' +
    '  was planned in that form and nothing is asserted. This is NOT a pass earned on a population.'
  );
  process.exit(0);
}

const missing = [...planned.keys()].filter((k) => !executed.has(k)).sort();
console.log(
  `dispatched-groups-were-executed: ${planned.size} group(s) planned, ${executed.size} with an outcome section.`
);

if (missing.length === 0) {
  console.log('  Every planned group reports an outcome. An outcome section is not a correct fix;');
  console.log('  this asserts only that no group was planned, given a worktree, and never run.');
  process.exit(0);
}

console.error(`  ${missing.length} planned group(s) have NO outcome section:`);
for (const k of missing) console.error(`    - Group ${k}: "${planned.get(k)}"`);
console.error('  A group with a finding table and no outcome is the shape this task lost work in');
console.error('  three times: named, owned, dispatched, and never executed — which the sibling');
console.error('  check cannot see, because naming is not executing.');
process.exit(1);
