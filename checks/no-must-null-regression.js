#!/usr/bin/env node
'use strict';

/*
 * Ratchet — whole-repository MUST-with-NULL-callee ceiling.
 *
 * Guards review finding arch_index.ml:359 (CRITICAL) at the scale the tezt
 * fixtures cannot reach.
 *
 * A `calls` row with kind='MUST' and callee_id IS NULL is read downstream as a
 * PROVEN external leaf: arch_graph.ml turns it into an "ext:" node and emits no
 * TOP frontier marker. So every resolver miss that lands in that shape becomes a
 * confident false UNREACHABLE for the real callee. Round 1 of
 * sound-qualified-name-resolution raised the count on this very repository from
 * 1975 to 2557 — 582 previously-resolved edges dropped — and the whole tezt suite
 * stayed green, because every fixture reference had the shape Wrapper.File.value.
 *
 * BASELINE is main's measured count. The invariant is one-directional: the count
 * may fall (that is a resolution gain), never rise. When it falls a long way,
 * lower the baseline in the same commit so the ratchet keeps its teeth.
 *
 * Recalibrated 2026-09-01 (item 0.2, wiring this ratchet into CI): the original
 * baseline of 1975 was measured before six commits' worth of ordinary growth
 * landed on main (#37 fix, the dropped-node MAY_TOP fix, tools/, new tezt
 * suites). Re-measured on main at 161f3d7: 2024, spread across 70 modules with
 * no module contributing more than ~7% of the delta — diffuse repo growth, not
 * a localized resolver regression. Confirmed by nested-module-resolution.js
 * (the fixture-scale ratchet for the same review finding) passing clean.
 *
 * Runs against this repository's OWN _build/default — the widest, most varied
 * OCaml index available without a network.
 *
 * Exit: 0 pass, 1 assertion fired (bug present), >=2 setup/error.
 */

const { execFileSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const BASELINE = 2024;

const REPO = path.resolve(__dirname, '..');
const BUILD_DIR = path.join(REPO, '_build/default');
const BIN = path.join(
  REPO,
  '_build/default/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe'
);
const SCHEMA = path.join(REPO, 'architecture-schema.sql');

function setupFail(msg) {
  console.error('SETUP FAILURE: ' + msg);
  process.exit(2);
}

if (!fs.existsSync(BUILD_DIR)) setupFail('no _build/default — run `dune build` first');
if (!fs.existsSync(BIN)) setupFail('indexer not built: ' + BIN);
if (!fs.existsSync(SCHEMA)) setupFail('missing schema: ' + SCHEMA);

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'arch-mustnull-'));
const db = path.join(tmp, 'self.db');

try {
  execFileSync(BIN, [
    '--build-dir=' + BUILD_DIR,
    '--db-path=' + db,
    '--schema-path=' + SCHEMA,
  ], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
} catch (e) {
  setupFail('indexing ' + BUILD_DIR + ' failed:\n' + (e.stderr || e.message));
}

function count(query) {
  const out = execFileSync('sqlite3', ['-noheader', db, query], {
    encoding: 'utf8',
  }).trim();
  const n = parseInt(out, 10);
  if (Number.isNaN(n)) setupFail('unexpected sqlite3 output for ' + query + ': ' + out);
  return n;
}

const total = count('SELECT count(*) FROM calls');
if (total === 0) setupFail('the index has no calls at all — nothing was measured');

const mustNull = count(
  "SELECT count(*) FROM calls WHERE kind = 'MUST' AND callee_id IS NULL"
);

console.log(
  'calls=' + total + '  MUST-with-NULL-callee=' + mustNull + '  baseline=' + BASELINE
);

if (mustNull > BASELINE) {
  console.error(
    'ASSERTION FAILED: ' +
      mustNull +
      ' calls rows are kind=MUST with callee_id IS NULL, above the baseline of ' +
      BASELINE +
      ' (+' +
      (mustNull - BASELINE) +
      '). Each one is a resolver miss stamped as a proven external leaf: ' +
      'arch_graph.ml emits no TOP marker for it, so the real callee is reported ' +
      'UNREACHABLE with confidence. Either resolve those references or emit them ' +
      'as MAY_TOP so the TOP frontier survives.'
  );
  process.exit(1);
}

console.log('OK no-must-null-regression');
process.exit(0);
