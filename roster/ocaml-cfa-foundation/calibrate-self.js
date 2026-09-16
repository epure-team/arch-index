'use strict';

// Stage2 self-index attribution.  This deliberately is not a variant of the
// Stage1 recalibrator: Stage2 changes the producer, so A=B and C=D are data to
// report, never preconditions for accepting a measurement.
const assert = require('node:assert/strict');
const child = require('node:child_process');
const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {DatabaseSync} = require('node:sqlite');

const ROOT = path.resolve(__dirname, '../..');
const BASE = 'c397efd1b2248564c05c74fdab795213dea593db';
const MANIFEST = path.join(ROOT, 'briefs/ocaml-cfa-foundation-manifest.txt');
const OUTPUT_PARENT = path.join(ROOT, 'improvement/2026-09-16-cfa');
const MAX_BUFFER = 64 * 1024 * 1024;
const COMMAND_TIMEOUT = 180000;
const BUILD_TIMEOUT = 600000;

class SetupError extends Error {}

const sha256 = value => crypto.createHash('sha256').update(value).digest('hex');
const fileHash = file => sha256(fs.readFileSync(file));
const posix = value => value.split(path.sep).join('/');

function parseOverlayManifest(text) {
  const lines = text.split(/\r?\n/);
  const separator = lines.indexOf('---');
  if (separator < 0) throw new SetupError('manifest lacks separator');
  const header = lines.slice(0, separator);
  const base = header.find(line => line.startsWith('base='))?.slice(5);
  if (!/^[0-9a-f]{40}$/.test(base || '')) throw new SetupError('manifest lacks exact base');
  const dirty = new Set(header.filter(line => line.startsWith('dirty=')).map(line => line.slice(6)));
  const entries = lines.slice(separator + 1).filter(Boolean);
  if (!entries.length) throw new SetupError('manifest has no owned entries');
  for (const entry of [...dirty, ...entries]) {
    if (!entry || path.isAbsolute(entry) || entry.split('/').includes('..'))
      throw new SetupError(`unsafe manifest path: ${entry}`);
  }
  return {base, dirty, entries};
}

function isOwned(manifest, relative) {
  return manifest.entries.some(entry => entry.endsWith('/')
    ? relative.startsWith(entry)
    : relative === entry);
}

function selectOverlayPaths(manifest, changed) {
  return [...new Set(changed)]
    .filter(relative => isOwned(manifest, relative) && !manifest.dirty.has(relative))
    .sort();
}

function subtractMultiset(before, after) {
  const count = values => {
    const result = new Map();
    for (const value of values) result.set(value, (result.get(value) || 0) + 1);
    return result;
  };
  const a = count(before), b = count(after), removed = [], added = [];
  for (const value of [...a.keys()].sort()) {
    const n = a.get(value) - (b.get(value) || 0);
    if (n > 0) removed.push({value, count: n});
  }
  for (const value of [...b.keys()].sort()) {
    const n = b.get(value) - (a.get(value) || 0);
    if (n > 0) added.push({value, count: n});
  }
  return {removed, added};
}

function removeOwned(target, parent, prefix) {
  const resolvedParent = fs.realpathSync(parent);
  const resolvedTarget = path.resolve(target);
  if (path.dirname(resolvedTarget) !== resolvedParent || !path.basename(resolvedTarget).startsWith(prefix))
    throw new SetupError(`refusing to remove unowned path: ${target}`);
  fs.rmSync(resolvedTarget, {recursive: true, force: true});
}

function withOwnedTemp(prefix, action) {
  const owned = fs.mkdtempSync(path.join(os.tmpdir(), prefix));
  try { return action(owned); }
  finally { removeOwned(owned, os.tmpdir(), prefix); }
}

function run(command, args, options = {}) {
  const result = child.spawnSync(command, args, {
    cwd: options.cwd || ROOT,
    encoding: 'utf8',
    input: options.input,
    maxBuffer: MAX_BUFFER,
    timeout: options.timeout || COMMAND_TIMEOUT,
  });
  const record = {command, args, cwd: options.cwd || ROOT, status: result.status,
    signal: result.signal, stdout: result.stdout || '', stderr: result.stderr || ''};
  if (result.error || result.signal || ![...(options.ok || [0])].includes(result.status)) {
    const detail = result.error?.message || result.signal || result.status;
    throw new SetupError(`${command} ${args.join(' ')} failed: ${detail}\n${record.stdout}\n${record.stderr}`);
  }
  return record;
}

function changedPaths() {
  // S1 overlays every owned difference from the pinned S0 commit, not merely
  // the working-tree difference from HEAD.  Foundation code may already be a
  // clean commit when this diagnostic is run.
  const tracked = run('git', ['diff', '--name-status', '-z', BASE]).stdout.split('\0').filter(Boolean);
  const changed = [];
  for (let i = 0; i < tracked.length;) {
    const status = tracked[i++];
    if (!status) continue;
    if (status.startsWith('R') || status.startsWith('C')) { changed.push(tracked[i++], tracked[i++]); }
    else changed.push(tracked[i++]);
  }
  const untracked = run('git', ['ls-files', '--others', '--exclude-standard', '-z']).stdout.split('\0').filter(Boolean);
  return [...new Set([...changed, ...untracked])].sort();
}

function writeRecord(output, name, record) {
  fs.writeFileSync(path.join(output, name), `${JSON.stringify(record, null, 2)}\n`);
}

function archiveBase(destination, base, log) {
  // A Git archive is binary; routing it through run()'s UTF-8 command log
  // would corrupt non-text tar members before tar receives them.
  const archive = child.spawnSync('git', ['archive', '--format=tar', base],
    {cwd: ROOT, maxBuffer: MAX_BUFFER, timeout: COMMAND_TIMEOUT});
  if (archive.error || archive.signal || archive.status !== 0)
    throw new SetupError(`git archive failed: ${archive.error?.message || archive.signal || archive.status}`);
  log.push({command: 'git', args: ['archive', '--format=tar', base], cwd: ROOT,
    status: archive.status, signal: archive.signal, stdout_bytes: archive.stdout.length,
    stderr: archive.stderr.toString('utf8') || '', label: 'archive-s0'});
  const extract = child.spawnSync('tar', ['-x', '-C', destination],
    {cwd: ROOT, input: archive.stdout, maxBuffer: MAX_BUFFER, timeout: COMMAND_TIMEOUT});
  if (extract.error || extract.signal || extract.status !== 0)
    throw new SetupError(`tar extraction failed: ${extract.error?.message || extract.signal || extract.status}`);
  log.push({command: 'tar', args: ['-x', '-C', destination], cwd: ROOT,
    status: extract.status, signal: extract.signal, stdout: extract.stdout.toString('utf8') || '',
    stderr: extract.stderr.toString('utf8') || '', label: 'extract-s0'});
}

function overlayCandidate(destination, manifest, changed, log) {
  const unexpected = changed.filter(relative => !manifest.dirty.has(relative) && !isOwned(manifest, relative));
  if (unexpected.length) throw new SetupError(`changed path outside active manifest: ${unexpected.join(', ')}`);
  const selected = selectOverlayPaths(manifest, changed);
  for (const relative of selected) {
    const source = path.join(ROOT, relative), target = path.join(destination, relative);
    if (!source.startsWith(`${ROOT}${path.sep}`) || !target.startsWith(`${destination}${path.sep}`))
      throw new SetupError(`unsafe overlay path: ${relative}`);
    if (fs.existsSync(source)) {
      fs.mkdirSync(path.dirname(target), {recursive: true});
      fs.copyFileSync(source, target);
    } else if (fs.existsSync(target)) fs.rmSync(target, {force: true});
    else throw new SetupError(`overlay deletion missing from archive: ${relative}`);
  }
  log.push({label: 'overlay-s1', selected});
  return selected;
}

function walk(root, suffixes) {
  const out = [];
  const visit = current => {
    for (const entry of fs.readdirSync(current, {withFileTypes: true})) {
      const next = path.join(current, entry.name);
      if (entry.isSymbolicLink()) {
        // Dune's public_cmi contains ordinary compiler-interface links, which
        // are not selected CMT inputs. Never follow a directory/input link.
        if (suffixes.some(suffix => entry.name.endsWith(suffix)) || fs.statSync(next).isDirectory())
          throw new SetupError(`symlink in pinned input: ${next}`);
        continue;
      }
      if (entry.isDirectory()) visit(next);
      else if (suffixes.some(suffix => entry.name.endsWith(suffix))) out.push(next);
    }
  };
  visit(root);
  return out.sort();
}

function inventory(root, suffixes) {
  return walk(root, suffixes).map(file => ({path: posix(path.relative(root, file)), sha256: fileHash(file)}));
}

function sourcePin(tree) {
  const source = path.join(tree, 'lib/arch_index');
  const cmts = path.join(tree, '_build/default/lib/arch_index');
  const tools = [
    'bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe',
    'bin/arch_rules/arch_rules.exe',
    'bin/arch_report/arch_report.exe',
    'architecture-schema.sql',
  ];
  for (const relative of tools) if (!fs.existsSync(path.join(tree, '_build/default', relative)) && relative !== 'architecture-schema.sql')
    throw new SetupError(`missing built tool: ${relative}`);
  if (!fs.existsSync(source) || !fs.existsSync(cmts)) throw new SetupError('missing self-index source or CMT corpus');
  return {
    sources: inventory(source, ['.ml', '.mli']),
    cmts: inventory(cmts, ['.cmt', '.cmti']),
    tools: Object.fromEntries(tools.map(relative => {
      const file = relative === 'architecture-schema.sql' ? path.join(tree, relative) : path.join(tree, '_build/default', relative);
      return [relative, fileHash(file)];
    })),
  };
}

function inventoryDigest(inventory) { return sha256(JSON.stringify(inventory)); }

function ignoredStatus(status, outputRelative) {
  return status.split(/\r?\n/).filter(line => {
    const candidate = line.slice(3);
    return candidate !== outputRelative && !candidate.startsWith(`${outputRelative}/`);
  }).join('\n');
}

function mutableRootSnapshot(outputRelative) {
  const sources = inventory(path.join(ROOT, 'lib/arch_index'), ['.ml', '.mli']);
  return {
    head: run('git', ['rev-parse', 'HEAD']).stdout.trim(),
    status: ignoredStatus(run('git', ['status', '--porcelain=v1', '--untracked-files=all']).stdout, outputRelative),
    manifest_sha256: fileHash(MANIFEST),
    sources,
    sources_sha256: inventoryDigest(sources),
  };
}

function build(tree, label, log) {
  const compiler = run('opam', ['exec', `--switch=${ROOT}`, '--', 'ocamlc', '-version'], {cwd: tree});
  log.push({...compiler, label: `${label}-ocaml-version`});
  if (compiler.stdout.trim() !== '5.3.0') throw new SetupError(`expected OCaml 5.3.0, got ${compiler.stdout.trim()}`);
  const command = run('opam', ['exec', `--switch=${ROOT}`, '--', 'dune', 'build', '--root', '.'],
    {cwd: tree, timeout: BUILD_TIMEOUT});
  log.push({...command, label: `${label}-build`});
}

const CALL_SQL = `SELECT cm.path caller_path,cf.name caller,c.call_site,
 tm.path target_path,tf.name target,c.callee_name,c.kind,c.edge_form,c.top_reason,c.top_anchor
 FROM calls c JOIN functions cf ON cf.id=c.caller_id JOIN modules cm ON cm.id=cf.module_id
 LEFT JOIN functions tf ON tf.id=c.callee_id LEFT JOIN modules tm ON tm.id=tf.module_id
 ORDER BY caller_path,caller,call_site,target_path,target,callee_name,kind,edge_form,top_reason,top_anchor`;
const ORIGIN_SQL = `SELECT m.path module_path,f.name function_name,o.form,o.exn_path,o.escapes,o.line,o.col,o.channel,
 o.operand_primitive,o.operand_slot,o.operand_category,o.operand_repr,o.operand_integer_kind,o.operand_unavailable_reason
 FROM exn_origins o JOIN functions f ON f.id=o.function_id JOIN modules m ON m.id=f.module_id
 ORDER BY module_path,function_name,form,exn_path,escapes,line,col,channel,operand_primitive,operand_slot,operand_category,operand_repr,operand_integer_kind,operand_unavailable_reason`;

function strings(rows) { return rows.map(row => JSON.stringify(row)).sort(); }

function snapshot(dbPath) {
  const db = new DatabaseSync(dbPath, {readOnly: true});
  try {
    const calls = db.prepare(CALL_SQL).all();
    const origins = db.prepare(ORIGIN_SQL).all();
    const totals = db.prepare(`SELECT
      (SELECT count(*) FROM modules) modules,(SELECT count(*) FROM functions) functions,
      (SELECT count(*) FROM calls) calls,(SELECT count(*) FROM exn_origins) origins`).get();
    const groups = db.prepare('SELECT channel,form,escapes,count(*) count FROM exn_origins GROUP BY channel,form,escapes ORDER BY channel,form,escapes').all();
    const indexedModules = db.prepare('SELECT path FROM modules ORDER BY path').all().map(row => row.path);
    return {totals, calls, call_sha256: sha256(JSON.stringify(strings(calls))),
      origins, origin_sha256: sha256(JSON.stringify(strings(origins))), origin_groups: groups,
      indexed_modules: indexedModules};
  } finally { db.close(); }
}

function produce(engineTree, corpusTree, dbPath, label, log) {
  const executable = path.join(engineTree, '_build/default/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe');
  const schema = path.join(engineTree, 'architecture-schema.sql');
  const corpus = path.join(corpusTree, '_build/default/lib/arch_index');
  const record = run(executable,
    [`--build-dir=${corpus}`, `--db-path=${dbPath}`, `--schema-path=${schema}`],
    {cwd: corpusTree});
  log.push({...record, label: `${label}-index`});
  return snapshot(dbPath);
}

function runOriginTools(engineTree, dbPath, output, label, log) {
  const rules = path.join(engineTree, 'test/fixtures/origin-consumer/self.rules');
  const rulesTool = path.join(engineTree, '_build/default/bin/arch_rules/arch_rules.exe');
  const reportTool = path.join(engineTree, '_build/default/bin/arch_report/arch_report.exe');
  const reportDir = path.join(output, `${label}-origin-report`);
  fs.mkdirSync(reportDir);
  const gate = run(rulesTool, [dbPath, rules, '--format', 'json', '--on-possible', 'fail', '--on-unknown', 'warn', '--on-vacuous', 'fail', '--on-not-computed', 'fail'],
    {cwd: engineTree, ok: [0, 1]});
  log.push({...gate, label: `${label}-origin-rules`});
  const report = run(reportTool, [dbPath, '--out', reportDir, '--rules', rules], {cwd: engineTree});
  log.push({...report, label: `${label}-origin-report`});
  return {gate_exit: gate.status, gate: JSON.parse(gate.stdout), report_dir: path.basename(reportDir)};
}

function parseAllowlist(file) {
  return fs.readFileSync(file, 'utf8').split(/\r?\n/).filter(line => line && !line.startsWith('#')).map(line => {
    const [function_name, coordinate, form, exn_path, multiplicity] = line.split(' | ');
    const match = /^(.*):(\d+)$/.exec(coordinate || '');
    if (!function_name || !match || !form || !exn_path || !multiplicity) throw new SetupError(`malformed allowlist entry: ${line}`);
    return {raw: line, function_name, module_path: match[1], line: Number(match[2]), form, exn_path, multiplicity};
  });
}

function allowlistRelocation(allow, beforeOrigins, afterOrigins) {
  const semantic = entry => origin => origin.module_path === entry.module_path && origin.function_name === entry.function_name
    && origin.form === entry.form && origin.exn_path === entry.exn_path;
  return allow.map(entry => {
    const oldRows = beforeOrigins.filter(semantic(entry));
    const newRows = afterOrigins.filter(semantic(entry));
    return {entry: entry.raw, old_coordinates: oldRows.map(row => [row.line, row.col]),
      new_coordinates: newRows.map(row => [row.line, row.col]),
      descriptor_matches: oldRows.length > 0 && newRows.length > 0,
      coordinate_changed: oldRows.length > 0 && newRows.length > 0
        && JSON.stringify(oldRows.map(row => [row.line, row.col])) !== JSON.stringify(newRows.map(row => [row.line, row.col])),
      additional_matching_origins: Math.max(0, newRows.length - oldRows.length),
      semantic_status: 'not_proven_manual_review_required'};
  });
}

function classifyCells(cells) {
  const delta = (left, right, field) => subtractMultiset(strings(cells[left][field]), strings(cells[right][field]));
  return {
    source_under_e0: {calls: delta('A', 'C', 'calls'), origins: delta('A', 'C', 'origins')},
    engine_on_c0: {calls: delta('A', 'B', 'calls'), origins: delta('A', 'B', 'origins')},
    engine_on_c1: {calls: delta('C', 'D', 'calls'), origins: delta('C', 'D', 'origins')},
    total: {calls: delta('A', 'D', 'calls'), origins: delta('A', 'D', 'origins')},
  };
}

function runCalibration() {
  const manifest = parseOverlayManifest(fs.readFileSync(MANIFEST, 'utf8'));
  if (manifest.base !== BASE) throw new SetupError(`manifest base ${manifest.base} differs from required ${BASE}`);
  const output = path.join(OUTPUT_PARENT, `self-2x2-${process.pid}-${Date.now()}`);
  if (fs.existsSync(output)) throw new SetupError(`output collision: ${output}`);
  const outputRelative = posix(path.relative(ROOT, output));
  const activeBefore = mutableRootSnapshot(outputRelative);
  fs.mkdirSync(output, {recursive: true});
  const logs = [], report = {format: 1, purpose: 'stage2 self-index 2x2 diagnostic; no reference or policy update',
    base: BASE, status: 'running', output: path.relative(ROOT, output), commands: logs,
    active_source: {before: activeBefore, after: null, copied_candidate_matches_active: false}};
  try {
    const changed = changedPaths();
    withOwnedTemp('arch-cfa-self-2x2-', workspace => {
      const s0 = path.join(workspace, 's0'), s1 = path.join(workspace, 's1');
      fs.mkdirSync(s0); fs.mkdirSync(s1);
      archiveBase(s0, BASE, logs); archiveBase(s1, BASE, logs);
      report.overlay = overlayCandidate(s1, manifest, changed, logs);
      build(s0, 's0', logs); build(s1, 's1', logs);
      const pinsBefore = {E0_C0: sourcePin(s0), E1_C1: sourcePin(s1)};
      assert.deepEqual(pinsBefore.E1_C1.sources, activeBefore.sources,
        'candidate archive/overlay source inventory differs from the active source');
      const cells = {};
      for (const [label, engine, corpus] of [['A', s0, s0], ['B', s1, s0], ['C', s0, s1], ['D', s1, s1]]) {
        const db = path.join(workspace, `${label}.db`);
        cells[label] = produce(engine, corpus, db, label, logs);
        cells[label].origin_policy = runOriginTools(engine, db, output, label, logs);
      }
      const pinsAfter = {E0_C0: sourcePin(s0), E1_C1: sourcePin(s1)};
      assert.deepEqual(pinsAfter, pinsBefore, 'pinned source/CMT/tool inputs changed during measurement');
      const activeAfter = mutableRootSnapshot(outputRelative);
      assert.deepEqual(activeAfter, activeBefore, 'active source, manifest, HEAD, or status changed during measurement');
      report.active_source = {before: activeBefore, after: activeAfter, copied_candidate_matches_active: true};
      report.pins = pinsAfter;
      report.cells = cells;
      report.deltas = classifyCells(cells);
      report.allowlist_relocation = allowlistRelocation(
        parseAllowlist(path.join(s0, 'test/fixtures/origin-consumer/self.allow')),
        cells.A.origins, cells.D.origins);
    });
    report.status = 'measured';
  } catch (error) {
    report.status = 'error';
    report.error = error.stack || String(error);
    throw error;
  } finally {
    if (report.active_source.after === null) {
      try { report.active_source.after = mutableRootSnapshot(outputRelative); }
      catch (error) { report.active_source.after_error = error.stack || String(error); }
    }
    writeRecord(output, 'report.json', report);
    writeRecord(output, 'commands.json', logs);
  }
  return output;
}

function cli() {
  if (process.argv.length !== 3 || process.argv[2] !== '--run') throw new SetupError('usage: node calibrate-self.js --run');
  const output = runCalibration();
  process.stdout.write(`PASS self-index 2x2 measured: ${output}\n`);
}

module.exports = {subtractMultiset, parseOverlayManifest, selectOverlayPaths, removeOwned, withOwnedTemp, inventory, runCalibration};
if (require.main === module) {
  try { cli(); }
  catch (error) {
    process.stderr.write(`${error.stack || error}\n`);
    process.exitCode = error instanceof assert.AssertionError ? 1 : 2;
  }
}
