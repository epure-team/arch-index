#!/usr/bin/env node
'use strict';

/* CHECK-5: exact CI self-smoke plus the attribution boundary for changing its
   frozen references and their duplicated checker constants. This checker never recalibrates or writes a
   reference.  It validates an already-produced pristine 2x2 record only when
   a reference actually differs from e8d072e. */
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const cp = require('node:child_process');
const crypto = require('node:crypto');

const root = path.resolve(__dirname, '../..');
const policyCommit = 'e8d072ec491c05637cacb76e4fe1b99367aa119f';
const policyHashes = {
  'scripts/recalibrate.sh': 'b36b62837f263ff8a4b89d9c29f8a0cad74a580124ada30e34521d8a5fb618c5',
  '.github/workflows/ci.yml': 'a6d331a4a8e6d5d3c29b9e039c15bc6450cc427cbe79b5bd840fc590f91fecc0',
};
const references = [
  'test/fixtures/self-index-stats.txt',
  'test/fixtures/origin-consumer/reference.json',
  'test/fixtures/origin-consumer/self.allow',
  'checks/origin-recurring-consumer.js',
];
const measuredSourcePaths = ['lib', 'bin', 'tezt', 'architecture-schema.sql', 'dune-project', 'dune-workspace'];
// This is declared pre-task dirt in the attempt3 manifest.  It is not
// calibration source and is excluded only after content pinning; every other
// untracked measured-path file remains a refusal.
const preTaskUntracked = {
  file: 'tezt/tests/lsp_doc_comment_lines.ml',
  sha256: '6a9691aa48e7308151f77adcd857ce7cfc6a04918d08d39025e12719e6ea31a7',
};
const evidenceFile = path.join(root, 'improvement/2026-09-14-tezos-resolution/attempt3-pristine-attribution.json');
const producer = path.join(root, '_build/default/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe');
const corpus = path.join(root, '_build/default/lib/arch_index');
const schema = path.join(root, 'architecture-schema.sql');
const selfQuery = "SELECT 'modules: ' || count(*) FROM modules; " +
  "SELECT 'functions: ' || count(*) FROM functions; " +
  "SELECT 'calls: ' || count(*) FROM calls;";

function sha(bytes) { return crypto.createHash('sha256').update(bytes).digest('hex'); }
function read(relative) { return fs.readFileSync(path.join(root, relative)); }
function git(args) {
  const result = cp.spawnSync('git', args, {cwd: root, encoding: null});
  if (result.error || result.status !== 0) throw new Error(`git ${args.join(' ')} failed`);
  return result.stdout;
}
function assertion(message) { const error = new Error(message); error.assertion = true; return error; }
function normalized(value) { return String(value).trim().replace(/\s+/g, ' '); }
function treeHash(commit) { return sha(git(['ls-tree', '-r', '-z', commit, '--', ...measuredSourcePaths])); }
function sourceTreeIsClean(commit) {
  const diff = cp.spawnSync('git', ['diff', '--quiet', commit, '--', ...measuredSourcePaths], {cwd: root});
  if (diff.error) throw new Error('cannot inspect measured source diff');
  if (diff.status !== 0) return false;
  const untracked = git(['ls-files', '--others', '--exclude-standard', '--', ...measuredSourcePaths])
    .toString('utf8').split('\n').filter(Boolean);
  const remaining = untracked.filter((file) => {
    if (file !== preTaskUntracked.file) return true;
    return !fs.existsSync(path.join(root, file)) || sha(read(file)) !== preTaskUntracked.sha256;
  });
  return remaining.length === 0;
}

function policyAndReferenceState() {
  for (const [file, expected] of Object.entries(policyHashes)) {
    if (sha(read(file)) !== expected) throw assertion(`full-guard policy changed: ${file}`);
    if (sha(git(['show', `${policyCommit}:${file}`])) !== expected)
      throw new Error(`policy commit does not contain expected bytes: ${file}`);
  }
  return references.map((file) => {
    const before = sha(git(['show', `${policyCommit}:${file}`]));
    const after = sha(read(file));
    return {file, before, after, changed: before !== after};
  });
}

function parseLog(bytes) {
  let metric = null, baseline = null, head = null, builtBase = false, builtHead = false;
  const cells = {}, sourceOnly = {};
  for (const line of bytes.toString('utf8').split(/\r?\n/)) {
    const baseLine = line.match(/^recalibrate: baseline ([0-9a-f]{40}) = /);
    if (baseLine) { if (baseline) throw assertion('raw log repeats baseline'); baseline = baseLine[1]; }
    const headLine = line.match(/^recalibrate: head\s+= ([0-9a-f]{7,40})$/);
    if (headLine) { if (head) throw assertion('raw log repeats head'); head = headLine[1]; }
    if (line === 'recalibrate: building baseline…') builtBase = true;
    if (line === 'recalibrate: building head…') builtHead = true;
    const heading = line.match(/^── (golden|ceiling) \(/);
    if (heading) {
      metric = heading[1];
      if (cells[metric]) throw assertion(`raw log repeats ${metric} metric`);
      cells[metric] = {}; continue;
    }
    const row = line.match(/^   ([ABCD]) (?:base bin\/base src| NEW bin\/base src|base bin\/ NEW src| NEW bin\/ NEW src)\s+(.*)$/);
    if (metric && row) {
      if (cells[metric][row[1]]) throw assertion(`raw log repeats ${metric} cell ${row[1]}`);
      cells[metric][row[1]] = normalized(row[2]);
    }
    if (metric && line === '   → attributable to source change only (B = A).') {
      if (sourceOnly[metric]) throw assertion(`raw log repeats ${metric} SOURCE_ONLY verdict`);
      sourceOnly[metric] = true;
    }
  }
  return {baseline, head, builtBase, builtHead, cells, sourceOnly};
}

function validCell(metric, value) {
  const number = '(?:0|[1-9][0-9]*)';
  const match = metric === 'golden'
    ? value.match(new RegExp(`^modules: (${number}) functions: (${number}) calls: (${number})$`))
    : value.match(new RegExp(`^(${number})$`));
  return Boolean(match) && match.slice(1).every((n) => Number(n) > 0);
}

function successfulSourceOnlyDiagnostic(parsed, raw, candidateCommit) {
  return parsed.baseline === policyCommit && typeof parsed.head === 'string' &&
    parsed.head === candidateCommit.slice(0, parsed.head.length) && parsed.builtBase && parsed.builtHead &&
    parsed.sourceOnly.golden === true && parsed.sourceOnly.ceiling === true &&
    !/(?:REFUSED|refusal-class|BUILD FAILED|DEGRADED)/i.test(raw.toString('utf8'));
}

function validateEvidence(state) {
  if (!fs.existsSync(evidenceFile)) throw assertion(`reference changed but attribution evidence is missing: ${path.relative(root, evidenceFile)}`);
  let evidence;
  try { evidence = JSON.parse(fs.readFileSync(evidenceFile, 'utf8')); }
  catch (error) { throw new Error(`cannot parse attribution evidence: ${error.message}`); }
  if (evidence.schema_version !== 'tezos-open-bodies-pristine-attribution-v1')
    throw assertion('attribution evidence schema/version refused');
  if (evidence.base_commit !== policyCommit || typeof evidence.candidate_commit !== 'string' || !/^[0-9a-f]{40}$/.test(evidence.candidate_commit))
    throw assertion('attribution commits are malformed');
  if (typeof evidence.candidate_source_tree_sha256 !== 'string' ||
      evidence.candidate_source_tree_sha256 !== treeHash(evidence.candidate_commit) ||
      evidence.candidate_source_tree_sha256 !== treeHash('HEAD') || !sourceTreeIsClean(evidence.candidate_commit))
    throw assertion('current measured product/test source tree differs from calibrated candidate');
  if (evidence.command !== `scripts/recalibrate.sh --explain --base ${policyCommit}`)
    throw assertion('attribution was not run with the exact unchanged-script command');
  if (evidence.script_sha256 !== policyHashes['scripts/recalibrate.sh'] ||
      evidence.ci_policy_sha256 !== policyHashes['.github/workflows/ci.yml'])
    throw assertion('attribution evidence does not bind frozen policy bytes');
  if (typeof evidence.raw_log_path !== 'string' || !evidence.raw_log_path.startsWith('improvement/2026-09-14-tezos-resolution/'))
    throw assertion('attribution raw log path is outside owned evidence');
  const rawPath = path.resolve(root, evidence.raw_log_path);
  if (!rawPath.startsWith(path.join(root, 'improvement/2026-09-14-tezos-resolution/') ))
    throw assertion('attribution raw log path escapes evidence directory');
  const raw = fs.readFileSync(rawPath);
  if (sha(raw) !== evidence.raw_log_sha256) throw assertion('attribution raw log hash mismatch');
  const parsed = parseLog(raw);
  if (!successfulSourceOnlyDiagnostic(parsed, raw, evidence.candidate_commit))
    throw assertion('raw diagnostic does not prove successful unchanged-script base/head builds');
  for (const metric of ['golden', 'ceiling']) {
    const declared = evidence.cells && evidence.cells[metric];
    if (!declared || declared.verdict !== 'SOURCE_ONLY') throw assertion(`declared ${metric} is not SOURCE_ONLY`);
    for (const cell of ['A', 'B', 'C', 'D']) {
      if (typeof declared[cell] !== 'string' || !validCell(metric, normalized(declared[cell])) ||
          parsed.cells[metric]?.[cell] !== normalized(declared[cell]))
        throw assertion(`raw ${metric} cell ${cell} does not match evidence`);
    }
    if (normalized(declared.A) !== normalized(declared.B) || normalized(declared.C) !== normalized(declared.D))
      throw assertion(`declared ${metric} cells are not source-only`);
  }
  if (!evidence.references || Object.keys(evidence.references).length !== references.length)
    throw assertion('attribution does not enumerate exactly the frozen references');
  for (const item of state) {
    const record = evidence.references[item.file];
    if (!record || record.pre_change_sha256 !== item.before || record.current_sha256 !== item.after)
      throw assertion(`reference hashes do not bind ${item.file}`);
  }
}

function selfSmoke() {
  for (const required of [producer, corpus, schema, path.join(root, references[0])]) {
    if (!fs.existsSync(required)) throw new Error(`required self-smoke input missing: ${required}`);
  }
  const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'arch-index-open-body-self-'));
  try {
    const db = path.join(scratch, 'self.db');
    const args = [producer, `--build-dir=${corpus}`, `--db-path=${db}`, `--schema-path=${schema}`];
    const localSwitch = fs.existsSync(path.join(root, '_opam'));
    const run = cp.spawnSync(localSwitch ? 'opam' : args[0],
      localSwitch ? ['exec', `--switch=${root}`, '--', ...args] : args.slice(1),
      {cwd: root, encoding: 'utf8', timeout: 120000, maxBuffer: 16 * 1024 * 1024});
    if (run.error || run.status !== 0) throw new Error(`self producer failed: ${run.error || run.stderr || run.stdout}`);
    const measured = cp.spawnSync('sqlite3', [db, selfQuery], {cwd: root, encoding: null, timeout: 120000});
    if (measured.error || measured.status !== 0) throw new Error(`self sqlite query failed: ${measured.error || (measured.stderr || '').toString()}`);
    if (!read(references[0]).equals(measured.stdout)) throw assertion(
      `self-index golden mismatch\nexpected:\n${read(references[0]).toString()}actual:\n${measured.stdout.toString()}`);
  } finally { fs.rmSync(scratch, {recursive: true, force: true}); }
}

function run() {
  if (process.argv.length !== 2) throw new Error('usage: check-self.js');
  const state = policyAndReferenceState();
  if (state.some((item) => item.changed)) validateEvidence(state);
  selfSmoke();
  console.log('PASS self: exact smoke, frozen full-guard policy, and attribution boundary');
}

if (require.main === module) try {
  run();
} catch (error) {
  process.stderr.write(`${error.assertion ? 'ASSERTION' : 'SETUP'}: ${error.message}\n`);
  process.exitCode = error.assertion ? 1 : 2;
}

module.exports = {parseLog, validCell, normalized, successfulSourceOnlyDiagnostic};
