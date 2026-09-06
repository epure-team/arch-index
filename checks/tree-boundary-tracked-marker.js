#!/usr/bin/env node
// checks/tree-boundary-tracked-marker.js — runnable directly: `node <path> [repo]`.
//
// Exit convention: 0 = passes · 1 = assertion fired · >=2 = error/setup failure.
//
// LABEL: this is a RULE, not a regression test. It does not pin the one cwd that motivated
// it; it pins the PROPERTY that decides FR-030's boundary — a `dune-project` narrows the
// boundary only when it identifies a checkout the enclosing git repository does not own —
// and it pins that property in BOTH directions plus on the TEXT of the diagnosis. The
// motivating input (this repository's own poc/decision-lint) is probe 4, and it is the
// probe this check could most afford to lose.
//
// WHY THIS EXISTS. FR-030's guard was repaired by anchoring on the NEARER of the git
// toplevel and the nearest `dune-project` above the working directory, chosen by path
// length. Nothing tested whether that marker identified a DIFFERENT checkout. A repository
// that carries a nested, git-TRACKED `dune-project` — this one carries
// poc/decision-lint/dune-project — therefore shrinks its own boundary to that subdirectory
// whenever the command is run from inside it, refuses the repository's OWN wrapper, and
// says the wrapper "belongs to a different tree". Both halves are wrong: the verdict is a
// legitimate invocation refused, and the diagnosis is false — git tracks both paths and
// says so.
//
// A boundary guard fails in three distinct ways, and a fix that treats one of them is the
// defect class this whole round documents:
//   (a) it lets through what it must refuse — the outer tree's wrapper, issue #77;
//   (b) it refuses what it must let through — the repository's own wrapper;
//   (c) it reaches the right verdict for a false reason — a refusal whose diagnosis sends
//       the operator hunting for a nesting that does not exist.
// Probes 1, 2/4 and 1/3 are the three, in that order. Probes 1 and 2 are also each other's
// NEGATIVE CONTROL: without probe 1, "accept everything" passes; without probe 2, "refuse
// everything" passes; a guard that hard-codes a diagnosis passes both and fails 1 or 3.

const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync, spawnSync } = require('child_process');

const repo = process.argv[2] || path.resolve(__dirname, '..');
const MUT = path.join(repo, '_build', 'default', 'bin', 'arch_mutants', 'arch_mutants.exe');
const SCHEMA = path.join(repo, 'architecture-schema.sql');
const MIGRATION = path.join(repo, 'mutants-schema-migration.sql');

function fatal(msg) { console.error(`tree-boundary-tracked-marker: ${msg}`); process.exit(2); }
if (!fs.existsSync(MUT)) fatal(`${MUT} is not built — run 'dune build' first. Nothing was checked.`);
for (const f of [SCHEMA, MIGRATION]) if (!fs.existsSync(f)) fatal(`${f} is missing`);
for (const bin of ['git', 'sqlite3']) {
  try { execFileSync(bin, ['--version'], { stdio: 'ignore' }); } catch (e) { fatal(`${bin} is required`); }
}

const W = fs.mkdtempSync(path.join(os.tmpdir(), 'tree-boundary-tracked.'));
process.on('exit', () => { try { fs.rmSync(W, { recursive: true, force: true }); } catch (e) {} });

// Probe 3 is only meaningful outside any repository. Asserted, not assumed: under a TMPDIR
// that happened to sit inside a checkout it would pass for a reason unrelated to the guard.
{
  const t = spawnSync('git', ['rev-parse', '--show-toplevel'], { cwd: W, encoding: 'utf8' });
  if (t.status === 0) fatal(`${W} is inside a git repository (${String(t.stdout).trim()}) — probe 3 would be vacuous. Set TMPDIR somewhere outside a checkout.`);
}

let fails = 0;
const assertEq = (label, want, got) => {
  if (String(want) === String(got)) console.log(`  ✓ ${label} — ${got}`);
  else { console.log(`  ✗ ${label} — expected ${JSON.stringify(String(want))}, got ${JSON.stringify(String(got))}`); fails++; }
};

const sh = (file, body) => { fs.mkdirSync(path.dirname(file), { recursive: true }); fs.writeFileSync(file, body); fs.chmodSync(file, 0o755); };
const git = (cwd, args) => {
  const r = spawnSync('git', args, { cwd, encoding: 'utf8' });
  if (r.status !== 0) fatal(`git ${args.join(' ')} failed in ${cwd}: ${r.stderr}`);
  return r;
};

// The run inputs live OUTSIDE every fixture tree and are named by absolute path, so that
// creating them never changes what any fixture repository tracks — the single variable this
// check turns.
const IN = path.join(W, 'inputs');
fs.mkdirSync(IN, { recursive: true });
{
  const db = path.join(IN, 't.db');
  for (const f of [SCHEMA, MIGRATION]) {
    const r = spawnSync('sqlite3', [db], { input: fs.readFileSync(f, 'utf8'), encoding: 'utf8' });
    if (r.status !== 0) fatal(`sqlite3 < ${f} failed: ${r.stderr}`);
  }
  sh(path.join(IN, 'engine.sh'), '#!/bin/sh\nexit 0\n');
  sh(path.join(IN, 'tests.sh'), '#!/bin/sh\nexit 0\n');
  fs.writeFileSync(path.join(IN, 'cat.ndjson'), '{"id":"1","file":"a.ml","line":1}\n');
  const plan = spawnSync(MUT, ['plan', db, '--format', 'json'], { cwd: IN, encoding: 'utf8' });
  if (plan.status !== 0) fatal(`arch-mutants plan failed: ${plan.stderr}`);
  fs.writeFileSync(path.join(IN, 'plan.json'), plan.stdout);
}

// Identical argv at every probe; only the working directory and the fixture layout vary.
function runFrom(cwd) {
  const env = { ...process.env };
  delete env.ARCH_IMPACT;
  delete env.ARCH_MUTANTS_WRAPPER;
  const r = spawnSync(MUT,
    ['run', path.join(IN, 't.db'), '--plan', path.join(IN, 'plan.json'),
      '--engine', path.join(IN, 'engine.sh'), '--test-cmd', path.join(IN, 'tests.sh'),
      '--catalogue', path.join(IN, 'cat.ndjson')],
    { cwd, encoding: 'utf8', env });
  return { code: r.status, out: (r.stdout || '') + (r.stderr || '') };
}

// The two diagnoses the guard can print, matched on the sentence each one turns on. Matched
// against the RENDERED text with its whitespace collapsed: the diagnoses are multi-line OCaml
// string literals whose continuation padding lands runs of spaces INSIDE the sentence, so an
// adjacency-based regex over the raw output silently stops matching the moment the wording is
// re-wrapped — which is a matcher that reads green while checking nothing.
const flat = (s) => String(s).replace(/\s+/g, ' ');
//
// Keyed on wording that appears ONLY in the two AFFIRMATIVE diagnoses. The honest fallback
// diagnosis contains the sentence "This is NOT a claim that this checkout is nested inside
// another one", so a matcher for "nested inside another one" fires on the message that
// exists precisely to deny it — the check would then report the fallback as a false nesting
// claim, which is the opposite of the truth. checks/tree-boundary-non-git-checkout.js uses
// that phrase and escapes it only because it matches the RAW text, where the literal's
// continuation padding happens to break the adjacency; re-wrapping that sentence would turn
// its probe-4 assertion vacuous with no signal.
const SAYS_FOREIGN_TREE = (s) =>
  /the campaign was about to run the OUTER tree's artefact|belongs to a different tree/i.test(flat(s));
const SAYS_FELL_BACK = (s) => /No boundary could be established|FELL BACK/i.test(flat(s));

// ---- PROBE 1 — the refuse polarity, and its diagnosis --------------------------------------
// An inner checkout the outer repository does NOT track. The marker must still narrow here:
// this is issue #77, and nothing below may trade it away.
console.log('probe 1 — an UNTRACKED nested checkout must still have the outer wrapper refused');
{
  const outer = path.join(W, 'p1', 'outer');
  sh(path.join(outer, 'scripts', 'mutaml-wrapper.sh'), '#!/bin/sh\nexit 0\n');
  fs.writeFileSync(path.join(outer, 'dune-project'), '(lang dune 3.0)\n');
  git(outer, ['init', '-q', '.']);
  git(outer, ['config', 'user.email', 'c@t.b']);
  git(outer, ['config', 'user.name', 'tb']);
  git(outer, ['add', '-A']);
  git(outer, ['commit', '-qm', 'outer']);
  // Written AFTER the commit and never added: the outer repository does not own it.
  const inner = path.join(outer, 'unpacked');
  fs.mkdirSync(path.join(inner, 'sub'), { recursive: true });
  fs.writeFileSync(path.join(inner, 'dune-project'), '(lang dune 3.0)\n');
  const tracked = spawnSync('git', ['ls-files', '--error-unmatch', '--', path.join(inner, 'dune-project')], { cwd: outer, stdio: 'ignore' });
  if (tracked.status === 0) fatal('probe 1 setup: the inner marker is tracked, which is the opposite of what this probe needs');
  if (fs.existsSync(path.join(inner, 'scripts'))) fatal('probe 1: the inner tree must NOT hold a wrapper');
  const r = runFrom(path.join(inner, 'sub'));
  assertEq('the outer wrapper is REFUSED (exit 1)', 1, r.code);
  assertEq('the refusal names the outside path',
    'true', String(r.out.includes(path.join(outer, 'scripts', 'mutaml-wrapper.sh'))));
  assertEq('and the diagnosis is the foreign-tree one, which is TRUE here',
    'true', String(SAYS_FOREIGN_TREE(r.out)));
}

// ---- PROBE 2 — the accept polarity ---------------------------------------------------------
// The same shape, one variable flipped: the nested marker is TRACKED by the repository. It is
// then the same checkout, and refusing the repository's own wrapper is a false refusal.
console.log('probe 2 — a TRACKED nested dune-project must NOT shrink the repository\'s boundary');
{
  const root = path.join(W, 'p2', 'proj');
  sh(path.join(root, 'scripts', 'mutaml-wrapper.sh'), '#!/bin/sh\nexit 0\n');
  fs.writeFileSync(path.join(root, 'dune-project'), '(lang dune 3.0)\n');
  const nested = path.join(root, 'poc', 'lint');
  fs.mkdirSync(nested, { recursive: true });
  fs.writeFileSync(path.join(nested, 'dune-project'), '(lang dune 3.0)\n(name lint)\n');
  git(root, ['init', '-q', '.']);
  git(root, ['config', 'user.email', 'c@t.b']);
  git(root, ['config', 'user.name', 'tb']);
  git(root, ['add', '-A']);
  git(root, ['commit', '-qm', 'proj']);
  const tracked = spawnSync('git', ['ls-files', '--error-unmatch', '--', 'poc/lint/dune-project'], { cwd: root, stdio: 'ignore' });
  if (tracked.status !== 0) fatal('probe 2 setup: the nested marker is NOT tracked, which is the opposite of what this probe needs');
  const r = runFrom(nested);
  assertEq('the repository\'s own wrapper is ACCEPTED (exit 0)', 0, r.code);
  assertEq('and nothing claims it belongs to a different tree',
    'false', String(SAYS_FOREIGN_TREE(r.out)));
}

// ---- PROBE 3 — the diagnosis on the fallback path ------------------------------------------
// No git, no marker. Refusing is defensible; asserting a nesting is not. This is the probe
// that separates "the verdict is right" from "the reason is right".
console.log('probe 3 — with no git and no marker the refusal must name the fallback, not a nesting');
{
  const tree = path.join(W, 'p3', 'tree');
  sh(path.join(tree, 'scripts', 'mutaml-wrapper.sh'), '#!/bin/sh\nexit 0\n');
  fs.mkdirSync(path.join(tree, 'sub'), { recursive: true });
  const r = runFrom(path.join(tree, 'sub'));
  assertEq('it refuses (exit 1), the narrower answer', 1, r.code);
  assertEq('it does NOT assert a nesting or a foreign tree',
    'false', String(SAYS_FOREIGN_TREE(r.out)));
  assertEq('it says the boundary fell back to the invocation directory',
    'true', String(SAYS_FELL_BACK(r.out)));
}

// ---- PROBE 4 — the motivating input, in this repository itself -----------------------------
// Skipped rather than faked where the repository is not a checkout carrying the nested marker:
// a probe that quietly passes on a tree that does not have the shape is a gate that cannot fail.
console.log('probe 4 — this repository, invoked from its own tracked nested checkout');
{
  const nested = path.join(repo, 'poc', 'decision-lint');
  const top = spawnSync('git', ['rev-parse', '--show-toplevel'], { cwd: repo, encoding: 'utf8' });
  const tracked = spawnSync('git', ['ls-files', '--error-unmatch', '--', 'poc/decision-lint/dune-project'], { cwd: repo, stdio: 'ignore' });
  if (top.status !== 0 || tracked.status !== 0 || !fs.existsSync(path.join(repo, 'scripts', 'mutaml-wrapper.sh'))) {
    console.log('  – SKIPPED: this tree is not a git checkout carrying a tracked poc/decision-lint/dune-project and scripts/mutaml-wrapper.sh. Probes 1-3 still ran.');
  } else {
    const r = runFrom(nested);
    assertEq('the repository\'s own wrapper is ACCEPTED from poc/decision-lint (exit 0)', 0, r.code);
    assertEq('and no foreign-tree diagnosis is printed',
      'false', String(SAYS_FOREIGN_TREE(r.out)));
  }
}

console.log('');
if (fails > 0) {
  console.error(`tree-boundary-tracked-marker: FAIL — ${fails} assertion(s) fired.`);
  console.error('  A `dune-project` may narrow FR-030\'s boundary only when it identifies a checkout the');
  console.error('  enclosing git repository does not own. Tracked, it is the same tree, and refusing the');
  console.error('  repository\'s own wrapper there is a false refusal carrying a false reason.');
  process.exit(1);
}
console.log('tree-boundary-tracked-marker: PASS — 4 of 4 probes over 10 assertions.');
console.log('  What would have made this non-zero: letting any nested marker narrow the boundary');
console.log('  (probes 2 and 4), dropping the marker branch so the outer wrapper is accepted');
console.log('  (probe 1), or printing a foreign-tree diagnosis where the boundary merely fell');
console.log('  back to the invocation directory (probe 3).');
process.exit(0);
