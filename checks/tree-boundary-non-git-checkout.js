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

const repo = process.argv[2] || path.resolve(__dirname, '..');
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
  sh(path.join(dir, 'engine.sh'), '#!/bin/sh\nexit 0\n');
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
  assertEq('no nesting is asserted', 'false', String(/nested inside another one/i.test(r.out)));
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
  assertEq('it does NOT claim the checkout is nested inside another one',
    'false', String(/nested inside another one/i.test(r.out)));
  assertEq('it says the boundary fell back to the invocation directory',
    'true', String(/no enclosing (git )?repository|fell back|working directory itself|not inside (a )?(git )?repositor/i.test(r.out)));
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
console.log('tree-boundary-non-git: PASS — 4 of 4 probes over 9 assertions.');
console.log('  What would have made this non-zero: anchoring on `git rev-parse --show-toplevel`');
console.log('  alone (probes 1 and 3), losing the guard where git IS present (probe 2), or keeping');
console.log('  the nesting wording on the fallback path (probe 4).');
process.exit(0);
