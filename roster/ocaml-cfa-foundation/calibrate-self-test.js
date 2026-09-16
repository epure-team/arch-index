'use strict';

// Pure controls for the Stage2 self-index 2x2 diagnostic.  They intentionally
// do not build, archive, or inspect the repository's CMTs.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

function assertion(error) {
  return error instanceof assert.AssertionError;
}

function run() {
  const {
    subtractMultiset,
    parseOverlayManifest,
    selectOverlayPaths,
    removeOwned,
    withOwnedTemp,
    inventory,
  } = require('./calibrate-self.js');

  assert.deepEqual(
    subtractMultiset(['alpha', 'alpha', 'beta'], ['alpha', 'gamma', 'gamma']),
    {removed: [{value: 'alpha', count: 1}, {value: 'beta', count: 1}],
      added: [{value: 'gamma', count: 2}]},
    'row deltas retain multiplicity rather than collapsing to a set');

  const manifest = parseOverlayManifest([
    'base=c397efd1b2248564c05c74fdab795213dea593db',
    'dirty=docs/foreign.md',
    '---',
    'lib/arch_index/',
    'tezt/tests/ocaml_cfa_foundation.ml',
    'roster/ocaml-cfa-foundation/',
    '',
  ].join('\n'));
  assert.deepEqual(
    selectOverlayPaths(manifest, [
      'lib/arch_index/arch_index_cmt.ml',
      'tezt/tests/ocaml_cfa_foundation.ml',
      'roster/ocaml-cfa-foundation/self-reference-plan.md',
      'docs/foreign.md',
      'tezt/tests/local_module_targets.ml',
    ]),
    [
      'lib/arch_index/arch_index_cmt.ml',
      'roster/ocaml-cfa-foundation/self-reference-plan.md',
      'tezt/tests/ocaml_cfa_foundation.ml',
    ],
    'only declared, non-foreign paths may overlay the archived S0 tree');

  const parent = fs.mkdtempSync(path.join(os.tmpdir(), 'arch-cfa-self-test-'));
  try {
    const owned = path.join(parent, 'owned');
    fs.mkdirSync(owned);
    removeOwned(owned, parent, 'owned');
    assert.equal(fs.existsSync(owned), false, 'owned directory is removed');
    assert.throws(
      () => removeOwned(path.join(os.tmpdir(), 'not-owned'), parent, 'owned'),
      /refusing to remove unowned path/,
      'cleanup refuses a path outside its exact owned parent/prefix');
  } finally {
    fs.rmSync(parent, {recursive: true, force: true});
  }

  let failedPath = null;
  assert.throws(
    () => withOwnedTemp('arch-cfa-self-test-failure-', owned => {
      failedPath = owned;
      throw new Error('injected failure');
    }),
    /injected failure/,
    'measurement failures propagate');
  assert.equal(fs.existsSync(failedPath), false,
    'an owned temporary workspace is removed even when measurement fails');

  withOwnedTemp('arch-cfa-self-test-inventory-', owned => {
    fs.writeFileSync(path.join(owned, 'module.cmt'), 'cmt fixture');
    fs.writeFileSync(path.join(owned, 'module.cmi'), 'cmi fixture');
    fs.symlinkSync('module.cmi', path.join(owned, 'public.cmi'));
    let observed;
    assert.doesNotThrow(() => { observed = inventory(owned, ['.cmt', '.cmti']); },
      'CMT inventory accepts an irrelevant public CMI symlink');
    assert.deepEqual(observed.map(x => x.path),
      ['module.cmt'], 'irrelevant Dune public CMI symlinks are not CMT inputs');
    fs.symlinkSync('module.cmt', path.join(owned, 'alias.cmt'));
    assert.throws(() => inventory(owned, ['.cmt', '.cmti']), /symlink in pinned input/);
  });
}

try {
  run();
  process.stdout.write('PASS calibrate-self pure controls\n');
} catch (error) {
  process.stderr.write(`${error.stack || error}\n`);
  process.exitCode = assertion(error) ? 1 : 2;
}
