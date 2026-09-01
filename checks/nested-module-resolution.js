#!/usr/bin/env node
'use strict';

/*
 * Ratchet — nested-module qualified-name resolution.
 *
 * Guards two CRITICAL findings from
 * briefs/sound-qualified-name-resolution-review.json:
 *
 *   arch_index.ml:359 (dropped edges) — resolve_module_root's multi-segment arm
 *     only ever reconstructed `Root__File`. A reference into a nested module of a
 *     single-unit library (`Foo.Bar.baz` where `Foo` IS the compilation unit and
 *     `Bar` a module inside it) matched nothing, fell to `Unknown, and was emitted
 *     as kind=MUST with callee_id=NULL — a resolver miss dressed as a proven
 *     external leaf.
 *
 *   arch_index.ml:344 (wrong target) — worse, if some UNRELATED library happens to
 *     produce the unit `Foo__Bar`, that same reference was stamped MUST at the other
 *     library's function, which the caller does not even link.
 *
 * Scenario A (no decoy) pins the first: the edge must be MUST to aaa/foo.ml's Bar.baz.
 * Scenario B adds the decoy library and pins the second: the edge must NEVER point at
 * the decoy. With both readings of `Foo.Bar` live and no link information in a .cmt,
 * the honest answer is MAY_TOP (P2: UNKNOWN is not "pick one"), so B accepts MAY_TOP
 * or a resolution to the linked library, and rejects anything naming the decoy.
 *
 * Exit: 0 pass, 1 assertion fired (bug present), >=2 setup/error.
 */

const { execFileSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const REPO = path.resolve(__dirname, '..');
const BIN = path.join(
  REPO,
  '_build/default/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe'
);
const SCHEMA = path.join(REPO, 'architecture-schema.sql');

const failures = [];
function assert(cond, msg) {
  if (!cond) failures.push(msg);
}

function setupFail(msg) {
  console.error('SETUP FAILURE: ' + msg);
  process.exit(2);
}

function run(cmd, args, opts) {
  return execFileSync(cmd, args, {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
    ...(opts || {}),
  });
}

function sql(db, query) {
  const out = run('sqlite3', ['-noheader', '-separator', '|', db, query]);
  return out
    .split('\n')
    .filter((l) => l.length > 0)
    .map((l) => l.split('|'));
}

function scalar(db, query) {
  const rows = sql(db, query);
  if (rows.length === 0) return null;
  const v = rows[0][0];
  return v === '' ? null : v;
}

function writeProject(root, files) {
  for (const [rel, content] of Object.entries(files)) {
    const full = path.join(root, rel);
    fs.mkdirSync(path.dirname(full), { recursive: true });
    fs.writeFileSync(full, content);
  }
}

const DUNE_PROJECT = '(lang dune 3.0)\n';

// aaalib is (wrapped false) with a single foo.ml, so its compilation unit is
// literally `Foo` and `Bar` is a module INSIDE that one unit. There is no
// `Foo__Bar` unit for this library — that is the whole point.
const AAA_DUNE =
  '(library\n (name aaalib)\n (wrapped false)\n (modules foo)\n (flags (:standard -w -a)))\n';
const AAA_FOO =
  'module Bar = struct\n  type t = string\n\n  let baz () : int = 99\nend\n';
const CALLER_DUNE =
  '(library\n (name callerlib)\n (libraries aaalib)\n (modules c)\n (flags (:standard -w -a)))\n';
const CALLER_C = 'let go () : int = Foo.Bar.baz ()\n';

// The decoy: an unrelated WRAPPED library named foo whose bar.ml compiles to the
// unit `Foo__Bar`. callerlib does not list it in (libraries).
const DECOY_DUNE =
  '(library\n (name foo)\n (modules bar)\n (flags (:standard -w -a)))\n';
const DECOY_BAR = 'let baz () : int = 1\n';

function buildAndIndex(label, files) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'arch-nested-' + label + '-'));
  writeProject(root, files);
  try {
    run('dune', ['build', '--root', root]);
  } catch (e) {
    setupFail(
      'fixture ' + label + ' failed to build:\n' + (e.stderr || e.message)
    );
  }
  const db = path.join(root, 'index.db');
  try {
    run(BIN, [
      '--build-dir=' + path.join(root, '_build/default'),
      '--db-path=' + db,
      '--schema-path=' + SCHEMA,
    ]);
  } catch (e) {
    setupFail('indexing ' + label + ' failed:\n' + (e.stderr || e.message));
  }
  return { root, db };
}

function fnId(db, modLike, names) {
  const list = names.map((n) => "'" + n + "'").join(',');
  return scalar(
    db,
    'SELECT f.id FROM functions f JOIN modules m ON m.id = f.module_id ' +
      "WHERE m.path LIKE '" +
      modLike +
      "' AND f.name IN (" +
      list +
      ')'
  );
}

// Exactly one call row for `go` is demanded: a fixture whose caller grew a second
// call would otherwise silently assert about whichever row came back first.
function goCall(db, label) {
  const rows = sql(
    db,
    'SELECT ifnull(c.callee_id, -1), c.kind FROM calls c ' +
      "JOIN functions f ON f.id = c.caller_id WHERE f.name = 'go'"
  );
  if (rows.length !== 1) {
    setupFail(
      'expected exactly one call row for `go` in ' +
        label +
        ', got ' +
        rows.length
    );
  }
  const [id, kind] = rows[0];
  return { callee: id === '-1' ? null : id, kind };
}

// -------------------------------------------------------------------------
// Scenario A — nested module of a single-unit library, no decoy present.
// -------------------------------------------------------------------------
{
  const { db } = buildAndIndex('a', {
    'dune-project': DUNE_PROJECT,
    'aaa/dune': AAA_DUNE,
    'aaa/foo.ml': AAA_FOO,
    'callerlib/dune': CALLER_DUNE,
    'callerlib/c.ml': CALLER_C,
  });
  const linked = fnId(db, '%aaa/foo.ml', ['Bar.baz', 'baz']);
  if (linked === null) setupFail('aaa/foo.ml Bar.baz is not indexed at all');
  const { callee, kind } = goCall(db, 'A');
  assert(
    !(kind === 'MUST' && callee === null),
    'A: go -> Foo.Bar.baz is kind=MUST with a NULL callee, although aaa/foo.ml IS ' +
      'indexed and holds Bar.baz (id ' +
      linked +
      '). A NULL-callee MUST reads downstream as a proven external leaf with no ' +
      'TOP marker — a dropped edge presented as a fact (review CRITICAL :359).'
  );
  assert(
    kind === 'MUST' && callee === linked,
    'A: go -> Foo.Bar.baz resolved kind=' +
      kind +
      ' callee_id=' +
      callee +
      ', expected MUST to aaa/foo.ml Bar.baz (' +
      linked +
      '). The root IS the compilation unit and Bar a module inside it; nothing ' +
      'about this reference is ambiguous.'
  );
}

// -------------------------------------------------------------------------
// Scenario B — same reference, plus an unrelated library that DOES emit Foo__Bar.
// -------------------------------------------------------------------------
{
  const { db } = buildAndIndex('b', {
    'dune-project': DUNE_PROJECT,
    'aaa/dune': AAA_DUNE,
    'aaa/foo.ml': AAA_FOO,
    'foo/dune': DECOY_DUNE,
    'foo/bar.ml': DECOY_BAR,
    'callerlib/dune': CALLER_DUNE,
    'callerlib/c.ml': CALLER_C,
  });
  const linked = fnId(db, '%aaa/foo.ml', ['Bar.baz', 'baz']);
  const decoy = fnId(db, '%foo/bar.ml', ['baz']);
  if (linked === null) setupFail('B: aaa/foo.ml Bar.baz is not indexed');
  if (decoy === null) setupFail('B: decoy foo/bar.ml baz is not indexed');
  if (linked === decoy) setupFail('B: fixture bug — both baz resolved to one row');
  const { callee, kind } = goCall(db, 'B');
  assert(
    callee !== decoy,
    'B: go -> Foo.Bar.baz was attributed to foo/bar.ml baz (' +
      decoy +
      ', kind=' +
      kind +
      '), a library callerlib does not link. The caller links only aaalib, whose ' +
      'foo.ml defines module Bar (' +
      linked +
      ') — review CRITICAL :344.'
  );
  assert(
    kind !== 'MUST' || callee === linked,
    'B: go -> Foo.Bar.baz is kind=MUST with callee_id=' +
      callee +
      '. Both readings of Foo.Bar name an indexed unit here, so a MUST to anything ' +
      'other than the linked aaalib (' +
      linked +
      ') is a guess presented as a proof (P2).'
  );
  assert(
    kind === 'MAY_TOP' || (kind === 'MUST' && callee === linked),
    'B: go -> Foo.Bar.baz resolved kind=' +
      kind +
      ' callee_id=' +
      callee +
      '. With two live readings the only honest answers are MAY_TOP (carrying the ' +
      'TOP frontier marker downstream) or a resolution to the linked library.'
  );
}

if (failures.length > 0) {
  for (const f of failures) console.error('ASSERTION FAILED: ' + f);
  process.exit(1);
}
console.log('OK nested-module-resolution: both scenarios hold');
process.exit(0);
