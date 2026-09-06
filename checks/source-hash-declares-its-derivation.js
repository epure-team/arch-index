#!/usr/bin/env node
// checks/source-hash-declares-its-derivation.js — runnable directly: `node <path> [repo]`.
//
// Exit convention: 0 = passes · 1 = assertion fired · >=2 = error/setup failure.
//
// WHY THIS EXISTS. `mutants.source_hash` is a column the UNIQUE key depends on, and it held
// TWO INCOMPARABLE DERIVATIONS in one TEXT field with nothing recording which was used:
//
//   * the digest of the actual SOURCE LINE — which is what makes the key survive an edit
//     above the mutant and refuse to conflate two different texts at one span; and
//   * the digest of a synthetic SITE DESCRIPTOR — file, line, columns, replacement — which
//     is stable and discriminating but notices no rewrite of the line at all.
//
// That is the same design error as the engine id in the identity field, in the very column
// the identity key is built from: two things of different kinds sharing one slot, with the
// difference recoverable by nobody. The degradation was named only in a docstring, which is
// to say only to a reader of the OCaml — never to a consumer holding the database.
//
// And the source-line branch was exercised NOWHERE. Every fixture in this repository names
// files that do not exist on disk, so every hash ever stored here was the degraded form,
// and the branch that is supposed to be the normal case had never run. Probe 1 exists as
// much to execute that branch as to assert about it.
//
// The probes:
//   1 LINE DERIVATION — the mutated file EXISTS under --repo. The stored hash must declare
//     that it came from the source line, readably, from SQL alone.
//   2 SITE DERIVATION — the same campaign with the file absent. The stored hash must declare
//     the degraded derivation, and it must be a DIFFERENT declaration from probe 1's.
//   3 DISCRIMINATION — the line derivation must still change when the line's TEXT changes at
//     an unchanged span, which is the property the line derivation exists for. Without this,
//     a constant tag prepended to a constant hash passes probes 1 and 2.
//   4 OCCURRENCE — two mutants distinguished only by their occurrence ordinal must receive
//     DIFFERENT hashes. The site key carries the ordinal; if the hash does not, the
//     database's own UNIQUE key collapses the pair the site key had just told apart.
//
// Anchored on content: `source_hash ~repo s` in bin/arch_mutants/arch_mutants.ml (:1000 at
// the time this was written), whose two arms returned bare `Digest.to_hex` strings.

const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync, spawnSync } = require('child_process');

const repo = process.argv[2] || path.resolve(__dirname, '..');
const B = path.join(repo, '_build', 'default', 'bin');
const LOAD = path.join(B, 'arch_load', 'arch_load.exe');
const MUT = path.join(B, 'arch_mutants', 'arch_mutants.exe');
const WRAPPER = path.join(repo, 'scripts', 'mutaml-wrapper.sh');

function fatal(msg) {
  console.error(`source-hash-declares-its-derivation: ${msg}`);
  process.exit(2);
}
for (const p of [LOAD, MUT])
  if (!fs.existsSync(p)) fatal(`${p} is not built — run 'dune build' first. Nothing was checked.`);
if (!fs.existsSync(WRAPPER)) fatal(`${WRAPPER} is missing`);
try { execFileSync('sqlite3', ['-version'], { stdio: 'ignore' }); } catch (e) { fatal('sqlite3 is required'); }

const W = fs.mkdtempSync(path.join(os.tmpdir(), 'source-hash-derivation.'));
process.on('exit', () => { try { fs.rmSync(W, { recursive: true, force: true }); } catch (e) {} });

let fails = 0;
const assertEq = (label, want, got) => {
  if (String(want) === String(got)) console.log(`  ✓ ${label} — ${got}`);
  else { console.log(`  ✗ ${label} — expected ${JSON.stringify(String(want))}, got ${JSON.stringify(String(got))}`); fails++; }
};
const sql = (db, q) => execFileSync('sqlite3', [db, q], { encoding: 'utf8' }).trim();

const STREAM = [
  '{"type":"function","name":"t_alpha","file_path":"test/alpha_test.ml","line_start":1,"line_end":5}',
  '{"type":"function","name":"covered","file_path":"lib/x.ml","line_start":10,"line_end":20}',
  '{"type":"call","caller_name":"t_alpha","caller_file":"test/alpha_test.ml","callee_name":"covered","callee_file":"lib/x.ml","call_site":"test/alpha_test.ml:2","kind":"MUST"}',
  '',
].join('\n');

// `sourceLine15` non-null means lib/x.ml is written to disk under the campaign's --repo,
// with that text on line 15. Null means the file is absent, which is the degraded case.
function campaign(name, catalogue, report, ids, sourceLine15) {
  const d = path.join(W, name);
  fs.mkdirSync(d, { recursive: true });
  const db = path.join(d, 't.db');
  const loaded = spawnSync(LOAD, [db], { input: STREAM, encoding: 'utf8' });
  if (loaded.status !== 0) fatal(`${name}: arch-load failed: ${loaded.stderr}`);
  if (sourceLine15 !== null) {
    fs.mkdirSync(path.join(d, 'lib'), { recursive: true });
    const lines = [];
    for (let i = 1; i <= 20; i++) lines.push(i === 15 ? sourceLine15 : `(* filler line ${i} *)`);
    fs.writeFileSync(path.join(d, 'lib', 'x.ml'), lines.join('\n') + '\n');
  }
  fs.writeFileSync(path.join(d, 'cat.ndjson'), catalogue.map((c) => JSON.stringify(c)).join('\n') + '\n');
  fs.writeFileSync(path.join(d, 'report.ndjson'), report.map((c) => JSON.stringify(c)).join('\n') + '\n');
  const plan = spawnSync(MUT, ['plan', db, '--tests', 'file:test/**', '--format', 'json'], { encoding: 'utf8' });
  if (plan.status !== 0) fatal(`${name}: arch-mutants plan failed: ${plan.stderr}`);
  fs.writeFileSync(path.join(d, 'plan.json'), plan.stdout);
  fs.writeFileSync(path.join(d, 'engine.sh'),
    '#!/bin/sh\nfor m in ' + ids.map((i) => `'${i}'`).join(' ') + '; do MUTAML_MUTANT="$m" "$1" || true; done\nexit 0\n');
  fs.chmodSync(path.join(d, 'engine.sh'), 0o755);
  const r = spawnSync(MUT,
    ['run', db, '--plan', path.join(d, 'plan.json'), '--engine', path.join(d, 'engine.sh'),
      '--test-cmd', 'true', '--catalogue', path.join(d, 'cat.ndjson'),
      '--report', path.join(d, 'report.ndjson'), '--tests', 'file:test/**',
      '--repo', d, '--format', 'json'],
    { encoding: 'utf8', env: { ...process.env, ARCH_MUTANTS_WORKDIR: path.join(d, 'work'), ARCH_MUTANTS_WRAPPER: WRAPPER } });
  return { code: r.status, stdout: r.stdout || '', stderr: r.stderr || '', db };
}

const ONE = [{ id: 'h1', file: 'lib/x.ml', line: 15, col_start: 3, col_end: 9, replacement: 'true' }];
const ONE_REP = [{ file: 'lib/x.ml', line: 15, status: 'KILLED', col_start: 3, col_end: 9, replacement: 'true' }];

// A derivation declaration is a prefix separated from the digest by ':' — readable from SQL
// with no knowledge of the OCaml. What is asserted is the SHAPE and the DISTINCTION, not a
// particular vocabulary, so renaming the tags does not silently disarm this check.
const tagOf = (h) => (h.includes(':') ? h.slice(0, h.indexOf(':')) : null);
const digestOf = (h) => (h.includes(':') ? h.slice(h.indexOf(':') + 1) : h);

let lineTag = null, siteTag = null, lineDigestA = null;

console.log('probe 1 — the mutated file EXISTS on disk: the source-LINE derivation');
{
  const r = campaign('present', ONE, ONE_REP, ['h1'], 'let f x = x + 1  (* the real line *)');
  if (r.code !== 0) { console.log(`  ✗ the campaign did not run (exit ${r.code})`); console.log(r.stderr.split('\n').slice(0, 8).map((l) => '      | ' + l).join('\n')); fails++; }
  const h = sql(r.db, 'SELECT source_hash FROM mutants');
  lineTag = tagOf(h);
  lineDigestA = digestOf(h);
  assertEq('the stored hash declares a derivation, readable from SQL alone', 'true', String(lineTag !== null));
  assertEq('the digest half is still a 32-hex MD5, as the repository idiom requires', 'true',
    String(/^[0-9a-f]{32}$/.test(lineDigestA)));
}

console.log('probe 2 — the mutated file is ABSENT: the degraded site-DESCRIPTOR derivation');
{
  const r = campaign('absent', ONE, ONE_REP, ['h1'], null);
  if (r.code !== 0) { console.log(`  ✗ the campaign did not run (exit ${r.code})`); console.log(r.stderr.split('\n').slice(0, 8).map((l) => '      | ' + l).join('\n')); fails++; }
  const h = sql(r.db, 'SELECT source_hash FROM mutants');
  siteTag = tagOf(h);
  assertEq('the stored hash declares a derivation here too', 'true', String(siteTag !== null));
  assertEq('and it is a DIFFERENT declaration from the source-line one', 'true',
    String(lineTag !== null && siteTag !== null && lineTag !== siteTag));
}

console.log('probe 3 — the source-line derivation still discriminates on the line\'s TEXT');
{
  const r = campaign('rewritten', ONE, ONE_REP, ['h1'], 'let f x = x - 1  (* a DIFFERENT line, same span *)');
  if (r.code !== 0) { console.log(`  ✗ the campaign did not run (exit ${r.code})`); fails++; }
  const h = sql(r.db, 'SELECT source_hash FROM mutants');
  // Asserted BEFORE the equality: comparing two absent declarations to each other is a
  // gate that cannot fail, and probe 3 must not read green on a hash that declares nothing.
  assertEq('a declaration is present at all', 'true', String(tagOf(h) !== null));
  assertEq('the same declaration as probe 1', String(lineTag), String(tagOf(h)));
  assertEq('a different digest, because the line\'s text changed', 'true',
    String(lineDigestA !== null && digestOf(h) !== lineDigestA));
}

console.log('probe 4 — two mutants distinguished only by occurrence get different hashes');
{
  const cat = [
    { id: 'o1', file: 'lib/x.ml', line: 15, col_start: 3, col_end: 9, replacement: 'true', occurrence: 1 },
    { id: 'o2', file: 'lib/x.ml', line: 15, col_start: 3, col_end: 9, replacement: 'true', occurrence: 2 },
  ];
  const rep = [
    { file: 'lib/x.ml', line: 15, status: 'KILLED', col_start: 3, col_end: 9, replacement: 'true', occurrence: 1 },
    { file: 'lib/x.ml', line: 15, status: 'SURVIVED', col_start: 3, col_end: 9, replacement: 'true', occurrence: 2 },
  ];
  const r = campaign('occ', cat, rep, ['o1', 'o2'], 'let f x = x + 1  (* two anchors here *)');
  if (r.code !== 0) { console.log(`  ✗ the campaign did not run (exit ${r.code})`); console.log(r.stderr.split('\n').slice(0, 8).map((l) => '      | ' + l).join('\n')); fails++; }
  assertEq('two distinct source_hash values', '2', sql(r.db, 'SELECT count(DISTINCT source_hash) FROM mutants'));
  assertEq('two distinct site rows survive the database\'s own UNIQUE key', '2',
    sql(r.db, 'SELECT count(*) FROM mutants'));
}

console.log('');
if (fails > 0) {
  console.error(`source-hash-declares-its-derivation: FAIL — ${fails} assertion(s) fired.`);
  console.error('  mutants.source_hash carries two incomparable derivations in one column with');
  console.error('  nothing recording which was used, so a consumer holding the database cannot');
  console.error('  tell a hash that tracks the source line from one that never will — in the very');
  console.error('  column the UNIQUE identity key is built from.');
  process.exit(1);
}
console.log('source-hash-declares-its-derivation: PASS — 4 probes, 8 assertions.');
console.log('  What would have made this non-zero: storing a bare digest (probes 1-2), tagging a');
console.log('  constant (probe 3), or leaving the occurrence ordinal out of the hash so the');
console.log('  database re-collapses a pair the site key had just distinguished (probe 4).');
process.exit(0);
