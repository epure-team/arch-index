#!/usr/bin/env node
// checks/empty-scope-and-unmatched-block-completion.js — runnable directly: `node <path> [repo]`.
//
// Exit convention: 0 = passes · 1 = assertion fired · >=2 = error/setup failure.
//
// WHY THIS EXISTS. Raised in round 1, re-raised in round 2 after the line moved, dispatched
// neither time. A `--diff` whose narrowing left ZERO mutants still stamped `completed_at`,
// and `verdict` then published all-zero counts — the exact "an empty read is not a clean
// read" conflation the rest of this design refuses, and which `load_catalogue`'s own
// empty-catalogue refusal exists to prevent. That refusal fires BEFORE narrowing and cannot
// see this case at all.
//
// Two more facts travelled with it, both measured. `report_entries_unmatched` was 2 — a
// TOTAL join failure — published in the JSON and absent from the `complete` conjunction, so
// a campaign that matched nothing at all was stamped complete. And two real wrapper refusals
// could not be counted: refusals are partitioned out of `matched`, so a refusal whose report
// entry matched no catalogued site reached `n_refused` by no path.
//
// THE FOUR PROBES:
//
//   1 EMPTY SCOPE — `--diff` narrows the catalogue to zero. The campaign must be REFUSED
//     before any row is written, on load_catalogue's own terms.
//   2 UNMATCHED — a report entry matching no catalogued site must leave `completed_at` NULL.
//   3 UNMATCHED REFUSAL — a wrapper refusal whose entry matched nothing must still be
//     counted as a refusal, not vanish between two partitions.
//   4 NEGATIVE CONTROL — a `--diff` that narrows to a NON-empty set still runs and completes.
//     Without it, "refuse every --diff" passes probes 1 to 3.
//
// `arch-impact` is supplied as a stub through ARCH_IMPACT — the same override the driver
// documents and `scripts/check-binary-provenance.sh` probes — so the scope is controlled
// exactly and the probe does not depend on a git range.

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
  console.error(`empty-scope-and-unmatched: ${msg}`);
  process.exit(2);
}
for (const p of [LOAD, MUT]) if (!fs.existsSync(p)) fatal(`${p} is not built — run 'dune build' first. Nothing was checked.`);
if (!fs.existsSync(WRAPPER)) fatal(`${WRAPPER} is missing`);
try { execFileSync('sqlite3', ['-version'], { stdio: 'ignore' }); } catch (e) { fatal('sqlite3 is required'); }

const W = fs.mkdtempSync(path.join(os.tmpdir(), 'empty-scope.'));
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

// touched: the function names the arch-impact stub will name. ids: what the engine activates.
function campaign(name, { catalogue, report, ids, touched }) {
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
    '#!/bin/sh\nfor m in ' + ids.join(' ') + '; do MUTAML_MUTANT="$m" "$1" || true; done\nexit 0\n');
  fs.chmodSync(path.join(d, 'engine.sh'), 0o755);
  const env = { ...process.env, ARCH_MUTANTS_WORKDIR: path.join(d, 'work'), ARCH_MUTANTS_WRAPPER: WRAPPER };
  const argv = ['run', db, '--plan', path.join(d, 'plan.json'), '--engine', path.join(d, 'engine.sh'),
    '--test-cmd', 'true', '--catalogue', path.join(d, 'cat.ndjson'),
    '--report', path.join(d, 'report.ndjson'), '--tests', 'file:test/**', '--format', 'json'];
  if (touched) {
    const body = JSON.stringify({ touched: touched.map((n) => ({ name: n, how: 'line' })) });
    fs.writeFileSync(path.join(d, 'impact.sh'), `#!/bin/sh\ncat <<'J'\n${body}\nJ\n`);
    fs.chmodSync(path.join(d, 'impact.sh'), 0o755);
    env.ARCH_IMPACT = path.join(d, 'impact.sh');
    argv.push('--diff', 'HEAD~1..HEAD');
  }
  const r = spawnSync(MUT, argv, { encoding: 'utf8', env });
  return { code: r.status, stdout: r.stdout || '', stderr: r.stderr || '', db };
}

const CAT = [{ id: 'm1', file: 'lib/x.ml', line: 15, col_start: 3, col_end: 9, replacement: 'true' }];
const jnum = (out, k) => (out.match(new RegExp(`"${k}":\\s*(-?\\d+)`)) || [, 'missing'])[1];
const jbool = (out, k) => (out.match(new RegExp(`"${k}":\\s*(true|false)`)) || [, 'missing'])[1];

// ---- PROBE 1: a --diff narrowing to zero must refuse, before any row is written ---------
console.log('probe 1 — --diff narrows the catalogue to ZERO mutants');
{
  const r = campaign('p1', {
    catalogue: CAT,
    report: [{ file: 'lib/x.ml', line: 15, status: 'KILLED', id: 'm1' }],
    ids: ['m1'],
    touched: ['a_function_this_index_does_not_have'],
  });
  assertEq('the driver refuses (exit 1)', 1, r.code);
  // BOTH conflations must be named, because they are two different wrong readings of the
  // same empty campaign: "nothing to test" (the selection) and "no survivors" (the result).
  assertEq('the refusal names the selection conflation', 'true',
    String(/nothing to test/i.test(r.stderr)));
  assertEq('and the result conflation', 'true', String(/no survivors/i.test(r.stderr)));
  assertEq('no campaign row was written at all', '0',
    fs.existsSync(r.db) ? sql(r.db, "SELECT count(*) FROM sqlite_master WHERE name='mutant_campaigns'") === '0'
      ? '0' : sql(r.db, 'SELECT count(*) FROM mutant_campaigns') : '0');
}

// ---- PROBE 2: an unmatched report entry blocks completion -------------------------------
console.log('probe 2 — a report entry matching no catalogued site');
{
  const r = campaign('p2', {
    catalogue: CAT,
    report: [
      { file: 'lib/x.ml', line: 15, status: 'KILLED', id: 'm1', col_start: 3, col_end: 9, replacement: 'true' },
      { file: 'lib/nowhere.ml', line: 99, status: 'KILLED', id: 'ghost' },
    ],
    ids: ['m1'],
  });
  assertEq('the run itself does not fail', 0, r.code);
  assertEq('the unmatched entry is counted', '1', jnum(r.stdout, 'report_entries_unmatched'));
  assertEq('completed is false in the JSON', 'false', jbool(r.stdout, 'completed'));
  assertEq('completed_at stays NULL in the database', '0',
    sql(r.db, 'SELECT count(*) FROM mutant_campaigns WHERE completed_at IS NOT NULL'));
}

// ---- PROBE 3: a refusal that matched nothing is still counted as a refusal ---------------
console.log('probe 3 — a wrapper refusal whose report entry matched no catalogued site');
{
  const r = campaign('p3', {
    catalogue: CAT,
    report: [
      { file: 'lib/x.ml', line: 15, status: 'KILLED', id: 'm1', col_start: 3, col_end: 9, replacement: 'true' },
      { file: 'lib/nowhere.ml', line: 99, status: 'REFUSED', id: 'ghost' },
    ],
    ids: ['m1'],
  });
  assertEq('the refusal is counted, not lost between two partitions', '1',
    jnum(r.stdout, 'mutants_refused_by_wrapper'));
  assertEq('the campaign is not complete', 'false', jbool(r.stdout, 'completed'));
}

// ---- PROBE 4: the negative control -------------------------------------------------------
console.log('probe 4 — negative control: a --diff narrowing to a NON-empty set still completes');
{
  const r = campaign('p4', {
    catalogue: CAT,
    report: [{ file: 'lib/x.ml', line: 15, status: 'KILLED', id: 'm1', col_start: 3, col_end: 9, replacement: 'true' }],
    ids: ['m1'],
    touched: ['covered'],
  });
  assertEq('exit 0', 0, r.code);
  assertEq('one mutant stayed in scope', '1', jnum(r.stdout, 'mutants_catalogued'));
  assertEq('nothing went unmatched', '0', jnum(r.stdout, 'report_entries_unmatched'));
  assertEq('the campaign completes', 'true', jbool(r.stdout, 'completed'));
}

console.log('');
if (fails > 0) {
  console.error(`empty-scope-and-unmatched: FAIL — ${fails} assertion(s) fired.`);
  console.error('  A campaign that attempted nothing, or matched nothing, was published as complete.');
  console.error('  An empty read and a clean read are the one distinction this design exists to keep.');
  process.exit(1);
}
console.log('empty-scope-and-unmatched: PASS — 4 of 4 probes over 14 assertions.');
console.log('  What would have made this non-zero: stamping completed_at on a --diff that narrowed');
console.log('  to zero (probe 1), leaving !unmatched out of the `complete` conjunction (probe 2),');
console.log('  counting refusals only over the MATCHED partition (probe 3), or refusing every');
console.log('  --diff (probe 4).');
process.exit(0);
