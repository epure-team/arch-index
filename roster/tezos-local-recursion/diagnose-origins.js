#!/usr/bin/env node
'use strict';

const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const cp = require('node:child_process');

const root = path.resolve(__dirname, '../..');
const inputDir = path.join(root, 'improvement/2026-09-14-tezos-resolution/attempt4-self-reference-N1yBlb');
const inputFile = path.join(inputDir, 'provenance.json');

const sha = data => crypto.createHash('sha256').update(data).digest('hex');
const fileSha = file => sha(fs.readFileSync(file));

function spawn(exe, args, options = {}) {
  const result = cp.spawnSync(exe, args, {
    cwd: options.cwd || root,
    env: options.env || process.env,
    encoding: options.encoding === undefined ? 'utf8' : options.encoding,
    maxBuffer: 64 * 1024 * 1024,
    input: options.input,
    stdio: options.stdio,
  });
  if (result.error || result.signal || result.status !== 0) {
    throw new Error(`${exe} ${args.join(' ')} failed (${result.status}): ${result.error || result.signal || result.stderr || ''}`);
  }
  return typeof result.stdout === 'string' ? result.stdout.trim() : result.stdout;
}

function rootState() {
  const index = path.resolve(root, spawn('git', ['rev-parse', '--git-path', 'index']));
  return {
    head: spawn('git', ['rev-parse', 'HEAD']),
    status: spawn('git', ['status', '--porcelain=v1', '-uall']),
    index_sha256: fs.existsSync(index) ? fileSha(index) : null,
  };
}

function filesBelow(dir, suffixes) {
  const out = [];
  const walk = current => {
    for (const entry of fs.readdirSync(current, {withFileTypes: true})) {
      const absolute = path.join(current, entry.name);
      if (entry.isSymbolicLink()) {
        // Dune's public_cmi aliases are not CMT/source inputs. Never follow
        // directory links or accept a symlink for a measured input itself.
        if (suffixes.some(suffix => entry.name.endsWith(suffix))
            || fs.statSync(absolute).isDirectory())
          throw new Error(`refusing symlink in inventory: ${absolute}`);
        continue;
      }
      if (entry.isDirectory()) walk(absolute);
      else if (suffixes.some(suffix => entry.name.endsWith(suffix))) out.push(absolute);
    }
  };
  walk(dir);
  return out.sort();
}

function inventory(dir, suffixes) {
  return Object.fromEntries(filesBelow(dir, suffixes).map(file => [
    path.relative(dir, file).split(path.sep).join('/'),
    fileSha(file),
  ]));
}

function logged(exe, args, cwd, log, env = process.env) {
  const fd = fs.openSync(log, 'wx');
  try {
    const result = cp.spawnSync(exe, args, {cwd, env, stdio: ['ignore', fd, fd]});
    if (result.error || result.signal || result.status !== 0) {
      throw new Error(`${exe} ${args.join(' ')} failed (${result.status}): ${result.error || result.signal || ''}; log=${log}`);
    }
  } finally {
    fs.closeSync(fd);
  }
}

function sqlite(db, sql) {
  const output = spawn('sqlite3', ['-json', db, sql]);
  return JSON.parse(output || '[]');
}

function observation(db) {
  const totals = sqlite(db, 'select (select count(*) from modules) modules,(select count(*) from functions) functions,(select count(*) from calls) calls,(select count(*) from exn_origins) origins')[0];
  const origin_groups = sqlite(db, 'select channel,form,escapes,count(*) count from exn_origins group by channel,form,escapes order by channel,form,escapes');
  const modules = sqlite(db, 'select path from modules order by path').map(row => row.path);
  const assertions = sqlite(db, `
    select m.path source_path,f.name function_name,o.channel,o.form,o.exn_path,
           o.escapes,o.line,o.col,o.operand_primitive,o.operand_slot,
           o.operand_category,o.operand_repr,o.operand_integer_kind,
           o.operand_unavailable_reason
    from exn_origins o
    join functions f on f.id=o.function_id
    join modules m on m.id=f.module_id
    where o.form='assert'
    order by m.path,f.name,o.line,o.col`);
  assert.equal(assertions.length, 1, `expected sole assert origin in ${db}`);
  for (const modulePath of modules) {
    assert.equal(path.isAbsolute(modulePath), false, `absolute module path in ${db}: ${modulePath}`);
    assert.equal(modulePath.split('/').includes('..'), false, `escaping module path in ${db}: ${modulePath}`);
  }
  assert.equal(path.isAbsolute(assertions[0].source_path), false, `absolute assert source in ${db}`);
  return {totals, origin_groups, modules, sole_assert: assertions[0]};
}

function main() {
  const sourceProvenance = JSON.parse(fs.readFileSync(inputFile, 'utf8'));
  assert.equal(sourceProvenance.version, 1);
  assert.equal(sourceProvenance.cleanup_verified, true);
  const base = sourceProvenance.base;
  const candidate = sourceProvenance.candidate_commit;
  assert.match(base, /^[0-9a-f]{40}$/);
  assert.match(candidate, /^[0-9a-f]{40}$/);
  assert.equal(spawn('git', ['rev-parse', `${candidate}^{tree}`]), sourceProvenance.candidate_tree);
  spawn('git', ['cat-file', '-e', `${base}^{commit}`]);

  const beforeRoot = rootState();
  assert.equal(beforeRoot.head, sourceProvenance.root_head, 'root HEAD differs from source provenance');
  assert.equal(beforeRoot.index_sha256, sourceProvenance.root_index_sha256, 'root index differs from source provenance');
  for (const [rel, expected] of Object.entries(sourceProvenance.selected_sha256)) {
    assert.equal(fileSha(path.join(root, rel)), expected, `selected source hash changed: ${rel}`);
  }
  const opamSwitch = spawn('opam', ['switch', 'show', '--safe']);
  assert.equal(opamSwitch, sourceProvenance.opam_switch, 'root opam switch differs from source provenance');

  const evidenceParent = path.join(root, 'improvement/2026-09-14-tezos-resolution');
  spawn('git', ['check-ignore', '-q', '--', path.join(evidenceParent, '.origin-attribution-ignore-probe')]);
  const evidence = fs.mkdtempSync(path.join(evidenceParent, 'attempt4-origin-attribution-'));
  const owner = fs.mkdtempSync(path.join(os.tmpdir(), 'arch-index-origin-attribution-'));
  const baseTree = path.join(owner, 'base');
  const candidateTree = path.join(owner, 'candidate');
  let baseAdded = false;
  let candidateAdded = false;
  let cleanupError = null;
  const provenance = {
    version: 1,
    input_provenance: path.relative(root, inputFile),
    input_provenance_sha256: fileSha(inputFile),
    base,
    candidate,
    opam_switch: opamSwitch,
    root_before: beforeRoot,
    cells: {},
    cleanup_verified: false,
  };

  try {
    spawn('git', ['worktree', 'add', '--detach', baseTree, base]);
    baseAdded = true;
    spawn('git', ['worktree', 'add', '--detach', candidateTree, candidate]);
    candidateAdded = true;

    const baseSourceBefore = inventory(path.join(baseTree, 'lib/arch_index'), ['.ml', '.mli']);
    const candidateSourceBefore = inventory(path.join(candidateTree, 'lib/arch_index'), ['.ml', '.mli']);
    logged('opam', ['exec', '--switch', opamSwitch, '--', 'dune', 'build', '--root', '.'], baseTree, path.join(evidence, 'build-base.log'));
    logged('opam', ['exec', '--switch', opamSwitch, '--', 'dune', 'build', '--root', '.'], candidateTree, path.join(evidence, 'build-candidate.log'));
    const baseSourceAfter = inventory(path.join(baseTree, 'lib/arch_index'), ['.ml', '.mli']);
    const candidateSourceAfter = inventory(path.join(candidateTree, 'lib/arch_index'), ['.ml', '.mli']);
    assert.deepEqual(baseSourceAfter, baseSourceBefore, 'base source changed during build');
    assert.deepEqual(candidateSourceAfter, candidateSourceBefore, 'candidate source changed during build');

    provenance.source_before = {base: baseSourceBefore, candidate: candidateSourceBefore};
    provenance.source_after = {base: baseSourceAfter, candidate: candidateSourceAfter};
    provenance.binaries = {
      base: fileSha(path.join(baseTree, '_build/default/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe')),
      candidate: fileSha(path.join(candidateTree, '_build/default/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe')),
    };
    provenance.schemas = {
      base: fileSha(path.join(baseTree, 'architecture-schema.sql')),
      candidate: fileSha(path.join(candidateTree, 'architecture-schema.sql')),
    };
    provenance.cmts = {
      base: inventory(path.join(baseTree, '_build/default/lib/arch_index'), ['.cmt', '.cmti']),
      candidate: inventory(path.join(candidateTree, '_build/default/lib/arch_index'), ['.cmt', '.cmti']),
    };

    const definitions = [
      ['A', baseTree, baseTree],
      ['B', candidateTree, baseTree],
      ['C', baseTree, candidateTree],
      ['D', candidateTree, candidateTree],
    ];
    const observations = {};
    for (const [name, binaryTree, corpusTree] of definitions) {
      const db = path.join(evidence, `${name}.db`);
      const log = path.join(evidence, `${name}.producer.log`);
      const producer = path.join(binaryTree, '_build/default/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe');
      const corpus = path.join(corpusTree, '_build/default/lib/arch_index');
      const schema = path.join(binaryTree, 'architecture-schema.sql');
      logged(producer, [`--build-dir=${corpus}`, `--db-path=${db}`, `--schema-path=${schema}`], corpusTree, log);
      observations[name] = observation(db);
      provenance.cells[name] = {
        binary_commit: name === 'A' || name === 'C' ? base : candidate,
        corpus_commit: name === 'A' || name === 'B' ? base : candidate,
        database: path.basename(db),
        database_sha256: fileSha(db),
        producer_log: path.basename(log),
      };
    }
    assert.deepEqual(observations.A, observations.B, 'origin 2x2 behavioural delta: A != B');
    assert.deepEqual(observations.C, observations.D, 'origin 2x2 interaction delta: C != D');
    fs.writeFileSync(path.join(evidence, 'observations.json'), `${JSON.stringify(observations, null, 2)}\n`, {flag: 'wx'});
  } finally {
    try {
      if (candidateAdded) spawn('git', ['worktree', 'remove', '--force', candidateTree]);
      if (baseAdded) spawn('git', ['worktree', 'remove', '--force', baseTree]);
      fs.rmSync(owner, {recursive: true, force: true});
      assert.equal(spawn('opam', ['switch', 'show', '--safe']), opamSwitch, 'root opam switch changed');
      assert.deepEqual(rootState(), beforeRoot, 'root HEAD/index/status changed');
      for (const [rel, expected] of Object.entries(sourceProvenance.selected_sha256)) {
        assert.equal(fileSha(path.join(root, rel)), expected, `root selected source changed: ${rel}`);
      }
      provenance.cleanup_verified = true;
    } catch (error) {
      cleanupError = error;
      provenance.cleanup_error = error.message;
    }
    fs.writeFileSync(path.join(evidence, 'provenance.json'), `${JSON.stringify(provenance, null, 2)}\n`, {flag: 'wx'});
    if (cleanupError) throw cleanupError;
  }
  process.stdout.write(`${evidence}\n`);
}

try {
  main();
} catch (error) {
  process.stderr.write(`diagnose-origins: ${error.stack || error}\n`);
  process.exitCode = 2;
}
