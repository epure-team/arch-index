#!/usr/bin/env node
// checks/ownership-is-a-record-not-a-mention.js — runnable directly: `node <path>`.
//
// Exit convention: 0 = passes · 1 = assertion fired · >=2 = error/setup failure.
//
// WHAT THIS HOLDS CLOSED. `checks/dispatch-covers-open-findings.js` decided ownership by two
// INDEPENDENT SUBSTRING SEARCHES over a brief section — `body.includes(finding.path)` and
// `body.includes(String(finding.line))` — with nothing binding the two to each other or to a
// claim of having done anything. Two shapes measured in this repository's own brief at
// 10f51bf are reproduced here as fixtures, byte-for-byte in kind:
//
//   PROBE A — NUMBERS USED AS OUTPUT SIZES. A paragraph that says "I instrumented
//     bin/arch_mutants/arch_mutants.ml and printed 1152 characters, then 2425, then 1378"
//     owned three unrelated findings at lines 1152, 2425 and 1378 of that file. Nothing in
//     that sentence is a line number and nothing in it claims a fix.
//
//   PROBE B — A COMPLAINT CLOSES A FINDING. A section whose prose says a finding was looked
//     at by nobody, was not fixed, and remains entirely unowned — quoting its fingerprint in
//     order to say so — was counted as that finding's owner.
//
// Both were PASSES under the old matcher and are REDS here. That is the whole claim, and it
// is falsifiable in the only way that matters: revert dispatch-covers-open-findings.js to
// 10f51bf and probes A and B go green while this check goes red.
//
//   PROBE F — the grammar, quoted inside a fenced code block as documentation, must own
//     nothing. A fix whose own documentation establishes ownership has reproduced its defect
//     one level up. The old matcher owned it: the example line carries the fingerprint.
//
//   PROBE C — THE ANTI-VACUITY CONTROL, and this check is worth nothing without it. A gate
//     that answered UNOWNED to everything would satisfy A and B. C is a well-formed record
//     naming a real commit that touches the finding, and a tracked check file, and it must
//     PASS. Without C, A and B are a green earned by refusing to answer.
//
//   PROBE D — an invented sha. The record is well-formed and deliberate and names a commit
//     that does not exist. It must NOT own.
//   PROBE E — a real commit that touched neither the finding's file nor the named check. The
//     record is well-formed, deliberate, and points at real history that has nothing to do
//     with the claim. It must NOT own.
//
// D and E are the ones that say something about DELIBERATE ownership rather than accidental
// ownership. They do not make a record TRUE — an agent can still name a commit that really
// did touch the file and claim a fix it did not make. They make the record COST something
// outside itself.

'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const GATE = path.join(__dirname, 'dispatch-covers-open-findings.js');
const TASK = 'ownership-fixture';

const fatal = (msg) => { console.error(`ownership-is-a-record: ${msg}`); process.exit(2); };

if (!fs.existsSync(GATE)) fatal(`${GATE} does not exist — there is nothing to hold closed.`);
if (spawnSync('git', ['--version']).status !== 0) fatal('git is not on PATH; every probe needs a fixture repository.');

const W = fs.mkdtempSync(path.join(os.tmpdir(), 'ownership-record.'));
process.on('exit', () => { try { fs.rmSync(W, { recursive: true, force: true }); } catch (_) {} });

// A probe that lands inside a real checkout would resolve shas against THAT repository, and
// probes D and E would then be measuring the wrong history. Asserted, not assumed.
if (spawnSync('git', ['rev-parse', '--show-toplevel'], { cwd: W, encoding: 'utf8' }).status === 0) {
  fatal(`${W} is inside a git repository — probes C, D and E would resolve against it. Set TMPDIR outside a checkout.`);
}

const FINDING_FILE = 'bin/arch_mutants/arch_mutants.ml';
const CHECK_FILE = 'checks/fixture-check.js';

// Builds a fixture repository: the file the findings point into, a tracked check file, and
// one commit that touches both — that commit is the only honest `commit=` in these probes.
const makeRepo = (name) => {
  const dir = path.join(W, name);
  fs.mkdirSync(path.join(dir, path.dirname(FINDING_FILE)), { recursive: true });
  fs.mkdirSync(path.join(dir, 'checks'), { recursive: true });
  fs.mkdirSync(path.join(dir, 'briefs'), { recursive: true });
  fs.mkdirSync(path.join(dir, 'docs'), { recursive: true });
  for (const a of [['init', '-q', '.'], ['config', 'user.email', 'f@x.t'], ['config', 'user.name', 'fixture'],
                   ['config', 'commit.gpgsign', 'false']]) {
    if (spawnSync('git', a, { cwd: dir }).status !== 0) fatal(`git ${a.join(' ')} failed in ${dir}`);
  }
  fs.writeFileSync(path.join(dir, FINDING_FILE), '(* fixture *)\nlet () = ()\n');
  fs.writeFileSync(path.join(dir, CHECK_FILE), '#!/usr/bin/env node\nprocess.exit(0);\n');
  const commit = (msg) => {
    if (spawnSync('git', ['add', '-A'], { cwd: dir }).status !== 0) fatal(`git add failed in ${dir}`);
    if (spawnSync('git', ['commit', '-q', '-m', msg], { cwd: dir }).status !== 0) fatal(`git commit failed in ${dir}`);
    const r = spawnSync('git', ['rev-parse', 'HEAD'], { cwd: dir, encoding: 'utf8' });
    if (r.status !== 0) fatal(`git rev-parse failed in ${dir}`);
    return r.stdout.trim();
  };
  const relevantSha = commit('fixture: the finding file and the check');
  fs.writeFileSync(path.join(dir, 'docs', 'unrelated.md'), 'nothing to do with the finding\n');
  const irrelevantSha = commit('fixture: an unrelated file');
  return { dir, relevantSha, irrelevantSha, commit };
};

const writeCorpus = (dir, findings, briefBody) => {
  fs.writeFileSync(
    path.join(dir, 'briefs', `${TASK}-review.json`),
    JSON.stringify({ task: TASK, findings }, null, 2) + '\n'
  );
  fs.writeFileSync(path.join(dir, 'briefs', `${TASK}-impl.md`), briefBody);
};

const finding = (p, line, category, severity, summary) => ({
  fingerprint: `${p}:${line}:${category}`,
  path: p, line, category, severity, status: 'OPEN', specialist: 'fixture', summary,
});

const runGate = (dir) => {
  const jsonPath = path.join(dir, 'ownership.json');
  const r = spawnSync(process.execPath, [GATE, TASK, dir], {
    cwd: dir, encoding: 'utf8', env: { ...process.env, DISPATCH_OWNERSHIP_JSON: jsonPath },
  });
  if (r.error) fatal(`could not run the gate: ${r.error.message}`);
  let json = null;
  if (fs.existsSync(jsonPath)) { try { json = JSON.parse(fs.readFileSync(jsonPath, 'utf8')); } catch (_) { json = null; } }
  return { code: r.status == null ? 2 : r.status, out: `${r.stdout || ''}${r.stderr || ''}`, json };
};

let fails = 0;
const check = (label, ok, detail) => {
  if (ok) console.log(`  ✓ ${label}`);
  else { console.log(`  ✗ ${label} — ${detail}`); fails++; }
};

// ── PROBE A — three numbers used as output sizes ────────────────────────────────────────
{
  console.log('probe A — a paragraph reporting three OUTPUT SIZES over a file three findings live in');
  const { dir } = makeRepo('probe-a');
  const fs_ = [
    finding(FINDING_FILE, 1152, 'architecture', 'LOW', 'a nested dune-project'),
    finding(FINDING_FILE, 2425, 'architecture', 'LOW', 'an identity-bearing hashtable'),
    finding(FINDING_FILE, 1378, 'correctness', 'HIGH', "the round's own fix reopened the defect"),
  ];
  writeCorpus(dir, fs_, [
    '# Implementation Brief — ownership fixture', '',
    '## Group Z — outcome', '',
    'To find out what the driver was emitting I instrumented `bin/arch_mutants/arch_mutants.ml`',
    'and printed the buffer at three points: 1152 characters, then 2425, then 1378. The three',
    'sizes are the reason the second pass was added; none of them is a line number and none of',
    'them is a claim that anything was fixed.', '',
  ].join('\n'));
  const r = runGate(dir);
  check('the gate fires (exit 1) instead of counting three output sizes as three owners',
    r.code === 1, `exit ${r.code}\n${r.out}`);
  for (const f of fs_) {
    const st = r.json && r.json.findings.find((x) => x.fingerprint === f.fingerprint);
    check(`${f.fingerprint} is UNOWNED`, !!st && st.state === 'UNOWNED',
      st ? `state=${st.state}` : 'the gate emitted no classification for it');
  }
}

// ── PROBE B — a complaint closes a finding ──────────────────────────────────────────────
{
  console.log('probe B — a section whose prose says the finding is unowned, quoting its fingerprint');
  const { dir } = makeRepo('probe-b');
  const f = finding('checks/dispatch-covers-open-findings.js', 80, 'gate-vacuous', 'HIGH', 'ownership is verbal');
  writeCorpus(dir, [f], [
    '# Implementation Brief — ownership fixture', '',
    '## Round 6 — what nobody did', '',
    'Nobody looked at this one. It was not dispatched, it was not fixed, no group took it, and',
    'it remains entirely unowned at the end of the round. Recording it here so the next round',
    `starts from the truth: \`${f.fingerprint}\`.`, '',
  ].join('\n'));
  const r = runGate(dir);
  check('the gate fires (exit 1) instead of letting a complaint close the finding it complains about',
    r.code === 1, `exit ${r.code}\n${r.out}`);
  const st = r.json && r.json.findings.find((x) => x.fingerprint === f.fingerprint);
  check(`${f.fingerprint} is UNOWNED`, !!st && st.state === 'UNOWNED',
    st ? `state=${st.state}` : 'the gate emitted no classification for it');
}

// ── PROBE C — the anti-vacuity control ──────────────────────────────────────────────────
{
  console.log('probe C — a corroborated record MUST own, or A and B are a green earned by refusing to answer');
  const { dir, relevantSha } = makeRepo('probe-c');
  const f = finding(FINDING_FILE, 1378, 'correctness', 'HIGH', "the round's own fix reopened the defect");
  writeCorpus(dir, [f], [
    '# Implementation Brief — ownership fixture', '',
    '## Group Z — outcome', '',
    `OWNER ${f.fingerprint} | status=dispatched | commit=${relevantSha} | check=${CHECK_FILE} | by=Z`, '',
  ].join('\n'));
  const r = runGate(dir);
  check('the gate passes (exit 0) on a record whose commit and check both resolve',
    r.code === 0, `exit ${r.code}\n${r.out}`);
  const st = r.json && r.json.findings.find((x) => x.fingerprint === f.fingerprint);
  check(`${f.fingerprint} is CLOSED`, !!st && st.state === 'CLOSED',
    st ? `state=${st.state} (${st.why || ''})` : 'the gate emitted no classification for it');
}

// ── PROBE D — an invented sha ───────────────────────────────────────────────────────────
{
  console.log('probe D — a deliberate record naming a commit that does not exist');
  const { dir } = makeRepo('probe-d');
  const f = finding(FINDING_FILE, 1378, 'correctness', 'HIGH', "the round's own fix reopened the defect");
  writeCorpus(dir, [f], [
    '# Implementation Brief — ownership fixture', '',
    '## Group Z — outcome', '',
    `OWNER ${f.fingerprint} | status=dispatched | commit=${'0'.repeat(40)} | check=${CHECK_FILE} | by=Z`, '',
  ].join('\n'));
  const r = runGate(dir);
  check('the gate fires (exit 1) on a sha that names no commit', r.code === 1, `exit ${r.code}\n${r.out}`);
  const st = r.json && r.json.findings.find((x) => x.fingerprint === f.fingerprint);
  check(`${f.fingerprint} is UNOWNED`, !!st && st.state === 'UNOWNED',
    st ? `state=${st.state}` : 'the gate emitted no classification for it');
}

// ── PROBE E — a real commit that touched nothing relevant ───────────────────────────────
{
  console.log('probe E — a deliberate record naming a real commit that touched neither the finding nor the check');
  const { dir, irrelevantSha } = makeRepo('probe-e');
  const f = finding(FINDING_FILE, 1378, 'correctness', 'HIGH', "the round's own fix reopened the defect");
  writeCorpus(dir, [f], [
    '# Implementation Brief — ownership fixture', '',
    '## Group Z — outcome', '',
    `OWNER ${f.fingerprint} | status=dispatched | commit=${irrelevantSha} | check=${CHECK_FILE} | by=Z`, '',
  ].join('\n'));
  const r = runGate(dir);
  check('the gate fires (exit 1) on a real commit that touched neither the finding nor the check',
    r.code === 1, `exit ${r.code}\n${r.out}`);
  const st = r.json && r.json.findings.find((x) => x.fingerprint === f.fingerprint);
  check(`${f.fingerprint} is UNOWNED`, !!st && st.state === 'UNOWNED',
    st ? `state=${st.state}` : 'the gate emitted no classification for it');
}

// ── PROBE F — a record inside a fenced code block ───────────────────────────────────────
//
// This grammar is documented in prose, in this repository and in the brief the gate reads, and
// a documented example carries a real-looking fingerprint. If a fenced example owned a finding,
// the fix would have reproduced its own defect one level up: writing ABOUT ownership would
// establish ownership. The old matcher did exactly that — the example line contains the
// fingerprint, which was one of its two grounds.
{
  console.log('probe F — the grammar documented inside a fenced code block must own nothing');
  const { dir, relevantSha } = makeRepo('probe-f');
  const f = finding(FINDING_FILE, 1378, 'correctness', 'HIGH', "the round's own fix reopened the defect");
  writeCorpus(dir, [f], [
    '# Implementation Brief — ownership fixture', '',
    '## How to claim a finding', '',
    'A closure names the commit that closed it and the check that holds it closed:', '',
    '```',
    `OWNER ${f.fingerprint} | status=dispatched | commit=${relevantSha} | check=${CHECK_FILE}`,
    '```', '',
    'That is documentation. Nothing above was done.', '',
  ].join('\n'));
  const r = runGate(dir);
  check('the gate fires (exit 1) on a record that is only an example', r.code === 1, `exit ${r.code}\n${r.out}`);
  const st = r.json && r.json.findings.find((x) => x.fingerprint === f.fingerprint);
  check(`${f.fingerprint} is UNOWNED`, !!st && st.state === 'UNOWNED',
    st ? `state=${st.state}` : 'the gate emitted no classification for it');
}

console.log('');
if (fails > 0) {
  console.error(`ownership-is-a-record-not-a-mention: ${fails} assertion(s) failed.`);
  console.error('  Ownership has fallen back to being a MENTION. A paragraph that happens to contain a');
  console.error('  path and a number, or a paragraph that complains a finding is unowned, is closing it.');
  process.exit(1);
}
console.log('ownership-is-a-record-not-a-mention: 6 probes, every assertion held.');
console.log('  A mention does not own; a record whose commit and check do not resolve does not own;');
console.log('  a record whose commit and check DO resolve owns. That makes ownership deliberate and');
console.log('  externally referenced. It does NOT make it true: probe C would pass just as well for a');
console.log('  group that named a real commit and did no work in it.');
process.exit(0);
