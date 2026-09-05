#!/usr/bin/env node
// checks/dispatch-covers-open-findings.js — runnable directly: `node <path> [task] [root]`.
//
// Exit convention: 0 = passes · 1 = assertion fired · >=2 = error/setup failure.
//
// WHY THIS EXISTS. Round 2 of this task's review found that three of round 1's nine HIGH
// findings had never been dispatched to any fix block, while the brief claimed all nine
// fixed. What would have surfaced them otherwise was measured, not assumed: nothing. The
// convergence gate checks missing-round-provenance, resolved-without-check, round-cap and
// unencodable-finding, and none is "an OPEN finding had no owner"; roster-implement reads
// the verdict only to widen the file manifest. So an unassigned finding is not blocked,
// not rejected, not in progress, and no state anywhere says so — it does not move.
//
// SCOPE, AND WHY IT IS NOT THE SEVERITY CUT. A first version of this file covered CRITICAL
// and HIGH while being named `open-findings` — a name broader than its check, which is the
// defect it was built to catch. The severity cut is where ATTENTION lives, not where
// consequence lives, which is exactly why the tier below it is where things sit: this
// repository's blocking finding on #88 was a MEDIUM, and two roadmap items came from
// findings below HIGH. So this covers EVERY open finding.
//
// A finding is owned when the brief NAMES it. Naming is not fixing, and the output says so.
// What naming makes impossible is the unowned state: a named finding has been dispatched,
// deferred with a reason, or accepted, and a reader can tell which by reading the sentence
// around it. A finding named under a heading matching /defer/i is reported as DEFERRED
// rather than DISPATCHED, so "deliberately not now" is expressible and counted — the state
// that could not previously be written down at all.
//
// Scope-category findings are excluded: the standing scope gate owns them.

const fs = require('fs');
const path = require('path');

const task = process.argv[2] || 'mutation-campaign-313';
const root = process.argv[3] || process.cwd();
const verdictPath = path.join(root, 'briefs', `${task}-review.json`);
const briefPath = path.join(root, 'briefs', `${task}-impl.md`);

for (const f of [verdictPath, briefPath]) {
  if (!fs.existsSync(f)) {
    console.error(`dispatch-covers-open-findings: ${f} does not exist — nothing was measured, so nothing is asserted.`);
    process.exit(2);
  }
}

let review;
try {
  review = JSON.parse(fs.readFileSync(verdictPath, 'utf8'));
} catch (e) {
  console.error(`dispatch-covers-open-findings: ${verdictPath} is not readable JSON: ${e.message}`);
  process.exit(2);
}
if (!Array.isArray(review.findings)) {
  console.error('dispatch-covers-open-findings: the verdict carries no findings array.');
  process.exit(2);
}

const briefText = fs.readFileSync(briefPath, 'utf8');

// Split the brief into sections so a mention under a "Deferred" heading can be told from a
// dispatch. A section runs from one markdown heading to the next, whatever its depth.
const sections = [];
{
  const lines = briefText.split('\n');
  let heading = '(preamble)';
  let buf = [];
  for (const l of lines) {
    if (/^#{1,6}\s/.test(l)) {
      sections.push({ heading, body: buf.join('\n') });
      heading = l.replace(/^#{1,6}\s*/, '').trim();
      buf = [];
    } else buf.push(l);
  }
  sections.push({ heading, body: buf.join('\n') });
}

const mentions = (finding) => {
  const hits = [];
  for (const s of sections) {
    const byFingerprint = finding.fingerprint && s.body.includes(finding.fingerprint);
    const bySite =
      finding.path && s.body.includes(finding.path) && finding.line != null && s.body.includes(String(finding.line));
    if (byFingerprint || bySite) hits.push(s.heading);
  }
  return hits;
};

const open = review.findings
  .filter((f) => (f.status || 'OPEN') === 'OPEN')
  .filter((f) => (f.category || '') !== 'scope');

const unowned = [];
const deferred = [];
let dispatched = 0;
for (const f of open) {
  const hits = mentions(f);
  if (hits.length === 0) unowned.push(f);
  else if (hits.every((h) => /defer/i.test(h))) deferred.push({ f, where: hits[0] });
  else dispatched++;
}

const bySeverity = (arr) => {
  const c = {};
  for (const x of arr) {
    const s = (x.severity || x.f?.severity || '?').toUpperCase();
    c[s] = (c[s] || 0) + 1;
  }
  return Object.entries(c).sort().map(([k, v]) => `${k} ${v}`).join(', ') || 'none';
};

console.log(
  `dispatch-covers-open-findings: ${open.length} OPEN finding(s) of every severity in ` +
  `${path.basename(verdictPath)} — ${dispatched} dispatched, ${deferred.length} deferred, ${unowned.length} unowned.`
);
if (deferred.length) {
  console.log(`  deferred (${bySeverity(deferred)}): named only under a heading matching /defer/i`);
  for (const d of deferred) console.log(`    - ${d.f.severity} ${d.f.fingerprint} — under "${d.where}"`);
}

if (open.length === 0) {
  console.log('  Nothing was open, so nothing is asserted about coverage — this pass was not earned on a population.');
  process.exit(0);
}

if (unowned.length > 0) {
  console.error(`  ${unowned.length} OPEN finding(s) are named nowhere in the brief (${bySeverity(unowned)}):`);
  for (const f of unowned) {
    console.error(
      `    - ${f.severity} ${f.fingerprint || `${f.path}:${f.line}`} [${f.specialist || '?'}] ` +
      `${(f.summary || '').slice(0, 84)}`
    );
  }
  console.error('  An unnamed finding has no owner: it is not blocked, not rejected, not in progress,');
  console.error('  and no state anywhere records that. Name it in the brief — as dispatched, as');
  console.error('  deliberately deferred under a "Deferred" heading with a reason, or as accepted.');
  console.error('  This gate covers EVERY severity: the tier below HIGH is where findings sit.');
  process.exit(1);
}

console.log('  Every OPEN finding is named. Naming is not fixing; this asserts only that none is unowned.');
process.exit(0);
