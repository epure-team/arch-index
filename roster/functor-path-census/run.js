#!/usr/bin/env node
'use strict';

const cp = require('node:child_process');
const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const root = path.resolve(__dirname, '../..');
const cap = 64 * 1024 * 1024;
function hash(file) { return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex'); }
function command(name, args, options = {}) {
  const result = cp.spawnSync(name, args, {cwd: root, encoding: 'utf8', maxBuffer: cap,
    timeout: 120000, ...options});
  if (result.error || result.signal || result.status === null) throw new Error(`${name}: ${result.error || result.signal}`);
  if (result.status !== 0) throw new Error(`${name} exited ${result.status}: ${result.stderr}`);
  return result.stdout;
}
function parseManifest(file) {
  const rows = fs.readFileSync(file, 'utf8').split(/\r?\n/).filter(line => line && !line.startsWith('#')).map((line, i) => {
    const columns = line.split('\t');
    if (columns.length !== 3 || columns.some(x => x === '')) throw new Error(`manifest row ${i + 1}: expected three nonempty columns`);
    const [slice, sha256, artifact] = columns;
    if (!/^[0-9a-f]{64}$/.test(sha256)) throw new Error(`manifest row ${i + 1}: invalid sha256`);
    if (!path.isAbsolute(artifact)) throw new Error(`manifest row ${i + 1}: artifact path is not absolute`);
    return {slice, sha256, artifact};
  });
  if (rows.length === 0) throw new Error('manifest has no inputs');
  if (new Set(rows.map(x => x.artifact)).size !== rows.length) throw new Error('manifest has duplicate artifact paths');
  for (const row of rows) {
    if (!fs.statSync(row.artifact).isFile()) throw new Error(`artifact is not a regular file: ${row.artifact}`);
    fs.accessSync(row.artifact, fs.constants.R_OK);
    if (hash(row.artifact) !== row.sha256) throw new Error(`digest mismatch: ${row.artifact}`);
  }
  return rows;
}
function validateArtifact(row, measured) {
  if (!measured || typeof measured.cmt_modname !== 'string' || !Array.isArray(measured.imports) || !Array.isArray(measured.applications)) throw new Error(`invalid probe JSON: ${row.artifact}`);
  const ordinals = measured.applications.map(x => x.ordinal);
  if (new Set(ordinals).size !== ordinals.length || ordinals.some((x, i) => x !== i + 1)) throw new Error(`non-contiguous ordinals: ${row.artifact}`);
  for (const app of measured.applications) {
    if (typeof app.status !== 'string' || !Object.hasOwn(app, 'reason')) throw new Error(`invalid application: ${row.artifact}`);
    if (app.reason === 'unsupported_path' && (!app.terminal_path || !app.root_category || !Number.isInteger(app.path_identity_class))) throw new Error(`incomplete unsupported row: ${row.artifact}`);
  }
}
function buildReport(manifest) {
  if (!fs.statSync(manifest).isFile()) throw new Error(`manifest is not a regular file: ${manifest}`);
  const beforeManifest = hash(manifest);
  const rows = parseManifest(manifest);
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'functor-path-census-'));
  try {
    const source = path.join(root, 'roster/functor-path-census/probe.ml');
    const copiedSource = path.join(dir, 'probe.ml');
    fs.copyFileSync(source, copiedSource);
    const executable = path.join(dir, 'probe.exe');
    const staging = path.join(root, '_build/install/default/lib');
    const env = {...process.env, OCAMLPATH: process.env.OCAMLPATH ? `${staging}${path.delimiter}${process.env.OCAMLPATH}` : staging};
    command('ocamlfind', ['ocamlopt', '-package', 'arch-index', '-linkpkg', copiedSource, '-o', executable], {cwd: dir, env});
    const artifacts = rows.map(row => {
      const measured = JSON.parse(command(executable, [row.artifact], {cwd: dir}));
      validateArtifact(row, measured);
      return {...row, ...measured};
    });
    if (hash(manifest) !== beforeManifest) throw new Error('manifest changed during census');
    for (const row of rows) if (hash(row.artifact) !== row.sha256) throw new Error(`artifact changed during census: ${row.artifact}`);
    const inventory = new Map();
    for (const artifact of artifacts) {
      const list = inventory.get(artifact.cmt_modname) || [];
      list.push(artifact.artifact); inventory.set(artifact.cmt_modname, list);
    }
    for (const artifact of artifacts) for (const application of artifact.applications) {
      if (application.reason === 'unsupported_path') {
        application.selected_unit_candidates = application.root_name === null
          ? [] : [...(inventory.get(application.root_name) || [])];
      }
    }
    const unsupported = artifacts.flatMap(x => x.applications).filter(x => x.reason === 'unsupported_path');
    const displays = new Set(unsupported.map(x => x.terminal_path.display));
    const identities = artifacts.reduce((n, artifact) => n + new Set(artifact.applications.filter(x => x.reason === 'unsupported_path').map(x => x.path_identity_class)).size, 0);
    const archive = command('ocamlfind', ['query', '-predicates', 'native', '-format', '%d/%A', 'arch-index'], {env}).trim();
    if (!archive.startsWith(`${staging}${path.sep}`) || !fs.existsSync(archive)) throw new Error(`arch-index did not resolve from exact staging: ${archive}`);
    return {contract: 'functor-path-census-v1', provenance: {manifest, manifest_sha256: beforeManifest,
      probe_source_sha256: hash(copiedSource), probe_binary_sha256: hash(executable),
      arch_index_archive_sha256: hash(archive),
      ocaml_version: command('ocamlc', ['-config-var', 'version']).trim(),
      limitations: ['fixed_manifest_only','no_source_freshness_claim','unit_name_presence_not_declaration_ownership','artifact_scoped_compiler_identity']},
      totals: {artifacts: artifacts.length, applications: artifacts.reduce((n, x) => n + x.applications.length, 0), unsupported_path: unsupported.length,
        unsupported_display_distinct: displays.size, unsupported_identity_classes: identities},
      unit_inventory: [...inventory].sort(([a], [b]) => a.localeCompare(b)).map(([name, candidates]) => ({name, candidates})), artifacts};
  } finally { fs.rmSync(dir, {recursive: true, force: true}); }
}
function publishReport(output, report) {
  // Same-filesystem hard-link publication is atomic and never replaces a target.
  const dir = fs.mkdtempSync(path.join(path.dirname(output), '.census-publish-'));
  try {
    const pending = path.join(dir, 'report.json');
    fs.writeFileSync(pending, `${JSON.stringify(report, null, 2)}\n`, {flag: 'wx'});
    fs.linkSync(pending, output);
  } finally { fs.rmSync(dir, {recursive: true, force: true}); }
}
function main(argv) {
  let manifest, out;
  for (let i = 0; i < argv.length; i += 2) {
    if (argv[i] === '--manifest') manifest = argv[i + 1]; else if (argv[i] === '--out') out = argv[i + 1]; else throw new Error('usage: run.js --manifest MANIFEST --out OUTPUT');
  }
  if (!manifest || !out) throw new Error('usage: run.js --manifest MANIFEST --out OUTPUT');
  const report = buildReport(path.resolve(manifest));
  const output = path.resolve(out);
  if (fs.existsSync(output)) throw new Error(`refusing to overwrite existing output: ${output}`);
  publishReport(output, report);
}
if (require.main === module) {
  try { main(process.argv.slice(2)); }
  catch (error) { process.stderr.write(`functor-path-census: ${error.message}\n`); process.exit(2); }
}
module.exports = {buildReport, parseManifest, publishReport};
