#!/usr/bin/env node
// checks/tree-boundary-git-cannot-answer.js — runnable directly: `node <path> [repo]`.
//
// Exit convention: 0 = passes · 1 = assertion fired · >=2 = error/setup failure.
//
// LABEL: this is a RULE, not a regression test. The property it pins is not "an unreadable
// index behaves thus". It is: WHEN THE THING A GUARD ASKS CANNOT ANSWER, THE GUARD MUST NOT
// READ THAT AS A NO. FR-030's marker branch asks git one question — does the enclosing
// repository track this nested `dune-project`? — and git can return three things, not two.
//
// WHY THIS EXISTS. The marker branch was repaired by asking git whether the nested marker is
// tracked, and the ask was written `Sys.command "... git ls-files --error-unmatch ..." = 0`.
// A boolean over an exit code with three meanings. Every non-zero exit — 128 for a fatal
// error, 127 for no git on PATH — therefore read as "not tracked", which is the LOUD, ACTED-ON
// answer rather than the quiet one, so the failure did not degrade the guard, it INVERTED it.
//
// The reachability is the part that makes this a defect rather than a note. `git ls-files`
// reads the INDEX. `git rev-parse --show-toplevel` does not. So the branch's own precondition
// — a git toplevel was found — survives exactly the failure that breaks the question asked
// inside it. MEASURED here, git 2.55.0, twice and by two different causes:
//
//     corrupt index (14 bytes of garbage over .git/index): ls-files 128, rev-parse 0
//     unreadable index (chmod 000 .git/index):             ls-files 128, rev-parse 0
//
// The consequence at the old code: a TRACKED marker declared untracked, the boundary shrunk to
// the subdirectory, the repository's own wrapper refused, and the refusal saying it "belongs to
// a different tree" — which git, if it could speak, would contradict. That is review finding
// :1133 returned verbatim through the ERROR PATH OF ITS OWN FIX.
//
// WHAT THE FIX IS, AND WHAT THIS CHECK DOES NOT CLAIM. The three answers are now distinct, and
// the undetermined one narrows the boundary (so issue #77 is not traded away on a broken index)
// while carrying its OWN reason, so the refusal says the index could not be read instead of
// asserting a nesting nobody established. This check does NOT assert that the verdict changed —
// it did not, and claiming so would be wider than the code. It asserts that the REASON is now
// true and that the two adjacent reasons are not borrowed for it, which is the third failure
// mode a boundary guard has: right verdict, false diagnosis.
//
// THE FOUR PROBES, and the two vocabularies each asserted in BOTH polarities — an absence that
// is never paired with a presence rots into a green that weighs nothing:
//   1 healthy index, TRACKED nested marker  -> accept (exit 0); no undetermined diagnosis
//   2 CORRUPT index, same fixture           -> refuse, undetermined diagnosis, NOT foreign-tree
//   3 UNREADABLE index, same fixture        -> same (skipped loudly if the setup cannot be made)
//   4 healthy index, UNTRACKED nested marker-> refuse, foreign-tree diagnosis, NOT undetermined
// Probe 1 is probe 2's negative control (a guard that always prints the new diagnosis fails 1),
// probe 4 is probe 2's (a guard that answers Undetermined to everything fails 4 and 1).

const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync, spawnSync } = require('child_process');

// RESOLVED, not taken as given: every path is joined onto this and handed to a subprocess run
// with a DIFFERENT cwd, so a relative `node <this> .` would otherwise name a driver that exists
// for this process and not for the one it spawns. That is an open finding against two sibling
// checks; it is not going to be re-introduced by a third.
const repo = path.resolve(process.argv[2] || path.join(__dirname, '..'));
const MUT = path.join(repo, '_build', 'default', 'bin', 'arch_mutants', 'arch_mutants.exe');
const SCHEMA = path.join(repo, 'architecture-schema.sql');
const MIGRATION = path.join(repo, 'mutants-schema-migration.sql');

function fatal(msg) { console.error(`tree-boundary-git-cannot-answer: ${msg}`); process.exit(2); }
if (!fs.existsSync(MUT)) fatal(`${MUT} is not built — run 'dune build' first. Nothing was checked.`);
for (const f of [SCHEMA, MIGRATION]) if (!fs.existsSync(f)) fatal(`${f} is missing`);
for (const bin of ['git', 'sqlite3']) {
  try { execFileSync(bin, ['--version'], { stdio: 'ignore' }); } catch (e) { fatal(`${bin} is required`); }
}

const W = fs.mkdtempSync(path.join(os.tmpdir(), 'tree-boundary-cannot-answer.'));
process.on('exit', () => {
  // The chmod-000 fixture would otherwise defeat the cleanup it is nested in.
  try { for (const f of restoreOnExit) { try { fs.chmodSync(f, 0o644); } catch (e) {} } } catch (e) {}
  try { fs.rmSync(W, { recursive: true, force: true }); } catch (e) {}
});
const restoreOnExit = [];

// Asserted, not assumed. Every fixture below runs `git init`, so its own toplevel is itself;
// but a scratch root inside a checkout would let `marker_root`'s upward walk leave the fixture
// entirely on any probe whose layout it did not expect, and the probes would then pass for a
// reason unrelated to the guard.
{
  const t = spawnSync('git', ['rev-parse', '--show-toplevel'], { cwd: W, encoding: 'utf8' });
  if (t.status === 0) fatal(`${W} is inside a git repository (${String(t.stdout).trim()}) — the probes would be vacuous. Set TMPDIR somewhere outside a checkout.`);
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

// ---- THE DIAGNOSIS MATCHERS -----------------------------------------------------------
// Matched against the RENDERED output with runs of whitespace collapsed. The diagnoses are
// multi-line OCaml literals whose continuation padding lands runs of spaces INSIDE sentences,
// so an adjacency regex over the raw text silently stops matching the moment the wording is
// re-wrapped. That exact failure is an open finding against a sibling check; it is copied here
// as the FIX, not as the defect.
//
// SAYS_UNDETERMINED is keyed on wording that appears ONLY in the new diagnosis. It is
// deliberately NOT keyed on any of git's own words: git localises its fatals — the measured one
// read `fichier d'index plus petit qu'attendu` — so a matcher on English index-error text would
// be a matcher that reads green under LANG=fr.
const flat = (s) => String(s).replace(/\s+/g, ' ');

// STRUCTURAL, and the only assertions in this file that are a property rather than an
// enumeration of phrasings. The driver names the arm that decided the boundary in a token IT
// chooses, by an exhaustive match on `type tree_anchor` with no wildcard, so no rewording of
// any diagnosis moves it and a fifth anchor cannot ship without a tag. Read off the RAW
// output: it is not prose and it is not reflowed.
const ANCHOR = (s) => {
  const m = /boundary-anchor=([a-z][a-z-]*)/.exec(String(s));
  return m ? m[1] : null;
};

// WHAT IS DELIBERATELY NOT ASSERTED HERE, so the next reader does not mistake its absence for
// coverage. The sibling checks also forbid the phrasing "nested inside another one" on the
// arms where no nesting was established, and the undetermined diagnosis below could acquire
// that false claim without any assertion in this file firing. That absence is NOT added here
// because every probe in this file takes the marker or the undetermined arm, and neither can
// ever emit a nesting claim truthfully: the assertion would be one no probe here could turn
// red, which is a green that weighs nothing — the exact defect this round removed from a
// sibling. The affirmative anchor for that phrasing lives in
// checks/tree-boundary-tracked-marker.js, which has a git-arm probe; this file relies on the
// tag instead, which distinguishes the arms without naming a single phrase.
const SAYS_FOREIGN_TREE = (s) =>
  /the campaign was about to run the OUTER tree's artefact|belongs to a different tree/i.test(flat(s));
const SAYS_FELL_BACK = (s) => /No boundary could be established|FELL BACK/i.test(flat(s));
const SAYS_UNDETERMINED = (s) =>
  /git COULD NOT SAY whether|neither 0 \(tracked\) nor 1 \(not tracked\)/i.test(flat(s));

// ---- RUN INPUTS, OUTSIDE EVERY FIXTURE ------------------------------------------------
// Named by absolute path from outside the trees, so creating them never changes what any
// fixture repository tracks — the single variable probes 1/4 turn — and never adds a file the
// corrupt-index probes would have to account for.
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

// A repository carrying its own wrapper at the root and a nested `dune-project` one level
// down. `trackNested` is the ONLY variable between probes 1/2/3 and probe 4.
function makeRepo(dir, { trackNested }) {
  sh(path.join(dir, 'scripts', 'mutaml-wrapper.sh'), '#!/bin/sh\nexit 0\n');
  fs.writeFileSync(path.join(dir, 'dune-project'), '(lang dune 3.0)\n');
  const nested = path.join(dir, 'poc', 'lint');
  fs.mkdirSync(nested, { recursive: true });
  git(dir, ['init', '-q', '.']);
  git(dir, ['config', 'user.email', 'c@t.b']);
  git(dir, ['config', 'user.name', 'tb']);
  if (trackNested) fs.writeFileSync(path.join(nested, 'dune-project'), '(lang dune 3.0)\n(name lint)\n');
  git(dir, ['add', '-A']);
  git(dir, ['commit', '-qm', 'proj']);
  // Written AFTER the commit when it must stay untracked, so it is never in any index —
  // including the healthy one probe 4 reads.
  if (!trackNested) fs.writeFileSync(path.join(nested, 'dune-project'), '(lang dune 3.0)\n(name lint)\n');
  const t = spawnSync('git', ['ls-files', '--error-unmatch', '--', 'poc/lint/dune-project'], { cwd: dir, stdio: 'ignore' });
  const want = trackNested ? 0 : 1;
  if (t.status !== want) fatal(`setup for ${dir}: nested marker ls-files exited ${t.status}, wanted ${want} — the fixture does not have the shape the probe needs`);
  return nested;
}

// Establishes the failure and PROVES it is the intended one before anything is concluded from
// it: ls-files must decline (>=2) while rev-parse still answers (0). Without both halves the
// probe would be testing some other code path and reading its result as this one's.
function breakIndex(dir, how) {
  const idx = path.join(dir, '.git', 'index');
  if (!fs.existsSync(idx)) fatal(`${idx} does not exist — nothing to break`);
  if (how === 'corrupt') fs.writeFileSync(idx, 'GARBAGEGARBAGE');
  else { restoreOnExit.push(idx); fs.chmodSync(idx, 0o000); }
  const ls = spawnSync('git', ['ls-files', '--error-unmatch', '--', 'poc/lint/dune-project'], { cwd: dir, stdio: 'ignore' });
  const top = spawnSync('git', ['rev-parse', '--show-toplevel'], { cwd: dir, stdio: 'ignore' });
  return { lsCode: ls.status, topCode: top.status };
}

// ---- PROBE 1 — the control: a healthy index and a TRACKED nested marker ----------------
console.log('probe 1 — healthy index, tracked nested marker: the repository keeps its own boundary');
{
  const dir = path.join(W, 'p1', 'proj');
  const nested = makeRepo(dir, { trackNested: true });
  const r = runFrom(nested);
  assertEq('the repository\'s own wrapper is ACCEPTED (exit 0)', 0, r.code);
  assertEq('and no could-not-determine diagnosis is printed', 'false', String(SAYS_UNDETERMINED(r.out)));
  assertEq('and nothing claims a foreign tree', 'false', String(SAYS_FOREIGN_TREE(r.out)));
}

// ---- PROBES 2 and 3 — git cannot answer, by two independent causes ---------------------
for (const [n, how, label] of [[2, 'corrupt', 'CORRUPT'], [3, 'unreadable', 'UNREADABLE']]) {
  console.log(`probe ${n} — ${label} index, tracked nested marker: git cannot answer and must not be read as "no"`);
  const dir = path.join(W, `p${n}`, 'proj');
  const nested = makeRepo(dir, { trackNested: true });
  const { lsCode, topCode } = breakIndex(dir, how);
  if (lsCode === 0 || lsCode === 1 || topCode !== 0) {
    // NEVER silently: a probe whose premise did not hold has checked nothing, and the honest
    // report of that is louder than a green. chmod is a no-op for uid 0, which is the one
    // configuration where probe 3's cause cannot be made to happen.
    console.log(`  – SKIPPED: could not establish the premise here (ls-files exited ${lsCode}, rev-parse exited ${topCode}); this probe needs ls-files to DECLINE while rev-parse still answers. Running as uid ${typeof process.getuid === 'function' ? process.getuid() : '?'}.`);
    if (n === 2) fatal('probe 2 is uid-independent — a corrupt index that git still reads means this check no longer measures what it says.');
    continue;
  }
  const r = runFrom(nested);
  assertEq(`git declined with a code that is neither 0 nor 1`, 'true', String(lsCode >= 2));
  assertEq('the artefact is REFUSED (exit 1), the narrower answer', 1, r.code);
  // STRUCTURAL: the undetermined arm, told apart from the plain marker arm of probe 4 by a
  // token the code picks. The two share the same boundary and differ only in their reason, so
  // before the tag the only thing separating them was the wording matched below.
  assertEq('the arm that decided the boundary, named by the driver',
    'marker-undetermined', String(ANCHOR(r.out)));
  assertEq('the refusal says git could not determine the marker\'s tracking', 'true', String(SAYS_UNDETERMINED(r.out)));
  assertEq('and it carries git\'s actual exit code', 'true', String(flat(r.out).includes(`exited ${lsCode}`)));
  assertEq('and it does NOT assert the marker belongs to a different tree', 'false', String(SAYS_FOREIGN_TREE(r.out)));
  assertEq('and it does NOT claim the boundary fell back for want of any anchor', 'false', String(SAYS_FELL_BACK(r.out)));
}

// ---- PROBE 4 — the answer git CAN give must still be acted on --------------------------
// Without this, "answer Undetermined to everything" passes probes 2 and 3, and issue #77 walks
// back in behind a polite diagnosis.
console.log('probe 4 — healthy index, UNTRACKED nested marker: the boundary still narrows, for the TRUE reason');
{
  const dir = path.join(W, 'p4', 'proj');
  const nested = makeRepo(dir, { trackNested: false });
  const r = runFrom(nested);
  assertEq('the outer wrapper is REFUSED (exit 1)', 1, r.code);
  assertEq('the refusal names the outside path', 'true',
    String(r.out.includes(path.join(dir, 'scripts', 'mutaml-wrapper.sh'))));
  // STRUCTURAL, and the negative control for the tag itself: probes 2 and 3 must NOT reach
  // this arm and this probe must NOT reach theirs.
  assertEq('the arm that decided the boundary, named by the driver', 'marker', String(ANCHOR(r.out)));
  assertEq('the diagnosis is the foreign-tree one, which is TRUE here', 'true', String(SAYS_FOREIGN_TREE(r.out)));
  assertEq('and NOT the could-not-determine one', 'false', String(SAYS_UNDETERMINED(r.out)));
}

console.log('');
if (fails > 0) {
  console.error(`tree-boundary-git-cannot-answer: FAIL — ${fails} assertion(s) fired.`);
  console.error('  `git ls-files --error-unmatch` returns 0 for tracked, 1 for untracked, and something');
  console.error('  else when it could not tell. Reading the third as the second declares a TRACKED file');
  console.error('  untracked on any unreadable index — while `rev-parse --show-toplevel`, which does not');
  console.error('  read the index, keeps the branch reachable — and the repository then refuses its own');
  console.error('  artefact claiming it belongs to another tree.');
  process.exit(1);
}
console.log('tree-boundary-git-cannot-answer: PASS.');
console.log('  What would have made this non-zero: testing the ls-files exit as a boolean, so a fatal');
console.log('  reads as "untracked" (probes 2 and 3); printing the foreign-tree or the fell-back');
console.log('  diagnosis on the undetermined path (probes 2 and 3); dropping git\'s exit code from the');
console.log('  message (probes 2 and 3); or answering "could not tell" to a git that answered plainly');
console.log('  (probes 1 and 4); or collapsing the undetermined arm into the plain marker arm, which');
console.log('  no wording matched here could see and the anchor tag does (probes 2, 3 and 4).');
console.log('  SCOPE: the ARM is enforced as a property, by that tag. Whether the PROSE beside it is');
console.log('  true is only ENUMERATED, over the phrasings named above, and a further phrasing would');
console.log('  pass. See the note beside the matchers for the one absence deliberately NOT asserted.');
process.exit(0);
