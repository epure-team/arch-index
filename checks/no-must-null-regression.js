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
 * BASELINE is main's measured count plus HEADROOM. The invariant is
 * one-directional: the count may fall (that is a resolution gain), never rise
 * past BASELINE. When it falls a long way, lower CLEAN_MEASURED in the same
 * commit so the ratchet keeps its teeth; a console warning below does that
 * check automatically.
 *
 * Recalibrated 2026-09-01 (item 0.2, wiring this ratchet into CI): the original
 * baseline of 1975 was measured before six commits' worth of ordinary growth
 * landed on main (#37 fix, the dropped-node MAY_TOP fix, tools/, new tezt
 * suites). Re-measured against a CLEAN checkout of main at 161f3d7 (a dirty
 * working tree inflated a first attempt at this number to 2024 — see review
 * round 1 of wire-checks-into-ci):
 *
 *   git worktree add --detach /tmp/clean <sha> && cd /tmp/clean && dune build \
 *     && node checks/no-must-null-regression.js
 *   => calls=9289  MUST-with-NULL-callee=2015
 *
 * The clean-checkout count is diffuse, not a localized resolver regression:
 * on the same 161f3d7 checkout, the current per-module breakdown (NOT a diff
 * against the 1975-era checkout — that would need this query run on both SHAs
 * and diffed, which this comment does not claim to have done) spans 69
 * modules, with no single module holding more than ~7% of the total
 * (144 / 2015). Reproducible via:
 *
 *   SELECT m.path, count(*) FROM calls c
 *   JOIN functions f ON f.id = c.caller_id
 *   JOIN modules m ON m.id = f.module_id
 *   WHERE c.kind = 'MUST' AND c.callee_id IS NULL
 *   GROUP BY m.path ORDER BY 2 DESC;
 *
 * Confirmed by nested-module-resolution.js (the fixture-scale ratchet for the
 * same review finding) passing clean on the same checkout.
 *
 * HEADROOM absorbs ordinary future growth of this shape without demanding a
 * recalibration commit for every unrelated PR; it is not slack for a real
 * regression; a rise that exceeds it still fails.
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

const CLEAN_MEASURED = 2015;
const HEADROOM = 25;
const BASELINE = CLEAN_MEASURED + HEADROOM;

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
  // Indexing failure is unambiguously a setup failure — the check never got
  // to measure anything.
  setupFail('indexing ' + BUILD_DIR + ' failed:\n' + (e.stderr || e.message));
}

// Every sqlite3 invocation is a setup dependency, not part of the assertion
// itself: an unguarded throw here (missing/broken sqlite3, a locked db) must
// exit >=2, never 1 — exit 1 is reserved for the assertion actually firing.
function count(query) {
  let out;
  try {
    out = execFileSync('sqlite3', ['-noheader', db, query], {
      encoding: 'utf8',
    }).trim();
  } catch (e) {
    setupFail('sqlite3 failed for ' + query + ':\n' + (e.stderr || e.message));
  }
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
  // leave the db inspectable on a fired assertion — no cleanup on this path
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

// Enforce the tightening half of the one-directional invariant: a count that
// has fallen a long way below CLEAN_MEASURED means the baseline itself is
// stale and should be lowered in this commit, per the policy stated above —
// this is advisory only, never a failure.
if (mustNull < CLEAN_MEASURED - HEADROOM) {
  console.warn(
    'NOTE: MUST-with-NULL-callee (' +
      mustNull +
      ') has fallen well below CLEAN_MEASURED (' +
      CLEAN_MEASURED +
      '). Consider lowering CLEAN_MEASURED in this commit so the ratchet keeps its teeth.'
  );
}

console.log('OK no-must-null-regression');
// Cleanup failure must never change the verdict — warn and continue, not throw.
try {
  fs.rmSync(tmp, { recursive: true, force: true });
} catch (e) {
  console.warn('NOTE: cleanup of ' + tmp + ' failed: ' + e.message);
}
process.exit(0);
