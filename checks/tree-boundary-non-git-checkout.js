#!/usr/bin/env node
// checks/tree-boundary-non-git-checkout.js — runnable directly: `node <path> [repo]`.
//
// Exit convention: 0 = passes · 1 = assertion fired · >=2 = error/setup failure.
//
// WHY THIS EXISTS. FR-030's guard was anchored on `git rev-parse --show-toplevel` alone, and
// that makes `git init` — not the layout — decide whether the guard fires.
//
//   THE UNREFUSED POLARITY. A checkout that is NOT itself a repository but sits inside one
//   (a release tarball unpacked into a repo, a vendored subtree, an unpacked build artefact)
//   resolves its toplevel to the OUTER repo. The boundary then spans both trees, the outer
//   tree's wrapper is judged INSIDE, and the campaign runs it — issue #77 exactly, silently.
//   Measured: `git init -q` in the inner tree, nothing else changed, byte-identical argv,
//   flipped exit 0 into exit 1.
//
//   THE OVER-REFUSED POLARITY. On a tree with NO repository anywhere above it, the fallback
//   boundary is the invocation DIRECTORY, so the tree's own wrapper — one directory up — is
//   refused, while the diagnosis printed asserts "this checkout is nested inside another
//   one", which is false there and sends the reader looking for a tree that does not exist.
//
// checks/tree-boundary-refusal.sh cannot see either: its `make_inner` always runs `git init`,
// and all three of its probes are inside a repository.
//
// THE FOUR PROBES:
//   1 a NON-git inner checkout inside an outer repo must still refuse the outer wrapper;
//   2 the same layout with `git init` must still refuse — the guard must not have been
//     traded for one that only fires without git;
//   3 a non-git tree with NO repository above it must ACCEPT its OWN wrapper from a
//     subdirectory;
//   4 where the boundary genuinely fell back to the invocation directory, the refusal must
//     say so and must NOT assert a nesting.

const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync, spawnSync } = require('child_process');

// RESOLVED, not taken as given. Every path below is joined onto this and then handed to
// a subprocess spawned with a DIFFERENT cwd, so a relative argument -- `node <this> .`,
// which is how a human runs it -- produced a driver path that existed when this process
// tested it and did not exist when the driver was spawned from a scratch directory. The
// check then exited 2 having verified nothing, while the argument-less form exited 0, so
// no spec row exercised it.
const repo = path.resolve(process.argv[2] || path.join(__dirname, '..'));
const B = path.join(repo, '_build', 'default', 'bin');
const MUT = path.join(B, 'arch_mutants', 'arch_mutants.exe');
const SCHEMA = path.join(repo, 'architecture-schema.sql');
const MIGRATION = path.join(repo, 'mutants-schema-migration.sql');

function fatal(msg) { console.error(`tree-boundary-non-git: ${msg}`); process.exit(2); }
if (!fs.existsSync(MUT)) fatal(`${MUT} is not built — run 'dune build' first. Nothing was checked.`);
for (const f of [SCHEMA, MIGRATION]) if (!fs.existsSync(f)) fatal(`${f} is missing`);
for (const bin of ['git', 'sqlite3']) {
  try { execFileSync(bin, ['--version'], { stdio: 'ignore' }); } catch (e) { fatal(`${bin} is required`); }
}

const W = fs.mkdtempSync(path.join(os.tmpdir(), 'tree-boundary-nongit.'));
process.on('exit', () => { try { fs.rmSync(W, { recursive: true, force: true }); } catch (e) {} });

// The out-of-any-repository probes are only meaningful if the scratch root really is outside
// one. Asserted rather than assumed: under a TMPDIR that happened to sit inside a checkout,
// probes 3 and 4 would pass for a reason that has nothing to do with the guard.
{
  const t = spawnSync('git', ['rev-parse', '--show-toplevel'], { cwd: W, encoding: 'utf8' });
  if (t.status === 0) fatal(`${W} is inside a git repository (${String(t.stdout).trim()}) — probes 3 and 4 would be vacuous. Set TMPDIR somewhere outside a checkout.`);
}

// ---- WHAT THE DIAGNOSES ARE MATCHED ON, and why it is not the obvious phrase ----------
//
// These three matchers replace `/nested inside another one/` used over the RAW output at two
// sites. That phrase occurs in the honest FALLBACK diagnosis too -- inside the sentence "This
// is NOT a claim that this checkout is nested inside another one", which exists precisely to
// deny it. Probe 4's absence assertion was green only because the OCaml literal's continuation
// padding lands runs of spaces between `inside` and `another`, breaking the adjacency the
// regex needs. MEASURED at 85ff36d: collapsing runs of spaces to one space inside that single
// literal -- four fills, the message semantically unchanged, still denying the nesting --
// turned the assertion red. The gate was measuring the source formatting of the thing it
// tested.
//
// So: match the RENDERED text with its whitespace collapsed, and key on wording that appears
// ONLY in the affirmative diagnoses. Widening the old pattern does not help; an absence over
// raw output is satisfied by any reflow, and widening moves the boundary rather than removing
// it.
//
// AND EACH VOCABULARY IS ASSERTED IN BOTH POLARITIES, which is what keeps the absences from
// rotting silently. SAYS_FOREIGN_TREE must be PRESENT on the git-anchored path (probes 1, 2)
// and ABSENT on the fallback path (probe 4). A rewording of the git diagnosis that quietly
// disarmed probe 4's absence therefore turns probes 1 and 2 RED rather than leaving a vacuous
// green behind. Same construction for SAYS_FELL_BACK, asserted present in probe 4.
const flat = (s) => String(s).replace(/\s+/g, ' ');
const SAYS_FOREIGN_TREE = (s) =>
  /the campaign was about to run the OUTER tree's artefact|belongs to a different tree/i.test(flat(s));
const SAYS_FELL_BACK = (s) => /No boundary could be established|FELL BACK/i.test(flat(s));

let fails = 0;
const assertEq = (label, want, got) => {
  if (String(want) === String(got)) console.log(`  ✓ ${label} — ${got}`);
  else { console.log(`  ✗ ${label} — expected ${JSON.stringify(String(want))}, got ${JSON.stringify(String(got))}`); fails++; }
};

const sh = (file, body) => { fs.writeFileSync(file, body); fs.chmodSync(file, 0o755); };

// An inner checkout carrying the minimum `run` needs to reach wrapper resolution. `gitInit`
// and `marker` are the two variables the whole check is about.
function makeInner(dir, { gitInit, marker }) {
  fs.mkdirSync(dir, { recursive: true });
  if (gitInit) {
    for (const a of [['init', '-q', '.'], ['config', 'user.email', 'c@t.b'], ['config', 'user.name', 'tb']]) {
      const r = spawnSync('git', a, { cwd: dir });
      if (r.status !== 0) fatal(`git ${a.join(' ')} failed in ${dir}`);
    }
  }
  const db = path.join(dir, 't.db');
  for (const f of [SCHEMA, MIGRATION]) {
    const r = spawnSync('sqlite3', [db], { input: fs.readFileSync(f, 'utf8'), encoding: 'utf8' });
    if (r.status !== 0) fatal(`sqlite3 < ${f} failed: ${r.stderr}`);
  }
  // The engine is invoked ONCE, with the wrapper path as its single argument -- that is the
  // driver/engine contract (`{ ENV... } <engine> <wrapper>`). Recording that argument is how
  // probe 3 can say something about the ACCEPTANCE path that an exit code cannot.
  sh(path.join(dir, 'engine.sh'),
    `#!/bin/sh\nprintf '%s' "$1" > ${JSON.stringify(path.join(dir, 'engine-argv1.txt'))}\nexit 0\n`);
  sh(path.join(dir, 'tests.sh'), '#!/bin/sh\nexit 0\n');
  fs.writeFileSync(path.join(dir, 'cat.ndjson'), '{"id":"1","file":"a.ml","line":1}\n');
  // `dune-project` is the tree-local marker: it is what says "this directory is the root of
  // the checkout the campaign belongs to" where git cannot, and every OCaml source tree
  // this driver could be run inside carries one.
  if (marker) fs.writeFileSync(path.join(dir, 'dune-project'), '(lang dune 3.0)\n');
  const plan = spawnSync(MUT, ['plan', db, '--format', 'json'], { cwd: dir, encoding: 'utf8' });
  if (plan.status !== 0) fatal(`arch-mutants plan failed in ${dir}: ${plan.stderr}`);
  fs.writeFileSync(path.join(dir, 'plan.json'), plan.stdout);
}

function runFrom(cwd, prefix) {
  const env = { ...process.env };
  delete env.ARCH_IMPACT;
  delete env.ARCH_MUTANTS_WRAPPER;
  const r = spawnSync(MUT,
    ['run', `${prefix}/t.db`, '--plan', `${prefix}/plan.json`, '--engine', `${prefix}/engine.sh`,
      '--test-cmd', `${prefix}/tests.sh`, '--catalogue', `${prefix}/cat.ndjson`],
    { cwd, encoding: 'utf8', env });
  return { code: r.status, out: (r.stdout || '') + (r.stderr || '') };
}

// ---- PROBES 1 and 2: an inner checkout nested inside an outer repository ------------------
for (const [n, gitInit] of [[1, false], [2, true]]) {
  console.log(`probe ${n} — inner checkout ${gitInit ? 'IS' : 'is NOT'} a git repository, nested inside an outer repo`);
  const outer = path.join(W, `p${n}`, 'outer');
  fs.mkdirSync(path.join(outer, 'scripts'), { recursive: true });
  for (const a of [['init', '-q', '.'], ['config', 'user.email', 'c@t.b'], ['config', 'user.name', 'tb']]) {
    const r = spawnSync('git', a, { cwd: outer });
    if (r.status !== 0) fatal(`probe ${n}: git ${a.join(' ')} failed`);
  }
  sh(path.join(outer, 'scripts', 'mutaml-wrapper.sh'), '#!/bin/sh\nexit 0\n');
  const inner = path.join(outer, 'inner');
  makeInner(inner, { gitInit, marker: true });
  if (fs.existsSync(path.join(inner, 'scripts'))) fatal(`probe ${n}: the inner tree must NOT hold a wrapper`);
  fs.mkdirSync(path.join(inner, 'sub', 'deeper'), { recursive: true });
  const r = runFrom(path.join(inner, 'sub', 'deeper'), '../..');
  assertEq('the outer tree\'s wrapper is REFUSED (exit 1)', 1, r.code);
  assertEq('the refusal names the outside path',
    'true', String(r.out.includes(path.join(outer, 'scripts', 'mutaml-wrapper.sh'))));
  // The affirmative half of probe 4's absence. Asserted here so that a rewording of the
  // git-anchored diagnosis cannot silently disarm probe 4: it turns this red instead.
  assertEq('and the diagnosis is the foreign-tree one, which is TRUE here',
    'true', String(SAYS_FOREIGN_TREE(r.out)));
}

// ---- PROBE 3: no repository anywhere above; the tree's OWN wrapper must be accepted --------
console.log('probe 3 — a non-git tree with no repository above it, invoked from a subdirectory');
{
  const tree = path.join(W, 'p3', 'tree');
  makeInner(tree, { gitInit: false, marker: true });
  fs.mkdirSync(path.join(tree, 'scripts'), { recursive: true });
  sh(path.join(tree, 'scripts', 'mutaml-wrapper.sh'), '#!/bin/sh\nexit 0\n');
  fs.mkdirSync(path.join(tree, 'sub'), { recursive: true });
  const r = runFrom(path.join(tree, 'sub'), '..');
  assertEq('the tree\'s own wrapper is accepted (exit 0)', 0, r.code);
  // AN ASSERTION WAS REPLACED HERE, AND THE REASON IS THE POINT. It read
  //
  //     assertEq('no nesting is asserted', 'false', String(/nested inside another one/i.test(r.out)));
  //
  // and it COULD NOT BE RED -- a third category, not a weaker version of probe 4's. This is
  // an ACCEPTANCE path: the guard did not fire, so no diagnosis of any kind was emitted.
  // MEASURED at 85ff36d by instrumenting the check to print what it examines: r.out is 1524
  // characters and is the output of a SUCCEEDING campaign ("== Mutation campaign 1 ..."); the
  // forbidden phrase lives only inside `refuse`. It forbade something its path cannot emit,
  // and a green that never weighed anything is worse than one fewer green because it counts.
  // Any restatement of it over the diagnosis vocabulary has the same defect: with exit 0
  // already asserted above, no boundary diagnosis can appear.
  //
  // What bears on THIS path is not what the refusal did not say, but WHICH ARTEFACT was
  // accepted. The engine records the wrapper it is handed; FR-030's acceptance polarity is
  // that it is the tree's OWN.
  const rec = path.join(tree, 'engine-argv1.txt');
  const handed = fs.existsSync(rec) ? fs.readFileSync(rec, 'utf8').trim() : '(the engine was never invoked)';
  assertEq('the wrapper handed to the engine is the tree\'s OWN',
    fs.realpathSync(path.join(tree, 'scripts', 'mutaml-wrapper.sh')),
    fs.existsSync(handed) ? fs.realpathSync(handed) : handed);
}

// ---- PROBE 4: the honest fallback — no git, no marker -------------------------------------
console.log('probe 4 — no git and no tree marker: the refusal must not assert a nesting that does not exist');
{
  const tree = path.join(W, 'p4', 'tree');
  makeInner(tree, { gitInit: false, marker: false });
  fs.mkdirSync(path.join(tree, 'scripts'), { recursive: true });
  sh(path.join(tree, 'scripts', 'mutaml-wrapper.sh'), '#!/bin/sh\nexit 0\n');
  fs.mkdirSync(path.join(tree, 'sub'), { recursive: true });
  const r = runFrom(path.join(tree, 'sub'), '..');
  // Refusing here is defensible — the boundary genuinely cannot be established — but the
  // DIAGNOSIS must be the true one.
  assertEq('it still refuses (exit 1), the narrower answer', 1, r.code);
  assertEq('it does NOT claim a nesting or a foreign tree',
    'false', String(SAYS_FOREIGN_TREE(r.out)));
  assertEq('it says the boundary fell back to the invocation directory',
    'true', String(SAYS_FELL_BACK(r.out)));
}

console.log('');
if (fails > 0) {
  console.error(`tree-boundary-non-git: FAIL — ${fails} assertion(s) fired.`);
  console.error('  FR-030\'s boundary must be the checkout the campaign belongs to, and `git init` must');
  console.error('  not be what decides whether the guard fires. Both polarities are defects: an');
  console.error('  unrefused outer wrapper is issue #77 unguarded, and a refused own wrapper with a');
  console.error('  false diagnosis sends the reader hunting for a tree that does not exist.');
  process.exit(1);
}
console.log('tree-boundary-non-git: PASS — 4 of 4 probes over 11 assertions.');
console.log('  What would have made this non-zero: anchoring on `git rev-parse --show-toplevel`');
console.log('  alone (probes 1 and 3), losing the guard where git IS present (probe 2), or keeping');
console.log('  the nesting wording on the fallback path (probe 4).');
process.exit(0);
