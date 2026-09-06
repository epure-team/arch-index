#!/usr/bin/env node
// checks/tree-boundary-anchor-is-structural.js — runnable directly: `node <path> [repo]`.
//
// Exit convention: 0 = passes · 1 = assertion fired · >=2 = error/setup failure.
//
// WHY THIS EXISTS, AND IT IS NOT THE DEFECT ITS SIBLINGS GUARD.
//
// FR-030's refusal picks its diagnosis from WHICH anchor established the boundary. For four
// rounds the only way to observe that choice from outside was to match phrases lifted out of
// the English prose, and an enumerated set of phrases is defeated by the next phrase. That is
// not a hypothetical: a repair that knew TWO of the phrasings shipped checks blind to the
// third, and the coverage hole it opened was on the very defect it was repairing. Widening
// the set to three does not fix the class. THREE IS ONLY THE COUNT SEEN SO FAR.
//
// So the driver names the arm itself, in `boundary-anchor=<tag>`, and this check pins the
// thing that makes that tag trustworthy — not any tag's spelling, but the CORRESPONDENCE:
//
//   PROPERTY 1 (source). The set of arms in `type tree_anchor` and the set of arms in
//   `anchor_tag` are EQUAL, the match carries no wildcard, and the tags are pairwise
//   DISTINCT. The arm set is DERIVED FROM THE TYPE, never written down here — which is the
//   whole answer to "where does the number of arms come from". Add a fifth constructor and
//   this check demands a tag for it without being edited; give it a tag that duplicates
//   another and this check says so. A wildcard would let a new arm inherit an old arm's tag
//   in silence, which is how the prose enumeration failed, one layer down.
//
//   PROPERTY 2 (runtime). The declaration is not merely self-consistent: three fixtures that
//   take three DIFFERENT arms make the real binary print three DIFFERENT tags, each one drawn
//   from the set declared in the source. Without this, `anchor_tag` could be dead code and
//   property 1 would still hold.
//
// WHAT THIS CHECK DOES NOT CLAIM. It says nothing about whether the English diagnosis beside
// a tag is TRUE of that arm. No mechanism decides whether a sentence is true, so that remains
// an ENUMERATION of known phrasings, asserted in the three sibling tree-boundary checks and
// labelled there as an enumeration. This check makes the ARM observable without reading prose;
// it does not make the prose honest.
//
// The undetermined arm is covered by property 1 only. Reaching it at runtime needs an index
// git cannot read, which checks/tree-boundary-git-cannot-answer.js builds; duplicating that
// setup here would add a uid-dependent skip to a check whose source half already covers every
// arm the type declares, including arms no fixture can reach.

const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync, spawnSync } = require('child_process');

// Resolved, not taken as given: every path is joined onto this and then handed to a
// subprocess spawned with a DIFFERENT cwd, so a relative argument would name a driver that
// exists here and not there.
const repo = path.resolve(process.argv[2] || path.join(__dirname, '..'));
const SRC = path.join(repo, 'bin', 'arch_mutants', 'arch_mutants.ml');
const MUT = path.join(repo, '_build', 'default', 'bin', 'arch_mutants', 'arch_mutants.exe');
const SCHEMA = path.join(repo, 'architecture-schema.sql');
const MIGRATION = path.join(repo, 'mutants-schema-migration.sql');

function fatal(msg) { console.error(`tree-boundary-anchor: ${msg}`); process.exit(2); }
if (!fs.existsSync(SRC)) fatal(`${SRC} is missing — nothing was checked.`);
if (!fs.existsSync(MUT)) fatal(`${MUT} is not built — run 'dune build' first. Nothing was checked.`);
for (const f of [SCHEMA, MIGRATION]) if (!fs.existsSync(f)) fatal(`${f} is missing`);
for (const bin of ['git', 'sqlite3']) {
  try { execFileSync(bin, ['--version'], { stdio: 'ignore' }); } catch (e) { fatal(`${bin} is required`); }
}

let fails = 0;
const assertEq = (label, want, got) => {
  if (String(want) === String(got)) console.log(`  ✓ ${label} — ${got}`);
  else { console.log(`  ✗ ${label} — expected ${JSON.stringify(String(want))}, got ${JSON.stringify(String(got))}`); fails++; }
};

// ---- PROPERTY 1: the source declares one tag per arm, and no arm twice ---------------------
console.log('property 1 — every arm of `type tree_anchor` has exactly one distinct tag, and no wildcard');
const src = fs.readFileSync(SRC, 'utf8');

// The type, and only the type: from `type tree_anchor =` to the first line that is not a
// constructor or documentation. Failing to PARSE it is exit 2, not a green: a check that
// cannot find what it grades has graded nothing.
const typeStart = src.indexOf('type tree_anchor =');
if (typeStart < 0) fatal('`type tree_anchor` was not found in the driver — this check cannot say anything about a type it cannot read.');
const typeBody = src.slice(typeStart, src.indexOf('\n\n', typeStart));
const declared = [...typeBody.matchAll(/^\s*\|\s*(Anchor_[A-Za-z_0-9]*)/gm)].map((m) => m[1]);
if (declared.length === 0) fatal('`type tree_anchor` was found but no constructors were parsed out of it.');
console.log(`  · arms DERIVED from the type declaration, not written down here: ${declared.join(', ')}`);

// The tag function. Its ABSENCE is an ASSERTION, not a setup failure — it is exactly the
// regression this check exists to catch, and reporting it as a broken harness would let the
// ratchet read amber where it must read red.
const fnStart = src.indexOf('let anchor_tag = function');
assertEq('the driver defines an `anchor_tag` mapping arms to machine-readable tags',
  'true', String(fnStart >= 0));
if (fnStart < 0) {
  console.log('');
  console.error('tree-boundary-anchor: FAIL — the boundary arm is not observable except through prose.');
  console.error('  Every check that needs to know which anchor fired must then match phrases out of the');
  console.error('  diagnoses, and an enumerated set of phrases is defeated by the next phrase. That is');
  console.error('  not hypothetical: it is the finding this file answers.');
  process.exit(1);
}
const fnBody = src.slice(fnStart, src.indexOf('\n\n', fnStart));
const arms = [...fnBody.matchAll(/^\s*\|\s*(Anchor_[A-Za-z_0-9]*)[^->]*->\s*"([^"]*)"/gm)];
const tagOf = new Map(arms.map((m) => [m[1], m[2]]));

assertEq('it carries NO wildcard arm, so a new anchor cannot inherit an old tag in silence',
  'false', String(/^\s*\|\s*_\s*->/m.test(fnBody)));
assertEq('every arm the TYPE declares is tagged — the set comes from the type, not from this file',
  '', declared.filter((c) => !tagOf.has(c)).join(','));
assertEq('and it tags nothing the type does not declare',
  '', [...tagOf.keys()].filter((c) => !declared.includes(c)).join(','));
const tags = [...tagOf.values()];
assertEq('the tags are pairwise DISTINCT, so the tag identifies the arm',
  String(tags.length), String(new Set(tags).size));
assertEq('and none is empty', 'false', String(tags.some((t) => t.trim() === '')));

// ---- PROPERTY 2: the binary really prints them, and different arms differ ------------------
const W = fs.mkdtempSync(path.join(os.tmpdir(), 'tree-boundary-anchor.'));
process.on('exit', () => { try { fs.rmSync(W, { recursive: true, force: true }); } catch (e) {} });

// Two preconditions, ASSERTED rather than assumed. Under a TMPDIR inside a checkout the git
// arm would be reached by the wrong repository; under one with a `dune-project` above it the
// cwd fixture would take the marker arm and its probe would pass for an unrelated reason.
{
  const t = spawnSync('git', ['rev-parse', '--show-toplevel'], { cwd: W, encoding: 'utf8' });
  if (t.status === 0) fatal(`${W} is inside a git repository (${String(t.stdout).trim()}) — the fixtures would not take the arms they name. Set TMPDIR somewhere outside a checkout.`);
  for (let d = W; ; d = path.dirname(d)) {
    if (fs.existsSync(path.join(d, 'dune-project'))) fatal(`${d}/dune-project sits above ${W} — the no-anchor fixture would take the marker arm. Set TMPDIR elsewhere.`);
    if (d === path.dirname(d)) break;
  }
}

const sh = (file, body) => { fs.mkdirSync(path.dirname(file), { recursive: true }); fs.writeFileSync(file, body); fs.chmodSync(file, 0o755); };
const git = (cwd, args) => {
  const r = spawnSync('git', args, { cwd, encoding: 'utf8' });
  if (r.status !== 0) fatal(`git ${args.join(' ')} failed in ${cwd}: ${r.stderr}`);
};

// Run inputs OUTSIDE every fixture and named by absolute path, so creating them never changes
// what a fixture repository tracks — the variable the arms turn on.
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

// Identical argv at every fixture; only the layout and the working directory vary.
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
const ANCHOR = (s) => {
  const m = /boundary-anchor=([a-z][a-z-]*)/.exec(String(s));
  return m ? m[1] : null;
};

// Three layouts, each reaching a wrapper outside its own boundary by a DIFFERENT anchor.
// Named by the layout, not by the tag they are expected to print: this half asserts that the
// three tags DIFFER and are declared, never that a particular arm spells its tag a particular
// way — that spelling is the source's business and pinning it here would be one more
// enumeration.
function layoutGit(root) {
  // An inner checkout that is its OWN repository: it is its own git toplevel.
  sh(path.join(root, 'scripts', 'mutaml-wrapper.sh'), '#!/bin/sh\nexit 0\n');
  fs.writeFileSync(path.join(root, 'dune-project'), '(lang dune 3.0)\n');
  git(root, ['init', '-q', '.']);
  const inner = path.join(root, 'inner');
  fs.mkdirSync(path.join(inner, 'sub'), { recursive: true });
  fs.writeFileSync(path.join(inner, 'dune-project'), '(lang dune 3.0)\n');
  git(inner, ['init', '-q', '.']);
  return path.join(inner, 'sub');
}
function layoutMarker(root) {
  // An inner checkout that is NOT a repository and that the outer one does not track.
  sh(path.join(root, 'scripts', 'mutaml-wrapper.sh'), '#!/bin/sh\nexit 0\n');
  git(root, ['init', '-q', '.']);
  const inner = path.join(root, 'inner');
  fs.mkdirSync(path.join(inner, 'sub'), { recursive: true });
  fs.writeFileSync(path.join(inner, 'dune-project'), '(lang dune 3.0)\n');
  return path.join(inner, 'sub');
}
function layoutNoAnchor(root) {
  // No repository anywhere above, no marker: nothing answers.
  sh(path.join(root, 'scripts', 'mutaml-wrapper.sh'), '#!/bin/sh\nexit 0\n');
  fs.mkdirSync(path.join(root, 'sub'), { recursive: true });
  return path.join(root, 'sub');
}

console.log('property 2 — three layouts taking three different arms print three different declared tags');
const seen = new Map();
for (const [name, build] of [['own-repository', layoutGit], ['untracked-marker', layoutMarker], ['no-anchor-at-all', layoutNoAnchor]]) {
  const root = path.join(W, name, 'tree');
  fs.mkdirSync(root, { recursive: true });
  const cwd = build(root);
  const r = runFrom(cwd);
  // The refusal is the precondition, not the subject: an accepted wrapper prints no anchor at
  // all and the tag assertion below would then be reading nothing. Asserted so that a layout
  // which stopped refusing is a RED, not a quiet null.
  assertEq(`${name}: the outside wrapper is REFUSED (exit 1), so an anchor is printed at all`, 1, r.code);
  const tag = ANCHOR(r.out);
  assertEq(`${name}: the refusal names its arm, and the name is one the source declares`,
    'true', String(tag !== null && tags.includes(tag)));
  seen.set(name, tag);
  console.log(`      → ${name} printed ${JSON.stringify(tag)}`);
}
assertEq('the three layouts are told APART by the tag alone, with no phrase matched',
  '3', String(new Set(seen.values()).size));

console.log('');
if (fails > 0) {
  console.error(`tree-boundary-anchor: FAIL — ${fails} assertion(s) fired.`);
  console.error('  Which anchor established FR-030\'s boundary must be readable from the refusal without');
  console.error('  parsing English. When it is not, every check that needs it matches phrases out of the');
  console.error('  diagnoses, and the next phrasing defeats the set — which is how a repair that knew');
  console.error('  two of three phrasings shipped a gate blind to the third.');
  process.exit(1);
}
console.log('tree-boundary-anchor: PASS — 2 properties.');
console.log('  What would have made this non-zero: removing `anchor_tag` or the tag from the refusal;');
console.log('  adding an arm to `type tree_anchor` without tagging it, or tagging one it does not');
console.log('  declare; giving two arms the same tag; adding a wildcard arm, which lets a new anchor');
console.log('  inherit an old tag in silence; or leaving `anchor_tag` correct but unused, which');
console.log('  property 2 catches by driving the real binary.');
console.log('  NOT claimed: that the prose beside a tag is TRUE of that arm. Nothing decides whether a');
console.log('  sentence is true; the sibling checks enumerate the known phrasings and say so.');
process.exit(0);
