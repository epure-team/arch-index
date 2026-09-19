#!/usr/bin/env node
'use strict';

/* A strict reader, deliberately separate from the FFI scanners.  Configuration
 * selects a closed proof recipe; it never supplies a regex or creates an edge. */
const crypto = require('crypto');
const fs = require('fs');

const MECHANISMS = new Set([
  'ocaml_c_primitive', 'rust_c_archive_endpoint', 'callback_registration'
]);
const TOP_KEYS = new Set(['schema_version', 'connectors']);
const CONNECTOR_KEYS = new Set([
  'id', 'mechanism', 'version', 'source_roots', 'build_targets', 'artifact_roots', 'enabled'
]);
const ID = /^[a-z0-9][a-z0-9._-]*$/;

class RegistryError extends Error {}
function fail(message) { throw new RegistryError(message); }

/* JSON.parse accepts duplicate object keys (last value wins), which is unsafe
 * for policy inputs. This small parser keeps the JSON grammar and rejects them. */
function parseJsonStrict(text) {
  let i = 0;
  const ws = () => { while (/\s/.test(text[i] || '')) i++; };
  const literal = (s, value) => {
    if (text.slice(i, i + s.length) !== s) fail(`invalid JSON at byte ${i}`);
    i += s.length; return value;
  };
  const string = () => {
    if (text[i++] !== '"') fail(`invalid JSON string at byte ${i - 1}`);
    let out = '';
    while (i < text.length) {
      const c = text[i++];
      if (c === '"') return out;
      if (c === '\\') {
        const e = text[i++];
        const map = { '"':'"', '\\':'\\', '/':'/', b:'\b', f:'\f', n:'\n', r:'\r', t:'\t' };
        if (Object.prototype.hasOwnProperty.call(map, e)) out += map[e];
        else if (e === 'u') {
          const hex = text.slice(i, i + 4);
          if (!/^[0-9a-fA-F]{4}$/.test(hex)) fail(`invalid JSON unicode escape at byte ${i}`);
          out += String.fromCharCode(parseInt(hex, 16)); i += 4;
        } else fail(`invalid JSON escape at byte ${i - 1}`);
      } else {
        if (c < ' ') fail(`unescaped control character at byte ${i - 1}`);
        out += c;
      }
    }
    fail('unterminated JSON string');
  };
  const value = () => {
    ws(); const c = text[i];
    if (c === '"') return string();
    if (c === '{') return object();
    if (c === '[') return array();
    if (c === 't') return literal('true', true);
    if (c === 'f') return literal('false', false);
    if (c === 'n') return literal('null', null);
    const match = text.slice(i).match(/^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?/);
    if (!match) fail(`invalid JSON value at byte ${i}`);
    i += match[0].length; return Number(match[0]);
  };
  const array = () => {
    i++; ws(); const out = [];
    if (text[i] === ']') { i++; return out; }
    for (;;) { out.push(value()); ws(); if (text[i] === ']') { i++; return out; }
      if (text[i++] !== ',') fail(`expected comma at byte ${i - 1}`); }
  };
  const object = () => {
    i++; ws(); const out = {}, keys = new Set();
    if (text[i] === '}') { i++; return out; }
    for (;;) {
      ws(); if (text[i] !== '"') fail(`expected object key at byte ${i}`);
      const key = string(); if (keys.has(key)) fail(`duplicate JSON key ${JSON.stringify(key)}`);
      keys.add(key); ws(); if (text[i++] !== ':') fail(`expected colon at byte ${i - 1}`);
      out[key] = value(); ws(); if (text[i] === '}') { i++; return out; }
      if (text[i++] !== ',') fail(`expected comma at byte ${i - 1}`);
    }
  };
  const result = value(); ws(); if (i !== text.length) fail(`trailing JSON at byte ${i}`); return result;
}

function onlyKeys(value, allowed, where) {
  if (!value || Array.isArray(value) || typeof value !== 'object') fail(`${where} must be an object`);
  for (const key of Object.keys(value)) if (!allowed.has(key)) fail(`${where} has unknown field ${key}`);
}
function safePath(value, where) {
  if (typeof value !== 'string' || !value || value.includes('\0') || value.includes('\\') || value.startsWith('/'))
    fail(`${where} must be a nonempty relative slash path`);
  const bits = value.split('/');
  if (bits.some(x => !x || x === '.' || x === '..')) fail(`${where} escapes or is not normalized`);
  return value;
}
function list(value, where, item) {
  if (!Array.isArray(value) || value.length === 0) fail(`${where} must be a nonempty array`);
  const out = value.map(item), seen = new Set();
  for (const x of out) { if (seen.has(x)) fail(`${where} has duplicate ${JSON.stringify(x)}`); seen.add(x); }
  return out.sort();
}
function buildTarget(value, where) {
  if (typeof value !== 'string' || !value || value.includes('\0') || value.startsWith('/') || value.split('/').includes('..'))
    fail(`${where} must be a bounded relative target`);
  return value;
}
function validateRegistry(value) {
  onlyKeys(value, TOP_KEYS, 'registry');
  if (value.schema_version !== 1) fail('registry schema_version must be 1');
  if (!Array.isArray(value.connectors) || value.connectors.length === 0) fail('registry connectors must be a nonempty array');
  const ids = new Set();
  const connectors = value.connectors.map((raw, index) => {
    const where = `connector[${index}]`; onlyKeys(raw, CONNECTOR_KEYS, where);
    if (typeof raw.id !== 'string' || !ID.test(raw.id)) fail(`${where}.id is invalid`);
    if (ids.has(raw.id)) fail(`duplicate connector id ${raw.id}`); ids.add(raw.id);
    if (!MECHANISMS.has(raw.mechanism)) fail(`${where}.mechanism is unsupported`);
    if (!Number.isSafeInteger(raw.version) || raw.version <= 0) fail(`${where}.version must be a positive integer`);
    if (typeof raw.enabled !== 'boolean') fail(`${where}.enabled must be boolean`);
    return { id: raw.id, mechanism: raw.mechanism, version: raw.version,
      source_roots: list(raw.source_roots, `${where}.source_roots`, x => safePath(x, `${where}.source_roots`)),
      build_targets: list(raw.build_targets, `${where}.build_targets`, x => buildTarget(x, `${where}.build_targets`)),
      artifact_roots: list(raw.artifact_roots, `${where}.artifact_roots`, x => safePath(x, `${where}.artifact_roots`)),
      enabled: raw.enabled };
  }).sort((a, b) => a.id.localeCompare(b.id));
  return {schema_version: 1, connectors};
}
function readRegistry(file) {
  let text; try { text = fs.readFileSync(file, 'utf8'); } catch (_) { fail(`cannot read registry ${file}`); }
  const registry = validateRegistry(parseJsonStrict(text));
  return {registry, digest: crypto.createHash('sha256').update(text).digest('hex')};
}
function cli() {
  const args = process.argv.slice(2);
  if (args.length !== 2 || args[0] !== '--validate') { process.stderr.write('usage: ffi-connector-registry.js --validate REGISTRY.json\n'); process.exit(2); }
  try { const r = readRegistry(args[1]); process.stdout.write(JSON.stringify({schema_version:1,status:'VALID',registry_digest:r.digest,connectors:r.registry.connectors}) + '\n'); }
  catch (e) { process.stderr.write(`ffi-connector-registry: ${e.message}\n`); process.exit(2); }
}
if (require.main === module) cli();
module.exports = {RegistryError, parseJsonStrict, validateRegistry, readRegistry};
