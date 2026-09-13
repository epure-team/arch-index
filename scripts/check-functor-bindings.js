#!/usr/bin/env node
'use strict';

/* Independent acceptance checker for same-CMT functor binding provenance.
 * Expected rows and renderer bytes are authored here.  This file does not import
 * the producer, query implementation, or a projection generated from either. */
const assert = require('node:assert/strict');
const cp = require('node:child_process');
const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const queryBinary = process.env.ARCH_FUNCTOR_QUERY ||
  path.join(root, '_build/default/bin/arch_query/arch_query.exe');
const indexer = process.env.ARCH_FUNCTOR_INDEXER ||
  path.join(root, '_build/default/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe');
const opamSwitch = process.env.ARCH_FUNCTOR_OPAM_SWITCH;
const cap = 16 * 1024 * 1024;
const formats = ['box', 'list', 'json', 'csv', 'line', 'markdown'];
const summaryHeaders = ['contract', 'selected_inputs', 'collected_inputs', 'total',
  'matched', 'unresolved', 'returned', 'truncated', 'scope', 'limitations'];
const bindingHeaders = ['artifact', 'source', 'compiler_unit', 'ordinal', 'status',
  'reason', 'declaration_key', 'declaration_name', 'formal_position', 'formal_kind',
  'formal_key', 'formal_name', 'head_application_ordinal', 'actual_root_key', 'argument'];
const limitations = 'not_runtime_instances;not_closed_world;no_call_target_resolution;no_actual_substitution;no_source_freshness_check;artifact_scoped_compiler_identity';

function run(command, args, options = {}) {
  const result = cp.spawnSync(command, args, {
    cwd: root, encoding: 'utf8', timeout: 120000, maxBuffer: cap, ...options
  });
  if (result.error || result.signal || result.status === null) {
    throw new Error(`setup: ${command}: ${result.error || result.signal}`);
  }
  return result;
}
function ok(command, args, options) {
  const result = run(command, args, options);
  if (result.status !== 0) throw new Error(`${command} exited ${result.status}: ${result.stderr}`);
  return result.stdout;
}
function mustFile(file) {
  if (!fs.existsSync(file)) throw new Error(`setup: missing executable: ${file}`);
  return file;
}
function sql(db, text) { return ok('sqlite3', [db], {input: text}); }
function rows(db, statement) {
  const text = ok('sqlite3', ['-json', db, statement]);
  return text.trim() ? JSON.parse(text) : [];
}
function quote(value) { return `'${String(value).replaceAll("'", "''")}'`; }
function hash(file) { return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex'); }
function temp(fn) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'functor-bindings-'));
  try { return fn(dir); } finally { fs.rmSync(dir, {recursive: true, force: true}); }
}
function queryRun(db, args = [], format = 'json') {
  return run(queryBinary, [db, 'functor-bindings', ...args], {
    env: {...process.env, ARCH_QUERY_FORMAT: format}
  });
}
function catalogueRun(db, args = [], format = 'json') {
  return run(queryBinary, [db, 'functor-applications', ...args], {
    env: {...process.env, ARCH_QUERY_FORMAT: format}
  });
}
function opamExecArgs(args) {
  return ['exec', ...(opamSwitch ? [`--switch=${opamSwitch}`] : []), '--', ...args];
}
function opam(args, options = {}) {
  // Dune/CI already supplies a selected compiler through PATH. A second opam
  // invocation from mkdtemp would lose a directory-local switch selection.
  return opamSwitch ? ok('opam', opamExecArgs(args), options)
    : ok(args[0], args.slice(1), options);
}
function indexDir(dir, db) {
  ok(indexer, ['--build-dir', dir, '--db-path', db,
    '--schema-path', path.join(root, 'architecture-schema.sql')]);
}
function assertRefusal(result, token, status) {
  assert.equal(result.status, status, result.stderr);
  assert.equal(result.stdout, '');
  assert.match(result.stderr, new RegExp(token));
}
function twoArrays(stdout) {
  const boundary = stdout.indexOf(']\n[');
  assert(boundary >= 0, `expected two JSON arrays: ${JSON.stringify(stdout)}`);
  assert.equal(stdout.indexOf(']\n[', boundary + 1), -1);
  return [JSON.parse(stdout.slice(0, boundary + 1)), JSON.parse(stdout.slice(boundary + 2))];
}

function nativeTraversalAndIdentity() {
  mustFile(indexer);
  return temp(dir => {
    const buildDir = path.join(dir, '_build/default');
    fs.mkdirSync(buildDir, {recursive: true});
    const traversalSource = path.join(dir, 'traversal_fixture.ml');
    fs.writeFileSync(traversalSource, `
module type S = sig val value : int end
module type FS = functor (X : S) -> S
module A = struct let value = 1 end
module DirectF (X : S) = X
module DirectUse = DirectF (A)
module Nested = struct
  module NestedF (X : S) = X
  module NestedUse = NestedF (A)
end
module type TypeofContext = module type of struct
  module TypeofF (X : S) = X
  module TypeofUse = TypeofF (A)
end
let local_value =
  let module LocalF (X : S) = X in
  let module LocalUse = LocalF (A) in
  LocalUse.value
let object_value = object
  method value =
    let module ObjectF (X : S) = X in
    let module ObjectUse = ObjectF (A) in
    ObjectUse.value
end
class context = object
  initializer
    let module InitF (X : S) = X in
    let module InitUse = InitF (A) in
    ignore InitUse.value
  method value =
    let module MethodF (X : S) = X in
    let module MethodUse = MethodF (A) in
    MethodUse.value
end
let deferred_function () =
  let module DeferredF (X : S) = X in
  let module DeferredUse = DeferredF (A) in
  DeferredUse.value
module OuterFunctor (P : S) = struct
  module BodyF (X : S) = X
  module BodyUse = BodyF (P)
end
module OuterUse = OuterFunctor (A)
module rec RecF : FS = functor (X : S) -> X
and RecPeer : sig val value : int end = struct let value = 0 end
module RecUse = RecF (A)
let packed = (module DirectF : FS)
let unpack_value =
  let module Unpacked = (val packed : FS) in
  let module UnpackUse = Unpacked (A) in
  UnpackUse.value
[@@@ignored_payload
  module AttributeOnlyF (X : S) = X
  [%%ignored_nested_extension module ExtensionOnlyF (X : S) = X]
]
`);
    opam(['ocamlc', '-w', '-a', '-bin-annot', '-c', path.basename(traversalSource),
      '-o', '_build/default/traversal_fixture.cmo'], {cwd: dir});
    const traversalDb = path.join(dir, 'traversal.db');
    indexDir(buildDir, traversalDb);

    const expectedDeclarations = [
      'BodyF', 'DeferredF', 'DirectF', 'InitF', 'LocalF', 'MethodF',
      'NestedF', 'ObjectF', 'OuterFunctor', 'RecF', 'TypeofF'
    ].sort();
    const actualDeclarations = rows(traversalDb, `SELECT name FROM functor_declarations
      ORDER BY name`).map(row => row.name);
    assert.deepEqual(actualDeclarations, expectedDeclarations,
      'closed traversal declaration-name multiset differs from authored fixture');
    assert.equal(actualDeclarations.includes('AttributeOnlyF'), false,
      'untyped attribute payload contributed a declaration');
    assert.equal(actualDeclarations.includes('ExtensionOnlyF'), false,
      'extension nested in an ignored untyped payload contributed a declaration');

    const expectedMatchedDeclarations = [
      'BodyF', 'DeferredF', 'DirectF', 'InitF', 'LocalF', 'MethodF',
      'NestedF', 'ObjectF', 'OuterFunctor', 'RecF', 'TypeofF'
    ].sort();
    const matchedDeclarations = rows(traversalDb, `SELECT d.name
      FROM functor_bindings b JOIN functor_declarations d
      ON d.producer_run_id=b.producer_run_id AND d.artifact=b.artifact
      AND d.declaration_key=b.declaration_key
      WHERE b.status='matched' ORDER BY d.name`).map(row => row.name);
    assert.deepEqual(matchedDeclarations, expectedMatchedDeclarations,
      'one or more traversal-context applications did not match its authored declaration');
    assert.equal(rows(traversalDb, `SELECT count(*) AS n FROM functor_bindings
      WHERE reason='unsupported_alias_rhs'`)[0].n, 1,
      'unpack-derived application premise did not remain explicitly unresolved');

    const identityDir = path.join(dir, 'identity');
    const identityBuild = path.join(identityDir, '_build/default');
    fs.mkdirSync(identityBuild, {recursive: true});
    for (const unit of ['left_identity', 'right_identity']) {
      fs.writeFileSync(path.join(identityDir, `${unit}.ml`), `
module type S = sig val value : int end
module F (X : S) = X
module A = struct let value = 1 end
module M = F (A)
`);
      opam(['ocamlc', '-bin-annot', '-c', `${unit}.ml`,
        '-o', `_build/default/${unit}.cmo`], {cwd: identityDir});
    }
    const identityDb = path.join(dir, 'identity.db');
    indexDir(identityBuild, identityDb);
    const identityRows = rows(identityDb, `SELECT b.artifact,b.declaration_key,d.name,
        a.ordinal,a.argument
      FROM functor_bindings b
      JOIN functor_declarations d ON d.producer_run_id=b.producer_run_id
        AND d.artifact=b.artifact AND d.declaration_key=b.declaration_key
      JOIN functor_applications a ON a.producer_run_id=b.producer_run_id
        AND a.artifact=b.artifact AND a.ordinal=b.ordinal
      WHERE b.status='matched' ORDER BY b.artifact,b.ordinal`);
    assert.equal(identityRows.length, 2, JSON.stringify(identityRows));
    assert.equal(new Set(identityRows.map(row => row.artifact)).size, 2);
    for (const row of identityRows) {
      assert.equal(row.name, 'F');
      assert.equal(JSON.parse(row.argument).source, 'A');
      assert.equal(rows(identityDb, `SELECT count(*) AS n FROM functor_declarations
        WHERE artifact=${quote(row.artifact)} AND declaration_key=${quote(row.declaration_key)}
        AND name='F'`)[0].n, 1,
        `${row.artifact}: binding key did not resolve inside its own artifact`);
    }
    return {
      declarations: expectedDeclarations,
      matched_contexts: expectedMatchedDeclarations.length,
      ignored_untyped_payload_declarations: 0,
      unpack_application_refusals: 1,
      cross_cmt_lookalikes: identityRows.length,
      artifact_local_joins: true,
      key_collision_policy: 'keys compared only within artifact; equality across artifacts allowed'
    };
  });
}

function collectionFailureInventory() {
  return temp(dir => {
    const source = path.join(dir, 'seed.ml');
    fs.writeFileSync(source, `module type S = sig val n : int end
module F (X:S) = struct let n=X.n end
module A = struct let n=1 end
module Alias = F
module M = Alias(A)
`);
    opam(['ocamlc', '-bin-annot', '-c', source], {cwd: dir});
    const copied = path.join(dir, 'collection_failure_probe.ml');
    fs.copyFileSync(path.join(root,
      'roster/functor-binding-resolution/collection_failure_probe.ml'), copied);
    const executable = path.join(dir, 'collection_failure_probe.exe');
    opam(['ocamlfind', 'ocamlopt', '-package', 'compiler-libs.common,yojson', '-linkpkg',
      copied, '-o', executable], {cwd: dir});
    const buildDir = path.join(dir, 'synthetic-build');
    fs.mkdirSync(buildDir);
    const output = path.join(buildDir, 'seed.cmt');
    const mutation = run(executable, [path.join(dir, 'seed.cmt'), output], {cwd: dir});
    if (mutation.status === 1) assert.fail(`collection-failure mutation assertion: ${mutation.stderr}`);
    if (mutation.status !== 0) throw new Error(`collection-failure mutation setup (${mutation.status}): ${mutation.stderr}`);
    assert.deepEqual(JSON.parse(mutation.stdout), {
      ok: true, synthetic: true, source_valid: false,
      premise: 'duplicate-binder-ident-same', serialized: true
    });
    const db = path.join(dir, 'collection-failure.db');
    const indexed = run(indexer, ['--build-dir', buildDir, '--db-path', db,
      '--schema-path', path.join(root, 'architecture-schema.sql')]);
    assert.equal(indexed.status, 0, indexed.stderr);
    assert.match(indexed.stderr, /functor binding collection failed/);
    assert.equal(rows(db, "SELECT count(*) AS n FROM functor_catalogue_inputs WHERE outcome='collected'")[0].n, 1);
    assert.equal(rows(db, 'SELECT count(*) AS n FROM functor_applications')[0].n, 1);
    assert.deepEqual(rows(db, `SELECT outcome,expected_declarations,expected_bindings
      FROM functor_binding_inputs`),
      [{outcome: 'collection_failed', expected_declarations: 0, expected_bindings: 0}]);
    assert.equal(rows(db, 'SELECT count(*) AS n FROM functor_declarations')[0].n, 0);
    assert.equal(rows(db, 'SELECT count(*) AS n FROM functor_bindings')[0].n, 0);
    assert.equal(rows(db, `SELECT count(*) AS n FROM comment_db_meta
      WHERE key='functor_catalogue_contract' AND value='v1'`)[0].n, 1);
    assert.equal(rows(db, `SELECT count(*) AS n FROM comment_db_meta
      WHERE key='functor_binding_contract'`)[0].n, 0);
    return {
      synthetic_not_source_valid: true, duplicate_identity_premise: true,
      catalogue_occurrences_preserved: 1, binding_outcome: 'collection_failed',
      expected_declarations: 0, expected_bindings: 0, partial_rows: 0,
      binding_marker_absent: true
    };
  });
}

function syntheticInventory() {
  return temp(dir => {
    const source = path.join(dir, 'seed.ml');
    fs.writeFileSync(source, `module type S = sig val n : int end
module F (X:S) = struct let n=X.n end
module A = struct let n=1 end
module Alias = F
module M = Alias(A)
`);
    opam(['ocamlc', '-bin-annot', '-c', source], {cwd: dir});
    const copied = path.join(dir, 'inventory_probe.ml');
    fs.copyFileSync(path.join(root, 'roster/functor-binding-resolution/inventory_probe.ml'), copied);
    const executable = path.join(dir, 'inventory_probe.exe');
    const staging = path.join(root, '_build/install/default/lib');
    const env = {...process.env, OCAMLPATH: process.env.OCAMLPATH
      ? `${staging}${path.delimiter}${process.env.OCAMLPATH}` : staging};
    opam(['ocamlfind', 'ocamlopt', '-package', 'arch-index', '-linkpkg', copied,
      '-o', executable], {cwd: dir, env});
    const result = run(executable, [path.join(dir, 'seed.cmt')], {cwd: dir});
    if (result.status === 1) assert.fail(`inventory probe assertion: ${result.stderr}`);
    if (result.status !== 0) throw new Error(`inventory probe setup (${result.status}): ${result.stderr}`);
    const evidence = JSON.parse(result.stdout);
    assert.deepEqual(evidence, {
      ok: true, evidence: 'premise-checked-synthetic-not-source-valid',
      identity: {identity_conflicts: true, alias_cycle: true},
      heads: {missing_local: true, persistent: true, named_unit_mismatch: true},
      nested: {overapplication: true, inner_refusal_precedence: true},
      roots: {pident_pdot: true, papply_pextra_persistent_null: true},
      formals: {named_nullable_combinations: 4},
      catalogue_unchanged: {occurrences: 1, byte_identical: true}
    });
    return evidence;
  });
}

function inventory() {
  mustFile(indexer);
  mustFile(queryBinary);
  return temp(dir => {
    const buildDir = path.join(dir, '_build/default');
    fs.mkdirSync(buildDir, {recursive: true});
    const source = path.join(dir, 'binding_fixture.ml');
    fs.writeFileSync(source, `
module type S = sig val value : int end
module ADirect = struct let value = 1 end
module AAlias = struct let value = 2 end
module ACurried = struct let value = 3 end
module BCurried = struct let value = 4 end
module AProjected = struct let value = 5 end
module AParam = struct let value = 6 end
module AApp = struct let value = 7 end
module BApp = struct let value = 8 end
module ALeft = struct let value = 9 end
module ARight = struct let value = 10 end
module AInline = struct let value = 11 end
module F (X : S) = X
module Alias = F
module Direct = F (ADirect)
module Via_alias = Alias (AAlias)
module Curried (X : S) (Y : S) = struct let value = X.value + Y.value end
module Curried_use = Curried (ACurried) (BCurried)
module Unit_functor () = struct let value = 12 end
module Unit_use = Unit_functor ()
module Anonymous = F (struct let value = 13 end)
module Outer = struct module F = F end
module Projected = Outer.F (AProjected)
module Parameter (H : functor (X : S) -> S) = struct module M = H (AParam) end
module Applied_head = Curried (AApp)
module Application_valued = Applied_head (BApp)
module Left = struct module F (X : S) = X module M = F (ALeft) end
module Right = struct module F (X : S) = X module M = F (ARight) end
module Inline = (functor (X : S) -> X) (AInline)
`);
    opam(['ocamlc', '-bin-annot', '-c', path.basename(source),
      '-o', '_build/default/binding_fixture.cmo'], {cwd: dir});
    const db = path.join(dir, 'inventory.db');
    indexDir(buildDir, db);

    const inputs = rows(db, `SELECT artifact,outcome,expected_declarations,expected_bindings
      FROM functor_binding_inputs ORDER BY artifact`);
    assert.equal(inputs.length, 1, JSON.stringify({
      catalogue: rows(db, 'SELECT * FROM functor_catalogue_inputs'),
      markers: rows(db, "SELECT key,value FROM comment_db_meta WHERE key LIKE 'functor_%'")
    }));
    assert.equal(inputs[0].outcome, 'collected');
    const declarations = rows(db, `SELECT declaration_key,name,formals
      FROM functor_declarations ORDER BY declaration_key`);
    assert.equal(declarations.length, inputs[0].expected_declarations);
    const byKey = new Map(declarations.map(d => [d.declaration_key, d]));
    for (const declaration of declarations) {
      const formals = JSON.parse(declaration.formals);
      assert(formals.length > 0);
      assert.deepEqual(formals.map(f => f.position),
        Array.from({length: formals.length}, (_, i) => i + 1));
    }
    const curriedDeclarations = declarations.filter(d => d.name === 'Curried');
    assert.equal(curriedDeclarations.length, 1);
    assert.deepEqual(JSON.parse(curriedDeclarations[0].formals).map(f => f.kind), ['named', 'named']);
    const unitDeclarations = declarations.filter(d => d.name === 'Unit_functor');
    assert.equal(unitDeclarations.length, 1);
    assert.deepEqual(JSON.parse(unitDeclarations[0].formals),
      [{position: 1, kind: 'unit', binder_key: null, name: null}]);

    const joined = rows(db, `SELECT a.ordinal,a.application_kind,a.argument,b.status,b.reason,
        b.declaration_key,b.formal_position,b.head_application_ordinal,b.actual_root_key
      FROM functor_applications a JOIN functor_bindings b
      USING(producer_run_id,artifact,ordinal) ORDER BY a.ordinal`);
    assert.equal(joined.length, inputs[0].expected_bindings);
    const argument = row => JSON.parse(row.argument);
    const pathArgument = name => joined.find(row => {
      const value = argument(row);
      return value.kind === 'path' && value.source === name;
    });
    const assertMatch = (name, declarationName, position) => {
      const row = pathArgument(name);
      assert(row, `missing native application argument ${name}`);
      assert.equal(row.status, 'matched', `${name}: ${row.reason}`);
      assert.equal(row.reason, null);
      assert.equal(row.formal_position, position);
      assert.equal(byKey.get(row.declaration_key).name, declarationName);
      const formal = JSON.parse(byKey.get(row.declaration_key).formals)[position - 1];
      assert.equal(formal.position, position);
      assert.equal(formal.kind, 'named');
      return row;
    };
    assertMatch('ADirect', 'F', 1);
    assertMatch('AAlias', 'F', 1);
    const inner = assertMatch('ACurried', 'Curried', 1);
    const outer = assertMatch('BCurried', 'Curried', 2);
    assert.equal(outer.head_application_ordinal, inner.ordinal);
    assertMatch('AApp', 'Curried', 1);
    const left = assertMatch('ALeft', 'F', 1);
    const right = assertMatch('ARight', 'F', 1);
    assert.notEqual(left.declaration_key, right.declaration_key,
      'same-spelled shadowed declarations must retain distinct compiler identities');
    const anonymous = joined.find(row => argument(row).kind === 'structure');
    assert(anonymous && anonymous.status === 'matched');
    const unit = joined.find(row => row.application_kind === 'apply_unit');
    assert(unit && unit.status === 'matched');
    assert.equal(JSON.parse(byKey.get(unit.declaration_key).formals)[unit.formal_position - 1].kind, 'unit');

    const expectedRefusals = new Map([
      ['AProjected', 'unsupported_path'],
      ['AParam', 'parameter_supplied_head'],
      ['BApp', 'unsupported_alias_rhs'],
      ['AInline', 'unsupported_head_shape']
    ]);
    for (const [name, reason] of expectedRefusals) {
      const row = pathArgument(name);
      assert(row, `missing native refusal premise ${name}`);
      assert.equal(row.status, 'unresolved');
      assert.equal(row.reason, reason);
      assert.equal(row.declaration_key, null);
      assert.equal(row.formal_position, null);
    }

    const catalogueArguments = new Map(joined.map(row => [row.ordinal, row.argument]));
    const result = queryRun(db, [], 'json');
    assert.equal(result.status, 0, result.stderr);
    const [, projected] = twoArrays(result.stdout);
    assert.equal(projected.length, joined.length);
    for (const row of projected) {
      assert.equal(row.argument, catalogueArguments.get(row.ordinal),
        `ordinal ${row.ordinal}: catalogue argument bytes changed`);
    }
    return {
      native_fixture: true,
      occurrences: joined.length,
      declarations: declarations.length,
      matched_cases: 9,
      native_refusal_reasons: [...expectedRefusals.values()],
      collection_failure: collectionFailureInventory(),
      synthetic: syntheticInventory(),
      traversal_and_identity: nativeTraversalAndIdentity()
    };
  });
}

const loc = JSON.stringify({file: 'src/a.ml', start_line: 2, start_col: 1,
  end_line: 2, end_col: 9, ghost: false});
const nullLoc = JSON.stringify({file: null, start_line: null, start_col: null,
  end_line: null, end_col: null, ghost: true});
const headF = JSON.stringify({kind: 'path', compiler: 'F', source: 'F', contains_apply: false});
const headG = JSON.stringify({kind: 'path', compiler: 'G', source: 'G', contains_apply: false});
const headApplication = JSON.stringify({kind: 'application', ordinal: 2});
const argumentA = JSON.stringify({kind: 'path', compiler: 'A', source: 'A', contains_apply: false});
const argumentEscaped = JSON.stringify({kind: 'path', compiler: 'B\"quoted', source: 'B,pipe|line\\tail', contains_apply: false});
const argumentUnit = JSON.stringify({kind: 'unit'});

function makeDb(db, mutation = '') {
  sql(db, fs.readFileSync(path.join(root, 'architecture-schema.sql'), 'utf8'));
  const allNullableNamedAndUnit = JSON.stringify([
    {position: 1, kind: 'named', binder_key: 'formal:X/1', name: 'X'},
    {position: 2, kind: 'named', binder_key: 'formal:key-only', name: null},
    {position: 3, kind: 'named', binder_key: null, name: 'Name only'},
    {position: 4, kind: 'named', binder_key: null, name: null},
    {position: 5, kind: 'unit', binder_key: null, name: null}
  ]);
  const secondFormals = JSON.stringify([
    {position: 1, kind: 'named', binder_key: null, name: 'Quoted \"formal\"'}
  ]);
  sql(db, `
    INSERT INTO producer_runs(id,producer) VALUES(1,'arch_index_cmt');
    INSERT INTO modules(id,path,lines) VALUES(1,'src/a.ml',3),(2,'src/z,pipe|.ml',2);
    INSERT INTO functor_catalogue_runs(producer_run_id,selected_inputs) VALUES(1,2);
    INSERT INTO functor_catalogue_inputs VALUES
      (1,'a.cmt','src/a.ml','A',1,'collected',2),
      (1,'z|quote".cmt','src/z,pipe|.ml','Z"unit',2,'collected',1);
    INSERT INTO functor_applications VALUES
      (1,'a.cmt',1,'apply',${quote(loc)},${quote(headApplication)},${quote(argumentEscaped)},'[]'),
      (1,'a.cmt',2,'apply',${quote(loc)},${quote(headF)},${quote(argumentA)},'[]'),
      (1,'z|quote".cmt',1,'apply_unit',${quote(nullLoc)},${quote(headG)},${quote(argumentUnit)},'["unusable_location"]');
    INSERT INTO functor_binding_inputs VALUES
      (1,'a.cmt','collected',1,2),(1,'z|quote".cmt','collected',1,1);
    INSERT INTO functor_declarations VALUES
      (1,'a.cmt','decl:F/1','F, pipe| "quoted"',${quote(loc)},${quote(allNullableNamedAndUnit)}),
      (1,'z|quote".cmt','decl:G/2','G',${quote(nullLoc)},${quote(secondFormals)});
    INSERT INTO functor_bindings VALUES
      (1,'a.cmt',1,'matched',NULL,'decl:F/1',2,2,NULL),
      (1,'a.cmt',2,'matched',NULL,'decl:F/1',1,NULL,'actual:A/9'),
      (1,'z|quote".cmt',1,'unresolved','formal_kind_mismatch',NULL,NULL,NULL,NULL);
    INSERT INTO comment_db_meta(key,value) VALUES
      ('functor_catalogue_contract','v1'),('functor_binding_contract','v1');
    PRAGMA foreign_keys=OFF;
    PRAGMA ignore_check_constraints=ON;
    ${mutation}`);
}

function authoredRows(limit) {
  const all = [
    {artifact: 'a.cmt', source: 'src/a.ml', compiler_unit: 'A', ordinal: 1,
      status: 'matched', reason: null, declaration_key: 'decl:F/1',
      declaration_name: 'F, pipe| "quoted"', formal_position: 2,
      formal_kind: 'named', formal_key: 'formal:key-only', formal_name: null,
      head_application_ordinal: 2, actual_root_key: null, argument: argumentEscaped},
    {artifact: 'a.cmt', source: 'src/a.ml', compiler_unit: 'A', ordinal: 2,
      status: 'matched', reason: null, declaration_key: 'decl:F/1',
      declaration_name: 'F, pipe| "quoted"', formal_position: 1,
      formal_kind: 'named', formal_key: 'formal:X/1', formal_name: 'X',
      head_application_ordinal: null, actual_root_key: 'actual:A/9', argument: argumentA},
    {artifact: 'z|quote".cmt', source: 'src/z,pipe|.ml', compiler_unit: 'Z"unit', ordinal: 1,
      status: 'unresolved', reason: 'formal_kind_mismatch', declaration_key: null,
      declaration_name: null, formal_position: null, formal_kind: null, formal_key: null,
      formal_name: null, head_application_ordinal: null, actual_root_key: null,
      argument: argumentUnit}
  ];
  const returned = Math.min(limit, all.length);
  return {
    summary: [{contract: 'v1', selected_inputs: 2, collected_inputs: 2, total: 3,
      matched: 2, unresolved: 1, returned, truncated: returned < 3 ? 1 : 0,
      scope: 'selected_cmt_local_binding_provenance', limitations}],
    bindings: all.slice(0, returned)
  };
}

function render(mode, headers, values) {
  const width = value => [...String(value)].length;
  const pad = (value, n) => String(value) + ' '.repeat(Math.max(0, n - width(value)));
  const centre = (value, n) => {
    const d = Math.max(0, n - width(value));
    return ' '.repeat(Math.floor(d / 2)) + value + ' '.repeat(Math.ceil(d / 2));
  };
  const csv = value => /[,\"]|[\x00-\x20\x80-\xff]/.test(String(value))
    ? `"${String(value).replaceAll('"', '""')}"` : String(value);
  const cells = values.map(row => headers.map(key => row[key] === null ? '' : String(row[key])));
  if (cells.length === 0) return '';
  const widths = headers.map((header, i) => Math.max(width(header), ...cells.map(row => width(row[i]))));
  if (mode === 'json') return `[${values.map(row => JSON.stringify(Object.fromEntries(headers.map(key => [key, row[key]])))).join(',\n')}]\n`;
  if (mode === 'list') return cells.map(row => row.join('|')).join('\n') + '\n';
  if (mode === 'csv') return cells.map(row => row.map(csv).join(',')).join('\n') + '\n';
  if (mode === 'line') {
    const headerWidth = Math.max(...headers.map(width));
    return cells.map(row => headers.map((header, i) =>
      `${' '.repeat(headerWidth - width(header))}${header} = ${row[i]}`).join('\n')).join('\n\n') + '\n';
  }
  if (mode === 'markdown') {
    const line = (row, align) => `| ${row.map((cell, i) => align(cell, widths[i])).join(' | ')} |`;
    return [line(headers, centre), `|${widths.map(w => '-'.repeat(w + 2)).join('|')}|`,
      ...cells.map(row => line(row, pad))].join('\n') + '\n';
  }
  const rule = (left, middle, right) => left + widths.map(w => '─'.repeat(w + 2)).join(middle) + right;
  const line = (row, align) => `│ ${row.map((cell, i) => align(cell, widths[i])).join(' │ ')} │`;
  return [rule('┌', '┬', '┐'), line(headers, centre), rule('├', '┼', '┤'),
    ...cells.map(row => line(row, pad)), rule('└', '┴', '┘')].join('\n') + '\n';
}
function oracle(format, limit) {
  const expected = authoredRows(limit);
  const summary = render(format, summaryHeaders, expected.summary);
  const bindings = render(format, bindingHeaders, expected.bindings);
  return summary + (format === 'json' && bindings === '' ? '[]\n' : bindings);
}

function relaxTable(table) {
  return `ALTER TABLE ${table} RENAME TO ${table}_checked;
    CREATE TABLE ${table} AS SELECT * FROM ${table}_checked;
    DROP TABLE ${table}_checked;`;
}
function mutateDb(db, statement) {
  sql(db, `PRAGMA foreign_keys=OFF; PRAGMA ignore_check_constraints=ON; ${statement}`);
}
function zeroRows() {
  return {summary: [{contract: 'v1', selected_inputs: 1, collected_inputs: 1,
    total: 0, matched: 0, unresolved: 0, returned: 0, truncated: 0,
    scope: 'selected_cmt_local_binding_provenance', limitations}], bindings: []};
}
function zeroOracle(format) {
  const expected = zeroRows();
  const summary = render(format, summaryHeaders, expected.summary);
  const bindings = render(format, bindingHeaders, expected.bindings);
  return summary + (format === 'json' ? '[]\n' : bindings);
}
function makeZeroDb(db) {
  makeDb(db);
  mutateDb(db, `DELETE FROM functor_bindings; DELETE FROM functor_applications;
    DELETE FROM functor_declarations; DELETE FROM functor_binding_inputs;
    DELETE FROM functor_catalogue_inputs; DELETE FROM modules WHERE id=2;
    INSERT INTO functor_catalogue_inputs VALUES(1,'a.cmt','src/a.ml','A',1,'collected',0);
    INSERT INTO functor_binding_inputs VALUES(1,'a.cmt','collected',0,0);
    UPDATE functor_catalogue_runs SET selected_inputs=1;`);
}
function makeManyDb(db) {
  makeDb(db);
  const oneFormal = JSON.stringify([
    {position: 1, kind: 'named', binder_key: 'formal:X/1', name: 'X'}
  ]);
  mutateDb(db, `DELETE FROM functor_bindings; DELETE FROM functor_applications;
    DELETE FROM functor_declarations; DELETE FROM functor_binding_inputs;
    DELETE FROM functor_catalogue_inputs; DELETE FROM modules WHERE id=2;
    INSERT INTO functor_catalogue_inputs VALUES(1,'a.cmt','src/a.ml','A',1,'collected',60);
    INSERT INTO functor_binding_inputs VALUES(1,'a.cmt','collected',1,60);
    INSERT INTO functor_declarations VALUES
      (1,'a.cmt','decl:F/1','F',${quote(loc)},${quote(oneFormal)});
    WITH RECURSIVE n(x) AS (VALUES(1) UNION ALL SELECT x+1 FROM n WHERE x<60)
      INSERT INTO functor_applications
      SELECT 1,'a.cmt',x,'apply',${quote(loc)},${quote(headF)},${quote(argumentA)},'[]' FROM n;
    WITH RECURSIVE n(x) AS (VALUES(1) UNION ALL SELECT x+1 FROM n WHERE x<60)
      INSERT INTO functor_bindings
      SELECT 1,'a.cmt',x,'matched',NULL,'decl:F/1',1,NULL,'actual:A/9' FROM n;
    UPDATE functor_catalogue_runs SET selected_inputs=1;`);
}
function manyRows(limit) {
  const bindings = Array.from({length: Math.min(60, limit)}, (_, i) => ({
    artifact: 'a.cmt', source: 'src/a.ml', compiler_unit: 'A', ordinal: i + 1,
    status: 'matched', reason: null, declaration_key: 'decl:F/1', declaration_name: 'F',
    formal_position: 1, formal_kind: 'named', formal_key: 'formal:X/1', formal_name: 'X',
    head_application_ordinal: null, actual_root_key: 'actual:A/9', argument: argumentA
  }));
  return {summary: [{contract: 'v1', selected_inputs: 1, collected_inputs: 1,
    total: 60, matched: 60, unresolved: 0, returned: bindings.length,
    truncated: bindings.length < 60 ? 1 : 0,
    scope: 'selected_cmt_local_binding_provenance', limitations}], bindings};
}

function query() {
  mustFile(queryBinary);
  const sqliteVersion = run('sqlite3', ['--version']);
  if (sqliteVersion.status !== 0) throw new Error('setup: sqlite3 unavailable');
  let successfulOracles = 0;
  let corruptions = 0;
  let schemaRefusals = 0;
  let markerRefusals = 0;
  temp(dir => {
    const valid = path.join(dir, 'valid.db');
    makeDb(valid);
    const original = hash(valid);
    for (const [args, limit] of [[[], 50], [['0'], 0], [['2'], 2]]) {
      for (const format of formats) {
        const result = queryRun(valid, args, format);
        assert.equal(result.status, 0, `${format}/${args}: ${result.stderr}`);
        assert.equal(result.stdout, oracle(format, limit), `exact ${format} byte oracle at limit ${limit}`);
        assert.equal(hash(valid), original, `${format} query changed database bytes`);
        if (format === 'json') {
          const [summary, bindings] = twoArrays(result.stdout);
          assert.deepEqual(Object.keys(summary[0]), summaryHeaders);
          for (const row of bindings) assert.deepEqual(Object.keys(row), bindingHeaders);
        }
        successfulOracles++;
      }
    }

    assert.equal(rows(valid, `SELECT count(*) n FROM functor_declarations
      WHERE declaration_key='decl:G/2'`)[0].n, 1, 'valid fixture must include an unused declaration');
    assert.deepEqual(JSON.parse(rows(valid, `SELECT formals FROM functor_declarations
      WHERE declaration_key='decl:F/1'`)[0].formals).map(f => [f.binder_key, f.name]),
      [['formal:X/1', 'X'], ['formal:key-only', null], [null, 'Name only'], [null, null], [null, null]]);

    const zero = path.join(dir, 'zero.db');
    makeZeroDb(zero);
    const zeroBefore = hash(zero);
    for (const args of [[], ['0'], ['7']]) for (const format of formats) {
      const zeroResult = queryRun(zero, args, format);
      assert.equal(zeroResult.status, 0, `${format}/${args}: ${zeroResult.stderr}`);
      assert.equal(zeroResult.stdout, zeroOracle(format), `zero-result ${format}/${args} oracle`);
      assert.equal(hash(zero), zeroBefore);
    }

    const many = path.join(dir, 'many.db');
    makeManyDb(many);
    const manyBefore = hash(many);
    const manyResult = queryRun(many, [], 'json');
    assert.equal(manyResult.status, 0, manyResult.stderr);
    const manyExpected = manyRows(50);
    assert.equal(manyResult.stdout,
      render('json', summaryHeaders, manyExpected.summary) + render('json', bindingHeaders, manyExpected.bindings),
      'default limit must return the first 50 of an authored 60-row fixture');
    assert.equal(hash(many), manyBefore);

    // FR-020's negative boundary: malformed facts outside the catalogue/binding
    // closure must not silently expand this reader into an effects validator.
    const unrelated = path.join(dir, 'unrelated.db');
    makeDb(unrelated);
    mutateDb(unrelated, `INSERT INTO exn_origins
      (function_id,form,exn_path,escapes,line,col,channel)
      VALUES(999,'not_a_real_origin_form','Bogus',7,-4,-9,'not_a_channel')`);
    assert.deepEqual(rows(unrelated, `SELECT function_id,form,escapes,line,col,channel
      FROM exn_origins`), [{function_id: 999, form: 'not_a_real_origin_form',
      escapes: 7, line: -4, col: -9, channel: 'not_a_channel'}],
    'unrelated-table corruption premise was not persisted');
    const unrelatedBefore = hash(unrelated);
    const unrelatedResult = queryRun(unrelated, [], 'json');
    assert.equal(unrelatedResult.status, 0, unrelatedResult.stderr);
    assert.equal(unrelatedResult.stdout, oracle('json', 50),
      'unrelated malformed rows changed the exact binding projection');
    assert.equal(hash(unrelated), unrelatedBefore,
      'query changed the database carrying unrelated malformed rows');

    const faults = [
      ['missing binding', 'DELETE FROM functor_bindings WHERE ordinal=2'],
      ['binding count', "UPDATE functor_binding_inputs SET expected_bindings=9 WHERE artifact='a.cmt'"],
      ['declaration count', "UPDATE functor_binding_inputs SET expected_declarations=9 WHERE artifact='a.cmt'"],
      ['selected count', 'UPDATE functor_catalogue_runs SET selected_inputs=1'],
      ['catalogue count', "UPDATE functor_catalogue_inputs SET expected_applications=9 WHERE artifact='a.cmt'"],
      ['failed binding input', "UPDATE functor_binding_inputs SET outcome='collection_failed' WHERE artifact='a.cmt'"],
      ['input storage type', "UPDATE functor_binding_inputs SET expected_bindings='nine' WHERE artifact='a.cmt'"],
      ['input foreign run', "UPDATE functor_binding_inputs SET producer_run_id=7 WHERE artifact='a.cmt'"],
      ['orphan binding input artifact', `${relaxTable('functor_binding_inputs')} UPDATE functor_binding_inputs SET artifact='orphan.cmt' WHERE artifact='a.cmt'`],
      ['declaration foreign run', "UPDATE functor_declarations SET producer_run_id=7 WHERE artifact='a.cmt'"],
      ['orphan declaration artifact', `${relaxTable('functor_declarations')} UPDATE functor_declarations SET artifact='orphan.cmt' WHERE artifact='a.cmt'`],
      ['binding foreign run', "UPDATE functor_bindings SET producer_run_id=7 WHERE artifact='a.cmt' AND ordinal=1"],
      ['orphan binding artifact', `${relaxTable('functor_bindings')} UPDATE functor_bindings SET artifact='orphan.cmt' WHERE artifact='a.cmt' AND ordinal=2`],
      ['binding without occurrence', `${relaxTable('functor_bindings')} UPDATE functor_bindings SET ordinal=99 WHERE artifact='a.cmt' AND ordinal=2`],
      ['orphan catalogue module', "UPDATE functor_catalogue_inputs SET module_id=99 WHERE artifact='a.cmt'"],
      ['catalogue provenance null', "UPDATE functor_catalogue_inputs SET source=NULL WHERE artifact='a.cmt'"],
      ['orphan catalogue result', `${relaxTable('functor_applications')} UPDATE functor_applications SET artifact='orphan.cmt' WHERE artifact='a.cmt' AND ordinal=2`],
      ['empty formal list', "UPDATE functor_declarations SET formals='[]' WHERE artifact='a.cmt'"],
      ['malformed formal JSON', "UPDATE functor_declarations SET formals='{' WHERE artifact='a.cmt'"],
      ['formal extra key', "UPDATE functor_declarations SET formals='[{\"position\":1,\"kind\":\"named\",\"binder_key\":null,\"name\":null,\"extra\":0}]' WHERE artifact='z|quote\".cmt'"],
      ['formal duplicate key', "UPDATE functor_declarations SET formals='[{\"position\":1,\"position\":1,\"kind\":\"named\",\"binder_key\":null,\"name\":null}]' WHERE artifact='z|quote\".cmt'"],
      ['formal position gap', "UPDATE functor_declarations SET formals='[{\"position\":2,\"kind\":\"named\",\"binder_key\":null,\"name\":null}]' WHERE artifact='z|quote\".cmt'"],
      ['formal unknown kind', "UPDATE functor_declarations SET formals='[{\"position\":1,\"kind\":\"other\",\"binder_key\":null,\"name\":null}]' WHERE artifact='z|quote\".cmt'"],
      ['unit invented key', "UPDATE functor_declarations SET formals='[{\"position\":1,\"kind\":\"unit\",\"binder_key\":\"invented\",\"name\":null}]' WHERE artifact='z|quote\".cmt'"],
      ['empty named key', "UPDATE functor_declarations SET formals='[{\"position\":1,\"kind\":\"named\",\"binder_key\":\"\",\"name\":null}]' WHERE artifact='z|quote\".cmt'"],
      ['empty named name', "UPDATE functor_declarations SET formals='[{\"position\":1,\"kind\":\"named\",\"binder_key\":null,\"name\":\"\"}]' WHERE artifact='z|quote\".cmt'"],
      ['bad declaration location JSON', "UPDATE functor_declarations SET location='{}' WHERE artifact='a.cmt'"],
      ['mixed null declaration location', `UPDATE functor_declarations SET location='{"file":null,"start_line":1,"start_col":null,"end_line":null,"end_col":null,"ghost":false}' WHERE artifact='a.cmt'`],
      ['empty declaration key', `${relaxTable('functor_declarations')} UPDATE functor_declarations SET declaration_key='' WHERE artifact='z|quote".cmt'`],
      ['empty declaration name', `${relaxTable('functor_declarations')} UPDATE functor_declarations SET name='' WHERE artifact='z|quote".cmt'`],
      ['invalid binding status shape', `${relaxTable('functor_bindings')} UPDATE functor_bindings SET status='matched',reason='alias_cycle' WHERE artifact='a.cmt' AND ordinal=1`],
      ['matched missing linkage', `${relaxTable('functor_bindings')} UPDATE functor_bindings SET declaration_key=NULL,formal_position=NULL WHERE artifact='a.cmt' AND ordinal=2`],
      ['unresolved missing reason', `${relaxTable('functor_bindings')} UPDATE functor_bindings SET reason=NULL WHERE artifact='z|quote".cmt'`],
      ['unknown refusal reason', `${relaxTable('functor_bindings')} UPDATE functor_bindings SET reason='unknown_reason' WHERE artifact='z|quote".cmt'`],
      ['unresolved has declaration', `${relaxTable('functor_bindings')} UPDATE functor_bindings SET declaration_key='decl:G/2',formal_position=1 WHERE artifact='z|quote".cmt'`],
      ['matched missing declaration', `${relaxTable('functor_bindings')} UPDATE functor_bindings SET declaration_key='absent' WHERE artifact='a.cmt' AND ordinal=2`],
      ['formal kind mismatch', "UPDATE functor_bindings SET formal_position=5 WHERE artifact='a.cmt' AND ordinal=2"],
      ['invalid head ordinal', "UPDATE functor_bindings SET head_application_ordinal=1 WHERE artifact='a.cmt' AND ordinal=2"],
      ['missing head occurrence', "UPDATE functor_bindings SET head_application_ordinal=99 WHERE artifact='a.cmt' AND ordinal=1"],
      ['direct starts at position two', "UPDATE functor_bindings SET formal_position=2 WHERE artifact='a.cmt' AND ordinal=2"],
      ['curried declaration mismatch', "UPDATE functor_bindings SET declaration_key='decl:G/2',formal_position=1 WHERE artifact='a.cmt' AND ordinal=2"],
      ['ineligible actual root', "UPDATE functor_bindings SET actual_root_key='root' WHERE artifact='z|quote\".cmt'"],
      ['contains-apply actual root', `UPDATE functor_applications SET argument='{"kind":"path","compiler":"A(X)","source":"A(X)","contains_apply":true}' WHERE artifact='a.cmt' AND ordinal=2`],
      ['empty actual root', `${relaxTable('functor_bindings')} UPDATE functor_bindings SET actual_root_key='' WHERE artifact='a.cmt' AND ordinal=2`],
      ['binding storage type', "UPDATE functor_bindings SET formal_position='one' WHERE artifact='a.cmt' AND ordinal=2"],
      ['binding nullable storage type', "UPDATE functor_bindings SET actual_root_key=X'00' WHERE artifact='a.cmt' AND ordinal=2"],
      ['declaration storage type', "UPDATE functor_declarations SET name=X'00' WHERE artifact='a.cmt'"],
      ['binding ordinal range', `${relaxTable('functor_bindings')} UPDATE functor_bindings SET ordinal=0 WHERE artifact='a.cmt' AND ordinal=2`],
      ['input negative range', "UPDATE functor_binding_inputs SET expected_bindings=-1 WHERE artifact='a.cmt'"],
      ['duplicate binding input', `${relaxTable('functor_binding_inputs')} INSERT INTO functor_binding_inputs SELECT * FROM functor_binding_inputs WHERE artifact='a.cmt'`],
      ['duplicate declaration', `${relaxTable('functor_declarations')} INSERT INTO functor_declarations SELECT * FROM functor_declarations WHERE artifact='a.cmt'`],
      ['duplicate binding', `${relaxTable('functor_bindings')} INSERT INTO functor_bindings SELECT * FROM functor_bindings WHERE artifact='a.cmt' AND ordinal=2`],
      ['duplicate catalogue input', `${relaxTable('functor_catalogue_inputs')} INSERT INTO functor_catalogue_inputs SELECT * FROM functor_catalogue_inputs WHERE artifact='a.cmt'`],
      ['duplicate catalogue occurrence', `${relaxTable('functor_applications')} INSERT INTO functor_applications SELECT * FROM functor_applications WHERE artifact='a.cmt' AND ordinal=2`],
      ['duplicate catalogue run', `${relaxTable('functor_catalogue_runs')} INSERT INTO functor_catalogue_runs SELECT * FROM functor_catalogue_runs`],
      ['second producer run', "INSERT INTO producer_runs(id,producer) VALUES(2,'other'); INSERT INTO functor_catalogue_runs VALUES(2,1)"],
      ['catalogue JSON corruption', "UPDATE functor_applications SET argument='{}' WHERE artifact='a.cmt' AND ordinal=2"]
    ];
    faults.forEach(([label, fault], i) => {
      const bad = path.join(dir, `bad-${i}.db`);
      makeDb(bad);
      const premise = queryRun(bad, ['0']);
      assert.equal(premise.status, 0, `${label}: valid premise rejected: ${premise.stderr}`);
      mutateDb(bad, fault);
      try { assertRefusal(queryRun(bad, ['0']), 'INCONSISTENT_BINDINGS', 3); }
      catch (error) { error.message = `${label}: ${error.message}`; throw error; }
      corruptions++;
    });

    const reasons = ['cross_unit_head', 'parameter_supplied_head', 'alias_cycle',
      'local_declaration_missing', 'unsupported_alias_rhs', 'unsupported_path',
      'unsupported_head_shape', 'curried_result_not_functor', 'formal_kind_mismatch'];
    for (const reason of reasons) {
      const db = path.join(dir, `reason-${reason}.db`); makeDb(db);
      mutateDb(db, `UPDATE functor_bindings SET reason=${quote(reason)}
        WHERE artifact='z|quote".cmt' AND ordinal=1`);
      const accepted = queryRun(db, ['0']);
      assert.equal(accepted.status, 0, `${reason} from the closed refusal vocabulary was rejected: ${accepted.stderr}`);
    }

    const schemaFaults = [
      ['missing new table', 'DROP TABLE functor_bindings'],
      ['missing old table', 'DROP TABLE functor_applications'],
      ['missing new column', 'ALTER TABLE functor_bindings DROP COLUMN actual_root_key'],
      ['missing binding-input column', 'ALTER TABLE functor_binding_inputs DROP COLUMN outcome'],
      ['missing declaration column', 'ALTER TABLE functor_declarations DROP COLUMN formals'],
      ['missing old column', 'ALTER TABLE functor_applications DROP COLUMN diagnostics'],
      ['missing catalogue-input column', 'ALTER TABLE functor_catalogue_inputs DROP COLUMN source'],
      ['missing catalogue-run column', 'ALTER TABLE functor_catalogue_runs DROP COLUMN selected_inputs'],
      ['missing marker column', 'ALTER TABLE comment_db_meta DROP COLUMN value'],
      ['flat discriminator', 'ALTER TABLE calls ADD COLUMN caller_name TEXT']
    ];
    schemaFaults.forEach(([label, fault], i) => {
      const bad = path.join(dir, `schema-${i}.db`); makeDb(bad);
      assert.equal(queryRun(bad, ['0']).status, 0, `${label}: valid premise rejected`);
      mutateDb(bad, fault);
      assertRefusal(queryRun(bad, ['0']), 'UNSUPPORTED_SCHEMA', 3); schemaRefusals++;
    });
    const markerFaults = [
      ['missing binding', "DELETE FROM comment_db_meta WHERE key='functor_binding_contract'"],
      ['binding version', "UPDATE comment_db_meta SET value='v2' WHERE key='functor_binding_contract'"],
      ['binding type', "UPDATE comment_db_meta SET value=X'7631' WHERE key='functor_binding_contract'"],
      ['missing catalogue', "DELETE FROM comment_db_meta WHERE key='functor_catalogue_contract'"],
      ['catalogue version', "UPDATE comment_db_meta SET value='v2' WHERE key='functor_catalogue_contract'"],
      ['catalogue type', "UPDATE comment_db_meta SET value=X'7631' WHERE key='functor_catalogue_contract'"],
      ['duplicate binding marker', `${relaxTable('comment_db_meta')} INSERT INTO comment_db_meta(key,value) VALUES('functor_binding_contract','v1')`]
    ];
    markerFaults.forEach(([label, fault], i) => {
      const bad = path.join(dir, `marker-${i}.db`); makeDb(bad);
      assert.equal(queryRun(bad, ['0']).status, 0, `${label}: valid premise rejected`);
      mutateDb(bad, fault);
      assertRefusal(queryRun(bad, ['0']), 'NOT_COLLECTED_BINDINGS', 3); markerRefusals++;
    });
    const precedence = path.join(dir, 'precedence.db'); makeDb(precedence);
    assert.equal(queryRun(precedence, ['0']).status, 0, 'schema precedence valid premise rejected');
    mutateDb(precedence, "DROP TABLE functor_bindings; DELETE FROM comment_db_meta WHERE key='functor_binding_contract'");
    assertRefusal(queryRun(precedence, ['0']), 'UNSUPPORTED_SCHEMA', 3);
    const markerPrecedence = path.join(dir, 'marker-precedence.db'); makeDb(markerPrecedence);
    assert.equal(queryRun(markerPrecedence, ['0']).status, 0, 'marker precedence valid premise rejected');
    mutateDb(markerPrecedence, "DELETE FROM comment_db_meta WHERE key='functor_binding_contract'; DELETE FROM functor_bindings WHERE ordinal=2");
    assertRefusal(queryRun(markerPrecedence, ['0']), 'NOT_COLLECTED_BINDINGS', 3);

    // AC-11 accessed-operation failure: retain every required table/view column
    // and both exact markers, then make reading an actually accessed validation
    // cell fail inside SQLite. This is neither an absent-schema refusal nor a
    // fabricated CLI status.
    const accessedFailure = path.join(dir, 'accessed-operation.db');
    makeDb(accessedFailure);
    assert.equal(queryRun(accessedFailure, ['0']).status, 0,
      'accessed-operation valid premise rejected');
    mutateDb(accessedFailure, `ALTER TABLE functor_bindings RENAME TO binding_rows_source;
      CREATE VIEW functor_bindings AS
      SELECT producer_run_id,artifact,ordinal,status,
        CASE WHEN reason IS NULL THEN abs(-9223372036854775808) ELSE reason END AS reason,
        declaration_key,formal_position,head_application_ordinal,actual_root_key
      FROM binding_rows_source`);
    assert.deepEqual(rows(accessedFailure, `SELECT name FROM pragma_table_info('functor_bindings')`)
      .map(row => row.name), ['producer_run_id', 'artifact', 'ordinal', 'status', 'reason',
      'declaration_key', 'formal_position', 'head_application_ordinal', 'actual_root_key'],
    'accessed-operation fixture did not retain the required binding columns');
    assert.deepEqual(rows(accessedFailure, `SELECT key,value FROM comment_db_meta
      WHERE key IN ('functor_catalogue_contract','functor_binding_contract') ORDER BY key`),
    [{key: 'functor_binding_contract', value: 'v1'},
     {key: 'functor_catalogue_contract', value: 'v1'}],
    'accessed-operation fixture lost an exact contract marker');
    const directRead = run('sqlite3', [accessedFailure,
      'SELECT typeof(reason) FROM functor_bindings']);
    assert.notEqual(directRead.status, 0, 'explosive validation cell unexpectedly read successfully');
    assert.match(directRead.stderr, /integer overflow/);
    assertRefusal(queryRun(accessedFailure, ['0']), 'integer overflow|database operation', 2);

    for (const args of [[''], ['+1'], [' 1'], ['1 '], ['-1'], ['0x10'], ['١'],
      ['999999999999999999999999999999999999'], ['1', 'extra']]) {
      assertRefusal(queryRun('/does/not/exist.db', args), 'usage|limit|integer', 2);
    }
    assertRefusal(queryRun(dir), 'open|database|directory', 2);
    const malformedDb = path.join(dir, 'malformed.db');
    fs.writeFileSync(malformedDb, 'this is not a SQLite database');
    assertRefusal(queryRun(malformedDb), 'database|disk image|open|not an arch-index DB', 2);
    const badFormat = run(queryBinary, ['/does/not/exist.db', 'functor-bindings'],
      {env: {...process.env, ARCH_QUERY_FORMAT: 'unknown'}});
    assertRefusal(badFormat, 'unknown ARCH_QUERY_FORMAT|format', 2);
  });
  return {valid_results: 3, matched: 2, unresolved: 1, renderer_oracles: successfulOracles,
    zero_result_oracles: formats.length * 3, default_limit_rows: 50,
    formats: formats.length, limit_zero_corruptions: corruptions,
    schema_refusals: schemaRefusals, marker_refusals: markerRefusals,
    unrelated_old_table_ignored: true, accessed_operation_failure: true, readonly: true};
}

function producerLifecycle() {
  mustFile(indexer);
  return temp(dir => {
    const buildDir = path.join(dir, '_build/default');
    fs.mkdirSync(buildDir, {recursive: true});
    const source = path.join(dir, 'producer_lifecycle.ml');
    fs.writeFileSync(source, `
module type S = sig val value : int end
module F (X : S) = X
module A = struct let value = 1 end
module B = struct let value = 2 end
module First = F (A)
module Second = F (B)
`);
    opam(['ocamlc', '-bin-annot', '-c', path.basename(source),
      '-o', '_build/default/producer_lifecycle.cmo'], {cwd: dir});

    const baseSchema = fs.readFileSync(path.join(root, 'architecture-schema.sql'), 'utf8');
    const partialTrigger = `
CREATE TRIGGER lifecycle_reject_second_binding BEFORE INSERT ON functor_bindings
WHEN NEW.ordinal=2 BEGIN
  SELECT CASE WHEN
    (SELECT count(*) FROM functor_bindings)=1 AND
    (SELECT count(*) FROM functor_declarations)=1 AND
    (SELECT count(*) FROM functor_binding_inputs)=1
  THEN RAISE(ABORT,'injected producer second-result failure')
  ELSE RAISE(ABORT,'wrong producer partial-insertion premise') END;
END;
`;
    const failedRowTrigger = `
CREATE TRIGGER lifecycle_reject_failed_row BEFORE INSERT ON functor_binding_inputs
WHEN NEW.outcome='collection_failed'
BEGIN SELECT RAISE(ABORT,'injected producer failed-row failure'); END;
`;
    const healthySchema = path.join(dir, 'healthy-schema.sql');
    const partialSchema = path.join(dir, 'partial-schema.sql');
    const failedRowSchema = path.join(dir, 'failed-row-schema.sql');
    fs.writeFileSync(healthySchema, baseSchema);
    fs.writeFileSync(partialSchema, baseSchema + partialTrigger);
    fs.writeFileSync(failedRowSchema, baseSchema + partialTrigger + failedRowTrigger);

    const indexWith = (db, schema) => run(indexer,
      ['--build-dir', buildDir, '--db-path', db, '--schema-path', schema]);
    const requireIndex = (db, schema) => {
      const result = indexWith(db, schema);
      assert.equal(result.status, 0, result.stderr);
      return result;
    };
    const stableFacts = db => ({
      catalogue_inputs: rows(db, `SELECT artifact,source,compiler_unit,outcome,expected_applications
        FROM functor_catalogue_inputs ORDER BY artifact`),
      catalogue_applications: rows(db, `SELECT artifact,ordinal,application_kind,location,head,argument,diagnostics
        FROM functor_applications ORDER BY artifact,ordinal`),
      modules: rows(db, `SELECT path,lines,has_mli,language FROM modules ORDER BY path`),
      functions: rows(db, `SELECT m.path AS module_path,f.name,f.signature,f.line_start,f.line_end,f.exposed
        FROM functions f JOIN modules m ON m.id=f.module_id
        ORDER BY m.path,f.name,f.line_start,f.line_end`),
      calls: rows(db, `SELECT cm.path AS caller_module,cf.name AS caller_name,c.callee_name,c.kind,c.edge_form,c.top_reason
        FROM calls c JOIN functions cf ON cf.id=c.caller_id
        JOIN modules cm ON cm.id=cf.module_id
        ORDER BY cm.path,cf.name,c.callee_name,c.kind,c.edge_form,c.top_reason`)
    });

    const baseline = path.join(dir, 'healthy.db');
    requireIndex(baseline, healthySchema);
    const healthyFacts = stableFacts(baseline);
    assert.equal(rows(baseline, 'SELECT count(*) AS n FROM functor_bindings')[0].n, 2);
    assert.deepEqual(rows(baseline, `SELECT value FROM comment_db_meta
      WHERE key='functor_binding_contract'`), [{value: 'v1'}]);

    const partial = path.join(dir, 'partial.db');
    const partialRun = requireIndex(partial, partialSchema);
    assert.match(partialRun.stderr, /injected producer second-result failure/);
    assert.doesNotMatch(partialRun.stderr, /wrong producer partial-insertion premise/);
    assert.deepEqual(stableFacts(partial), healthyFacts,
      'binding storage failure changed catalogue or graph semantics');
    assert.deepEqual(rows(partial, `SELECT outcome,expected_declarations,expected_bindings
      FROM functor_binding_inputs`),
      [{outcome: 'collection_failed', expected_declarations: 0, expected_bindings: 0}]);
    assert.equal(rows(partial, 'SELECT count(*) AS n FROM functor_declarations')[0].n, 0);
    assert.equal(rows(partial, 'SELECT count(*) AS n FROM functor_bindings')[0].n, 0);
    assert.equal(rows(partial, `SELECT count(*) AS n FROM comment_db_meta
      WHERE key='functor_binding_contract'`)[0].n, 0);

    const failedRow = path.join(dir, 'failed-row.db');
    const failedRowRun = requireIndex(failedRow, failedRowSchema);
    assert.match(failedRowRun.stderr, /injected producer second-result failure/);
    assert.match(failedRowRun.stderr, /injected producer failed-row failure/);
    assert.doesNotMatch(failedRowRun.stderr, /wrong producer partial-insertion premise/);
    assert.deepEqual(stableFacts(failedRow), healthyFacts,
      'failed outcome recording changed catalogue or graph semantics');
    assert.equal(rows(failedRow, 'SELECT count(*) AS n FROM functor_binding_inputs')[0].n, 0);
    assert.equal(rows(failedRow, 'SELECT count(*) AS n FROM functor_bindings')[0].n, 0);
    assert.equal(rows(failedRow, `SELECT count(*) AS n FROM comment_db_meta
      WHERE key='functor_binding_contract'`)[0].n, 0);

    const reindex = path.join(dir, 'reindex.db');
    requireIndex(reindex, healthySchema);
    assert.equal(rows(reindex, `SELECT count(*) AS n FROM comment_db_meta
      WHERE key='functor_binding_contract' AND value='v1'`)[0].n, 1);
    requireIndex(reindex, partialSchema);
    assert.deepEqual(rows(reindex, `SELECT outcome,expected_declarations,expected_bindings
      FROM functor_binding_inputs`),
      [{outcome: 'collection_failed', expected_declarations: 0, expected_bindings: 0}]);
    assert.equal(rows(reindex, `SELECT count(*) AS n FROM comment_db_meta
      WHERE key='functor_binding_contract'`)[0].n, 0,
      'failed reindex retained a stale binding marker');
    requireIndex(reindex, healthySchema);
    assert.deepEqual(rows(reindex, `SELECT outcome,expected_bindings
      FROM functor_binding_inputs`), [{outcome: 'collected', expected_bindings: 2}]);
    assert.equal(rows(reindex, 'SELECT count(*) AS n FROM functor_bindings')[0].n, 2);
    assert.equal(rows(reindex, `SELECT count(*) AS n FROM comment_db_meta
      WHERE key='functor_binding_contract' AND value='v1'`)[0].n, 1);

    const emptyDir = path.join(dir, 'empty', '_build/default');
    fs.mkdirSync(emptyDir, {recursive: true});
    const emptyRoot = path.dirname(path.dirname(emptyDir));
    const emptySource = path.join(emptyRoot, 'zero_fixture.ml');
    fs.writeFileSync(emptySource, 'module Value = struct let value = 0 end\n');
    opam(['ocamlc', '-bin-annot', '-c', path.basename(emptySource),
      '-o', '_build/default/zero_fixture.cmo'], {cwd: emptyRoot});
    fs.writeFileSync(path.join(emptyDir, 'unreadable.cmt'), 'owned unreadable CMT premise\n');
    const incomplete = path.join(dir, 'zero-unreadable.db');
    const incompleteRun = run(indexer,
      ['--build-dir', emptyDir, '--db-path', incomplete, '--schema-path', healthySchema]);
    assert.equal(incompleteRun.status, 0, incompleteRun.stderr);
    const catalogueInputs = rows(incomplete, `SELECT artifact,outcome,expected_applications
      FROM functor_catalogue_inputs ORDER BY artifact`);
    assert.equal(catalogueInputs.filter(row => row.outcome === 'collected' && row.expected_applications === 0).length, 1);
    assert.equal(catalogueInputs.filter(row => row.outcome === 'unreadable').length, 1);
    assert.equal(rows(incomplete, 'SELECT count(*) AS n FROM functor_applications')[0].n, 0);
    assert.equal(rows(incomplete, 'SELECT count(*) AS n FROM functor_bindings')[0].n, 0,
      'zero/unreadable inputs fabricated binding ordinals');
    assert.equal(rows(incomplete, `SELECT count(*) AS n FROM functor_binding_inputs bi
      JOIN functor_catalogue_inputs ci USING(producer_run_id,artifact)
      WHERE ci.outcome='unreadable'`)[0].n, 0,
      'unreadable catalogue input fabricated a binding input');
    assert.equal(rows(incomplete, `SELECT count(*) AS n FROM comment_db_meta
      WHERE key='functor_binding_contract'`)[0].n, 0);

    return {
      evidence: 'real-producer-cli-owned-schema-faults',
      healthy_bindings: 2,
      partial_failure: {failed_row_recorded: true, old_facts_match_baseline: true, marker_absent: true},
      failed_row_failure: {input_absent: true, old_facts_match_baseline: true, marker_absent: true},
      reindex_sequence: ['valid', 'failed', 'valid'],
      zero_and_unreadable: {applications: 0, bindings: 0, unreadable_binding_inputs: 0}
    };
  });
}

function lifecycle() {
  const source = path.join(root, 'roster/functor-binding-resolution/lifecycle_probe.ml');
  if (!fs.existsSync(source)) throw new Error(`PENDING_LIFECYCLE: missing direct API probe ${source}`);
  return temp(dir => {
    const copied = path.join(dir, 'lifecycle_probe.ml');
    const executable = path.join(dir, 'lifecycle_probe.exe');
    fs.copyFileSync(source, copied);
    const stagingPath = path.join(root, '_build/install/default/lib');
    const env = {...process.env,
      OCAMLPATH: process.env.OCAMLPATH
        ? `${stagingPath}${path.delimiter}${process.env.OCAMLPATH}`
        : stagingPath};
    opam(['ocamlfind', 'ocamlopt', '-package', 'arch-index', '-linkpkg',
      copied, '-o', executable], {cwd: dir, env});
    const result = run(executable, [path.join(root, 'architecture-schema.sql')], {cwd: dir});
    if (result.status === 1) assert.fail(`lifecycle probe assertion: ${result.stderr}`);
    if (result.status !== 0) throw new Error(`lifecycle probe setup (${result.status}): ${result.stderr}`);
    let evidence;
    try { evidence = JSON.parse(result.stdout); }
    catch (error) { throw new Error(`lifecycle probe returned invalid JSON: ${error.message}`); }
    assert.deepEqual(evidence, {
      ok: true,
      evidence: 'direct-api-not-full-cli-orchestration',
      storage: {
        partial_failure_raised: true,
        binding_rows_after_rollback: 0,
        catalogue_rows_preserved: 2,
        graph_sentinel_preserved: true,
        failed_row_success: true,
        failed_row_rejection_raised: true
      },
      rollback_uncertainty: {
        raised_rollback_uncertainty: true,
        binding_input_absent: true,
        old_facts_preserved: true
      },
      marker_lifecycle: {
        zero_result_finalized: true,
        marker_absent_before_finalize: true,
        marker_write_failure_raised: true,
        marker_absent_after_write_failure: true,
        empty_selection_ineligible: true
      }
    });
    return {direct_api: evidence, producer_cli: producerLifecycle()};
  });
}

function compatibility() {
  mustFile(queryBinary);
  const priorArgs = ['node', path.join(root, 'scripts/check-functor-catalogue.js'), 'compatibility'];
  const prior = opamSwitch
    ? run('opam', opamExecArgs(priorArgs), {cwd: root})
    : run(priorArgs[0], priorArgs.slice(1), {cwd: root});
  if (prior.status === 1) assert.fail(`catalogue compatibility assertion: ${prior.stderr}`);
  if (prior.status !== 0) throw new Error(`catalogue compatibility setup (${prior.status}): ${prior.stderr}`);
  let priorEvidence;
  try { priorEvidence = JSON.parse(prior.stdout); }
  catch (error) { throw new Error(`catalogue compatibility returned invalid JSON: ${error.message}`); }
  assert.equal(priorEvidence.mode, 'compatibility');

  const readonly = temp(dir => {
    const db = path.join(dir, 'compatibility.db');
    makeDb(db);
    const beforeHash = hash(db);
    const catalogueBefore = catalogueRun(db, [], 'json');
    assert.equal(catalogueBefore.status, 0, catalogueBefore.stderr);
    const binding = queryRun(db, [], 'json');
    assert.equal(binding.status, 0, binding.stderr);
    const catalogueAfter = catalogueRun(db, [], 'json');
    assert.equal(catalogueAfter.status, 0, catalogueAfter.stderr);
    assert.equal(catalogueAfter.stdout, catalogueBefore.stdout,
      'binding query changed the existing catalogue projection');
    assert.equal(hash(db), beforeHash, 'catalogue/binding queries changed database bytes');
    return {catalogue_bytes_unchanged: true, database_bytes_unchanged: true,
      binding_results_observed: twoArrays(binding.stdout)[1].length};
  });
  const flat = temp(dir => {
    const db = path.join(dir, 'flat.db');
    // This is the committed runner.ml flat-1.3 shape, populated with the
    // longstanding point-free-alias query premise from
    // tezt/tests/point_free_aliases.ml: a real caller counts; a value alias
    // does not. The expected bytes below are authored from that pre-feature
    // contract, not obtained by querying this binary to create an oracle.
    sql(db, `
      CREATE TABLE comment_db_meta(key TEXT PRIMARY KEY,value TEXT NOT NULL);
      INSERT INTO comment_db_meta VALUES
        ('callgraph_contract','v1'),('schema_version','1.3');
      CREATE TABLE functions(
        id INTEGER PRIMARY KEY,name TEXT NOT NULL,file_path TEXT NOT NULL,
        line_start INTEGER NOT NULL DEFAULT 0,line_end INTEGER NOT NULL DEFAULT 0,
        exported INTEGER NOT NULL DEFAULT 0,signature TEXT,summary TEXT,
        comment_quality_score INTEGER,has_pre INTEGER NOT NULL DEFAULT 0,
        has_post INTEGER NOT NULL DEFAULT 0,has_violators INTEGER NOT NULL DEFAULT 0,
        has_violates INTEGER NOT NULL DEFAULT 0,violators_raw TEXT,violates_raw TEXT,
        tests_raw TEXT,quint_raw TEXT,language TEXT);
      CREATE TABLE calls(
        id INTEGER PRIMARY KEY,caller_name TEXT NOT NULL,caller_file TEXT NOT NULL,
        callee_name TEXT NOT NULL,callee_file TEXT,call_site TEXT,kind TEXT,edge_form TEXT);
      INSERT INTO functions(id,name,file_path,exported) VALUES
        (1,'caller','flat.ml',1),(2,'sink','flat.ml',0),(3,'alias','flat.ml',0);
      INSERT INTO calls VALUES
        (1,'caller','flat.ml','sink','flat.ml','flat.ml:1','MAY_ENUMERATED',NULL),
        (2,'alias','flat.ml','sink','flat.ml','flat.ml:2','MAY_ENUMERATED','value_alias');`);
    assert.deepEqual(rows(db, `SELECT caller_name,edge_form FROM calls ORDER BY id`),
      [{caller_name: 'caller', edge_form: null},
       {caller_name: 'alias', edge_form: 'value_alias'}],
    'flat compatibility premise must contain both real and excluded alias edges');
    const legacyOracles = [
      {args: ['callers-of', 'sink'], stdout: '[{"caller_name":"caller","caller_file":"flat.ml"}]\n'},
      {args: ['fan-in', '10'], stdout: '[{"callee_name":"sink","callers":1}]\n'},
      {args: ['reachable-from', 'caller'], stdout: '[{"reachable":"sink"}]\n'}
    ];
    const checkLegacy = phase => {
      for (const expected of legacyOracles) {
        const result = run(queryBinary, [db, ...expected.args],
          {env: {...process.env, ARCH_QUERY_FORMAT: 'json'}});
        assert.equal(result.status, 0, `${phase}/${expected.args.join(' ')}: ${result.stderr}`);
        assert.equal(result.stdout, expected.stdout,
          `${phase}/${expected.args.join(' ')} changed the historical flat oracle`);
      }
    };
    const before = hash(db);
    checkLegacy('before-binding-command');
    const bindingRefusal = queryRun(db, [], 'json');
    assertRefusal(bindingRefusal, 'UNSUPPORTED_SCHEMA', 3);
    checkLegacy('after-binding-command');
    assert.equal(hash(db), before, 'flat queries or binding refusal changed database bytes');
    return {schema: 'flat-1.3', historical_oracles: legacyOracles.length,
      alias_exclusion_premise: true, before_after_binding_refusal: true,
      database_bytes_unchanged: true};
  });
  return {prior_catalogue_checker: priorEvidence.result, readonly, flat};
}

try {
  const mode = process.argv[2];
  const groups = {
    inventory,
    lifecycle,
    query,
    compatibility
  };
  if (!groups[mode] || process.argv.length !== 3) {
    throw new Error('usage: check-functor-bindings.js inventory|lifecycle|query|compatibility');
  }
  console.log(JSON.stringify({mode, result: groups[mode]()}));
} catch (error) {
  console.error(error.stack || String(error));
  process.exitCode = error instanceof assert.AssertionError ? 1 : 2;
}
