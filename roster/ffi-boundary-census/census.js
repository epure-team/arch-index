#!/usr/bin/env node
/* Read-only, source-level FFI boundary census.  This intentionally reports
 * declarations and exports only: it does not claim that equal symbol spellings
 * are linked together. */
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');

const SKIP_DIRS = new Set([
  '.git', '_build', 'node_modules', 'target', 'vendor', 'vendors', 'worktrees',
  'generated', 'gen', 'dist', 'build', '_opam', '.opam-switch',
]);

function fail(message) { process.stderr.write(`ffi-census: ${message}\n`); process.exit(2); }
function sha(value) { return crypto.createHash('sha256').update(value).digest('hex'); }
function lineAt(text, offset) { return text.slice(0, offset).split('\n').length; }
function posixRelative(root, file) { return path.relative(root, file).split(path.sep).join('/'); }

function walk(root) {
  const files = [];
  function visit(dir) {
    for (const entry of fs.readdirSync(dir, {withFileTypes: true})) {
      const full = path.join(dir, entry.name);
      if (entry.isSymbolicLink()) continue;
      if (entry.isDirectory()) {
        if (!SKIP_DIRS.has(entry.name)) visit(full);
      } else if (entry.isFile() && /\.(ml|mli|c|h|rs)$/.test(entry.name)) files.push(full);
    }
  }
  visit(root);
  return files.sort();
}

function record(records, root, mechanism, file, line, symbol, detail = {}) {
  records.push({mechanism, path: posixRelative(root, file), line, symbol, ...detail});
}

function scanOcaml(records, root, file, text) {
  const re = /^\s*external\s+([A-Za-z_][A-Za-z0-9_']*|\([^\n]*\))\s*:[\s\S]*?=\s*((?:"(?:[^"\\]|\\.)*"\s*)+)/gm;
  for (const match of text.matchAll(re)) {
    const symbols = [...match[2].matchAll(/"((?:[^"\\]|\\.)*)"/g)].map(m => m[1]);
    const nonPrimitive = symbols.filter(symbol => symbol !== '' && !symbol.startsWith('%'));
    if (nonPrimitive.length === 0) continue;
    for (const symbol of nonPrimitive)
      record(records, root, 'ocaml_external', file, lineAt(text, match.index), symbol,
        {ocaml_name: match[1], primitive_variants: nonPrimitive});
  }
}

function scanC(records, root, file, text) {
  for (const match of text.matchAll(/\bCAMLprim\s+(?:CAMLexport\s+)?(?:value|int|void)\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(/g))
    record(records, root, 'camlprim', file, lineAt(text, match.index), match[1]);
  for (const match of text.matchAll(/\bcaml_callback(?:[a-z_0-9]*)?\s*\(/g))
    record(records, root, 'callback', file, lineAt(text, match.index), match[0].replace(/\s*\($/, ''));
  for (const match of text.matchAll(/\bdlsym\s*\(/g))
    record(records, root, 'dynamic_load', file, lineAt(text, match.index), 'dlsym');
}

function scanRust(records, root, file, text) {
  const lines = text.split('\n');
  for (let i = 0; i < lines.length; i++) {
    const exported = /#\[(?:no_mangle|export_name\s*=)/.test(lines[i]);
    const window = lines.slice(Math.max(0, i - 2), Math.min(lines.length, i + 4)).join('\n');
    const fn = window.match(/(?:pub\s+)?(?:unsafe\s+)?extern\s+"C"\s+fn\s+([A-Za-z_][A-Za-z0-9_]*)/);
    if (exported && fn) record(records, root, 'rust_c_abi', file, i + 1, fn[1]);
    if (/\blibloading\b|\bdlsym\s*\(/.test(lines[i]))
      record(records, root, 'dynamic_load', file, i + 1, 'dynamic_load');
  }
}

function census(root) {
  const records = [];
  for (const file of walk(root)) {
    const text = fs.readFileSync(file, 'utf8');
    if (/\.(ml|mli)$/.test(file)) scanOcaml(records, root, file, text);
    else if (/\.(c|h)$/.test(file)) scanC(records, root, file, text);
    else if (file.endsWith('.rs')) scanRust(records, root, file, text);
  }
  records.sort((a, b) =>
    a.mechanism.localeCompare(b.mechanism) || a.path.localeCompare(b.path) ||
    a.line - b.line || a.symbol.localeCompare(b.symbol));
  const counts = Object.fromEntries([...new Set(records.map(r => r.mechanism))]
    .sort().map(mechanism => [mechanism, records.filter(r => r.mechanism === mechanism).length]));
  return {
    schema_version: 1,
    analysis: 'ffi_boundary_census',
    root: path.resolve(root),
    exclusions: [...SKIP_DIRS].sort(),
    scope: 'source declarations and exports only; no linkage inferred',
    files_scanned: walk(root).length,
    summary: {records: records.length, by_mechanism: counts},
    records,
  };
}

function selfTest() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'arch-index-ffi-census-'));
  try {
    fs.mkdirSync(path.join(root, 'nested', 'worktrees'), {recursive: true});
    fs.mkdirSync(path.join(root, '_opam'), {recursive: true});
    fs.writeFileSync(path.join(root, 'a.ml'), 'external run : unit -> unit = "c_run"\nexternal add : int -> int = "%addint"\n');
    fs.writeFileSync(path.join(root, 'stub.c'), 'CAMLprim value c_run(value x) { return x; }\nvoid f(void) { caml_callback(0, 0); dlsym(0, "x"); }\n');
    fs.writeFileSync(path.join(root, 'ffi.rs'), '#[no_mangle]\npub extern "C" fn rust_run() {}\n');
    fs.writeFileSync(path.join(root, 'nested', 'worktrees', 'ignored.ml'), 'external bad : unit -> unit = "bad"\n');
    fs.writeFileSync(path.join(root, '_opam', 'ignored.ml'), 'external bad_switch : unit -> unit = "bad_switch"\n');
    const output = census(root);
    const got = output.records.map(r => `${r.mechanism}:${r.symbol}`).sort();
    const expected = ['callback:caml_callback', 'camlprim:c_run', 'dynamic_load:dlsym', 'ocaml_external:c_run', 'rust_c_abi:rust_run'];
    if (JSON.stringify(got) !== JSON.stringify(expected) || output.files_scanned !== 3) throw new Error(`unexpected census ${JSON.stringify(output)}`);
    process.stdout.write('CHECK1_PASS: census excludes compiler primitives and nested worktrees\n');
  } finally { fs.rmSync(root, {recursive: true, force: true}); }
}

const args = process.argv.slice(2);
if (args.length === 1 && args[0] === '--self-test') selfTest();
else if (args.length === 1 && !args[0].startsWith('-')) {
  const root = path.resolve(args[0]);
  if (!fs.existsSync(root) || !fs.statSync(root).isDirectory()) fail(`root is not a readable directory: ${root}`);
  const output = census(root);
  output.source_digest = sha(JSON.stringify(output.records));
  process.stdout.write(`${JSON.stringify(output, null, 2)}\n`);
} else fail('usage: census.js <corpus-root> | --self-test');
