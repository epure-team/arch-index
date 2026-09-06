#!/usr/bin/env node
// checks/site-key-collision-is-refused.js — runnable directly: `node <path> [repo]`.
//
// Exit convention: 0 = passes · 1 = assertion fired · >=2 = error/setup failure.
//
// WHY THIS EXISTS. Once the site key is the ONLY discriminant of a mutant's identity — which
// is what `mutants-schema-migration.sql` has said all along, `UNIQUE(file_path, line,
// col_start, col_end, replacement, source_hash)` and "never by an engine-assigned id" — a
// catalogue that offers two DIFFERENT mutants under one site key is a catalogue the driver
// cannot honour. It has two verdicts to store and one row to store them in.
//
// What used to happen, measured rather than argued: the two catalogue entries collapsed into
// ONE `mutants` row (`INSERT OR IGNORE` then read the id back). Both report entries then
// joined — correctly, by the engine id! — and resolved to the SAME `mutant_id`. The first
// `insert_run` succeeded; the second violated `UNIQUE(campaign_id, mutant_id)`, and its
// exception was caught and printed to stderr and nothing else. The counters had already been
// incremented, so `run` printed `survived: 1` with two `mutant_runs` entries counted while
// the database held one, `completed_at` was stamped anyway, and a SURVIVOR — the only thing
// this whole tool exists to find — was deleted in silence. A lost survivor was
// indistinguishable from no survivor, which is the one conflation the design forbids.
//
// The refusal is the point, and it is deliberately NOT a resolution. The tempting
// implementation is to pick one (`LIMIT 1`, or the head of the list). Picking turns an
// honest "I cannot attribute this" into a false attribution — the same failure in a new
// costume. There is no correct choice available: nothing in the two entries distinguishes
// them, so any choice is list order recorded as a fact.
//
// The two probes:
//   1 COLLISION — two catalogue entries, one site key. The driver must refuse, write no
//     campaign completion, and NAME both entries so the operator can fix the catalogue.
//   2 NEGATIVE CONTROL — the same two entries made distinguishable by their `occurrence`
//     ordinal (which comes from the MUTATION SPECIFICATION, never from a report position)
//     must run, complete, and produce two separate `mutants` rows carrying two verdicts.
//     Without this probe, "refuse every catalogue" passes probe 1.
//
// Anchored on content: the collapse happened in `insert_mutant`'s INSERT OR IGNORE + SELECT
// (bin/arch_mutants/arch_mutant_db.ml) feeding `run`'s `mutant_ids` table (:1964 at the time
// this was written).

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
  console.error(`site-key-collision-is-refused: ${msg}`);
  process.exit(2);
}
for (const p of [LOAD, MUT])
  if (!fs.existsSync(p)) fatal(`${p} is not built — run 'dune build' first. Nothing was checked.`);
if (!fs.existsSync(WRAPPER)) fatal(`${WRAPPER} is missing`);
try { execFileSync('sqlite3', ['-version'], { stdio: 'ignore' }); } catch (e) { fatal('sqlite3 is required'); }

const W = fs.mkdtempSync(path.join(os.tmpdir(), 'site-key-collision.'));
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

function campaign(name, catalogue, report, ids) {
  const d = path.join(W, name);
  fs.mkdirSync(d, { recursive: true });
  const db = path.join(d, 't.db');
  const loaded = spawnSync(LOAD, [db], { input: STREAM, encoding: 'utf8' });
  if (loaded.status !== 0) fatal(`${name}: arch-load failed: ${loaded.stderr}`);
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
      '--report', path.join(d, 'report.ndjson'), '--tests', 'file:test/**', '--format', 'json'],
    { encoding: 'utf8', env: { ...process.env, ARCH_MUTANTS_WORKDIR: path.join(d, 'work'), ARCH_MUTANTS_WRAPPER: WRAPPER } });
  return { code: r.status, stdout: r.stdout || '', stderr: r.stderr || '', db };
}

// ---- PROBE 1: two catalogue entries under one site key ---------------------------------
console.log('probe 1 — two catalogue entries whose site keys are identical in every column');
{
  const cat = [
    { id: 'c_first', file: 'lib/x.ml', line: 15, col_start: 3, col_end: 9, replacement: 'true' },
    { id: 'c_second', file: 'lib/x.ml', line: 15, col_start: 3, col_end: 9, replacement: 'true' },
  ];
  const rep = [
    { file: 'lib/x.ml', line: 15, status: 'KILLED', id: 'c_first', col_start: 3, col_end: 9, replacement: 'true' },
    { file: 'lib/x.ml', line: 15, status: 'SURVIVED', id: 'c_second', col_start: 3, col_end: 9, replacement: 'true' },
  ];
  const r = campaign('collide', cat, rep, ['c_first', 'c_second']);
  assertEq('the driver refuses (exit 1) rather than collapsing the two into one row', 1, r.code);
  assertEq('the refusal names BOTH colliding catalogue entries', 'true',
    String(/c_first/.test(r.stderr) && /c_second/.test(r.stderr)));
  assertEq('the campaign is NOT stamped complete', '0',
    sql(r.db, 'SELECT count(*) FROM mutant_campaigns WHERE completed_at IS NOT NULL'));
  // The precise shape of the silent loss: one row where two verdicts were counted.
  const runs = Number(sql(r.db, 'SELECT count(*) FROM mutant_runs'));
  assertEq('no half-written pair of verdicts was left behind (0 rows, not 1 of 2)', '0', String(runs));
  // The counters were incremented BEFORE the write, so the old driver published
  // `"survived": 1` on stdout while the database held no such row. The key is `survived`
  // — the name the driver actually emits (arch_mutants.ml, the JSON block) and not a
  // plausible-looking one, because a mis-spelled key makes this assertion unfailable.
  const survivedPrinted = (r.stdout.match(/"survived":\s*(\d+)/) || [, null])[1];
  assertEq('no survivor count is published for a campaign that stored none', 'null', String(survivedPrinted));
}

// ---- PROBE 2: the negative control — an occurrence ordinal makes them distinct ----------
console.log('probe 2 — negative control: the same two sites, told apart by their occurrence ordinal');
{
  const cat = [
    { id: 'c_first', file: 'lib/x.ml', line: 15, col_start: 3, col_end: 9, replacement: 'true', occurrence: 1 },
    { id: 'c_second', file: 'lib/x.ml', line: 15, col_start: 3, col_end: 9, replacement: 'true', occurrence: 2 },
  ];
  const rep = [
    { file: 'lib/x.ml', line: 15, status: 'KILLED', col_start: 3, col_end: 9, replacement: 'true', occurrence: 1 },
    { file: 'lib/x.ml', line: 15, status: 'SURVIVED', col_start: 3, col_end: 9, replacement: 'true', occurrence: 2 },
  ];
  const r = campaign('occurrence', cat, rep, ['c_first', 'c_second']);
  if (r.code !== 0) {
    console.log(`  ✗ the campaign did not run (exit ${r.code})`);
    console.log(r.stderr.split('\n').slice(0, 10).map((l) => '      | ' + l).join('\n'));
    fails++;
  }
  assertEq('two distinct mutant SITE rows, not one', '2', sql(r.db, 'SELECT count(*) FROM mutants'));
  assertEq('two run rows, one verdict each', '2', sql(r.db, 'SELECT count(*) FROM mutant_runs'));
  assertEq('one KILLED and one SURVIVED, both stored', 'KILLED|SURVIVED',
    sql(r.db, "SELECT group_concat(engine_status,'|') FROM (SELECT engine_status FROM mutant_runs ORDER BY engine_status)"));
  assertEq('the campaign completes', '1',
    sql(r.db, 'SELECT count(*) FROM mutant_campaigns WHERE completed_at IS NOT NULL'));
}

console.log('');
if (fails > 0) {
  console.error(`site-key-collision-is-refused: FAIL — ${fails} assertion(s) fired.`);
  console.error('  Two catalogued mutants sharing one site key are not being refused. They collapse');
  console.error('  into a single `mutants` row, the second verdict violates UNIQUE(campaign_id,');
  console.error('  mutant_id), the exception is printed and swallowed, and the campaign is stamped');
  console.error('  COMPLETE with a survivor deleted — indistinguishable from having found none.');
  process.exit(1);
}
console.log('site-key-collision-is-refused: PASS — 2 probes, 9 assertions.');
console.log('  What would have made this non-zero: resolving a multi-candidate site key by taking');
console.log('  one (LIMIT 1 / list head), or swallowing the UNIQUE violation and completing anyway.');
process.exit(0);
