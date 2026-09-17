#!/usr/bin/env node
'use strict';
/* Stage 2 consumes the Stage-1 inventory but deliberately stops before symbol
 * resolution. A Dune stanza proves build ownership, never ABI linkage. */
const cp = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');

const EXCLUDED = new Set(['.git', '_build', '_opam', '.opam-switch', 'node_modules', 'target', 'vendor', 'vendors', 'worktrees', 'generated', 'gen', 'dist', 'build']);
const ROOT_DEFAULT = '/home/mathias/dev/tezos/tezos';
function fail(m) { process.stderr.write(`ffi-attribution: ${m}\n`); process.exit(2); }
function rel(root, value) { return path.relative(root, value).split(path.sep).join('/'); }
function digest(value) { return crypto.createHash('sha256').update(JSON.stringify(value)).digest('hex'); }
function walkDune(root) {
  const answer = [];
  function visit(dir) {
    for (const entry of fs.readdirSync(dir, {withFileTypes: true})) {
      const full = path.join(dir, entry.name);
      if (entry.isSymbolicLink()) continue;
      if (entry.isDirectory()) { if (!EXCLUDED.has(entry.name)) visit(full); }
      else if (entry.isFile() && entry.name === 'dune') answer.push(full);
    }
  }
  visit(root); return answer.sort();
}
function tokenize(text) {
  const tokens = []; let i = 0;
  while (i < text.length) {
    if (/\s/.test(text[i])) { i++; continue; }
    if (text[i] === ';') { while (i < text.length && text[i] !== '\n') i++; continue; }
    const line = text.slice(0, i).split('\n').length;
    if ('()'.includes(text[i])) { tokens.push({v:text[i++], line}); continue; }
    if (text[i] === '"') {
      const start = ++i; let value = '';
      while (i < text.length && text[i] !== '"') { if (text[i] === '\\' && i + 1 < text.length) i++; value += text[i++]; }
      if (i >= text.length) throw new Error('unterminated string'); i++;
      tokens.push({v:value, line}); continue;
    }
    const start = i; while (i < text.length && !/\s|[();]/.test(text[i])) i++;
    if (start !== i) tokens.push({v:text.slice(start, i), line});
  }
  return tokens;
}
function parse(tokens) {
  let p = 0;
  function one() {
    const t = tokens[p++]; if (!t) throw new Error('unexpected EOF');
    if (t.v !== '(') return t;
    const items = []; const line = t.line;
    while (p < tokens.length && tokens[p].v !== ')') items.push(one());
    if (!tokens[p]) throw new Error('unclosed list'); p++;
    return {items, line};
  }
  const all = []; while (p < tokens.length) all.push(one()); return all;
}
function atom(value) { return value && value.v && value.v !== '(' && value.v !== ')'; }
function child(list, name) { return list && list.items ? list.items.find(x => x.items && atom(x.items[0]) && x.items[0].v === name) : undefined; }
function atoms(list) { return (list ? list.items.slice(1) : []).filter(atom).map(x => x.v); }
function targetsIn(duneFile, root) {
  let forms; try { forms = parse(tokenize(fs.readFileSync(duneFile, 'utf8'))); } catch (_) { return []; }
  const known = new Set(['library', 'executable', 'executables', 'test']);
  return forms.filter(x => x.items && atom(x.items[0]) && known.has(x.items[0].v)).map(form => {
    const name = atoms(child(form, 'name'))[0] || null;
    const publicName = atoms(child(form, 'public_name'))[0] || null;
    const foreign = child(form, 'foreign_stubs');
    const language = atoms(child(foreign, 'language'))[0] || null;
    const foreignNames = atoms(child(foreign, 'names'));
    const libraries = atoms(child(form, 'libraries'));
    return {dune_path:rel(root, duneFile), stanza_line:form.line, stanza_kind:form.items[0].v,
      name, public_name:publicName, foreign_stubs:{language, names:foreignNames}, libraries};
  });
}
function readCensus(root) {
  const script = path.resolve(__dirname, '../ffi-boundary-census/census.js');
  const out = cp.execFileSync(process.execPath, [script, root], {encoding:'utf8', maxBuffer:64*1024*1024});
  return JSON.parse(out);
}
function build(root) {
  const census = readCensus(root);
  const targets = walkDune(root).flatMap(file => targetsIn(file, root));
  const targetByDir = new Map();
  for (const target of targets) {
    const dir = path.posix.dirname(target.dune_path);
    const values = targetByDir.get(dir) || []; values.push(target); targetByDir.set(dir, values);
  }
  const records = census.records.map(candidate => {
    const dir = path.posix.dirname(candidate.path);
    const owners = (targetByDir.get(dir) || []).map(target => {
      const base = path.posix.basename(candidate.path).replace(/\.(c|h)$/,'');
      return {...target, ownership: candidate.mechanism === 'camlprim' && target.foreign_stubs.names.includes(base)
        ? 'foreign_stub_source' : 'same_dune_directory'};
    });
    return {candidate, targets:owners, availability:owners.length ? 'ATTRIBUTED' : 'UNATTRIBUTED'};
  });
  const rustDependencies = targets.filter(t => t.libraries.some(x => /(?:rust-deps|rust_deps)/.test(x)))
    .map(t => ({...t, evidence:'target dependency only; not a Rust symbol link'}));
  const summary = {candidates:records.length, attributed:records.filter(r=>r.targets.length).length,
    unattributed:records.filter(r=>!r.targets.length).length, targets:targets.length,
    rust_dependency_targets:rustDependencies.length};
  return {schema_version:1, analysis:'ffi_build_attribution', root:path.resolve(root),
    scope:'Dune source ownership and target dependencies only; no ABI or symbol link inferred',
    census_record_digest:census.source_digest, summary, records, rust_dependency_targets:rustDependencies};
}
function selfTest() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(),'arch-index-ffi-attr-'));
  try {
    fs.mkdirSync(path.join(root,'lib'),{recursive:true});
    fs.writeFileSync(path.join(root,'lib','dune'),'(library (name demo) (foreign_stubs (language c) (names stub)) (libraries octez-rust-deps))\n');
    fs.writeFileSync(path.join(root,'lib','stub.c'),'CAMLprim value stub(value x) { return x; }\n');
    fs.writeFileSync(path.join(root,'lib','api.ml'),'external run : unit -> unit = "stub"\n');
    const result = build(root);
    if (result.summary.candidates !== 2 || result.summary.attributed !== 2 || result.rust_dependency_targets.length !== 1) throw new Error(JSON.stringify(result.summary));
    const c = result.records.find(x=>x.candidate.mechanism==='camlprim');
    if (c.targets[0].ownership !== 'foreign_stub_source') throw new Error('lost C source ownership');
    process.stdout.write('CHECK2_PASS: Dune ownership does not become a symbol link\n');
  } finally { fs.rmSync(root,{recursive:true,force:true}); }
}
const args=process.argv.slice(2);
if (args.length===1 && args[0]==='--self-test') selfTest();
else if (args.length===1 && !args[0].startsWith('-')) { const root=path.resolve(args[0]); if (!fs.existsSync(root)||!fs.statSync(root).isDirectory()) fail(`root is not a readable directory: ${root}`); const out=build(root); out.record_digest=digest(out.records); process.stdout.write(JSON.stringify(out,null,2)+'\n'); }
else fail('usage: attribution.js <corpus-root> | --self-test');
