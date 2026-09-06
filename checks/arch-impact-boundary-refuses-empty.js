#!/usr/bin/env node
// checks/arch-impact-boundary-refuses-empty.js — runnable directly: `node <path> [repo]`.
//
// Exit convention: 0 = passes · 1 = assertion fired · >=2 = error/setup failure.
//
// WHY THIS EXISTS. Raised in round 1, re-raised in round 2 after the line moved, dispatched
// neither time. The process boundary to `arch-impact` refused a MISSING or non-list
// `touched` key and nothing else. A present-but-EMPTY array reached `Impact_ok []` and the
// campaign scoped itself to nothing, ran nothing and completed — word for word the outcome
// the sibling arm's own refusal message says it exists to prevent: "refusing to continue on
// an empty set, which would select nothing and read as 'nothing to test'".
//
// WHERE THE REFUSAL BELONGS, because the obvious place is wrong. An empty `touched` array is
// NOT on its own a defect: rules 1 and 2 selecting nothing is exactly what a
// documentation-only range does, and rule 3 — the deleted-test recheck — can still select
// mutants with no touched function at all. Refusing at the boundary breaks that rule, which
// this driver's own tezt suite exercises. The refusal belongs where the UNION of the three
// rules is known, and probe 4 below is what holds it there.
//
// The second half is quieter and worse. Each entry's function name is read with
// `List.filter_map`, so an entry whose `name` field is RENAMED — an arch-impact release that
// calls it `function` or `fn` — is dropped with no count and no message. A touched set
// silently shrunk from twelve to three is indistinguishable from a correct set of three, and
// every mutant outside those three publishes as "not at risk" rather than "not looked at".
//
// THE THREE PROBES:
//   1 EMPTY ARRAY — `{"touched": []}` must be refused with the message the sibling arm
//     already carries.
//   2 RENAMED FIELD — entries the reader cannot understand must be COUNTED and refused, not
//     dropped into an empty set.
//   3 NEGATIVE CONTROL — a well-formed `touched` array must still scope a campaign. Without
//     it, "refuse every arch-impact answer" passes probes 1 and 2.
//   4 THE OTHER NEGATIVE CONTROL — an EMPTY `touched` array whose campaign is still non-empty
//     through the deleted-test rule must RUN. This is the probe that stops probe 1 from being
//     satisfied by a refusal at the wrong place.

const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync, spawnSync } = require('child_process');

const repo = process.argv[2] || path.resolve(__dirname, '..');
const B = path.join(repo, '_build', 'default', 'bin');
const LOAD = path.join(B, 'arch_load', 'arch_load.exe');
const MUT = path.join(B, 'arch_mutants', 'arch_mutants.exe');
const WRAPPER = path.join(repo, 'scripts', 'mutaml-wrapper.sh');

function fatal(msg) { console.error(`arch-impact-boundary: ${msg}`); process.exit(2); }
for (const p of [LOAD, MUT]) if (!fs.existsSync(p)) fatal(`${p} is not built — run 'dune build' first. Nothing was checked.`);
if (!fs.existsSync(WRAPPER)) fatal(`${WRAPPER} is missing`);
try { execFileSync('sqlite3', ['-version'], { stdio: 'ignore' }); } catch (e) { fatal('sqlite3 is required'); }

const W = fs.mkdtempSync(path.join(os.tmpdir(), 'impact-boundary.'));
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

// `impactBody` is the RAW stdout the arch-impact stub prints — the whole point is to control
// shapes the driver's reader has to cope with, including ones a real release could emit.
function campaign(name, impactBody, seedPrior) {
  const d = path.join(W, name);
  fs.mkdirSync(d, { recursive: true });
  const db = path.join(d, 't.db');
  const loaded = spawnSync(LOAD, [db], { input: STREAM, encoding: 'utf8' });
  if (loaded.status !== 0) fatal(`${name}: arch-load failed: ${loaded.stderr}`);
  fs.writeFileSync(path.join(d, 'cat.ndjson'),
    JSON.stringify({ id: 'm1', file: 'lib/x.ml', line: 15, col_start: 3, col_end: 9, replacement: 'true' }) + '\n');
  fs.writeFileSync(path.join(d, 'report.ndjson'),
    JSON.stringify({ file: 'lib/x.ml', line: 15, status: 'KILLED', id: 'm1', col_start: 3, col_end: 9, replacement: 'true' }) + '\n');
  if (seedPrior) {
    // A COMPLETED prior campaign whose single kill row names a test the current index no
    // longer carries. That is rule 3's whole precondition, and it selects lib/x.ml:15 with
    // no touched function at all.
    const seed = fs.readFileSync(path.join(repo, 'mutants-schema-migration.sql'), 'utf8') + `
INSERT INTO mutants(file_path,line,col_start,col_end,replacement,source_hash,function_name)
  VALUES ('lib/x.ml',15,3,9,'true','prior-x','covered');
INSERT INTO mutant_campaigns(engine,engine_path,test_runner_path,granularity,completed_at)
  VALUES ('stub','/bin/true','/bin/true','case','2026-09-05T00:00:00Z');
INSERT INTO mutant_runs(campaign_id,mutant_id,engine_status,selection_provenance,intended_tests,executed_tests)
  SELECT 1, id, 'KILLED', 'proved_superset', 1, 1 FROM mutants;
INSERT INTO mutant_kills(campaign_id,mutant_id,test_name,attribution)
  SELECT 1, id, 't_deleted', 'singleton_executed_set' FROM mutants;
`;
    const sr = spawnSync('sqlite3', [db], { input: seed, encoding: 'utf8' });
    if (sr.status !== 0) fatal(`${name}: seeding the prior campaign failed: ${sr.stderr}`);
  }
  const plan = spawnSync(MUT, ['plan', db, '--tests', 'file:test/**', '--format', 'json'], { encoding: 'utf8' });
  if (plan.status !== 0) fatal(`${name}: arch-mutants plan failed: ${plan.stderr}`);
  fs.writeFileSync(path.join(d, 'plan.json'), plan.stdout);
  fs.writeFileSync(path.join(d, 'engine.sh'), '#!/bin/sh\nMUTAML_MUTANT=m1 "$1" || true\nexit 0\n');
  fs.chmodSync(path.join(d, 'engine.sh'), 0o755);
  fs.writeFileSync(path.join(d, 'impact.sh'), `#!/bin/sh\ncat <<'J'\n${impactBody}\nJ\n`);
  fs.chmodSync(path.join(d, 'impact.sh'), 0o755);
  const r = spawnSync(MUT,
    ['run', db, '--plan', path.join(d, 'plan.json'), '--engine', path.join(d, 'engine.sh'),
      '--test-cmd', 'true', '--catalogue', path.join(d, 'cat.ndjson'),
      '--report', path.join(d, 'report.ndjson'), '--tests', 'file:test/**', '--format', 'json',
      '--diff', 'HEAD~1..HEAD'],
    { encoding: 'utf8', env: { ...process.env, ARCH_MUTANTS_WORKDIR: path.join(d, 'work'),
        ARCH_MUTANTS_WRAPPER: WRAPPER, ARCH_IMPACT: path.join(d, 'impact.sh') } });
  return { code: r.status, stdout: r.stdout || '', stderr: r.stderr || '', db };
}

const campaignRows = (db) => {
  if (!fs.existsSync(db)) return '0';
  if (sql(db, "SELECT count(*) FROM sqlite_master WHERE name='mutant_campaigns'") === '0') return '0';
  return sql(db, 'SELECT count(*) FROM mutant_campaigns');
};

// ---- PROBE 1: a present-but-empty touched array -----------------------------------------
console.log('probe 1 — arch-impact answers {"touched": []}');
{
  const r = campaign('p1', '{"touched": []}');
  assertEq('the driver refuses rather than scoping to nothing', 'true', String(r.code !== 0));
  assertEq('the refusal names the empty set', 'true',
    String(/empty set|nothing to test/i.test(r.stderr)));
  assertEq('the refusal names the EMPTY touched array as the cause', 'true',
    String(/EMPTY `touched` array/i.test(r.stderr)));
  assertEq('no campaign row was written', '0', campaignRows(r.db));
}

// ---- PROBE 2: entries whose `name` field was renamed -------------------------------------
console.log('probe 2 — every entry carries `fn` where the reader wants `name`');
{
  const r = campaign('p2', '{"touched": [{"fn":"covered","how":"line"},{"fn":"other","how":"line"}]}');
  assertEq('the driver refuses rather than silently shrinking the set', 'true', String(r.code !== 0));
  assertEq('the refusal COUNTS the entries it could not read', 'true', String(/\b2\b/.test(r.stderr)));
  assertEq('no campaign row was written', '0', campaignRows(r.db));
}

// ---- PROBE 3: the negative control --------------------------------------------------------
console.log('probe 3 — negative control: a well-formed touched array still scopes a campaign');
{
  const r = campaign('p3', '{"touched": [{"name":"covered","how":"line"}]}');
  assertEq('exit 0', 0, r.code);
  assertEq('one mutant is in scope', '1', (r.stdout.match(/"mutants_catalogued":\s*(\d+)/) || [, 'missing'])[1]);
  assertEq('the campaign completes', 'true', (r.stdout.match(/"completed":\s*(true|false)/) || [, 'missing'])[1]);
}

// ---- PROBE 4: an empty touched array that the DELETED-TEST rule still fills ---------------
console.log('probe 4 — negative control: empty `touched`, but rule 3 re-selects a mutant');
{
  const r = campaign('p4', '{"touched": []}', true);
  assertEq('the campaign RUNS — an empty touched set is not on its own a defect', 0, r.code);
  assertEq('the deleted-test rule re-selected the mutant', '1',
    (r.stdout.match(/"mutants_catalogued":\s*(\d+)/) || [, 'missing'])[1]);
  assertEq('and nothing was touched by the range', '0',
    (r.stdout.match(/"touched_functions":\s*\[([^\]]*)\]/) || [, 'x'])[1].trim() === '' ? '0' : 'more');
}

console.log('');
if (fails > 0) {
  console.error(`arch-impact-boundary: FAIL — ${fails} assertion(s) fired.`);
  console.error('  The boundary accepted an answer that selects nothing, or shrank the touched set');
  console.error('  with no count. A silently shrunk set is indistinguishable from a correct small one,');
  console.error('  and every mutant outside it publishes as "not at risk" rather than "not looked at".');
  process.exit(1);
}
console.log('arch-impact-boundary: PASS — 4 of 4 probes over 13 assertions.');
console.log('  What would have made this non-zero: an empty `touched` array scoping a campaign to');
console.log('  nothing and completing (probe 1), unreadable entries dropped through');
console.log('  List.filter_map with no count (probe 2), refusing every arch-impact answer');
console.log('  (probe 3), or putting probe 1\'s refusal at the BOUNDARY, where it would break the');
console.log('  deleted-test rule (probe 4).');
process.exit(0);
