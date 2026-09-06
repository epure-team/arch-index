#!/usr/bin/env node
// checks/unmapped-survivor-carries-its-verdict.js — runnable directly: `node <path> [repo]`.
//
// Exit convention: 0 = passes · 1 = assertion fired · >=2 = error/setup failure.
//
// WHY THIS EXISTS. Round 2's fix removed the naked-status shape from the `survivors` array
// and left it, whole, in the `unmapped` array. A survivor the index cannot map to a function
// was published as `{file, line, status: "SURVIVED", id, mutation}` — a bare engine status,
// no verdict and no selection provenance — while the SAME document declared, at its top,
// `survivors_publish_as: UNKNOWN`. Two answers to one question in one object, and the naked
// one is the one attached to the record a reader copies out.
//
// In the text rendering it was worse: the unmapped survivor printed as a bare `file:line`
// with no verdict at all, under a headline reading "1 mutant(s) in the report: 0 survived,
// 0 killed" — because `List.length survivors` excludes the unmapped, while the
// `--fail-on-survivors` gate counts `survivors + unmapped`. The summary line a reader acts
// on contradicted the gate on the same run.
//
// EXECUTED, per the review: index with a ⊤ edge inside the test cone (so the published
// verdict is UNKNOWN and not SURVIVED — the discriminating case), and a report record for a
// file the index does not carry.
//
// THE FOUR PROBES:
//   1 JSON — the unmapped record carries the same three keys a mapped survivor gets:
//     verdict, selection_provenance, verdict_basis.
//   2 TEXT — the verdict is printed for the unmapped survivor, not just its location.
//   3 THE HEADLINE — the count includes unmapped survivors, and names their share.
//   4 NEGATIVE CONTROL — a MAPPED survivor still renders with everything it had.

const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const repo = process.argv[2] || path.resolve(__dirname, '..');
const B = path.join(repo, '_build', 'default', 'bin');
const LOAD = path.join(B, 'arch_load', 'arch_load.exe');
const MUT = path.join(B, 'arch_mutants', 'arch_mutants.exe');

function fatal(msg) { console.error(`unmapped-survivor-verdict: ${msg}`); process.exit(2); }
for (const p of [LOAD, MUT]) if (!fs.existsSync(p)) fatal(`${p} is not built — run 'dune build' first. Nothing was checked.`);

const W = fs.mkdtempSync(path.join(os.tmpdir(), 'unmapped-survivor.'));
process.on('exit', () => { try { fs.rmSync(W, { recursive: true, force: true }); } catch (e) {} });

let fails = 0;
const assertEq = (label, want, got) => {
  if (String(want) === String(got)) console.log(`  ✓ ${label} — ${got}`);
  else { console.log(`  ✗ ${label} — expected ${JSON.stringify(String(want))}, got ${JSON.stringify(String(got))}`); fails++; }
};

// One ⊤ edge held by `covered`, INSIDE the test cone: that is what makes the published
// verdict UNKNOWN rather than SURVIVED, and therefore what makes a naked "SURVIVED" on the
// record visibly the wrong answer rather than an abbreviation of the right one.
const STREAM = [
  '{"type":"function","name":"t_alpha","file_path":"test/alpha_test.ml","line_start":1,"line_end":5}',
  '{"type":"function","name":"covered","file_path":"lib/x.ml","line_start":10,"line_end":20}',
  '{"type":"call","caller_name":"t_alpha","caller_file":"test/alpha_test.ml","callee_name":"covered","callee_file":"lib/x.ml","call_site":"test/alpha_test.ml:2","kind":"MUST"}',
  '{"type":"call","caller_name":"covered","caller_file":"lib/x.ml","callee_name":"*TOP*","callee_file":null,"call_site":"lib/x.ml:12","kind":"MAY_TOP"}',
  '',
].join('\n');

const db = path.join(W, 't.db');
{
  const r = spawnSync(LOAD, [db], { input: STREAM, encoding: 'utf8' });
  if (r.status !== 0) fatal(`arch-load failed: ${r.stderr}`);
}

const report = (name, records) => {
  const p = path.join(W, name);
  fs.writeFileSync(p, records.map((r) => JSON.stringify(r)).join('\n') + '\n');
  return p;
};
const run = (rp, fmt) => {
  const r = spawnSync(MUT, ['report', db, rp, '--tests', 'file:test/**', '--format', fmt], { encoding: 'utf8' });
  if (r.status !== 0) fatal(`arch-mutants report --format ${fmt} exited ${r.status}: ${r.stderr}`);
  return r.stdout || '';
};

// lib/zzz_unmapped.ml is in no index: its survivor cannot be mapped to a function.
const UNMAPPED = report('unmapped.ndjson', [{ file: 'lib/zzz_unmapped.ml', line: 999, status: 'SURVIVED', id: 'u1', mutation: 'a && b -> a || b' }]);
const MAPPED = report('mapped.ndjson', [{ file: 'lib/x.ml', line: 15, status: 'SURVIVED', id: 'm1', mutation: 'a && b -> a || b' }]);

// The premise, asserted rather than assumed: the document-level answer really is UNKNOWN.
// If the fixture ever stopped producing a ⊤-bounded selection, every assertion below would
// still pass while checking nothing interesting.
const jsonUnmapped = JSON.parse(run(UNMAPPED, 'json'));
if (jsonUnmapped.survivors_publish_as !== 'UNKNOWN')
  fatal(`the fixture no longer yields a ⊤-bounded selection (survivors_publish_as = ${jsonUnmapped.survivors_publish_as}); the naked-status case would be indistinguishable from the correct one`);
if (jsonUnmapped.unmapped.length !== 1) fatal('the fixture no longer produces exactly one unmapped survivor');

console.log('probe 1 — the JSON record for an unmapped survivor');
{
  const u = jsonUnmapped.unmapped[0];
  assertEq('it carries a verdict', 'UNKNOWN', u.verdict);
  assertEq('and it is the document-level one, not a naked SURVIVED', jsonUnmapped.survivors_publish_as, u.verdict);
  assertEq('it carries its selection provenance', 'top_bounded', u.selection_provenance);
  assertEq('it carries the basis the verdict was derived from', 'true', String(typeof u.verdict_basis === 'string' && u.verdict_basis.length > 0));
  assertEq('the engine status is still there, beside the verdict and never instead of it', 'SURVIVED', u.status);
}

console.log('probe 2 — the text rendering');
{
  const text = run(UNMAPPED, 'text');
  const line = text.split('\n').find((l) => l.includes('lib/zzz_unmapped.ml:999'));
  assertEq('the unmapped survivor appears at all', 'true', String(!!line));
  assertEq('its line carries the verdict, not just the location', 'true', String(!!line && /UNKNOWN/.test(line)));
}

console.log('probe 3 — the headline count');
{
  const text = run(UNMAPPED, 'text');
  const head = text.split('\n').find((l) => /mutant\(s\) in the report/.test(l)) || '';
  assertEq('the headline exists', 'true', String(head !== ''));
  assertEq('it does NOT read "0 survived" for a report holding one survivor', 'false', String(/0 survived/.test(head)));
  assertEq('it counts the survivor', 'true', String(/1 survived/.test(head)));
  assertEq('and it names the unmapped share inline', 'true', String(/unmapped/i.test(head)));
}

console.log('probe 4 — negative control: a MAPPED survivor is unchanged');
{
  const j = JSON.parse(run(MAPPED, 'json'));
  assertEq('one mapped survivor', 1, j.survivors.length);
  assertEq('nothing unmapped', 0, j.unmapped.length);
  assertEq('it still carries its verdict', 'UNKNOWN', j.survivors[0].verdict);
  assertEq('it still names its function', 'covered', j.survivors[0].function);
  const head = run(MAPPED, 'text').split('\n').find((l) => /mutant\(s\) in the report/.test(l)) || '';
  assertEq('the headline counts it once, and mentions no unmapped share', 'true',
    String(/1 survived/.test(head) && !/unmapped/i.test(head)));
}

console.log('');
if (fails > 0) {
  console.error(`unmapped-survivor-verdict: FAIL — ${fails} assertion(s) fired.`);
  console.error('  A survivor that could not be mapped to a function is still a defect, and it was');
  console.error('  published with a naked engine status while the same document said survivors');
  console.error('  publish as UNKNOWN — and left out of the headline the reader acts on.');
  process.exit(1);
}
console.log('unmapped-survivor-verdict: PASS — 4 of 4 probes over 14 assertions.');
console.log('  What would have made this non-zero: an `unmapped` element carrying {file, line,');
console.log('  status, id, mutation} and nothing else (probe 1), a text line printing only the');
console.log('  location (probe 2), `List.length survivors` in the headline (probe 3), or a fix');
console.log('  that moved the problem onto the mapped survivors instead (probe 4).');
process.exit(0);
