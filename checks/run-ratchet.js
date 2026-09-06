#!/usr/bin/env node
// checks/run-ratchet.js — run the ratchet, classify what came back, and be runnable by the
// two things that need to run it. `node checks/run-ratchet.js [--list] [root]`.
//
// Exit convention: 0 = every check that ran passed · 1 = a check ASSERTED · >=2 = a check
// could not run, or this runner found nothing to run.
//
// WHY THIS EXISTS — TWO FINDINGS, ONE MECHANISM.
//
// First: the ratchet was wired into nothing. CI ran `dune build` and `dune test`; no workflow
// step, no dune rule and no script referenced `checks/` or `scripts/check-*`. Every check in
// this campaign was therefore a file someone had to remember to run, which is the state a
// ratchet exists to leave. Measured, not assumed: `grep -n 'scripts/check' .github/workflows/
// ci.yml` returned nothing, and so did `grep -rn checks --include=dune .`.
//
// Second: the review-convergence gate resolves a linked check as `node <path>`. Nine of the
// eleven checks are bash, so `node checks/no-score-scans-sql-strings.sh` died on line 2 and the
// gate recorded six `green-failure` violations for six checks that all exit 0 under bash. The
// gate could neither green- nor red-verify any of them. This file is node, so ONE gate link
// reaches the whole ratchet; that is a narrower answer than nine node shims and an honest one,
// because a link to this path really does execute every check behind it.
//
// WHY A CI STEP AND NOT A TEZT PORT. The repository did migrate a standalone check into tezt
// once — tezt/tests/must_null_ceiling.ml records it — and that was right THERE: the ceiling is
// a query over the index database, and OCaml is where the database already is. It is wrong
// here, for two reasons that are properties of these checks rather than preferences.
//
//   1. Several of them assert on the behaviour of SHELL ARTEFACTS: that scripts/mutaml-
//      wrapper.sh exits exactly 99 on every refusal path, that scripts/check-no-score.sh's
//      scanner sees past a SQL literal, that the tree-boundary guard refuses from a
//      subdirectory of a foreign checkout. Rewriting those in OCaml replaces the artefact
//      under test with a reimplementation of it, which is the oldest way to build a test that
//      cannot fail.
//   2. Their exit vocabulary is wider than pass/fail and the extra width is the point. 3 means
//      "the callee declined to answer" — an integration that was NOT exercised, which this
//      branch spends its exit codes keeping apart from one that was exercised and failed.
//      Tezt has one failure, so a port collapses 2 and 3 into it and destroys exactly the
//      distinction the campaign is built on.
//
// TWO TIERS, because the checks answer to different preconditions and one rule for both would
// be a lie in one direction or the other.
//
//   ratchet  (checks/*)        Self-contained: each builds whatever fixture it needs. There is
//                              no configuration in which one of these legitimately cannot run,
//                              so >=2 here is a broken check and is FATAL.
//   campaign (scripts/check-*) Population-dependent: they want a campaign database, a git
//                              range, a review verdict, an installed mutation engine. A bare CI
//                              clone has none of those, and the scripts say so with 2 or 3
//                              rather than pretending. Those are reported as UNRUN and are not
//                              fatal. An ASSERTION (1) is fatal in both tiers — a check that
//                              ran and said no is the signal the whole ratchet is for.
//
// The one thing this runner must never do is pass by running nothing, so an empty tier is exit
// 2 and the counts are printed whether or not anything failed.

'use strict';

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const argv = process.argv.slice(2);
const listOnly = argv.includes('--list');
const root = argv.find((a) => !a.startsWith('--')) || path.resolve(__dirname, '..');

const SELF = path.basename(__filename);
const PER_CHECK_TIMEOUT_MS = 15 * 60 * 1000;

const discover = (dir, pattern) => {
  const abs = path.join(root, dir);
  if (!fs.existsSync(abs)) return [];
  return fs
    .readdirSync(abs)
    .filter((f) => pattern.test(f) && f !== SELF)
    .sort()
    .map((f) => path.join(dir, f));
};

const tiers = [
  { name: 'ratchet', fatalUnrun: true, files: discover('checks', /\.(sh|js)$/) },
  { name: 'campaign', fatalUnrun: false, files: discover('scripts', /^check-.*\.(sh|js)$/) },
];

if (listOnly) {
  for (const t of tiers) for (const f of t.files) console.log(`${t.name}\t${f}`);
  process.exit(tiers.every((t) => t.files.length > 0) ? 0 : 2);
}

for (const t of tiers) {
  if (t.files.length === 0) {
    console.error(
      `run-ratchet: the ${t.name} tier is EMPTY. A runner that runs nothing passes everything, ` +
        `which is the failure this file exists to remove.`
    );
    process.exit(2);
  }
}

// Campaign-tier checks are population-dependent: each one's own Usage: comment names the path
// it needs (a review.json, a qa-state.json, a manifest). The repository's own documented
// convention for those paths — .claude/commands/roster-review.md, roster-qa.md,
// roster-implement.md — is briefs/<task>-{review.json,qa-state.json,manifest.txt}, where
// <task> is the content of briefs/ACTIVE_TASK. Running these with NO argument at all never
// exercises the precondition they document: it only makes them print their own usage line,
// which reads like "declined to run" but is really "never asked to do anything".
const ACTIVE_TASK_FILE = path.join(root, 'briefs', 'ACTIVE_TASK');
const activeTask = fs.existsSync(ACTIVE_TASK_FILE)
  ? fs.readFileSync(ACTIVE_TASK_FILE, 'utf8').trim()
  : null;

const REQUIRED_ARG_BY_BASENAME = activeTask
  ? {
      'check-review-convergence.js': path.join('briefs', `${activeTask}-review.json`),
      'check-qa-convergence.js': path.join('briefs', `${activeTask}-qa-state.json`),
      'check-scope-diff.sh': path.join('briefs', `${activeTask}-manifest.txt`),
    }
  : {};

const extraArgsFor = (rel) => {
  const arg = REQUIRED_ARG_BY_BASENAME[path.basename(rel)];
  return arg ? [arg] : [];
};

const runOne = (rel) => {
  const abs = path.join(root, rel);
  const extra = extraArgsFor(rel);
  const argv0 = rel.endsWith('.js') ? process.execPath : '/usr/bin/env';
  const args = rel.endsWith('.js') ? [abs, ...extra] : ['bash', abs, ...extra];
  const r = spawnSync(argv0, args, {
    cwd: root,
    encoding: 'utf8',
    timeout: PER_CHECK_TIMEOUT_MS,
    maxBuffer: 64 * 1024 * 1024,
  });
  if (r.error && r.error.code === 'ETIMEDOUT') return { code: 2, out: `timed out after ${PER_CHECK_TIMEOUT_MS} ms` };
  if (r.error) return { code: 2, out: String(r.error.message) };
  return { code: r.status == null ? 2 : r.status, out: `${r.stdout || ''}${r.stderr || ''}` };
};

const asserted = [];
const broken = [];
const unrun = [];
let passed = 0;

for (const t of tiers) {
  console.log(`\n── ${t.name} tier: ${t.files.length} check(s)`);
  for (const rel of t.files) {
    const { code, out } = runOne(rel);
    let verdict;
    if (code === 0) {
      verdict = 'PASS';
      passed++;
    } else if (code === 1) {
      verdict = 'ASSERTED';
      asserted.push({ rel, code, out });
    } else if (!t.fatalUnrun) {
      verdict = code === 3 ? 'REFUSED (3)' : `UNRUN (${code})`;
      unrun.push({ rel, code, out });
    } else {
      verdict = `HARNESS ERROR (${code})`;
      broken.push({ rel, code, out });
    }
    console.log(`  ${verdict.padEnd(20)} ${rel}`);
  }
}

const dump = (label, xs) => {
  if (!xs.length) return;
  console.log(`\n${label}`);
  for (const x of xs) {
    console.log(`\n  ── ${x.rel} (exit ${x.code})`);
    for (const line of x.out.replace(/\s+$/, '').split('\n')) console.log(`    ${line}`);
  }
};

console.log(
  `\nrun-ratchet: ${passed} passed, ${asserted.length} asserted, ${broken.length} harness error(s), ` +
    `${unrun.length} not run.`
);

dump('NOT RUN — reported, not counted as a pass. Each names its own precondition:', unrun);
dump('HARNESS ERRORS — a check in the self-contained tier could not run:', broken);
dump('ASSERTIONS — a check ran and said no:', asserted);

if (asserted.length) {
  console.error('\nrun-ratchet: FAIL — a ratchet assertion fired. That is a regression, not a setup problem.');
  process.exit(1);
}
if (broken.length) {
  console.error(
    '\nrun-ratchet: ERROR — a self-contained check could not run. Nothing is asserted about what it\n' +
      '  covers, so this is exit 2 and not a failure: fix the check, then re-read the verdict.'
  );
  process.exit(2);
}
console.log('run-ratchet: PASS — every check that could run, ran, and none asserted.');
process.exit(0);
