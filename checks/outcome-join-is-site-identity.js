#!/usr/bin/env node
// checks/outcome-join-is-site-identity.js — runnable directly: `node <path> [repo]`.
//
// Exit convention: 0 = passes · 1 = assertion fired · >=2 = error/setup failure.
//
// WHY THIS EXISTS. Round 1 raised it, round 2 re-raised it after the line number moved, and
// nothing dispatched it either time: `run` joined the engine's report entries to the
// catalogued mutant sites by `Filename.basename path` plus LINE alone, consuming duplicates
// in list order and never refusing. Two facts made that indefensible rather than merely
// coarse. The schema's own key is UNIQUE(file_path, line, col_start, col_end, replacement,
// source_hash) — the discriminating columns are present on the catalogue side. And the
// engine's id is carried by BOTH records — the catalogue's `id` and the report entry's `id`
// — so the join had the exact identity available and threw it away.
//
// The consequences were executed, not argued: two mutants on one line had their
// KILLED/SURVIVED verdicts INVERTED in the database, and a `mutant_kills` row was written
// against a different FILE under `attribution = singleton_executed_set` — the one
// attribution in this schema that claims to name a killer — while the campaign published
// `certification: self_certifying`.
//
// THE FOUR PROBES, and why each is needed:
//
//   1 INVERSION — two mutants on one line, distinguishable only by column and replacement.
//     The engine reports the SECOND killed and the FIRST survived. A basename+line join
//     pairs them in list order and stores both statuses on the wrong sites.
//
//   2 WRONG FILE — two mutants on the same LINE of two files sharing a BASENAME
//     (lib/a/main.ml and lib/b/main.ml). A basename join writes the kill, and its
//     attribution, against whichever came first.
//
//   3 REFUSAL — two catalogued sites on one line and a report entry that discriminates
//     between them in no way at all (an id matching neither, no columns, no replacement).
//     Taking the head of the list here is a coin flip recorded as a fact. The driver must
//     REFUSE and leave the campaign incomplete.
//
//   4 NEGATIVE CONTROL — an ordinary campaign, one mutant, one matching report entry, must
//     still join and complete. Without it, "refuse everything" passes probes 1 to 3 and is
//     indistinguishable from a correct join.
//
// Probes 1, 2 and 4 are red-provable together; probe 3 is what separates a join that is
// merely stricter from one that declines to guess.

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
  console.error(`outcome-join-is-site-identity: ${msg}`);
  process.exit(2);
}

for (const p of [LOAD, MUT]) if (!fs.existsSync(p)) fatal(`${p} is not built — run 'dune build' first. Nothing was checked.`);
if (!fs.existsSync(WRAPPER)) fatal(`${WRAPPER} is missing`);
try {
  execFileSync('sqlite3', ['-version'], { stdio: 'ignore' });
} catch (e) {
  fatal('sqlite3 is required');
}

const W = fs.mkdtempSync(path.join(os.tmpdir(), 'outcome-join.'));
process.on('exit', () => { try { fs.rmSync(W, { recursive: true, force: true }); } catch (e) {} });

let fails = 0;
const assertEq = (label, want, got) => {
  if (String(want) === String(got)) console.log(`  ✓ ${label} — ${got}`);
  else { console.log(`  ✗ ${label} — expected ${JSON.stringify(String(want))}, got ${JSON.stringify(String(got))}`); fails++; }
};

const sql = (db, q) => execFileSync('sqlite3', [db, q], { encoding: 'utf8' }).trim();

// The index every probe shares: two test cases, and production functions in three files
// whose basenames collide on purpose.
const STREAM = [
  '{"type":"function","name":"t_alpha","file_path":"test/alpha_test.ml","line_start":1,"line_end":5}',
  '{"type":"function","name":"t_beta","file_path":"test/beta_test.ml","line_start":1,"line_end":5}',
  '{"type":"function","name":"covered","file_path":"lib/x.ml","line_start":10,"line_end":20}',
  '{"type":"function","name":"a_main","file_path":"lib/a/main.ml","line_start":10,"line_end":20}',
  '{"type":"function","name":"b_main","file_path":"lib/b/main.ml","line_start":10,"line_end":20}',
  '{"type":"call","caller_name":"t_alpha","caller_file":"test/alpha_test.ml","callee_name":"covered","callee_file":"lib/x.ml","call_site":"test/alpha_test.ml:2","kind":"MUST"}',
  '{"type":"call","caller_name":"t_alpha","caller_file":"test/alpha_test.ml","callee_name":"a_main","callee_file":"lib/a/main.ml","call_site":"test/alpha_test.ml:3","kind":"MUST"}',
  '{"type":"call","caller_name":"t_beta","caller_file":"test/beta_test.ml","callee_name":"b_main","callee_file":"lib/b/main.ml","call_site":"test/beta_test.ml:2","kind":"MUST"}',
  '',
].join('\n');

// One campaign. `catalogue` and `report` are arrays of objects; `ids` is the order the
// engine stub activates mutants in. Returns { code, stdout, stderr, db }.
function campaign(name, catalogue, report, ids) {
  const d = path.join(W, name);
  fs.mkdirSync(d, { recursive: true });
  const db = path.join(d, 't.db');
  fs.writeFileSync(path.join(d, 'stream.ndjson'), STREAM);
  const loaded = spawnSync(LOAD, [db], { input: STREAM, encoding: 'utf8' });
  if (loaded.status !== 0) fatal(`${name}: arch-load failed: ${loaded.stderr}`);
  fs.writeFileSync(path.join(d, 'cat.ndjson'), catalogue.map((c) => JSON.stringify(c)).join('\n') + '\n');
  fs.writeFileSync(path.join(d, 'report.ndjson'), report.map((c) => JSON.stringify(c)).join('\n') + '\n');
  const plan = spawnSync(MUT, ['plan', db, '--tests', 'file:test/**', '--format', 'json'], { encoding: 'utf8' });
  if (plan.status !== 0) fatal(`${name}: arch-mutants plan failed: ${plan.stderr}`);
  fs.writeFileSync(path.join(d, 'plan.json'), plan.stdout);
  // The engine stub IS the loop mutaml runs internally: it calls the wrapper once per
  // mutant with MUTAML_MUTANT set, which is what makes the trace lines real.
  fs.writeFileSync(
    path.join(d, 'engine.sh'),
    '#!/bin/sh\nfor m in ' + ids.join(' ') + '; do MUTAML_MUTANT="$m" "$1" || true; done\nexit 0\n'
  );
  fs.chmodSync(path.join(d, 'engine.sh'), 0o755);
  const r = spawnSync(
    MUT,
    ['run', db, '--plan', path.join(d, 'plan.json'), '--engine', path.join(d, 'engine.sh'),
      '--test-cmd', 'true', '--catalogue', path.join(d, 'cat.ndjson'),
      '--report', path.join(d, 'report.ndjson'), '--tests', 'file:test/**', '--format', 'json'],
    { encoding: 'utf8', env: { ...process.env, ARCH_MUTANTS_WORKDIR: path.join(d, 'work'), ARCH_MUTANTS_WRAPPER: WRAPPER } }
  );
  return { code: r.status, stdout: r.stdout || '', stderr: r.stderr || '', db };
}

// ---- PROBE 1: two mutants on ONE line must not have their statuses swapped -------------
console.log('probe 1 — two mutants on lib/x.ml:15, the engine reporting the SECOND killed');
{
  const cat = [
    { id: 'm1', file: 'lib/x.ml', line: 15, col_start: 3, col_end: 9, replacement: 'true' },
    { id: 'm2', file: 'lib/x.ml', line: 15, col_start: 11, col_end: 15, replacement: 'false' },
  ];
  const rep = [
    { file: 'lib/x.ml', line: 15, status: 'KILLED', id: 'm2', col_start: 11, col_end: 15, replacement: 'false' },
    { file: 'lib/x.ml', line: 15, status: 'SURVIVED', id: 'm1', col_start: 3, col_end: 9, replacement: 'true' },
  ];
  const r = campaign('p1', cat, rep, ['m1', 'm2']);
  if (r.code !== 0) { console.log(`  ✗ the campaign did not run (exit ${r.code})`); console.log(r.stderr.split('\n').slice(0, 8).map((l) => '      | ' + l).join('\n')); fails++; }
  assertEq('cols 3-9 / true is the SURVIVED one', 'SURVIVED',
    sql(r.db, "SELECT r.engine_status FROM mutant_runs r JOIN mutants m ON m.id=r.mutant_id WHERE m.col_start=3"));
  assertEq('cols 11-15 / false is the KILLED one', 'KILLED',
    sql(r.db, "SELECT r.engine_status FROM mutant_runs r JOIN mutants m ON m.id=r.mutant_id WHERE m.col_start=11"));
  assertEq('the engine id travels with the site it belongs to', 'm1',
    sql(r.db, "SELECT r.engine_mutant_id FROM mutant_runs r JOIN mutants m ON m.id=r.mutant_id WHERE m.col_start=3"));
}

// ---- PROBE 2: a kill is never attributed against a different FILE -----------------------
console.log('probe 2 — lib/a/main.ml and lib/b/main.ml share a basename and a line');
{
  const cat = [
    { id: 'ma', file: 'lib/a/main.ml', line: 15, col_start: 1, col_end: 4, replacement: 'x' },
    { id: 'mb', file: 'lib/b/main.ml', line: 15, col_start: 1, col_end: 4, replacement: 'y' },
  ];
  const rep = [
    { file: 'lib/b/main.ml', line: 15, status: 'KILLED', id: 'mb', col_start: 1, col_end: 4, replacement: 'y' },
    { file: 'lib/a/main.ml', line: 15, status: 'SURVIVED', id: 'ma', col_start: 1, col_end: 4, replacement: 'x' },
  ];
  const r = campaign('p2', cat, rep, ['ma', 'mb']);
  if (r.code !== 0) { console.log(`  ✗ the campaign did not run (exit ${r.code})`); console.log(r.stderr.split('\n').slice(0, 8).map((l) => '      | ' + l).join('\n')); fails++; }
  assertEq('the KILLED row is against lib/b/main.ml', 'lib/b/main.ml',
    sql(r.db, "SELECT m.file_path FROM mutant_runs r JOIN mutants m ON m.id=r.mutant_id WHERE r.engine_status='KILLED'"));
  assertEq('the kill attribution names the b-side file only', 'lib/b/main.ml',
    sql(r.db, "SELECT DISTINCT m.file_path FROM mutant_kills k JOIN mutants m ON m.id=k.mutant_id"));
  assertEq('the kill names the test that reaches THAT file', 't_beta',
    sql(r.db, 'SELECT DISTINCT test_name FROM mutant_kills'));
}

// ---- PROBE 3: two indistinguishable candidates must be REFUSED, not guessed -------------
console.log('probe 3 — a report entry that discriminates between two catalogued sites in no way');
{
  const cat = [
    { id: 'p1', file: 'lib/x.ml', line: 15, col_start: 3, col_end: 9, replacement: 'true' },
    { id: 'p2', file: 'lib/x.ml', line: 15, col_start: 11, col_end: 15, replacement: 'false' },
  ];
  // No id the catalogue knows, no columns, no replacement: nothing to join on but the line.
  const rep = [{ file: 'lib/x.ml', line: 15, status: 'KILLED', id: 'zz' }];
  const r = campaign('p3', cat, rep, ['p1', 'p2']);
  assertEq('the driver refuses (exit 1) rather than taking the head of the list', 1, r.code);
  const named = /indistinguishable|cannot be told apart|ambiguous/i.test(r.stderr);
  assertEq('the refusal says the candidates could not be told apart', 'true', String(named));
  assertEq('no kill row was written on a coin flip', '0', sql(r.db, 'SELECT count(*) FROM mutant_kills'));
  assertEq('the campaign is left incomplete', '0',
    sql(r.db, 'SELECT count(*) FROM mutant_campaigns WHERE completed_at IS NOT NULL'));
}

// ---- PROBE 4: the negative control ------------------------------------------------------
console.log('probe 4 — negative control: an ordinary one-mutant campaign still joins');
{
  const cat = [{ id: 'n1', file: 'lib/x.ml', line: 15, col_start: 3, col_end: 9, replacement: 'true' }];
  const rep = [{ file: 'lib/x.ml', line: 15, status: 'KILLED', id: 'n1', col_start: 3, col_end: 9, replacement: 'true' }];
  const r = campaign('p4', cat, rep, ['n1']);
  assertEq('exit 0', 0, r.code);
  assertEq('one run row, joined', '1', sql(r.db, 'SELECT count(*) FROM mutant_runs'));
  assertEq('it is the KILLED one', 'KILLED', sql(r.db, 'SELECT engine_status FROM mutant_runs'));
  assertEq('nothing went unmatched', '0', (r.stdout.match(/"report_entries_unmatched":\s*(\d+)/) || [, 'missing'])[1]);
  assertEq('the campaign completes', '1',
    sql(r.db, 'SELECT count(*) FROM mutant_campaigns WHERE completed_at IS NOT NULL'));
}

console.log('');
if (fails > 0) {
  console.error(`outcome-join-is-site-identity: FAIL — ${fails} assertion(s) fired.`);
  console.error('  The join between engine outcomes and catalogued sites is not the site identity.');
  console.error('  A join on (basename, line) pairs two mutants on one line in LIST ORDER, so the');
  console.error('  database holds each verdict against the other mutant, and a kill attribution —');
  console.error('  the one record that claims to name a killer — lands on the wrong file.');
  process.exit(1);
}
console.log('outcome-join-is-site-identity: PASS — 4 of 4 probes over 12 assertions.');
console.log('  What would have made this non-zero: joining on Filename.basename plus line and');
console.log('  consuming duplicates in list order (probes 1 and 2), taking the head when two');
console.log('  candidates are indistinguishable (probe 3), or refusing everything (probe 4).');
process.exit(0);
