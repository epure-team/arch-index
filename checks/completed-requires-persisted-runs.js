#!/usr/bin/env node
// checks/completed-requires-persisted-runs.js — runnable directly: `node <path> [repo]`.
//
// Exit convention: 0 = passes · 1 = assertion fired · >=2 = error/setup failure.
//
// WHY THIS EXISTS. `completed_at` is the strongest claim this schema can make: the migration
// says a mutant with no `mutant_runs` row inside a campaign whose `completed_at` is NULL is
// PENDING, never SURVIVED. The whole PENDING/SURVIVED distinction — the distinction the tool
// exists for — rests on that stamp being honest.
//
// It was not checked against anything. `run` decided completeness from arithmetic over its
// OWN in-memory counters (`pending = catalogued - n_attempted`, plus the refused, unobserved
// and unmatched tallies) and never once asked the database how many rows it had actually
// WRITTEN. Every `insert_run` failure was caught with `prerr_endline` and dropped, and the
// counters had already been incremented before the write, so a failed write produced a
// campaign that printed `survived: 1`, held zero rows, and stamped `completed_at` anyway. A
// lost survivor was then indistinguishable from no survivor.
//
// This check does NOT reproduce any one cause of a failed write — the point is that the
// cause does not matter and the driver must not have to enumerate them. It induces a write
// failure by the most neutral means available, a SQLite trigger on `mutant_runs` created in
// the fixture database before the driver ever opens it, and then asks the only two questions
// that matter: is the stamp withheld, and does the tool SAY the number it wrote differs from
// the number it attempted.
//
// The probes:
//   1 SHORTFALL — one attempted mutant, its run row rejected at the database. `completed_at`
//     must stay NULL, the exit status must be non-zero, and stderr must state both numbers.
//   2 NEGATIVE CONTROL — the identical fixture with no trigger must complete, so that
//     "never complete anything" cannot pass probe 1.
//
// Anchored on content: the unreconciled stamp was `if complete then MDb.complete_campaign`
// guarded only by in-memory tallies, in `run` (:2239 at the time this was written), with the
// swallowed write at `with MDb.Write_failed msg -> prerr_endline` a few lines above.

const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync, spawnSync } = require('child_process');

const repo = process.argv[2] || path.resolve(__dirname, '..');
const B = path.join(repo, '_build', 'default', 'bin');
const LOAD = path.join(B, 'arch_load', 'arch_load.exe');
const MUT = path.join(B, 'arch_mutants', 'arch_mutants.exe');
const WRAPPER = path.join(repo, 'scripts', 'mutaml-wrapper.sh');
const MIGRATION = path.join(repo, 'mutants-schema-migration.sql');

function fatal(msg) {
  console.error(`completed-requires-persisted-runs: ${msg}`);
  process.exit(2);
}
for (const p of [LOAD, MUT])
  if (!fs.existsSync(p)) fatal(`${p} is not built — run 'dune build' first. Nothing was checked.`);
for (const p of [WRAPPER, MIGRATION]) if (!fs.existsSync(p)) fatal(`${p} is missing`);
try { execFileSync('sqlite3', ['-version'], { stdio: 'ignore' }); } catch (e) { fatal('sqlite3 is required'); }

const W = fs.mkdtempSync(path.join(os.tmpdir(), 'completed-reconcile.'));
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

const CAT = [{ id: 'k1', file: 'lib/x.ml', line: 15, col_start: 3, col_end: 9, replacement: 'true' }];
const REP = [{ file: 'lib/x.ml', line: 15, status: 'SURVIVED', id: 'k1', col_start: 3, col_end: 9, replacement: 'true' }];

function campaign(name, { blockWrites }) {
  const d = path.join(W, name);
  fs.mkdirSync(d, { recursive: true });
  const db = path.join(d, 't.db');
  const loaded = spawnSync(LOAD, [db], { input: STREAM, encoding: 'utf8' });
  if (loaded.status !== 0) fatal(`${name}: arch-load failed: ${loaded.stderr}`);
  if (blockWrites) {
    // Apply the campaign's own migration first — it is IF NOT EXISTS throughout, so the
    // driver re-applying it is a no-op — then arm a trigger that rejects the run row. This
    // stands in for ANY cause of a rejected write; the driver must not have to know which.
    execFileSync('sqlite3', [db], { input: fs.readFileSync(MIGRATION, 'utf8'), encoding: 'utf8' });
    execFileSync('sqlite3', [db,
      "CREATE TRIGGER reject_run BEFORE INSERT ON mutant_runs BEGIN SELECT RAISE(ABORT, 'rejected by the fixture'); END;"],
      { encoding: 'utf8' });
  }
  fs.writeFileSync(path.join(d, 'cat.ndjson'), CAT.map((c) => JSON.stringify(c)).join('\n') + '\n');
  fs.writeFileSync(path.join(d, 'report.ndjson'), REP.map((c) => JSON.stringify(c)).join('\n') + '\n');
  const plan = spawnSync(MUT, ['plan', db, '--tests', 'file:test/**', '--format', 'json'], { encoding: 'utf8' });
  if (plan.status !== 0) fatal(`${name}: arch-mutants plan failed: ${plan.stderr}`);
  fs.writeFileSync(path.join(d, 'plan.json'), plan.stdout);
  fs.writeFileSync(path.join(d, 'engine.sh'),
    '#!/bin/sh\nfor m in \'k1\'; do MUTAML_MUTANT="$m" "$1" || true; done\nexit 0\n');
  fs.chmodSync(path.join(d, 'engine.sh'), 0o755);
  const r = spawnSync(MUT,
    ['run', db, '--plan', path.join(d, 'plan.json'), '--engine', path.join(d, 'engine.sh'),
      '--test-cmd', 'true', '--catalogue', path.join(d, 'cat.ndjson'),
      '--report', path.join(d, 'report.ndjson'), '--tests', 'file:test/**', '--format', 'json'],
    { encoding: 'utf8', env: { ...process.env, ARCH_MUTANTS_WORKDIR: path.join(d, 'work'), ARCH_MUTANTS_WRAPPER: WRAPPER } });
  return { code: r.status, stdout: r.stdout || '', stderr: r.stderr || '', db };
}

// ---- PROBE 1: the run row is rejected; the stamp must be withheld -----------------------
console.log('probe 1 — one attempted mutant whose run row the database rejects');
{
  const r = campaign('blocked', { blockWrites: true });
  assertEq('the driver reports a non-zero status', 'true', String(r.code !== 0));
  assertEq('zero run rows were actually persisted', '0', sql(r.db, 'SELECT count(*) FROM mutant_runs'));
  assertEq('completed_at is NOT stamped', '0',
    sql(r.db, 'SELECT count(*) FROM mutant_campaigns WHERE completed_at IS NOT NULL'));
  // Not merely "it failed" — the reconciliation must SAY both numbers, because "0 of 1
  // persisted" is the fact an operator acts on and "a write failed" is not.
  assertEq('stderr states the rows written against the mutants attempted', 'true',
    String(/0[^\n]*\b1\b/.test(r.stderr) && /persist|written|reconcil/i.test(r.stderr)));
}

// ---- PROBE 2: the negative control ------------------------------------------------------
console.log('probe 2 — negative control: the same fixture with nothing blocking the write');
{
  const r = campaign('clear', { blockWrites: false });
  assertEq('exit 0', 0, r.code);
  assertEq('one run row persisted', '1', sql(r.db, 'SELECT count(*) FROM mutant_runs'));
  assertEq('it is the SURVIVED one', 'SURVIVED', sql(r.db, 'SELECT engine_status FROM mutant_runs'));
  assertEq('completed_at IS stamped', '1',
    sql(r.db, 'SELECT count(*) FROM mutant_campaigns WHERE completed_at IS NOT NULL'));
}

console.log('');
if (fails > 0) {
  console.error(`completed-requires-persisted-runs: FAIL — ${fails} assertion(s) fired.`);
  console.error('  A campaign is stamped COMPLETE without the driver ever counting the rows it');
  console.error('  wrote. Its in-memory counters are incremented before the write, so a rejected');
  console.error('  insert publishes a verdict that reached no table — and a survivor lost that way');
  console.error('  is indistinguishable from a survivor that never existed.');
  process.exit(1);
}
console.log('completed-requires-persisted-runs: PASS — 2 probes, 8 assertions.');
console.log('  What would have made this non-zero: deciding completeness from in-memory tallies');
console.log('  alone, or catching a failed insert with prerr_endline and carrying on.');
process.exit(0);
