#!/usr/bin/env node
'use strict';
/* Stage 3 turns no spelling equality into a binding.  A result is strict only
 * when an OCaml declaration, a target-owned CAMLprim source, its Dune source
 * mirror, and a target stub artefact all witness the same primitive symbol. */
const cp = require('child_process');
const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');

function fail(m) { process.stderr.write(`ffi-ocaml-c: ${m}\n`); process.exit(2); }
function shaFile(file) { return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex'); }
function rel(root, file) { return path.relative(root, file).split(path.sep).join('/'); }
function key(t) { return [t.dune_path, t.stanza_line, t.name || '', t.stanza_kind].join(':'); }
function readAttribution(root) {
  const script = path.join(__dirname, '../ffi-build-attribution/attribution.js');
  return JSON.parse(cp.execFileSync(process.execPath, [script, root], {encoding:'utf8', maxBuffer:64 * 1024 * 1024}));
}
function targetArtefacts(root, target) {
  if (!target.name) return [];
  const dir = path.join(root, '_build/default', path.posix.dirname(target.dune_path));
  return [`lib${target.name}_stubs.a`, `dll${target.name}_stubs.so`]
    .map(name => path.join(dir, name)).filter(fs.existsSync);
}
function nmSymbols(file) {
  const r = cp.spawnSync('nm', ['-g', '--defined-only', file], {encoding:'utf8', maxBuffer:16 * 1024 * 1024});
  if (r.error || r.status !== 0) return null;
  return new Set((r.stdout.match(/\b[A-Za-z_][A-Za-z0-9_]*$/gm) || []));
}
function sourceMirror(root, candidate) {
  const source = path.join(root, candidate.path);
  const mirror = path.join(root, '_build/default', candidate.path);
  if (!fs.existsSync(mirror)) return null;
  const source_digest = shaFile(source), mirror_digest = shaFile(mirror);
  return {path: rel(root, mirror), source_digest, mirror_digest, identical: source_digest === mirror_digest};
}
function resolve(root, {readSymbols = nmSymbols} = {}) {
  const attr = readAttribution(root);
  const cRows = attr.records.filter(r => r.candidate.mechanism === 'camlprim');
  const externals = attr.records.filter(r => r.candidate.mechanism === 'ocaml_external');
  const records = externals.map(external => {
    const witnesses = [];
    for (const target of external.targets) {
      const targetKey = key(target);
      const definitions = cRows.filter(c => c.candidate.symbol === external.candidate.symbol && c.targets.some(t =>
        t.ownership === 'foreign_stub_source' && key(t) === targetKey));
      for (const definition of definitions) {
        const mirror = sourceMirror(root, definition.candidate);
        if (!mirror || !mirror.identical) continue;
        for (const artefact of targetArtefacts(root, target)) {
          const symbols = readSymbols(artefact);
          if (symbols && symbols.has(external.candidate.symbol)) witnesses.push({
            target: {dune_path: target.dune_path, stanza_line: target.stanza_line, name: target.name},
            definition: {path: definition.candidate.path, line: definition.candidate.line, symbol: definition.candidate.symbol},
            source_mirror: mirror,
            artefact: {path: rel(root, artefact), symbol: external.candidate.symbol},
          });
        }
      }
    }
    const unique = new Map();
    for (const witness of witnesses) unique.set([witness.target.dune_path, witness.target.stanza_line, witness.definition.path, witness.definition.line].join(':'), witness);
    const eligible = [...unique.values()];
    let availability = 'MAY_TOP', reason;
    if (eligible.length === 1) availability = 'RESOLVED_STRICT';
    else if (eligible.length > 1) reason = 'ambiguous_strict_witnesses';
    else if (!external.targets.length) reason = 'no_build_target';
    else reason = 'no_source_build_symbol_witness';
    return {external: external.candidate, availability, top_reason: reason || null, witnesses: eligible};
  });
  const summary = {externals: records.length, resolved_strict: records.filter(r => r.availability === 'RESOLVED_STRICT').length,
    may_top: records.filter(r => r.availability === 'MAY_TOP').length};
  return {schema_version: 1, analysis: 'ffi_ocaml_c_resolution', root: path.resolve(root),
    scope: 'strict OCaml runtime primitive binding only; no ABI signature, loaded-image, call-graph edge, or MUST claim',
    attribution_record_digest: attr.record_digest, summary, records};
}
function selfTest() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'arch-index-ffi-strict-'));
  try {
    fs.mkdirSync(path.join(root, 'lib'), {recursive:true});
    fs.mkdirSync(path.join(root, '_build/default/lib'), {recursive:true});
    fs.writeFileSync(path.join(root, 'lib/dune'), '(library (name demo) (foreign_stubs (language c) (names stub)))\n');
    fs.writeFileSync(path.join(root, 'lib/api.ml'), 'external run : unit -> unit = "c_run"\nexternal miss : unit -> unit = "c_miss"\n');
    fs.writeFileSync(path.join(root, 'lib/stub.c'), 'CAMLprim value c_run(value x) { return x; }\nCAMLprim value c_miss(value x) { return x; }\n');
    fs.writeFileSync(path.join(root, 'lib/extra.c'), 'CAMLprim value c_run(value x) { return x; }\n');
    fs.copyFileSync(path.join(root, 'lib/stub.c'), path.join(root, '_build/default/lib/stub.c'));
    const archive = path.join(root, '_build/default/lib/libdemo_stubs.a'); fs.writeFileSync(archive, 'fixture');
    const result = resolve(root, {readSymbols: file => file === archive ? new Set(['c_run']) : new Set()});
    const run = result.records.find(r => r.external.symbol === 'c_run');
    const miss = result.records.find(r => r.external.symbol === 'c_miss');
    if (run.availability !== 'RESOLVED_STRICT' || run.witnesses.length !== 1 || run.witnesses[0].definition.path !== 'lib/stub.c' || miss.availability !== 'MAY_TOP') throw new Error(JSON.stringify(result));
    fs.writeFileSync(path.join(root, '_build/default/lib/stub.c'), 'stale');
    const stale = resolve(root, {readSymbols: () => new Set(['c_run'])}).records.find(r => r.external.symbol === 'c_run');
    if (stale.availability !== 'MAY_TOP') throw new Error('stale mirror accepted');
    fs.copyFileSync(path.join(root, 'lib/stub.c'), path.join(root, '_build/default/lib/stub.c'));
    fs.writeFileSync(path.join(root, 'lib/dune'), '(library (name demo) (foreign_stubs (language c) (names stub extra)))\n');
    fs.copyFileSync(path.join(root, 'lib/extra.c'), path.join(root, '_build/default/lib/extra.c'));
    const ambiguous = resolve(root, {readSymbols: () => new Set(['c_run'])}).records.find(r => r.external.symbol === 'c_run');
    if (ambiguous.availability !== 'MAY_TOP' || ambiguous.top_reason !== 'ambiguous_strict_witnesses') throw new Error('ambiguous definitions accepted');
    process.stdout.write('CHECK3_PASS: exact target source, mirror, and artefact symbol are all required\n');
  } finally { fs.rmSync(root, {recursive:true, force:true}); }
}
const args = process.argv.slice(2);
if (args.length === 1 && args[0] === '--self-test') selfTest();
else if (args.length === 1 && !args[0].startsWith('-')) {
  const root = path.resolve(args[0]); if (!fs.existsSync(root) || !fs.statSync(root).isDirectory()) fail(`root is not a readable directory: ${root}`);
  const output = resolve(root); output.record_digest = crypto.createHash('sha256').update(JSON.stringify(output.records)).digest('hex');
  process.stdout.write(JSON.stringify(output, null, 2) + '\n');
} else fail('usage: resolution.js <corpus-root> | --self-test');
