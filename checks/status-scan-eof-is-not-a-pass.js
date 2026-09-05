#!/usr/bin/env node
// checks/status-scan-eof-is-not-a-pass.js — runnable directly: `node <path> [root]`.
//
// Exit convention: 0 = passes · 1 = assertion fired · >=2 = error/setup failure.
//
// WHY THIS EXISTS. scripts/check-status-provenance.sh was repaired once and REINTRODUCED ITS
// OWN VACUITY IN A NEW FORM. The repair replaced a line-oriented scan with a character
// tokenizer, and the tokenizer had no end-of-file guard: a single OCaml char literal holding a
// double quote — `'"'`, ordinary code, and ordinary in a doc comment — opened a string that
// never closed, so every following line was consumed as string content. The check then scanned
// ZERO records and printed PASS. Measured: a fixture with `(* '"' *)` above an `Assoc carrying
// engine_status and no provenance gave "inspected 0 JSON record(s)" and exit 0, while the
// byte-identical fixture without the comment gave exit 1.
//
// The general shape, which is what this check pins rather than the one literal: A SCAN THAT
// LOST ITS PLACE MUST NOT REPORT COVERAGE. Three ways to lose it — an unterminated string, an
// unclosed comment, an unclosed record — and the sibling scripts/check-no-score.sh already
// emitted the first two. So this asserts the guard is red in all three states AND that the
// char literal is tokenized rather than mistaken for a delimiter.
//
// It also asserts the two ordinary answers, because a guard that fails on everything is as
// useless as one that passes on everything: a clean record must still be 0, a bare offender
// must still be 1, and the offender-behind-a-char-literal must be found ON ITS MERITS — the
// output has to say it inspected the record, not merely that the scan broke.

'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const root = process.argv[2] || path.resolve(__dirname, '..');
const guard = path.join(root, 'scripts', 'check-status-provenance.sh');

if (!fs.existsSync(guard)) {
  console.error(`status-scan-eof-is-not-a-pass: ${guard} does not exist — nothing measured, nothing asserted.`);
  process.exit(2);
}

const work = fs.mkdtempSync(path.join(os.tmpdir(), 'status-scan-eof-'));
process.on('exit', () => fs.rmSync(work, { recursive: true, force: true }));

const RECORD_OK =
  'let j status prov =\n' +
  '  `Assoc [ ("engine_status", `String status); ("selection_provenance", `String prov) ]\n';
const RECORD_BAD = 'let j status =\n  `Assoc [ ("engine_status", `String status) ]\n';

// Each case is a whole .ml file and the exit it must produce. `needle` is asserted against the
// combined output so a case cannot be satisfied by the RIGHT exit for the WRONG reason — the
// exact substitution this check exists to prevent.
const cases = [
  {
    name: 'a clean record',
    body: RECORD_OK,
    want: 0,
    needle: 'inspected 1 JSON record',
  },
  {
    name: 'a bare offender',
    body: RECORD_BAD,
    want: 1,
    needle: 'a JSON record carries a status without selection_provenance',
  },
  {
    name: 'an offender behind a comment holding a quote-char literal',
    body: `(* a doc comment holding a char literal: '"' *)\n${RECORD_BAD}`,
    want: 1,
    needle: 'a JSON record carries a status without selection_provenance',
  },
  {
    name: 'a clean record behind a quote-char literal in code',
    body: `let q = '"'\nlet _ = q\n${RECORD_OK}`,
    want: 0,
    needle: 'inspected 1 JSON record',
  },
  {
    name: 'an unterminated string literal at end of file',
    body: `let s = "unterminated\n${RECORD_BAD}`,
    want: 1,
    needle: 'UNTERMINATED string literal at end of file',
  },
  {
    name: 'an unclosed comment at end of file',
    body: `(* unclosed comment\n${RECORD_BAD}`,
    want: 1,
    needle: 'UNBALANCED comment depth',
  },
  {
    name: 'an unclosed `Assoc record at end of file',
    body: 'let j status =\n  `Assoc [ ("engine_status", `String status)\n',
    want: 1,
    needle: 'UNCLOSED `Assoc record at end of file',
  },
];

const failures = [];
cases.forEach((c, i) => {
  const dir = path.join(work, `case${i}`);
  fs.mkdirSync(dir);
  fs.writeFileSync(path.join(dir, 'x.ml'), c.body);
  const r = spawnSync('/usr/bin/env', ['bash', guard, dir], { encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 });
  if (r.error) {
    console.error(`status-scan-eof-is-not-a-pass: could not run the guard: ${r.error.message}`);
    process.exit(2);
  }
  const out = `${r.stdout || ''}${r.stderr || ''}`;
  const got = r.status;
  if (got >= 2) {
    console.error(`status-scan-eof-is-not-a-pass: the guard exited ${got} (harness error) on "${c.name}":`);
    console.error(out.replace(/^/gm, '    '));
    process.exit(2);
  }
  const okExit = got === c.want;
  const okReason = out.includes(c.needle);
  console.log(`  ${okExit && okReason ? 'ok  ' : 'FAIL'} ${c.name} — exit ${got} (want ${c.want})`);
  if (!okExit || !okReason) failures.push({ c, got, out, okExit, okReason });
});

console.log(`status-scan-eof-is-not-a-pass: ${cases.length} fixture(s) through scripts/check-status-provenance.sh.`);

if (failures.length) {
  console.error(`  ${failures.length} of ${cases.length} did not behave as the guard's own contract requires:`);
  for (const f of failures) {
    console.error(`\n  ── ${f.c.name}`);
    if (!f.okExit) console.error(`     exit ${f.got}, wanted ${f.c.want}`);
    if (!f.okReason) console.error(`     output never said: ${f.c.needle}`);
    console.error(f.out.replace(/^/gm, '       '));
  }
  console.error('\n  A scan that ended inside a string, inside a comment or inside a record consumed the');
  console.error('  rest of the file as prose. It inspected nothing it could have judged, so its zero is');
  console.error('  not coverage and must never be printed as PASS.');
  process.exit(1);
}

console.log('  Every state that makes the scan worthless is a hit, and the two ordinary answers still hold.');
process.exit(0);
