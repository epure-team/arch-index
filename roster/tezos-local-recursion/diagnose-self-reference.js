#!/usr/bin/env node
'use strict';

const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const cp = require('node:child_process');

const root = path.resolve(__dirname, '../..');
const base = '05e4a8a7ba2d64ff08a15e268005f800e06ea4d7';
const selected = [
  'lib/arch_index/arch_index_cmt.ml',
  'tezt/tests/main.ml',
  'tezt/tests/local_recursion_targets.ml',
];

function run(exe, args, options = {}) {
  const result = cp.spawnSync(exe, args, {
    cwd: options.cwd || root,
    env: options.env || process.env,
    encoding: 'utf8',
    maxBuffer: 64 * 1024 * 1024,
    input: options.input,
  });
  if (result.error || result.signal || result.status !== 0) {
    throw new Error(`${exe} ${args.join(' ')} failed (${result.status}): ${result.error || result.signal || result.stderr}`);
  }
  return result.stdout.trim();
}

const hashBuffer = data => crypto.createHash('sha256').update(data).digest('hex');
const hashFile = file => hashBuffer(fs.readFileSync(file));
const existsHash = file => fs.existsSync(file) ? hashFile(file) : null;

function rootState() {
  const index = path.resolve(root, run('git', ['rev-parse', '--git-path', 'index']));
  return {
    head: run('git', ['rev-parse', 'HEAD']),
    status: run('git', ['status', '--porcelain=v1', '-uall']),
    index,
    index_sha256: existsHash(index),
    selected_sha256: Object.fromEntries(selected.map(p => [p, hashFile(path.join(root, p))])),
  };
}

function assertRootUnchanged(before) {
  const after = rootState();
  assert.deepEqual(after, before, 'root HEAD/index/status or selected source changed');
  return after;
}

function main() {
  assert.equal(run('git', ['rev-parse', '--show-toplevel']), root);
  run('git', ['cat-file', '-e', `${base}^{commit}`]);
  for (const rel of selected) {
    const absolute = path.join(root, rel);
    assert.equal(fs.existsSync(absolute), true, `missing selected path: ${rel}`);
  }

  const before = rootState();
  const opamSwitch = run('opam', ['switch', 'show', '--safe']);
  assert.notEqual(opamSwitch, '', 'no active root opam switch');

  const evidenceRoot = path.join(root, 'improvement/2026-09-14-tezos-resolution');
  const evidenceProbe = path.join(evidenceRoot, '.diagnose-self-reference-ignore-probe');
  run('git', ['check-ignore', '-q', '--', evidenceProbe]);
  fs.mkdirSync(evidenceRoot, {recursive: true});
  const evidence = fs.mkdtempSync(path.join(evidenceRoot, 'attempt4-self-reference-'));
  const rawLog = path.join(evidence, 'recalibrate-explain.log');
  const provenanceFile = path.join(evidence, 'provenance.json');

  const indexOwner = fs.mkdtempSync(path.join(os.tmpdir(), 'arch-index-self-reference-index-'));
  const temporaryIndex = path.join(indexOwner, 'index');
  const worktreeOwner = fs.mkdtempSync(path.join(os.tmpdir(), 'arch-index-self-reference-worktree-'));
  const worktree = path.join(worktreeOwner, 'candidate');
  const indexEnv = {...process.env, GIT_INDEX_FILE: temporaryIndex};
  let candidateTree = null;
  let candidateCommit = null;
  let recalibrateExit = null;
  let cleanupError = null;

  try {
    run('git', ['read-tree', 'HEAD'], {env: indexEnv});
    run('git', ['add', '--', ...selected], {env: indexEnv});
    candidateTree = run('git', ['write-tree'], {env: indexEnv});
    candidateCommit = run(
      'git',
      ['commit-tree', candidateTree, '-p', before.head],
      {env: indexEnv, input: 'ephemeral local-recursion self-reference diagnosis\n'},
    );

    for (const rel of selected) {
      const snapshot = cp.spawnSync('git', ['show', `${candidateCommit}:${rel}`], {
        cwd: root,
        encoding: null,
        maxBuffer: 64 * 1024 * 1024,
      });
      if (snapshot.error || snapshot.signal || snapshot.status !== 0) {
        throw new Error(`cannot read candidate snapshot path ${rel}`);
      }
      assert.equal(hashBuffer(snapshot.stdout), before.selected_sha256[rel], `snapshot mismatch: ${rel}`);
    }

    run('git', ['worktree', 'add', '--detach', worktree, candidateCommit]);
    const logFd = fs.openSync(rawLog, 'wx');
    try {
      const result = cp.spawnSync(
        'opam',
        ['exec', '--switch', opamSwitch, '--', 'bash', 'scripts/recalibrate.sh', '--explain', '--base', base],
        {cwd: worktree, env: process.env, stdio: ['ignore', logFd, logFd]},
      );
      if (result.error || result.signal) {
        throw new Error(`recalibrate execution failed: ${result.error || result.signal}`);
      }
      recalibrateExit = result.status;
    } finally {
      fs.closeSync(logFd);
    }
  } finally {
    try {
      if (fs.existsSync(worktree)) {
        run('git', ['worktree', 'remove', '--force', worktree]);
      }
      fs.rmSync(worktreeOwner, {recursive: true, force: true});
      fs.rmSync(indexOwner, {recursive: true, force: true});
      assert.equal(run('opam', ['switch', 'show', '--safe']), opamSwitch, 'root opam switch changed');
      assertRootUnchanged(before);
    } catch (error) {
      cleanupError = error;
    }
    const provenance = {
      version: 1,
      command: `scripts/recalibrate.sh --explain --base ${base}`,
      base,
      root_head: before.head,
      root_status: before.status.split(/\r?\n/).filter(Boolean),
      root_index_sha256: before.index_sha256,
      opam_switch: opamSwitch,
      selected_sha256: before.selected_sha256,
      candidate_tree: candidateTree,
      candidate_commit: candidateCommit,
      recalibrate_exit: recalibrateExit,
      raw_log: path.basename(rawLog),
      cleanup_verified: cleanupError === null,
      cleanup_error: cleanupError ? cleanupError.message : null,
    };
    fs.writeFileSync(provenanceFile, `${JSON.stringify(provenance, null, 2)}\n`, {flag: 'wx'});
    if (cleanupError) throw cleanupError;
  }

  if (recalibrateExit !== 0) {
    throw new Error(`recalibrate --explain exited ${recalibrateExit}; evidence retained at ${evidence}`);
  }
  process.stdout.write(`${evidence}\n`);
}

try {
  main();
} catch (error) {
  process.stderr.write(`diagnose-self-reference: ${error.stack || error}\n`);
  process.exitCode = 2;
}
