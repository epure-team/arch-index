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
// ── WHY THE MATCHER WAS REPLACED (R5-B) ────────────────────────────────────────────────
//
// The previous version owned a finding when a brief SECTION contained `finding.path` as a
// substring AND `String(finding.line)` as a substring — two independent substring searches,
// anywhere in the section, in any order, with nothing tying them to each other. That does
// not answer "does this finding have an owner". It answers "is this finding MENTIONED
// somewhere", and the two diverge exactly in the case the gate exists to catch: a group
// writing about work it did not do.
//
// MEASURED at 10f51bf, on this task's own corpus (29 OPEN non-scope findings):
//
//   - 23 findings counted as owned. SIX of those matched a fingerprint; SEVENTEEN matched
//     on nothing but the loose path+line pair.
//   - `checks/run-ratchet.js:1` was claimed by NINE different sections at once. An owner
//     that is nine sections is not an owner.
//   - `bin/arch_mutants/arch_mutants.ml:1` is a line-1 finding, so the "line" half was
//     satisfied by the digit `1` appearing anywhere at all — unconditionally, in every
//     section that names the file. Several findings in this verdict sit at line 1.
//   - A paragraph reading "I instrumented bin/arch_mutants/arch_mutants.ml and printed 1152
//     characters, then 2425, then 1378" — three OUTPUT SIZES — owns three unrelated findings
//     at lines 1152, 2425 and 1378 of that file.
//   - A section whose prose says a finding was looked at by nobody, was not fixed, and is
//     entirely unowned, quoting its fingerprint to say so, CLOSED that finding. Complaining
//     about a finding was a way of owning it.
//
// ── WHAT REPLACES IT, AND WHAT THAT IS AND IS NOT WORTH ────────────────────────────────
//
// Ownership is now claimed by an explicit RECORD, never by prose. The record grammar, one
// per line, outside fenced code blocks:
//
//   OWNER <fingerprint> | status=dispatched | commit=<sha> | check=<repo-relative path>
//   OWNER <fingerprint> | status=deferred   | reason=<why not now, >= 24 chars>
//   OWNER <fingerprint> | status=accepted   | reason=<why this is the end state, >= 24 chars>
//
// The fingerprint is matched by EXACT EQUALITY against the verdict, not by substring, so no
// coincidence of digits and paths can produce one.
//
// AN EXPLICIT FIELD ONLY CLOSES THE ACCIDENTAL HALF. It removes ownership claimed by a
// paragraph that happened to contain a path and a number. It does NOT stop an agent from
// writing an owner for work it did not do: a field written deliberately can be written
// falsely, by an agent under pressure to show coverage. So this gate makes ownership
// DELIBERATE, not VERIDICAL, and the distance between those two is the residual hole.
//
// What narrows that hole is the same thing that makes any assertion checkable: something
// OUTSIDE the claim that can contradict it. A `dispatched` record is therefore not believed
// on its own word. Both of its references are resolved against git:
//
//   commit=  must name a real commit object, which must be an ANCESTOR OF HEAD, and which
//            must touch either the finding's own path or the named check. A sha invented to
//            fill the field fails; a real sha that touched nothing relevant fails.
//   check=   must name a file that EXISTS and is TRACKED, under checks/, scripts/ or tezt/ —
//            somewhere the ratchet or the suite can actually reach it.
//
// A record that fails either resolution is NOT owned. It is reported as a record that could
// not be corroborated, which is a louder state than silence, and it still fires the gate.
//
// `deferred` and `accepted` name no commit and no check because nothing was done — that is
// their whole content — so they are corroborated by nothing and are the standing way to
// claim coverage without doing work. They are counted and listed SEPARATELY from closed
// findings for exactly that reason, and they carry an attributed reason a reader can dispute.
//
// TWO NUMBERS, NEVER ONE. This gate reports the old prose measure alongside the new record
// measure on every run. A reader who sees the unowned count jump does not have to guess
// whether the work regressed or the instrument changed; both counts are printed and the
// difference between them is named.
//
// Scope-category findings are excluded: the standing scope gate owns them.

'use strict';

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

// ── THE READING IS NAMED, AND ITS INPUTS ARE PARAMETERS ───────────────────────────────
//
// CONVENTION. Every number this file prints is stamped `record-v1`. The numbers printed by
// every version before it were produced under `mention-v0` — the two substring searches — and
// they are NOT comparable: `mention-v0` answers "is this finding mentioned somewhere". Three
// verdicts in this task's history carry `mention-v0` readings, including a round-4 line of
// "25 open, 19 dispatched, 6 deferred, 0 unowned". A stamp is the only thing that lets a
// reader of a mixed pile tell which rule produced which line.
//
// RE-DERIVABLE OVER PAST STATES. A corrected census of an earlier round means running THIS
// convention over THAT round's brief and verdict, which are not at HEAD and may not sit in a
// briefs/ directory at all. So the two inputs are explicit parameters and the git root is a
// third, independent one — a brief extracted with `git show <sha>:briefs/...` into a scratch
// directory still resolves its commits against the real repository:
//
//   node checks/dispatch-covers-open-findings.js [task] [root]
//   node checks/dispatch-covers-open-findings.js --brief=<path> --verdict=<path> [--repo=<path>]
//                                                [--json=<path>]
//
// MACHINE-READABLE, WITH THE GROUND OF EACH DECISION. `--json=<path>` (or the environment
// variable DISPATCH_OWNERSHIP_JSON) writes one row per OPEN finding carrying its state, the
// convention that produced it, WHAT ESTABLISHED IT (`established_by`), and the same two fields
// under the old convention (`mention_v0_state`, `mention_v0_established_by`). A re-derivation
// of a past round therefore produces a table that lines up against the old one row by row, and
// the rows that moved are readable as a set instead of as prose.

const CONVENTION = 'record-v1';
const LEGACY_CONVENTION = 'mention-v0';

const argv = process.argv.slice(2);
const flag = (name) => {
  const hit = argv.find((a) => a.startsWith(`--${name}=`));
  return hit ? hit.slice(name.length + 3) : null;
};
const positional = argv.filter((a) => !a.startsWith('--'));

const task = positional[0] || 'mutation-campaign-313';
const root = path.resolve(flag('repo') || positional[1] || process.cwd());
const verdictPath = path.resolve(flag('verdict') || path.join(root, 'briefs', `${task}-review.json`));
const briefPath = path.resolve(flag('brief') || path.join(root, 'briefs', `${task}-impl.md`));
const jsonOut = flag('json') || process.env.DISPATCH_OWNERSHIP_JSON || null;

const fatal = (msg) => {
  console.error(`dispatch-covers-open-findings: ${msg}`);
  process.exit(2);
};

for (const f of [verdictPath, briefPath]) {
  if (!fs.existsSync(f)) fatal(`${f} does not exist — nothing was measured, so nothing is asserted.`);
}

let review;
try {
  review = JSON.parse(fs.readFileSync(verdictPath, 'utf8'));
} catch (e) {
  fatal(`${verdictPath} is not readable JSON: ${e.message}`);
}
if (!Array.isArray(review.findings)) fatal('the verdict carries no findings array.');

const briefText = fs.readFileSync(briefPath, 'utf8');
const briefLines = briefText.split('\n');

// ── THE OLD MEASURE, KEPT VERBATIM SO THE TWO NUMBERS ARE COMPARABLE ────────────────────
// This is the previous matcher, unchanged, retained for reporting only. It decides nothing.
const sections = [];
{
  let heading = '(preamble)';
  let buf = [];
  for (const l of briefLines) {
    if (/^#{1,6}\s/.test(l)) {
      sections.push({ heading, body: buf.join('\n') });
      heading = l.replace(/^#{1,6}\s*/, '').trim();
      buf = [];
    } else buf.push(l);
  }
  sections.push({ heading, body: buf.join('\n') });
}
// It returns WHICH of its two grounds fired, per section, because that is the distinction a
// re-derivation of a past round turns on: a `mention-v0` ownership resting on a fingerprint is
// a different kind of claim from one resting on a path and a digit found separately, and the
// old output could not tell them apart.
const legacyMentions = (finding) => {
  const hits = [];
  for (const s of sections) {
    const byFingerprint = !!(finding.fingerprint && s.body.includes(finding.fingerprint));
    const bySite = !!(
      finding.path && s.body.includes(finding.path) && finding.line != null && s.body.includes(String(finding.line))
    );
    if (byFingerprint || bySite) hits.push({ heading: s.heading, byFingerprint, bySite });
  }
  return hits;
};

// ── THE RECORDS ─────────────────────────────────────────────────────────────────────────
// Lines inside fenced code blocks are skipped: the grammar is documented in this repository
// and in the brief itself, and a documentation example must not own a real finding. That is
// the same class of defect as the one this rewrite removes, one level up.
const STATUSES = new Set(['dispatched', 'deferred', 'accepted']);
const MIN_REASON = 24;
const records = [];
const malformed = [];
{
  let inFence = false;
  briefLines.forEach((line, i) => {
    if (/^\s*(```|~~~)/.test(line)) { inFence = !inFence; return; }
    if (inFence) return;
    const m = /^\s*(?:[-*+]\s*)?OWNER\s+(\S+)\s*\|\s*(.+?)\s*$/.exec(line);
    if (!m) return;
    const [, fingerprint, rest] = m;
    const fields = {};
    for (const part of rest.split('|')) {
      const kv = /^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$/.exec(part);
      if (kv) fields[kv[1].toLowerCase()] = kv[2];
    }
    const rec = { fingerprint, fields, lineNo: i + 1, raw: line.trim() };
    if (!STATUSES.has((fields.status || '').toLowerCase())) {
      malformed.push({ ...rec, why: `status must be one of ${[...STATUSES].join('/')}, got ${JSON.stringify(fields.status || '')}` });
      return;
    }
    rec.status = fields.status.toLowerCase();
    records.push(rec);
  });
}

// ── RESOLVING A RECORD'S REFERENCES AGAINST GIT ─────────────────────────────────────────
const git = (...args) => spawnSync('git', ['-C', root, ...args], { encoding: 'utf8' });
let gitUsable = null;
const ensureGit = () => {
  if (gitUsable !== null) return gitUsable;
  const r = git('rev-parse', '--git-dir');
  gitUsable = r.status === 0;
  return gitUsable;
};

const trackedCache = new Map();
const isTracked = (rel) => {
  if (trackedCache.has(rel)) return trackedCache.get(rel);
  const v = git('ls-files', '--error-unmatch', '--', rel).status === 0;
  trackedCache.set(rel, v);
  return v;
};
const commitTouches = new Map();
const filesOf = (sha) => {
  if (commitTouches.has(sha)) return commitTouches.get(sha);
  const r = git('diff-tree', '--no-commit-id', '--name-only', '-r', '--root', sha);
  const v = r.status === 0 ? r.stdout.split('\n').map((s) => s.trim()).filter(Boolean) : null;
  commitTouches.set(sha, v);
  return v;
};

// Returns [] when the record corroborates, or a list of the reasons it does not.
const corroborate = (rec, finding) => {
  const f = rec.fields;
  if (rec.status !== 'dispatched') {
    const reason = f.reason || '';
    if (reason.length < MIN_REASON) {
      return [`status=${rec.status} needs reason=<...> of at least ${MIN_REASON} characters (got ${reason.length})`];
    }
    return [];
  }
  const problems = [];
  const sha = (f.commit || '').trim();
  const check = (f.check || '').trim();
  if (!sha) problems.push('status=dispatched needs commit=<sha>: a closure names the commit that closed it');
  if (!check) problems.push('status=dispatched needs check=<path>: a closure names the check that holds it closed');
  if (problems.length) return problems;

  if (!ensureGit()) {
    fatal(
      `${root} is not a git repository, and ${records.length} ownership record(s) name commits that must be\n` +
      `  resolved there. Nothing can be corroborated, so nothing is asserted rather than passed.`
    );
  }

  // check=: exists, tracked, and somewhere a runner can reach.
  if (!/^(checks|scripts|tezt)\//.test(check)) {
    problems.push(`check=${check} is not under checks/, scripts/ or tezt/ — nothing runs it`);
  } else if (!fs.existsSync(path.join(root, check))) {
    problems.push(`check=${check} does not exist in the tree`);
  } else if (!isTracked(check)) {
    problems.push(`check=${check} exists but is UNTRACKED — it is not part of what anyone else gets`);
  }

  // commit=: real, an ancestor of HEAD, and touching something this closure could be about.
  if (!/^[0-9a-fA-F]{7,40}$/.test(sha)) {
    problems.push(`commit=${sha} is not a sha`);
  } else if (git('rev-parse', '--verify', '--quiet', `${sha}^{commit}`).status !== 0) {
    problems.push(`commit=${sha} names no commit object in this repository`);
  } else if (git('merge-base', '--is-ancestor', sha, 'HEAD').status !== 0) {
    problems.push(`commit=${sha} is not an ancestor of HEAD — it is not in the history this tree ships`);
  } else {
    const touched = filesOf(sha);
    if (!touched) problems.push(`commit=${sha} could not be diffed`);
    else if (!touched.includes(finding.path) && !touched.includes(check)) {
      problems.push(
        `commit=${sha} touches neither ${finding.path} (the finding) nor ${check} (the check) — ` +
        `it touched ${touched.length} file(s), none of them relevant`
      );
    }
  }
  return problems;
};

// ── CLASSIFY ────────────────────────────────────────────────────────────────────────────
const open = review.findings
  .filter((f) => (f.status || 'OPEN') === 'OPEN')
  .filter((f) => (f.category || '') !== 'scope');

const byFingerprint = new Map();
for (const r of records) {
  if (!byFingerprint.has(r.fingerprint)) byFingerprint.set(r.fingerprint, []);
  byFingerprint.get(r.fingerprint).push(r);
}

const classified = [];
for (const f of open) {
  const legacyHits = legacyMentions(f);
  const legacyOwned = legacyHits.length > 0;
  const anyFingerprint = legacyHits.some((h) => h.byFingerprint);
  const anySiteOnly = legacyHits.some((h) => h.bySite && !h.byFingerprint);
  const recs = byFingerprint.get(f.fingerprint) || [];
  const entry = {
    fingerprint: f.fingerprint,
    severity: f.severity,
    path: f.path,
    line: f.line,
    convention: CONVENTION,
    mention_v0_state: legacyOwned
      ? (legacyHits.every((h) => /defer/i.test(h.heading)) ? 'DEFERRED' : 'DISPATCHED')
      : 'UNOWNED',
    mention_v0_established_by: !legacyOwned
      ? 'nothing'
      : anyFingerprint && anySiteOnly
        ? 'fingerprint-substring+path-and-line-substrings'
        : anyFingerprint
          ? 'fingerprint-substring'
          : 'path-and-line-substrings',
    mention_v0_sections: legacyHits.map((h) => h.heading),
  };
  if (recs.length === 0) {
    entry.state = 'UNOWNED';
    entry.established_by = legacyOwned ? 'prose-mention-only' : 'nothing';
    entry.why = legacyOwned
      ? `MENTIONED ONLY — prose in ${legacyHits.length} section(s) matched it by ${entry.mention_v0_established_by}, no OWNER record claims it`
      : 'no OWNER record, and no prose matched it either';
  } else if (recs.length > 1) {
    entry.state = 'UNOWNED';
    entry.established_by = 'conflicting-owner-records';
    entry.why = `${recs.length} conflicting OWNER records (brief lines ${recs.map((r) => r.lineNo).join(', ')}) — contradictory ownership is no ownership`;
  } else {
    const rec = recs[0];
    const problems = corroborate(rec, f);
    if (problems.length) {
      entry.state = 'UNOWNED';
      entry.established_by = 'owner-record-not-corroborated';
      entry.why = `OWNER record at brief line ${rec.lineNo} could not be corroborated: ${problems.join('; ')}`;
      entry.record = rec.raw;
    } else if (rec.status === 'dispatched') {
      entry.state = 'CLOSED';
      entry.established_by = 'owner-record+commit-resolved+check-resolved';
      entry.commit = rec.fields.commit;
      entry.check = rec.fields.check;
    } else {
      entry.state = rec.status.toUpperCase();
      entry.established_by = `owner-record:${rec.status}+reason-only`;
      entry.reason = rec.fields.reason;
    }
  }
  classified.push(entry);
}

const closed = classified.filter((c) => c.state === 'CLOSED');
const deferred = classified.filter((c) => c.state === 'DEFERRED');
const accepted = classified.filter((c) => c.state === 'ACCEPTED');
const unowned = classified.filter((c) => c.state === 'UNOWNED');
const legacyOwnedCount = classified.filter((c) => c.mention_v0_state !== 'UNOWNED').length;

// The classification is computed ONCE and drives both this file and the exit code, so a
// reader of the file is reading the thing that decided, not a second rendering of it.
if (jsonOut) {
  fs.writeFileSync(
    jsonOut,
    JSON.stringify(
      {
        convention: CONVENTION,
        legacy_convention: LEGACY_CONVENTION,
        produced_at: new Date().toISOString(),
        task,
        repo: root,
        brief: briefPath,
        verdict: verdictPath,
        open: open.length,
        record_v1: { closed: closed.length, deferred: deferred.length, accepted: accepted.length, unowned: unowned.length },
        mention_v0: { owned: legacyOwnedCount, unowned: open.length - legacyOwnedCount },
        findings: classified,
      },
      null, 2
    ) + '\n'
  );
}

const bySeverity = (arr) => {
  const c = {};
  for (const x of arr) c[(x.severity || '?').toUpperCase()] = (c[(x.severity || '?').toUpperCase()] || 0) + 1;
  return Object.entries(c).sort().map(([k, v]) => `${k} ${v}`).join(', ') || 'none';
};

console.log(
  `dispatch-covers-open-findings [convention ${CONVENTION}]: ${open.length} OPEN finding(s) of every ` +
  `severity — ${closed.length} closed, ${deferred.length} deferred, ${accepted.length} accepted, ` +
  `${unowned.length} unowned.`
);
console.log(`  verdict: ${verdictPath}`);
console.log(`  brief:   ${briefPath}`);
console.log(`  repo:    ${root} (where commit= is resolved)`);
console.log(
  `  A reading of this gate that is not stamped ${CONVENTION} was produced under ${LEGACY_CONVENTION} and\n` +
  `  does not answer the same question. Both are printed below.`
);
console.log(`  ${records.length} OWNER record(s) parsed from the brief; ${malformed.length} malformed.`);
for (const m of malformed) console.log(`    ! brief line ${m.lineNo}: ${m.why}`);

const orphans = [...byFingerprint.keys()].filter((fp) => !open.some((f) => f.fingerprint === fp));
if (orphans.length) {
  console.log(`  ${orphans.length} OWNER record(s) name a fingerprint that is not an OPEN non-scope finding:`);
  for (const o of orphans) console.log(`    ? ${o}`);
}

// TWO NUMBERS, NEVER ONE.
console.log('');
console.log('  THE MEASURE OF OWNERSHIP CHANGED — both numbers, so a reader can tell an instrument');
console.log('  change from a work change:');
console.log(`    ${LEGACY_CONVENTION}: a section containing the path and the line as separate substrings,`);
console.log(`                or the fingerprint as a substring    -> ${legacyOwnedCount} owned, ${open.length - legacyOwnedCount} unowned`);
console.log(`    ${CONVENTION}:  an OWNER line whose commit and check resolve against git`);
console.log(`                                                    -> ${closed.length + deferred.length + accepted.length} owned, ${unowned.length} unowned`);
const delta = legacyOwnedCount - (closed.length + deferred.length + accepted.length);
if (delta !== 0) {
  console.log(
    `    ${delta > 0 ? delta : -delta} finding(s) ${delta > 0 ? 'that a MENTION owned and a RECORD does not' : 'that a RECORD owns and no MENTION did'}. ` +
    `The work did not change here; what counts as ownership did.`
  );
}
console.log('');

if (closed.length) {
  console.log(`  closed (${bySeverity(closed)}) — each names a commit in this history and a check that exists:`);
  for (const c of closed) console.log(`    - ${c.severity} ${c.fingerprint} — ${c.commit} / ${c.check}`);
}
if (deferred.length) {
  console.log(`  deferred (${bySeverity(deferred)}) — claimed, not done, corroborated by nothing but the reason given:`);
  for (const d of deferred) console.log(`    - ${d.severity} ${d.fingerprint} — ${(d.reason || '').slice(0, 100)}`);
}
if (accepted.length) {
  console.log(`  accepted (${bySeverity(accepted)}) — claimed as the end state, corroborated by nothing but the reason given:`);
  for (const a of accepted) console.log(`    - ${a.severity} ${a.fingerprint} — ${(a.reason || '').slice(0, 100)}`);
}

if (open.length === 0) {
  console.log('  Nothing was open, so nothing is asserted about coverage — this pass was not earned on a population.');
  process.exit(0);
}

if (unowned.length > 0) {
  console.error(`  ${unowned.length} OPEN finding(s) have no corroborated owner (${bySeverity(unowned)}):`);
  for (const u of unowned) {
    console.error(`    - ${u.severity} ${u.fingerprint}`);
    console.error(`        ${u.why}`);
  }
  console.error('');
  console.error('  An unowned finding is not blocked, not rejected, not in progress, and no state anywhere');
  console.error('  records that. Claim it with an OWNER line in the brief:');
  console.error('    OWNER <fingerprint> | status=dispatched | commit=<sha> | check=<path under checks|scripts|tezt>');
  console.error('    OWNER <fingerprint> | status=deferred   | reason=<why not now>');
  console.error('    OWNER <fingerprint> | status=accepted   | reason=<why this is the end state>');
  console.error('  A MENTION IS NOT AN OWNER. Writing a paragraph about a finding — including a paragraph');
  console.error('  saying nobody has looked at it — no longer closes it. Neither does a number that happens');
  console.error('  to equal its line. This gate covers EVERY severity: the tier below HIGH is where findings sit.');
  process.exit(1);
}

console.log('  Every OPEN finding carries a corroborated OWNER record. A record is DELIBERATE, not');
console.log('  VERIDICAL: a commit and a check that resolve prove someone pointed at real history, not');
console.log('  that the finding is fixed. Deferred and accepted are claims with a reason and nothing else.');
process.exit(0);
