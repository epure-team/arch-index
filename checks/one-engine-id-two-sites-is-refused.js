#!/usr/bin/env node
// checks/one-engine-id-two-sites-is-refused.js — runnable directly: `node <path> [repo]`.
//
// Exit convention: 0 = passes · 1 = assertion fired · >=2 = error/setup failure.
//
// THIS IS A RULE, NOT A REGRESSION TEST. It states a property of the catalogue the driver
// will accept — the engine id must address at most one selected site — and every arm below
// asserts that property rather than replaying the fixture that exposed it.
//
// WHY IT EXISTS. Step 5a in `run` is commented "THE CATALOGUE MUST BE AN INJECTION FROM ids
// TO SITE KEYS" and checks ONE of the two directions: no two entries may share a site key.
// The other direction was never checked. Two DISTINCT site keys claiming the SAME engine id
// were accepted, and downstream the driver keyed the map from a selection to its database
// row on that engine id:
//
//     Hashtbl.replace mutant_ids s.s_id id      (* filling the map, per selection *)
//     Hashtbl.find_opt mutant_ids sel.sel_site.s_id  (* reading it back, per verdict *)
//
// That is the deleted join arm, alive under a different name: a map keyed on a RUN-SCOPED
// coordinate, standing between a mutant and the row its verdict is stored in.
//
// MEASURED, not argued — two catalogue entries on lib/x.ml:15, one at cols 3-9 replacing
// with `true` and SURVIVED, the other at cols 11-15 replacing with `false` and KILLED, both
// claiming the engine id "1", against the driver at 664e0d8:
//
//   * two `mutants` rows were written, so the sites were correctly distinguished as sites;
//   * the second `Hashtbl.replace mutant_ids` overwrote the first, so BOTH selections
//     resolved to the col-11 row;
//   * ONE `mutant_runs` row was persisted — mutant_id = the col-11 site, engine_status =
//     SURVIVED. That is the col-3 site's verdict stored against the col-11 mutant: a FALSE
//     ATTRIBUTION, the exact failure this round exists to remove;
//   * the KILLED verdict was rejected by UNIQUE(campaign_id, mutant_id), and the only
//     diagnostic was the raw SQLite constraint message.
//
// AND WHAT DID NOT HAPPEN, said plainly so this check is not read as bigger than it is: the
// campaign did NOT read as complete. The reconciliation guard saw 1 row against 2 attempts,
// withheld `completed_at`, published `completed: false` and exited 1. So this was a wrong
// row, not a silent success — a real mitigation, already in the tree, doing its job. What
// remained was a false attribution written into `mutant_runs` and an operator handed a
// constraint error instead of a cause.
//
// AND THE ENGINE ID IS THE WRAPPER'S ONLY HANDLE. `run` writes one selection line per site
// whose first field is the engine id, and the engine activates a mutant by exporting that
// string as MUTAML_MUTANT. Two sites under one id are therefore not merely awkward to store:
// they are genuinely unaddressable — nothing the driver can send activates one and not the
// other. So the honest answer is a REFUSAL, in the same doctrine as 5a: nothing distinguishes
// the candidates, so any choice is list order recorded as a fact.
//
// WHAT THIS CHECK DOES NOT COVER, stated so no reader infers more than it holds:
//   * it does not stop a future author from comparing two engine ids in code. Nothing can:
//     both legitimate uses of the id require rendering it to a string, and `render a =
//     render b` reconstitutes any comparison an abstract type would have forbidden. The
//     naming in arch_mutants.ml (`for_wrapper_argv`, `to_display_string`, never a bare
//     `to_string`) makes such a comparison read as wrong at the call site; it does not
//     prevent one, and this check cannot see one that has no observable consequence.
//   * it looks only at SELECTED sites. A catalogue with duplicate ids among entries that no
//     target reaches is not refused, because no such id is ever handed to the wrapper.
//   * it says nothing about ids that collide only after some future normalisation
//     (trimming, case folding). There is none today; if one is added, this check passes
//     while the collision is reintroduced inside it.

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
  console.error(`one-engine-id-two-sites-is-refused: ${msg}`);
  process.exit(2);
}

for (const p of [LOAD, MUT])
  if (!fs.existsSync(p)) fatal(`${p} is not built — run 'dune build' first. Nothing was checked.`);
if (!fs.existsSync(WRAPPER)) fatal(`${WRAPPER} is missing`);
try {
  execFileSync('sqlite3', ['-version'], { stdio: 'ignore' });
} catch (e) {
  fatal('sqlite3 is required');
}

const W = fs.mkdtempSync(path.join(os.tmpdir(), 'one-id-two-sites.'));
process.on('exit', () => {
  try { fs.rmSync(W, { recursive: true, force: true }); } catch (e) {}
});

let fails = 0;
const assertEq = (label, want, got) => {
  if (String(want) === String(got)) console.log(`  ✓ ${label} — ${got}`);
  else {
    console.log(`  ✗ ${label} — expected ${JSON.stringify(String(want))}, got ${JSON.stringify(String(got))}`);
    fails++;
  }
};

const sql = (db, q) => execFileSync('sqlite3', [db, q], { encoding: 'utf8' }).trim();

const STREAM = [
  '{"type":"function","name":"t_alpha","file_path":"test/alpha_test.ml","line_start":1,"line_end":5}',
  '{"type":"function","name":"covered","file_path":"lib/x.ml","line_start":10,"line_end":20}',
  '{"type":"call","caller_name":"t_alpha","caller_file":"test/alpha_test.ml","callee_name":"covered","callee_file":"lib/x.ml","call_site":"test/alpha_test.ml:2","kind":"MUST"}',
  '',
].join('\n');

function campaign(name, catalogue, report) {
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
  // The engine walks the catalogue's OWN ids, which is what an engine does: it is the
  // catalogue, not the driver, that decides what handle each mutant answers to.
  const ids = catalogue.map((c) => c.id);
  fs.writeFileSync(
    path.join(d, 'engine.sh'),
    '#!/bin/sh\nfor m in ' + ids.map((i) => `'${i}'`).join(' ') + '; do MUTAML_MUTANT="$m" "$1" || true; done\nexit 0\n'
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

const SITE_A = { file: 'lib/x.ml', line: 15, col_start: 3, col_end: 9, replacement: 'true' };
const SITE_B = { file: 'lib/x.ml', line: 15, col_start: 11, col_end: 15, replacement: 'false' };
const SITE_C = { file: 'lib/x.ml', line: 16, col_start: 3, col_end: 9, replacement: 'true' };
const site = (s, extra) => Object.assign({}, s, extra);

// The report is the same in every arm and names each site by its own column span and
// replacement, so the site key alone decides it. Nothing here is ambiguous EXCEPT the ids.
const REPORT_AB = [site(SITE_A, { status: 'SURVIVED' }), site(SITE_B, { status: 'KILLED' })];

// --- The refusing arms. Each one differs from the control in NOTHING but the ids. ---------
function refusingArm(label, catalogue, report) {
  console.log(`arm — ${label}`);
  const r = campaign('arm-' + label.replace(/[^a-z0-9]+/gi, '-').toLowerCase(), catalogue, report);
  if (r.code === 0) {
    console.log('  ✗ the campaign COMPLETED on a catalogue whose engine id addresses two sites');
    console.log(`      | mutant_runs rows: ${sql(r.db, 'SELECT count(*) FROM mutant_runs')}`);
    console.log(`      | mutants rows:     ${sql(r.db, 'SELECT count(*) FROM mutants')}`);
    fails++;
    return;
  }
  assertEq('the driver refuses (exit 1)', 1, r.code);
  // A refusal must leave the database as it was found: no campaign row, and therefore no
  // verdict stored against anything. This is the half that separates a refusal from a crash
  // after a partial write.
  assertEq('no campaign row was written', '0', sql(r.db, 'SELECT count(*) FROM mutant_campaigns'));
  assertEq('no run row was written', '0', sql(r.db, 'SELECT count(*) FROM mutant_runs'));
  // Measured at 664e0d8: this was 2. A refusal that had already inserted the mutants would
  // be a refusal after a partial write, which is a different and weaker thing.
  assertEq('no mutant row was written either', '0', sql(r.db, 'SELECT count(*) FROM mutants'));
  // The diagnostic must NAME the shared id. A refusal an operator cannot act on sends them
  // to read this source, which is the failure mode a bare exit code has.
  const named = catalogue.filter((c, i) => catalogue.findIndex((o) => o.id === c.id) !== i)[0].id;
  assertEq(`the diagnostic names the shared id ${JSON.stringify(named)}`, true,
    r.stderr.includes(JSON.stringify(named)) || r.stderr.includes(`"${named}"`));
}

refusingArm('NUMBERED — two sites both claiming the engine id "1"',
  [site(SITE_A, { id: '1' }), site(SITE_B, { id: '1' })], REPORT_AB);

// The same collision under a vocabulary in which no id could ever be confused with a report
// line ordinal. If the refusal were really about numeric shape, this arm would pass on a
// build that only special-cased digits — which is the difference between a rule and a
// fixture replayed.
refusingArm('NAMED — two sites both claiming the engine id "m1"',
  [site(SITE_A, { id: 'm1' }), site(SITE_B, { id: 'm1' })], REPORT_AB);

// A duplicate among three, where a well-formed third entry could plausibly be read as making
// the catalogue "mostly fine". It does not: one unaddressable pair is one unaddressable pair.
refusingArm('AMONG THREE — a well-formed third entry does not rescue the pair',
  [site(SITE_A, { id: 'a' }), site(SITE_B, { id: 'dup' }), site(SITE_C, { id: 'dup' })],
  [site(SITE_A, { status: 'SURVIVED' }), site(SITE_B, { status: 'KILLED' }), site(SITE_C, { status: 'KILLED' })]);

// --- The control. The refusal must be about the COLLISION and not about the fixture. -------
// Same two sites, same report, ids made distinct and nothing else changed. If this arm ever
// refuses, the rule has become a blanket and the check would otherwise still read green.
console.log('arm — CONTROL: the identical catalogue with distinct ids must still run');
{
  const r = campaign('arm-control', [site(SITE_A, { id: '1' }), site(SITE_B, { id: '2' })], REPORT_AB);
  if (r.code !== 0) {
    console.log(`  ✗ the control campaign did not run (exit ${r.code})`);
    console.log(r.stderr.split('\n').slice(0, 12).map((l) => '      | ' + l).join('\n'));
    fails++;
  } else {
    assertEq('two run rows, one per site', '2', sql(r.db, 'SELECT count(*) FROM mutant_runs'));
    assertEq('cols 3-9 carries its own verdict', 'SURVIVED',
      sql(r.db, 'SELECT r.engine_status FROM mutant_runs r JOIN mutants m ON m.id=r.mutant_id WHERE m.col_start=3'));
    assertEq('cols 11-15 carries its own verdict', 'KILLED',
      sql(r.db, 'SELECT r.engine_status FROM mutant_runs r JOIN mutants m ON m.id=r.mutant_id WHERE m.col_start=11'));
  }
}

console.log('');
if (fails > 0) {
  console.error(`one-engine-id-two-sites-is-refused: FAIL — ${fails} assertion(s) fired.`);
  console.error('  A catalogue whose engine id addresses two DIFFERENT sites was accepted. The id is');
  console.error('  the wrapper\'s only handle on a mutant, so the two are literally unaddressable —');
  console.error('  and the map from a selection to its database row was keyed on that id, so one');
  console.error('  entry overwrote the other and a verdict was stored against the WRONG mutant');
  console.error('  while the second was dropped by UNIQUE(campaign_id, mutant_id). The campaign is');
  console.error('  still marked PARTIAL by the reconciliation guard, so this is a false row rather');
  console.error('  than a silent success — but the false row is written and the operator is handed');
  console.error('  a raw constraint message instead of a cause.');
  process.exit(1);
}
console.log('one-engine-id-two-sites-is-refused: PASS — 3 refusing arms (numbered, named, among three) + 1 control.');
console.log('  What would have made this non-zero: accepting a selection set in which one engine');
console.log('  id addresses two site keys, or refusing the control in which it addresses one.');
process.exit(0);
