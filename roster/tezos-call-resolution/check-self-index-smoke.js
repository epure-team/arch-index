#!/usr/bin/env node
'use strict';

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const cp = require('node:child_process');

const root = path.resolve(__dirname, '../..');
const producer = path.join(root,
  '_build/default/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe');
const corpus = path.join(root, '_build/default/lib/arch_index');
const schema = path.join(root, 'architecture-schema.sql');
const fixture = path.join(root, 'test/fixtures/self-index-stats.txt');
const query = "SELECT 'modules: ' || count(*) FROM modules; " +
  "SELECT 'functions: ' || count(*) FROM functions; " +
  "SELECT 'calls: ' || count(*) FROM calls;";

let scratch;
try {
  for (const required of [producer, corpus, schema, fixture]) {
    if (!fs.existsSync(required)) throw new Error(`required input missing: ${required}`);
  }
  scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'arch-index-self-smoke-'));
  const db = path.join(scratch, 'self.db');
  const producerArgs = [producer, `--build-dir=${corpus}`, `--db-path=${db}`,
    `--schema-path=${schema}`];
  const localSwitch = fs.existsSync(path.join(root, '_opam'));
  const produced = cp.spawnSync(localSwitch ? 'opam' : producerArgs[0],
    localSwitch ? ['exec', `--switch=${root}`, '--', ...producerArgs] : producerArgs.slice(1),
    {cwd: root, encoding: 'utf8', timeout: 120000, maxBuffer: 16 * 1024 * 1024});
  if (produced.error) throw produced.error;
  if (produced.status !== 0) {
    throw new Error(`producer exited ${produced.status}:\n${produced.stdout || ''}${produced.stderr || ''}`);
  }

  const measured = cp.spawnSync('sqlite3', [db, query],
    {cwd: root, encoding: null, timeout: 120000, maxBuffer: 16 * 1024 * 1024});
  if (measured.error) throw measured.error;
  if (measured.status !== 0) {
    throw new Error(`sqlite3 exited ${measured.status}:\n${(measured.stderr || Buffer.alloc(0)).toString()}`);
  }
  const expected = fs.readFileSync(fixture);
  if (!expected.equals(measured.stdout)) {
    process.stderr.write('ASSERTION: self-index golden mismatch\n');
    process.stderr.write(`expected:\n${expected.toString()}actual:\n${measured.stdout.toString()}`);
    process.exitCode = 1;
  } else {
    process.stdout.write(`PASS self-index smoke\n${measured.stdout.toString()}`);
  }
} catch (error) {
  process.stderr.write(`SETUP: ${error.message}\n`);
  process.exitCode = 2;
} finally {
  if (scratch) {
    try {
      fs.rmSync(scratch, {recursive: true, force: true});
    } catch (error) {
      process.stderr.write(`SETUP: temporary cleanup failed: ${error.message}\n`);
      process.exitCode = 2;
    }
  }
}
