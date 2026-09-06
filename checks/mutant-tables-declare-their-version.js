#!/usr/bin/env node
// checks/mutant-tables-declare-their-version.js — runnable directly: `node <path> [repo]`.
//
// Exit convention: 0 = passes · 1 = assertion fired · >=2 = error/setup failure.
//
// WHY THIS EXISTS. This branch's one version decision — bumping the index's
// `current_schema_version` to 1.13 "for the executed-mutation-campaign tables" — was inert,
// and inert in BOTH directions. Both halves are measurable and both are measured here:
//
//   * 1.13 does not IMPLY the tables. `lib/arch_index/arch_index_db.ml` stamps it from the
//     main indexer, whose `architecture-schema.sql` creates none of the four mutant tables.
//     A consumer that reads 1.13 and concludes `mutant_runs` exists is wrong.
//   * the tables do not IMPLY 1.13. `Arch_mutant_db.open_and_migrate` created all four and
//     wrote NO version at all, so a database carrying a FINISHED campaign reports whatever
//     its indexer happened to stamp — measured at 1.2, arch-load's own flat-schema version.
//
// Between them there was no value of `schema_version`, in either direction, on which a
// consumer could refuse. The fix is not a bigger number: it is a SEPARATE declaration,
// written by the code that creates the tables, whose presence means exactly "these four
// tables exist at this version" and whose absence means exactly "they may not". This check
// asserts that biconditional by executing both sides.
//
// The probes:
//   1 ABSENCE — a database the indexer wrote and no campaign has touched must NOT carry the
//     declaration. (This is the half that keeps the declaration meaningful: a key written
//     unconditionally somewhere would pass probe 2 alone.)
//   2 PRESENCE — after a campaign, the declaration is there and non-empty.
//   3 INDEPENDENCE — in that same database, the global `schema_version` is UNCHANGED by the
//     campaign, which is the executed demonstration that it never carried this fact.
//
// Anchored on content: `open_and_migrate` in bin/arch_mutants/arch_mutant_db.ml, which ran
// `exec db ddl` and returned without writing any version, and the `current_schema_version =
// "1.13"` constant in lib/arch_index/arch_index_db.ml (:103 at the time this was written).

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
  console.error(`mutant-tables-declare-their-version: ${msg}`);
  process.exit(2);
}
for (const p of [LOAD, MUT])
  if (!fs.existsSync(p)) fatal(`${p} is not built — run 'dune build' first. Nothing was checked.`);
if (!fs.existsSync(WRAPPER)) fatal(`${WRAPPER} is missing`);
try { execFileSync('sqlite3', ['-version'], { stdio: 'ignore' }); } catch (e) { fatal('sqlite3 is required'); }

const W = fs.mkdtempSync(path.join(os.tmpdir(), 'mutant-schema-version.'));
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

// The declaration is looked up by a KEY WHOSE NAME NAMES THE TABLES, not by the global one.
// Whatever value it carries, what is asserted is that it is present exactly when the tables
// are — a version string is checked for shape, never for a literal, so a later bump does not
// silently disarm this file.
const KEY = 'mutants_schema_version';
const declared = (db) => sql(db, `SELECT value FROM comment_db_meta WHERE key='${KEY}'`);
const tableCount = (db) =>
  sql(db, "SELECT count(*) FROM sqlite_master WHERE type='table' AND name IN ('mutant_campaigns','mutants','mutant_runs','mutant_kills')");

const d = path.join(W, 'c');
fs.mkdirSync(d, { recursive: true });
const db = path.join(d, 't.db');
const loaded = spawnSync(LOAD, [db], { input: STREAM, encoding: 'utf8' });
if (loaded.status !== 0) fatal(`arch-load failed: ${loaded.stderr}`);

console.log('probe 1 — a database the indexer wrote, no campaign yet');
{
  assertEq('none of the four mutant tables exists', '0', tableCount(db));
  assertEq('and the tables are NOT declared', '', declared(db));
}

const beforeGlobal = sql(db, "SELECT value FROM comment_db_meta WHERE key='schema_version'");

fs.writeFileSync(path.join(d, 'cat.ndjson'),
  JSON.stringify({ id: 'v1', file: 'lib/x.ml', line: 15, col_start: 3, col_end: 9, replacement: 'true' }) + '\n');
fs.writeFileSync(path.join(d, 'report.ndjson'),
  JSON.stringify({ file: 'lib/x.ml', line: 15, status: 'KILLED', col_start: 3, col_end: 9, replacement: 'true' }) + '\n');
const plan = spawnSync(MUT, ['plan', db, '--tests', 'file:test/**', '--format', 'json'], { encoding: 'utf8' });
if (plan.status !== 0) fatal(`arch-mutants plan failed: ${plan.stderr}`);
fs.writeFileSync(path.join(d, 'plan.json'), plan.stdout);
fs.writeFileSync(path.join(d, 'engine.sh'), '#!/bin/sh\nMUTAML_MUTANT=\'v1\' "$1" || true\nexit 0\n');
fs.chmodSync(path.join(d, 'engine.sh'), 0o755);
const r = spawnSync(MUT,
  ['run', db, '--plan', path.join(d, 'plan.json'), '--engine', path.join(d, 'engine.sh'),
    '--test-cmd', 'true', '--catalogue', path.join(d, 'cat.ndjson'),
    '--report', path.join(d, 'report.ndjson'), '--tests', 'file:test/**', '--format', 'json'],
  { encoding: 'utf8', env: { ...process.env, ARCH_MUTANTS_WORKDIR: path.join(d, 'work'), ARCH_MUTANTS_WRAPPER: WRAPPER } });

console.log('probe 2 — the same database after a campaign has created its tables');
{
  if (r.status !== 0) {
    console.log(`  ✗ the campaign did not run (exit ${r.status})`);
    console.log((r.stderr || '').split('\n').slice(0, 8).map((l) => '      | ' + l).join('\n'));
    fails++;
  }
  assertEq('all four mutant tables now exist', '4', tableCount(db));
  assertEq('the campaign genuinely completed, so this is a finished record', '1',
    sql(db, 'SELECT count(*) FROM mutant_campaigns WHERE completed_at IS NOT NULL'));
  const v = declared(db);
  assertEq('the tables ARE declared', 'true', String(v !== ''));
  assertEq('the declaration is a <major>.<minor> version, not a flag', 'true', String(/^\d+\.\d+$/.test(v)));
}

console.log('probe 3 — the global schema_version never carried this fact');
{
  const afterGlobal = sql(db, "SELECT value FROM comment_db_meta WHERE key='schema_version'");
  assertEq('the campaign did not touch the global schema_version', beforeGlobal, afterGlobal);
  assertEq('so a consumer reading only that value cannot know the tables are here', 'true',
    String(afterGlobal !== declared(db)));
}

console.log('');
if (fails > 0) {
  console.error(`mutant-tables-declare-their-version: FAIL — ${fails} assertion(s) fired.`);
  console.error('  The code that CREATES the four mutant tables writes no version for them, so a');
  console.error('  database carrying a finished campaign reports whatever its indexer stamped, and');
  console.error('  a consumer has no value — in either direction — on which it could refuse.');
  process.exit(1);
}
console.log('mutant-tables-declare-their-version: PASS — 3 probes, 8 assertions.');
console.log('  What would have made this non-zero: creating the tables without declaring them');
console.log('  (probe 2), or writing the declaration unconditionally so its absence means');
console.log('  nothing (probe 1), or folding the fact into the index-wide schema_version (probe 3).');
process.exit(0);
