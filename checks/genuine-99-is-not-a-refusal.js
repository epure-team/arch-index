#!/usr/bin/env node
// checks/genuine-99-is-not-a-refusal.js — runnable directly: `node <path> [repo]`.
//
// Exit convention: 0 = passes · 1 = assertion fired · >=2 = error/setup failure.
//
// WHY THIS EXISTS. `scripts/mutaml-wrapper.sh` reserves exit 99 to mean REFUSED — nothing
// ran — and then ends with `exit "$rc"`, forwarding the TEST COMMAND's own exit code
// unchanged. So a runner that legitimately exits 99 is read as the wrapper's refusal: the
// mutant loses its run row, can never be KILLED, lands in PENDING and blocks the campaign's
// completion for ever. The wrapper's own defence — "no test runner in this repo's profiles
// emits 99" — is a statement about five hardcoded profiles today, and slice 5's arbitrary
// per-profile test commands are exactly what removes it.
//
// The discriminator was free and unused, and it is the reason this is a two-line fix rather
// than an exit-code negotiation: a GENUINE 99 reaches the end of the wrapper and writes its
// trace line; a refusal exits from `fail()` before the trace is written. The wrapper knows
// which one it is at the moment it happens.
//
// THE THREE PROBES, run through the real chain — the engine stub captures the WRAPPER's exit
// code and writes it into a mutaml-format report, which is what mutaml itself does
// (src/runner/runner.ml:109-110 persists the raw code over a `status : int`):
//
//   1 A TEST RUNNER EXITING 99 must reach the database as an OUTCOME, never as a refusal.
//   2 A REAL REFUSAL must still be a refusal — the guard must not have been traded away.
//   3 THE DISCRIMINATOR must be the one claimed: a trace line for the genuine 99, none for
//     the refusal.

const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync, spawnSync } = require('child_process');

const repo = process.argv[2] || path.resolve(__dirname, '..');
const B = path.join(repo, '_build', 'default', 'bin');
const LOAD = path.join(B, 'arch_load', 'arch_load.exe');
const MUT = path.join(B, 'arch_mutants', 'arch_mutants.exe');
const WRAPPER = path.join(repo, 'scripts', 'mutaml-wrapper.sh');

function fatal(msg) { console.error(`genuine-99-is-not-a-refusal: ${msg}`); process.exit(2); }
for (const p of [LOAD, MUT]) if (!fs.existsSync(p)) fatal(`${p} is not built — run 'dune build' first. Nothing was checked.`);
if (!fs.existsSync(WRAPPER)) fatal(`${WRAPPER} is missing`);
try { execFileSync('sqlite3', ['-version'], { stdio: 'ignore' }); } catch (e) { fatal('sqlite3 is required'); }

const W = fs.mkdtempSync(path.join(os.tmpdir(), 'genuine99.'));
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
  '{"type":"function","name":"other","file_path":"lib/x.ml","line_start":30,"line_end":40}',
  '{"type":"call","caller_name":"t_alpha","caller_file":"test/alpha_test.ml","callee_name":"covered","callee_file":"lib/x.ml","call_site":"test/alpha_test.ml:2","kind":"MUST"}',
  '{"type":"call","caller_name":"t_alpha","caller_file":"test/alpha_test.ml","callee_name":"other","callee_file":"lib/x.ml","call_site":"test/alpha_test.ml:3","kind":"MUST"}',
  '',
].join('\n');

// A mutaml `.muts` catalogue: two mutants, in lib/x.ml, one per function.
const MUTS = JSON.stringify([
  { number: 1, repl: 'true', loc: { loc_start: { pos_fname: 'lib/x.ml', pos_lnum: 15, pos_bol: 0, pos_cnum: 3 }, loc_end: { pos_fname: 'lib/x.ml', pos_lnum: 15, pos_bol: 0, pos_cnum: 9 }, loc_ghost: false } },
  { number: 2, repl: 'false', loc: { loc_start: { pos_fname: 'lib/x.ml', pos_lnum: 35, pos_bol: 0, pos_cnum: 1 }, loc_end: { pos_fname: 'lib/x.ml', pos_lnum: 35, pos_bol: 0, pos_cnum: 4 }, loc_ghost: false } },
]);

const d = path.join(W, 'c');
fs.mkdirSync(d, { recursive: true });
const db = path.join(d, 't.db');
{
  const r = spawnSync(LOAD, [db], { input: STREAM, encoding: 'utf8' });
  if (r.status !== 0) fatal(`arch-load failed: ${r.stderr}`);
}
fs.writeFileSync(path.join(d, 'cat.muts'), MUTS);
{
  const plan = spawnSync(MUT, ['plan', db, '--tests', 'file:test/**', '--format', 'json'], { encoding: 'utf8' });
  if (plan.status !== 0) fatal(`arch-mutants plan failed: ${plan.stderr}`);
  fs.writeFileSync(path.join(d, 'plan.json'), plan.stdout);
}

// The test runner: exits 99 deliberately. A real runner may; nothing forbids it.
fs.writeFileSync(path.join(d, 'runner99.sh'), '#!/bin/sh\nexit 99\n');
fs.chmodSync(path.join(d, 'runner99.sh'), 0o755);

// The engine stub IS mutaml's loop, faithfully in the one respect that matters: it persists
// the WRAPPER's RAW exit code into the report. Mutant 1 runs normally, so its 99 comes from
// the test runner. Mutant 2 is invoked with the selection file removed from the environment,
// which is a genuine wrapper refusal — and the wrapper exits before writing a trace line.
const entry = (n, line, cs, ce, repl, rcvar) =>
  `{"status":${rcvar},"mutant":{"number":${n},"repl":"${repl}","loc":{"loc_start":{"pos_fname":"lib/x.ml","pos_lnum":${line},"pos_bol":0,"pos_cnum":${cs}},"loc_end":{"pos_fname":"lib/x.ml","pos_lnum":${line},"pos_bol":0,"pos_cnum":${ce}},"loc_ghost":false}}}`;
// A heredoc, not a double-quoted printf: the report is JSON, so every double quote in it
// would be eaten by the shell before printf ever saw it.
fs.writeFileSync(path.join(d, 'engine.sh'), `#!/bin/sh
MUTAML_MUTANT='lib/x:1' "$1"; RC1=$?
env -u ARCH_MUTANTS_SELECTION MUTAML_MUTANT='lib/x:2' "$1"; RC2=$?
cat > "$REPORT" <<EOF
[${entry(1, 15, 3, 9, 'true', '$RC1')},${entry(2, 35, 1, 4, 'false', '$RC2')}]
EOF
echo "wrapper exit codes: 1=$RC1 2=$RC2" >&2
exit 0
`);
fs.chmodSync(path.join(d, 'engine.sh'), 0o755);

const work = path.join(d, 'work');
const reportPath = path.join(d, 'mutaml-report.json');
const r = spawnSync(MUT,
  ['run', db, '--plan', path.join(d, 'plan.json'), '--engine', path.join(d, 'engine.sh'),
    '--test-cmd', path.join(d, 'runner99.sh'), '--catalogue', path.join(d, 'cat.muts'),
    '--from', 'mutaml', '--report', reportPath, '--tests', 'file:test/**', '--format', 'json'],
  { encoding: 'utf8', env: { ...process.env, ARCH_MUTANTS_WORKDIR: work, ARCH_MUTANTS_WRAPPER: WRAPPER, REPORT: reportPath } });
const out = r.stdout || '';
const err = r.stderr || '';
const jnum = (k) => (out.match(new RegExp(`"${k}":\\s*(-?\\d+)`)) || [, 'missing'])[1];

// The fixture is only meaningful if the wrapper really was reached twice and really did see
// a 99 from the runner. Asserted, not assumed.
const codes = (err.match(/wrapper exit codes: 1=(\d+) 2=(\d+)/) || [, '?', '?']).slice(1);
if (codes[0] === '?') fatal(`the engine stub did not report the wrapper exit codes; stderr was:\n${err.slice(0, 800)}`);

console.log('probe 1 — the TEST RUNNER exits 99');
{
  assertEq('the run itself does not fail', 0, r.status);
  assertEq('mutant 1 is recorded as an outcome, not a refusal', '1', sql(db, "SELECT count(*) FROM mutant_runs r JOIN mutants m ON m.id=r.mutant_id WHERE m.line=15"));
  assertEq('and that outcome is KILLED — the tests failed', 'KILLED', sql(db, "SELECT r.engine_status FROM mutant_runs r JOIN mutants m ON m.id=r.mutant_id WHERE m.line=15"));
}

console.log('probe 2 — a REAL wrapper refusal, on the same run');
{
  assertEq('the refusal is still counted as a refusal', '1', jnum('mutants_refused_by_wrapper'));
  assertEq('it has no run row of any kind', '0', sql(db, "SELECT count(*) FROM mutant_runs r JOIN mutants m ON m.id=r.mutant_id WHERE m.line=35"));
  assertEq('the campaign is NOT complete while a mutant was never attempted', 'false',
    (out.match(/"completed":\s*(true|false)/) || [, 'missing'])[1]);
}

console.log('probe 3 — the discriminator the wrapper already holds');
{
  const trace = fs.existsSync(path.join(work, 'wrapper-trace.tsv')) ? fs.readFileSync(path.join(work, 'wrapper-trace.tsv'), 'utf8') : '';
  const lines = trace.split('\n').filter((l) => l.trim() !== '');
  assertEq('exactly one trace line was written', 1, lines.length);
  assertEq('and it is the genuine-99 mutant, not the refused one', 'true', String(lines[0].startsWith('lib/x:1\t')));
}

console.log('');
if (fails > 0) {
  console.error(`genuine-99-is-not-a-refusal: FAIL — ${fails} assertion(s) fired.`);
  console.error('  Exit 99 is not reserved end to end: the wrapper forwards the test command\'s raw');
  console.error('  code, so a runner legitimately exiting 99 is read as the wrapper\'s refusal and the');
  console.error('  mutant can never be killed. The discriminator is free and was unused — a genuine');
  console.error('  99 writes a trace line, a refusal exits before writing one.');
  process.exit(1);
}
console.log('genuine-99-is-not-a-refusal: PASS — 3 of 3 probes over 8 assertions.');
console.log('  What would have made this non-zero: `exit "$rc"` forwarding a test-command 99');
console.log('  unchanged (probe 1), dropping the refusal guard to make room for it (probe 2), or a');
console.log('  wrapper that writes its trace line before deciding it refuses (probe 3).');
process.exit(0);
