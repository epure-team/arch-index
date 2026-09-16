#!/usr/bin/env node
'use strict';

// Fresh 2x2 attribution for self-index ratchets. This never changes a pin.
const assert = require('node:assert/strict');
const cp = require('node:child_process');
const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const root = path.resolve(__dirname, '../..');
const manifestFile = path.join(root, 'briefs/ocaml-functor-targets-manifest.txt');
const output = path.join(root,
  'improvement/2026-09-16-ocaml-functor-targets/self-calibration');
const sha256 = value => crypto.createHash('sha256').update(value).digest('hex');

function run(command, args, cwd = root) {
  const result = cp.spawnSync(command, args, {
    cwd, encoding: 'utf8', timeout: 300000, maxBuffer: 64 * 1024 * 1024,
  });
  if (result.error || result.signal || result.status !== 0)
    throw new Error(`${command} ${args.join(' ')}: ${result.error || result.signal || result.status}\n${result.stdout || ''}\n${result.stderr || ''}`);
  return result.stdout;
}

function query(db, sql) {
  return JSON.parse(run('sqlite3', ['-readonly', '-json', db, sql]) || '[]');
}

const manifest = fs.readFileSync(manifestFile, 'utf8').split('\n');
const excluded = new Set(manifest.filter(line => line.startsWith('dirty=')).map(line => line.slice(6)));
const scope = manifest.slice(manifest.indexOf('---') + 1).filter(Boolean);
const inScope = file => !excluded.has(file) && scope.some(entry =>
  entry.endsWith('/') ? file.startsWith(entry) : file === entry);
const changed = [...new Set([
  ...run('git', ['diff', '--name-only', 'HEAD']).trim().split('\n'),
  ...run('git', ['ls-files', '--others', '--exclude-standard']).trim().split('\n'),
])].filter(Boolean).filter(inScope).sort();
for (const file of changed)
  if (path.isAbsolute(file) || file.split('/').includes('..')) throw new Error(`unsafe scoped path: ${file}`);
const inventory = changed.map(file => ({file, sha256: sha256(fs.readFileSync(path.join(root, file)))}));
const statusBefore = run('git', ['status', '--porcelain=v1', '--untracked-files=all']);
const base = run('git', ['rev-parse', 'HEAD']).trim();
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'arch-functor-target-calibration-'));
const trees = [path.join(temporary, 'base'), path.join(temporary, 'candidate')];
const made = [];
const evidence = {base, snapshot: inventory, cells: {}, verdict: 'RUNNING'};

try {
  for (const tree of trees) {
    run('git', ['worktree', 'add', '--detach', tree, base]);
    made.push(tree);
  }
  for (const file of changed) {
    const destination = path.join(trees[1], file);
    fs.mkdirSync(path.dirname(destination), {recursive: true});
    fs.copyFileSync(path.join(root, file), destination);
  }
  for (const tree of trees)
    run('opam', ['exec', `--switch=${root}`, '--', 'dune', 'build', '--root', '.'], tree);
  for (const [label, engine, corpus] of [['A', 0, 0], ['B', 1, 0], ['C', 0, 1], ['D', 1, 1]]) {
    const db = path.join(temporary, `${label}.db`);
    const producer = path.join(trees[engine],
      '_build/default/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe');
    run(producer, ['--build-dir', path.join(trees[corpus], '_build/default'),
      '--db-path', db, '--schema-path', path.join(trees[engine], 'architecture-schema.sql')],
      trees[corpus]);
    const totals = query(db, `SELECT (SELECT count(*) FROM modules) modules,
      (SELECT count(*) FROM functions) functions,(SELECT count(*) FROM calls) calls,
      (SELECT count(*) FROM exn_origins) origins,
      (SELECT count(*) FROM calls WHERE kind='MUST' AND callee_id IS NULL
        AND callee_name NOT LIKE 'Stdlib.%') must_null`)[0];
    const external = query(db, `SELECT m.path,f.name,c.callee_name,count(*) n
      FROM calls c JOIN functions f ON f.id=c.caller_id JOIN modules m ON m.id=f.module_id
      WHERE c.kind='MUST' AND c.callee_id IS NULL AND c.callee_name NOT LIKE 'Stdlib.%'
      GROUP BY m.path,f.name,c.callee_name ORDER BY m.path,f.name,c.callee_name`);
    evidence.cells[label] = {totals, external};
  }
  assert.deepEqual(evidence.cells.A, evidence.cells.B, 'engine changed the base source corpus');
  assert.deepEqual(evidence.cells.C, evidence.cells.D, 'engine changed the candidate source corpus');
  for (const entry of inventory)
    assert.equal(sha256(fs.readFileSync(path.join(root, entry.file))), entry.sha256,
      `source changed during calibration: ${entry.file}`);
  assert.equal(run('git', ['status', '--porcelain=v1', '--untracked-files=all']), statusBefore,
    'active checkout changed during calibration');
  evidence.verdict = 'SOURCE_ONLY';
  fs.mkdirSync(output, {recursive: true});
  fs.writeFileSync(path.join(output, 'evidence.json'), `${JSON.stringify(evidence, null, 2)}\n`);
  process.stdout.write(`${JSON.stringify({verdict: evidence.verdict,
    cells: Object.fromEntries(Object.entries(evidence.cells).map(([key, value]) => [key, value.totals]))})}\n`);
} finally {
  for (const tree of made.reverse()) run('git', ['worktree', 'remove', '--force', tree]);
  assert.equal(path.dirname(temporary), os.tmpdir());
  assert(path.basename(temporary).startsWith('arch-functor-target-calibration-'));
  fs.rmSync(temporary, {recursive: true, force: true});
  process.stdout.write(`removed owned worktrees and build artifacts: ${temporary}\n`);
}
