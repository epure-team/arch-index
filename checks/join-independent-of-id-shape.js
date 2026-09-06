#!/usr/bin/env node
// checks/join-independent-of-id-shape.js — runnable directly: `node <path> [repo]`.
//
// Exit convention: 0 = passes · 1 = assertion fired · >=2 = error/setup failure.
//
// WHY THIS EXISTS, AND WHY IT IS NOT checks/outcome-join-is-site-identity.js.
//
// That check proved the join uses the SITE. It did not — and could not — prove that the
// join's ANSWER is independent of what the catalogue happens to CALL its mutants, because
// every fixture it builds names them `m1`, `m2`, `ma`, `mb`, `p1`, `n1`. Three rounds of
// review closed on the same defect underneath it: `load_generic` wrote a SYNTHESISED
// ordinal — the physical line counter of the report file — into the same `id : string`
// field that carries an engine's real name for a mutant, and the join's first arm then
// compared that field against the catalogue's own id. The comparison therefore succeeded or
// failed on the LEXICAL FORM of the catalogue's identifiers:
//
//   * a catalogue numbered 1, 2 collides with the report's line ordinals 1, 2, so the join
//     pairs report line N with catalogue entry N — LIST ORDER, wearing an id's clothes —
//     and stores each verdict against the other mutant;
//   * the IDENTICAL report against a catalogue named m1, m2 misses that arm entirely, falls
//     through to the site key, and is correct.
//
// A fixture with named ids cannot see this. That is the whole point of this file: it runs
// ONE report against TWO catalogues that differ in nothing but the SHAPE of their ids, and
// asserts both that each is right and that the two AGREE. The agreement assertion is the
// general one — it fires for any residue of id-shape sensitivity, not only for the ordinal
// collision that happens to be the instance we found.
//
// The design rule this enforces, stated as a property rather than a mechanism: an engine id
// is a COORDINATE, not an identity. It is handed out by one run of one engine over one
// catalogue; nothing in the mutant determines it. Re-run the engine, reorder the catalogue,
// change the adapter, and the same mutant gets a different number. A join keyed on it is a
// join keyed on a position, and it silently misattributes the moment the position moves.
//
// Anchored on CONTENT, not on a coordinate: the defect was `by_id` matching
// `sel.sel_site.s_id = m.id` in `run`'s join (:2040 at the time this was written) against an
// `id` filled by `Option.value ~default:(string_of_int !n)` in `load_generic` (:450 then).

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
  console.error(`join-independent-of-id-shape: ${msg}`);
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

const W = fs.mkdtempSync(path.join(os.tmpdir(), 'join-id-shape.'));
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

// The SAME two mutant sites, and the SAME report, under two id vocabularies. The report
// entries carry NO `id` of their own — which is the ordinary case for a generic engine and
// the case that makes the driver synthesise one — but they DO carry the column span and the
// replacement, so the site key alone decides them without ambiguity.
//
// The report's FIRST line describes the SECOND catalogue entry. That ordering is the entire
// experiment: under a line-ordinal join, report line 1 lands on catalogue entry 1.
const REPORT = [
  { file: 'lib/x.ml', line: 15, status: 'KILLED', col_start: 11, col_end: 15, replacement: 'false' },
  { file: 'lib/x.ml', line: 15, status: 'SURVIVED', col_start: 3, col_end: 9, replacement: 'true' },
];

// FOUR ARMS, and the last two are the ones nobody had written.
//
// Two PURE arms — wholly numbered, wholly named — are necessary and NOT sufficient. A residue
// of id-shape sensitivity that required EVERY catalogue id to be numeric would pass both of
// them: each arm would be individually right, and the agreement assertion would be comparing
// two correct answers. That is the difference between a check that distinguishes two trees and
// a check that enforces a property.
//
//   MIXED — ['1', 'm2']: one entry collides with a report line ordinal and the other does not.
//     A partial residue lives exactly here, and it degrades worse than the pure numbered case:
//     the colliding entry is captured by the ordinal while the second entry then finds its own
//     site already consumed, so one verdict is inverted AND one is lost.
//   DEGENERATE — a single mutant whose id '1' coincides with the ordinal 1 by accident. There
//     is nothing to permute with, so the collision is INVISIBLE and this arm is green on the
//     broken code too. It is here deliberately: it states the property (the answer does not
//     depend on the id) rather than exhibiting a permutation, and it is what stops a future
//     rewrite from "fixing" the join by special-casing multi-candidate lines.
const arms = [
  { name: 'numbered', label: "numbered 1,2 — both ids collide with the report file's line ordinals", ids: ['1', '2'] },
  { name: 'named', label: 'named m1,m2 — neither id can collide with any ordinal', ids: ['m1', 'm2'] },
  { name: 'mixed', label: "MIXED 1,m2 — the first id collides with an ordinal, the second does not", ids: ['1', 'm2'] },
];

const observed = [];

for (const arm of arms) {
  console.log(`arm — a catalogue ${arm.label}`);
  const cat = [
    { id: arm.ids[0], file: 'lib/x.ml', line: 15, col_start: 3, col_end: 9, replacement: 'true' },
    { id: arm.ids[1], file: 'lib/x.ml', line: 15, col_start: 11, col_end: 15, replacement: 'false' },
  ];
  const r = campaign('arm-' + arm.name, cat, REPORT, arm.ids);
  if (r.code !== 0) {
    console.log(`  ✗ the campaign did not run (exit ${r.code})`);
    console.log(r.stderr.split('\n').slice(0, 10).map((l) => '      | ' + l).join('\n'));
    fails++;
    observed.push({ name: arm.name, a: `exit ${r.code}`, b: `exit ${r.code}` });
    continue;
  }
  const at3 = sql(r.db, 'SELECT r.engine_status FROM mutant_runs r JOIN mutants m ON m.id=r.mutant_id WHERE m.col_start=3');
  const at11 = sql(r.db, 'SELECT r.engine_status FROM mutant_runs r JOIN mutants m ON m.id=r.mutant_id WHERE m.col_start=11');
  assertEq('cols 3-9 / replacement "true" is the SURVIVED one', 'SURVIVED', at3);
  assertEq('cols 11-15 / replacement "false" is the KILLED one', 'KILLED', at11);
  observed.push({ name: arm.name, a: at3, b: at11 });
}

// The degenerate arm: ONE mutant, its id equal to its own report ordinal. Nothing to permute
// with, so this is green on the broken code as well — which is the point. It asserts the
// PROPERTY on the case where the defect is invisible, and it joins the differential below on
// the one column it has.
console.log('arm — DEGENERATE: a single mutant whose id \'1\' equals its report ordinal by accident');
{
  const cat = [{ id: '1', file: 'lib/x.ml', line: 15, col_start: 3, col_end: 9, replacement: 'true' }];
  const rep = [{ file: 'lib/x.ml', line: 15, status: 'SURVIVED', col_start: 3, col_end: 9, replacement: 'true' }];
  const r = campaign('arm-degenerate', cat, rep, ['1']);
  if (r.code !== 0) {
    console.log(`  ✗ the campaign did not run (exit ${r.code})`);
    console.log(r.stderr.split('\n').slice(0, 10).map((l) => '      | ' + l).join('\n'));
    fails++;
    observed.push({ name: 'degenerate', a: `exit ${r.code}`, b: null });
  } else {
    const at3 = sql(r.db, 'SELECT r.engine_status FROM mutant_runs r JOIN mutants m ON m.id=r.mutant_id WHERE m.col_start=3');
    assertEq('the lone mutant carries its own verdict', 'SURVIVED', at3);
    assertEq('exactly one run row, so nothing was matched twice', '1', sql(r.db, 'SELECT count(*) FROM mutant_runs'));
    observed.push({ name: 'degenerate', a: at3, b: null });
  }
}

// THE GENERAL ASSERTION. Not "each arm is right" — "every arm is the SAME answer". A join that
// still consults the id in any residual way, total or partial, makes these diverge, whatever
// the particular mechanism, because the catalogues differ in nothing else.
console.log('differential — every arm describes the same mutants under the same report');
{
  const base = observed[0];
  for (const o of observed.slice(1)) {
    assertEq(`cols 3-9: ${o.name} agrees with ${base.name}`, base.a, o.a);
    if (o.b !== null && base.b !== null) assertEq(`cols 11-15: ${o.name} agrees with ${base.name}`, base.b, o.b);
  }
}

console.log('');
if (fails > 0) {
  console.error(`join-independent-of-id-shape: FAIL — ${fails} assertion(s) fired.`);
  console.error('  The outcome join still depends on what the catalogue CALLS its mutants. A');
  console.error('  synthesised ordinal sharing a field with a real engine name makes a numbered');
  console.error('  catalogue join by LIST ORDER while an identically-shaped named one joins by');
  console.error('  site — so the same report yields two different databases, and the numbered one');
  console.error('  holds each verdict against the wrong mutant with no error of any kind.');
  process.exit(1);
}
console.log('join-independent-of-id-shape: PASS — 4 arms (numbered, named, MIXED, degenerate).');
console.log('  What would have made this non-zero: any join arm that compares a report-side id');
console.log('  against a catalogue id, since a generic report carries none and the driver must');
console.log('  then invent one from the record\'s position in the file.');
process.exit(0);
