#!/usr/bin/env node
// checks/dispatch-covers-open-findings.js — runnable directly: `node <path>`.
//
// Exit convention: 0 = passes · 1 = assertion fired · >=2 = error/setup failure.
//
// WHY THIS EXISTS. Round 2 of this task's review found that three of round 1's nine
// HIGH findings had never been dispatched to any fix block, while the implementation
// brief claimed all nine were fixed. Nothing surfaced it: the convergence gate checks
// missing-round-provenance, resolved-without-check, round-cap and unencodable-finding,
// and none of those is "an OPEN finding had no owner". `roster-implement` reads
// review.json only to widen the file manifest. So an unassigned finding is not blocked,
// not rejected, not in progress, and no state anywhere says so — it simply does not move.
//
// This asserts the one thing that would have caught it: every OPEN CRITICAL/HIGH finding
// in the review verdict is NAMED in the implementation brief. Naming is not fixing, and
// this check does not pretend otherwise — but an unnamed finding cannot have been
// deliberately deferred either, and that is the state this exists to make impossible.

const fs = require('fs');
const path = require('path');

const task = process.argv[2] || 'mutation-campaign-313';
const root = process.argv[3] || process.cwd();
const verdict = path.join(root, 'briefs', `${task}-review.json`);
const brief = path.join(root, 'briefs', `${task}-impl.md`);

for (const f of [verdict, brief]) {
  if (!fs.existsSync(f)) {
    console.error(`dispatch-covers-open-findings: ${f} does not exist — nothing was measured, so nothing is asserted.`);
    process.exit(2);
  }
}

let review;
try {
  review = JSON.parse(fs.readFileSync(verdict, 'utf8'));
} catch (e) {
  console.error(`dispatch-covers-open-findings: ${verdict} is not readable JSON: ${e.message}`);
  process.exit(2);
}
if (!Array.isArray(review.findings)) {
  console.error('dispatch-covers-open-findings: the verdict carries no findings array.');
  process.exit(2);
}

const text = fs.readFileSync(brief, 'utf8');
const open = review.findings.filter(
  (f) => (f.severity || '').toUpperCase() === 'HIGH' || (f.severity || '').toUpperCase() === 'CRITICAL'
).filter((f) => (f.status || 'OPEN') === 'OPEN')
 .filter((f) => (f.category || '') !== 'scope');

// A finding is NAMED if the brief mentions its fingerprint, or its path together with
// its line. Both forms occur in practice; requiring the fingerprint alone would fail on
// a brief that cites the site the way a human writes it.
const unnamed = open.filter((f) => {
  if (f.fingerprint && text.includes(f.fingerprint)) return false;
  if (f.path && text.includes(f.path) && f.line != null && text.includes(String(f.line))) return false;
  return true;
});

console.log(
  `dispatch-covers-open-findings: ${open.length} OPEN CRITICAL/HIGH finding(s) in ${path.basename(verdict)}, ` +
  `${open.length - unnamed.length} named in ${path.basename(brief)}.`
);

if (open.length === 0) {
  console.log('  Nothing was open, so nothing is asserted about coverage — this is not a pass earned on a population.');
  process.exit(0);
}

if (unnamed.length > 0) {
  console.error(`  ${unnamed.length} OPEN finding(s) are named nowhere in the brief:`);
  for (const f of unnamed) {
    console.error(`    - ${f.severity} ${f.fingerprint || `${f.path}:${f.line}`} [${f.specialist || '?'}] ${(f.summary || '').slice(0, 88)}`);
  }
  console.error('  An unnamed finding has no owner: it is not blocked, not rejected, not in progress,');
  console.error('  and no state anywhere records that. Name it in the brief — as dispatched, as');
  console.error('  deliberately deferred with a reason, or as accepted — before reporting COMPLETED.');
  process.exit(1);
}

console.log('  Every OPEN CRITICAL/HIGH finding is named. Naming is not fixing; this asserts only that none is unowned.');
process.exit(0);
