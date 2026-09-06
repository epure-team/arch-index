#!/usr/bin/env node
// checks/mutant-key-parse-error-is-not-a-rejection.js — runnable directly: `node <path> [root]`.
//
// Exit convention: 0 = passes · 1 = assertion fired · >=2 = error/setup failure.
//
// WHY THIS EXISTS. scripts/check-mutant-key.sh asserts that `mutants`'s natural key is live by
// re-offering a row the table already holds and requiring the UNIQUE constraint to reject it.
// The statement that re-offered it named `function_id`, a column that had been deleted from
// mutants-schema-migration.sql, so sqlite3 aborted the INSERT with "table mutants has no column
// named function_id" BEFORE the constraint was consulted — and the script read the resulting
// zero-rows-inserted as the constraint rejecting the row. It then printed "the key is live and
// discriminating". Measured: against a probe schema whose UNIQUE line had been DELETED, so that
// sqlite_master showed no UNIQUE at all, it printed the same sentence and exited 0. It could
// not go red.
//
// So the defect is not the stale column name; the column name is how it got in. THE DEFECT IS
// THAT A STATEMENT WHICH NEVER REACHED THE CONSTRAINT WAS COUNTED AS THE CONSTRAINT ANSWERING.
// This check pins both halves, and the second is the one that survives the next schema change:
//
//   green  — a real population under the real migration: exit 0, and the output must carry NO
//            "Parse error" at all. A pass printed over a parse error is the original bug.
//   red    — the same population under a probe schema with the UNIQUE line removed: exit 1. If
//            this arm does not fire, the check cannot fail and every 0 it has ever printed was
//            worth nothing.
//   unrun  — the same population under a script whose INSERT names a column that does not
//            exist: exit 2, NOT 0 and NOT 1. A parse error is a harness error; it is neither a
//            rejection nor a pass.
//
// Self-contained: it builds its own population and its own two mutated copies under a temp
// directory, and reads nothing from a campaign.

'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const root = process.argv[2] || path.resolve(__dirname, '..');
const script = path.join(root, 'scripts', 'check-mutant-key.sh');
const migration = path.join(root, 'mutants-schema-migration.sql');

for (const f of [script, migration]) {
  if (!fs.existsSync(f)) {
    console.error(`mutant-key-parse-error-is-not-a-rejection: ${f} does not exist — nothing measured.`);
    process.exit(2);
  }
}

const sqlite = spawnSync('/usr/bin/env', ['sqlite3', '--version'], { encoding: 'utf8' });
if (sqlite.status !== 0) {
  console.error('mutant-key-parse-error-is-not-a-rejection: sqlite3 is required and is not runnable.');
  process.exit(2);
}

const work = fs.mkdtempSync(path.join(os.tmpdir(), 'mutant-key-'));
process.on('exit', () => fs.rmSync(work, { recursive: true, force: true }));

const sql = (db, text) => {
  const r = spawnSync('/usr/bin/env', ['sqlite3', db], { input: text, encoding: 'utf8' });
  if (r.status !== 0) {
    console.error(`mutant-key-parse-error-is-not-a-rejection: fixture sqlite3 failed: ${r.stderr}`);
    process.exit(2);
  }
  return r.stdout;
};

const migrationText = fs.readFileSync(migration, 'utf8');
const uniqueLine = /^\s*UNIQUE\(file_path, line, col_start, col_end, replacement, source_hash\).*$/m;
if (!uniqueLine.test(migrationText)) {
  console.error('mutant-key-parse-error-is-not-a-rejection: the migration no longer declares the mutants');
  console.error('  UNIQUE key in the shape this check mutates. That is either the key being dropped or the');
  console.error('  key being rewritten; either way this check can no longer build its red arm, and a check');
  console.error('  that cannot build its red arm must say so rather than pass.');
  process.exit(2);
}

// The population. 200 rows, pairwise distinct on the key and deliberately NOT distinct on the
// columns outside it, so a key that had silently widened would show up as a different answer.
const POP = path.join(work, 'population.db');
sql(POP, migrationText);
{
  const values = [];
  for (let i = 0; i < 200; i++) {
    values.push(`('lib/f${i % 5}.ml', ${i}, 0, 4, '${i % 2 ? 'true' : 'false'}', 'h${String(i).padStart(4, '0')}', 'fn_${i % 7}')`);
  }
  sql(
    POP,
    'INSERT INTO mutants(file_path, line, col_start, col_end, replacement, source_hash, function_name) VALUES\n' +
      values.join(',\n') +
      ';'
  );
}
const rows = Number(sql(POP, 'SELECT count(*) FROM mutants;').trim());
if (rows !== 200) {
  console.error(`mutant-key-parse-error-is-not-a-rejection: the fixture population is ${rows} rows, not 200.`);
  process.exit(2);
}

// Three roots, each a two-file copy of what the script reads: itself and the migration beside it.
const mkRoot = (name, { scriptText, migrationSql }) => {
  const r = path.join(work, name);
  fs.mkdirSync(path.join(r, 'scripts'), { recursive: true });
  fs.writeFileSync(path.join(r, 'scripts', 'check-mutant-key.sh'), scriptText);
  fs.writeFileSync(path.join(r, 'mutants-schema-migration.sql'), migrationSql);
  return path.join(r, 'scripts', 'check-mutant-key.sh');
};

const scriptText = fs.readFileSync(script, 'utf8');
// Removing the UNIQUE line leaves a trailing comma on the line before it; strip that too, or
// sqlite3 refuses the CREATE TABLE and the red arm would be a syntax error instead of a
// missing constraint — which is a different fact and would not test anything.
const noKeySql = migrationText.replace(uniqueLine, '').replace(/,(\s*\n\s*)\);/g, '$1);');
// A column that does not exist, injected into the INSERT column lists exactly as the stale
// `function_id` was. This is the "never reached the constraint" arm. The last column is matched
// by POSITION rather than by name so the arm survives the column being renamed again — naming it
// is what let the original defect hide, and a check that can only mutate one spelling would go
// quiet the same way.
const badColumnText = scriptText.replace(/source_hash,[^)\n]*\)/g, 'source_hash, no_such_column)');
if (badColumnText === scriptText) {
  console.error('mutant-key-parse-error-is-not-a-rejection: the script no longer contains the INSERT column');
  console.error('  list this check mutates, so the parse-error arm cannot be built. Refusing rather than passing.');
  process.exit(2);
}

const arms = [
  { name: 'the real key, on a real population', bin: mkRoot('green', { scriptText, migrationSql: migrationText }), want: 0, forbid: 'Parse error' },
  { name: 'the probe schema with UNIQUE deleted', bin: mkRoot('red', { scriptText, migrationSql: noKeySql }), want: 1, needle: 'was ACCEPTED' },
  { name: 'an INSERT naming a column that does not exist', bin: mkRoot('unrun', { scriptText: badColumnText, migrationSql: migrationText }), want: 2, needle: 'never consulted' },
];

const failures = [];
for (const a of arms) {
  const r = spawnSync('/usr/bin/env', ['bash', a.bin, POP], { encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 });
  if (r.error) {
    console.error(`mutant-key-parse-error-is-not-a-rejection: could not run ${a.bin}: ${r.error.message}`);
    process.exit(2);
  }
  const out = `${r.stdout || ''}${r.stderr || ''}`;
  const okExit = r.status === a.want;
  const okNeedle = a.needle ? out.includes(a.needle) : true;
  const okForbid = a.forbid ? !out.includes(a.forbid) : true;
  console.log(`  ${okExit && okNeedle && okForbid ? 'ok  ' : 'FAIL'} ${a.name} — exit ${r.status} (want ${a.want})`);
  if (!okExit || !okNeedle || !okForbid) failures.push({ a, got: r.status, out, okExit, okNeedle, okForbid });
}

console.log('mutant-key-parse-error-is-not-a-rejection: 3 arm(s) through scripts/check-mutant-key.sh on a 200-row population.');

if (failures.length) {
  for (const f of failures) {
    console.error(`\n  ── ${f.a.name}`);
    if (!f.okExit) console.error(`     exit ${f.got}, wanted ${f.a.want}`);
    if (!f.okNeedle) console.error(`     output never said: ${f.a.needle}`);
    if (!f.okForbid) console.error(`     output contained what it must not: ${f.a.forbid}`);
    console.error(f.out.replace(/^/gm, '       '));
  }
  console.error('\n  CHECK-9 asserts that the key rejects a duplicate. A statement that failed before the');
  console.error('  constraint was consulted did not measure the key, and reading its zero as a rejection is');
  console.error('  how this check reported a live key on a table that had none.');
  process.exit(1);
}

console.log('  A parse error is exit 2, a dropped UNIQUE is exit 1, and the pass is printed over no error at all.');
process.exit(0);
