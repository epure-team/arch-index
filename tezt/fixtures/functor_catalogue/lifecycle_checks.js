'use strict';

/* Lifecycle group kept separate from the dispatcher: root supplies all process
 * helpers so this module never reimplements producer/query semantics. */
function runLifecycleChecks(h) {
  const {assert, fs, path, root, indexer, indexDir, queryRun, assertRefusal, rows, temp,
    probeJson, typedtree, storage, lifecycleProbe, selection, seed, ok} = h;
  for (const value of [indexer, typedtree, storage, lifecycleProbe, selection, seed])
    assert(value, 'missing lifecycle harness prerequisite');

  const selected = probeJson(selection, []);
  assert.equal(selected.ok, true);
  assert.deepEqual(selected.selected, ['./same.cmt', 'link/same.cmt', 'z.cmt']);
  const rollback = probeJson(storage, []);
  assert.equal(rollback.ok, true);
  assert.equal(rollback.catalogue_inputs, 0);
  assert.equal(rollback.functor_applications, 0);
  assert.equal(rollback.graph_facts, 1);
  const failedOutcome = probeJson(storage, ['--collection-failed']);
  assert.equal(failedOutcome.ok, true);
  assert.equal(failedOutcome.outcome, 'collection_failed');
  assert.equal(failedOutcome.catalogue_inputs, 1);
  assert.equal(failedOutcome.functor_applications, 0);
  const boundaries = probeJson(lifecycleProbe, []);
  assert.equal(boundaries.ok, true);
  assert.equal(boundaries.marker_before_finalize, 0);
  assert.equal(boundaries.finalized, true);
  assert.equal(boundaries.marker_after_finalize, 1);
  const indexExpectedIncomplete = (dir, db) => {
    const result = h.run(indexer, ['--build-dir', dir, '--db-path', db, '--schema-path', path.join(root, 'architecture-schema.sql')]);
    assert.equal(result.status, 1, result.stderr);
  };

  temp(dir => {
    const outcomes = [];
    for (const [mode, expected] of [['unsupported-annotation', 'unsupported_annotation'], ['missing-source', 'missing_source']]) {
      const variant = path.join(dir, mode); fs.mkdirSync(variant);
      const artifact = path.join(variant, 'catalogue.cmt');
      const premise = probeJson(typedtree, [mode, '--input', seed, '--output', artifact]);
      assert.equal(premise.ok, true); assert.equal(premise.synthetic, true);
      if (mode === 'unsupported-annotation') assert.equal(premise.after, null);
      if (mode === 'missing-source') assert.equal(premise.source_resolvable, false);
      const db = path.join(variant, 'result.db'); indexDir(variant, db);
      const input = rows(db, 'SELECT artifact,outcome,expected_applications FROM functor_catalogue_inputs');
      assert.deepEqual(input.map(x => x.outcome), [expected]);
      assert.equal(input[0].expected_applications, 0);
      assert.equal(rows(db, 'SELECT count(*) n FROM functor_applications')[0].n, 0);
      assert.equal(rows(db, "SELECT count(*) n FROM comment_db_meta WHERE key='functor_catalogue_contract'")[0].n, 0);
      assertRefusal(queryRun(db), 'NOT_COLLECTED', 3);
      outcomes.push(expected);
    }
    /* A genuinely unreadable selected CMT is independently classified, rather
       than inferred from one of the synthetic annotation/source outcomes. */
    const unreadable = path.join(dir, 'unreadable'); fs.mkdirSync(unreadable);
    fs.writeFileSync(path.join(unreadable, 'broken.cmt'), 'not a cmt');
    const unreadableDb = path.join(unreadable, 'result.db'); indexDir(unreadable, unreadableDb);
    assert.deepEqual(rows(unreadableDb, 'SELECT outcome FROM functor_catalogue_inputs').map(x => x.outcome), ['unreadable']);
    assert.equal(rows(unreadableDb, 'SELECT count(*) n FROM functor_applications')[0].n, 0);
    outcomes.push('unreadable');
    assert.deepEqual(outcomes.sort(), ['missing_source', 'unreadable', 'unsupported_annotation']);

    const copies = path.join(dir, 'copies'); fs.mkdirSync(copies);
    const first = path.join(copies, 'first'); const second = path.join(copies, 'second');
    fs.mkdirSync(first); fs.mkdirSync(second);
    fs.copyFileSync(seed, path.join(first, 'catalogue.cmt'));
    fs.copyFileSync(seed, path.join(second, 'catalogue.cmt'));
    const collisionDb = path.join(dir, 'collision.db'); indexExpectedIncomplete(copies, collisionDb);
    const collision = rows(collisionDb, 'SELECT artifact,outcome FROM functor_catalogue_inputs ORDER BY artifact');
    assert.equal(collision.length, 2);
    assert.deepEqual(collision.map(x => x.outcome).sort(), ['collected', 'dropped_module']);
    const dropped = collision.find(x => x.outcome === 'dropped_module');
    assert.equal(rows(collisionDb, `SELECT count(*) n FROM functor_applications WHERE artifact=${h.quote(dropped.artifact)}`)[0].n, 0);
    assert.equal(rows(collisionDb, "SELECT count(*) n FROM comment_db_meta WHERE key='functor_catalogue_contract'")[0].n, 0);
    assertRefusal(queryRun(collisionDb), 'NOT_COLLECTED', 3);
    fs.unlinkSync(path.join(second, 'catalogue.cmt'));
    indexDir(copies, collisionDb);
    const reindexed = rows(collisionDb, 'SELECT artifact,outcome FROM functor_catalogue_inputs ORDER BY artifact');
    assert.deepEqual(reindexed.map(x => x.outcome), ['collected']);
    assert.equal(rows(collisionDb, `SELECT count(*) n FROM functor_catalogue_inputs WHERE artifact=${h.quote(dropped.artifact)}`)[0].n, 0);
    assert.equal(rows(collisionDb, "SELECT value FROM comment_db_meta WHERE key='functor_catalogue_contract'")[0].value, 'v1');
    fs.unlinkSync(path.join(first, 'catalogue.cmt'));
    fs.writeFileSync(path.join(first, 'catalogue.cmt'), 'now unreadable');
    indexDir(copies, collisionDb);
    assert.deepEqual(rows(collisionDb, 'SELECT outcome FROM functor_catalogue_inputs').map(x => x.outcome), ['unreadable']);
    assert.equal(rows(collisionDb, "SELECT count(*) n FROM comment_db_meta WHERE key='functor_catalogue_contract'")[0].n, 0);
    assertRefusal(queryRun(collisionDb), 'NOT_COLLECTED', 3);

    const symlinks = path.join(dir, 'symlinks'); const target = path.join(symlinks, 'target'); const link = path.join(symlinks, 'link');
    fs.mkdirSync(target, {recursive:true}); fs.mkdirSync(link, {recursive:true});
    fs.copyFileSync(seed, path.join(target, 'catalogue.cmt'));
    fs.symlinkSync(path.join(target, 'catalogue.cmt'), path.join(link, 'catalogue.cmt'));
    const symlinkDb = path.join(dir, 'symlink.db'); indexExpectedIncomplete(symlinks, symlinkDb);
    const symlinkInputs = rows(symlinkDb, 'SELECT artifact,outcome FROM functor_catalogue_inputs ORDER BY artifact');
    assert.equal(symlinkInputs.length, 2);
    assert.deepEqual(symlinkInputs.map(x => x.outcome).sort(), ['collected', 'dropped_module']);
    assert(symlinkInputs.some(x => x.artifact.includes('/link/catalogue.cmt')), 'symlink string must remain selected');

    const empty = path.join(dir, 'empty'); fs.mkdirSync(empty);
    const emptyDb = path.join(empty, 'result.db'); indexDir(empty, emptyDb);
    assert.equal(rows(emptyDb, 'SELECT count(*) n FROM functor_catalogue_inputs')[0].n, 0);
    assert.equal(rows(emptyDb, "SELECT count(*) n FROM comment_db_meta WHERE key='functor_catalogue_contract'")[0].n, 0);
    assertRefusal(queryRun(emptyDb), 'NOT_COLLECTED', 3);

    const zero = path.join(dir, 'zero'); const zeroBuild = path.join(zero, '_build/default'); fs.mkdirSync(zeroBuild, {recursive:true});
    fs.writeFileSync(path.join(zero, 'zero.ml'), 'let x = 1\n');
    ok(process.env.ARCH_FUNCTOR_OCAMLC || 'ocamlc', ['-bin-annot', '-c', 'zero.ml', '-o', '_build/default/zero.cmo'], {cwd:zero});
    const zeroDb = path.join(zero, 'result.db'); indexDir(zeroBuild, zeroDb);
    assert.deepEqual(rows(zeroDb, 'SELECT outcome,expected_applications FROM functor_catalogue_inputs').map(x => [x.outcome,x.expected_applications]), [['collected',0]]);
    assert.equal(rows(zeroDb, "SELECT value FROM comment_db_meta WHERE key='functor_catalogue_contract'")[0].value, 'v1');
  });
  return {checked_outcomes: ['unreadable', 'unsupported_annotation', 'missing_source', 'dropped_module', 'collection_failed'],
    lifecycle: ['reindex-stale-rows', 'zero-selection-marker', 'collected-zero-applications']};
}

module.exports = {runLifecycleChecks};
