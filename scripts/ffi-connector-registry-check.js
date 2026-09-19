#!/usr/bin/env node
'use strict';
const assert = require('assert');
const {RegistryError, parseJsonStrict, validateRegistry} = require('./ffi-connector-registry.js');
function valid() { return {schema_version:1,connectors:[{id:'tezos-ocaml-c',mechanism:'ocaml_c_primitive',version:1,source_roots:['src/z','src/a'],build_targets:['src/lib:target'],artifact_roots:['_build/default/lib'],enabled:true}]}; }
function rejects(f, text) { assert.throws(f, e => e instanceof RegistryError && e.message.includes(text)); }
const x = validateRegistry(valid());
assert.deepStrictEqual(x.connectors[0].source_roots, ['src/a','src/z']);
rejects(() => parseJsonStrict('{"schema_version":1,"schema_version":1,"connectors":[]}'), 'duplicate JSON key');
rejects(() => validateRegistry({...valid(), extra:true}), 'unknown field');
rejects(() => validateRegistry({schema_version:1,connectors:[...valid().connectors, {...valid().connectors[0]}]}), 'duplicate connector id');
for (const bad of ['../x', '/x', 'a//b', 'a\\b']) { const v=valid(); v.connectors[0].source_roots=[bad]; rejects(() => validateRegistry(v), 'source_roots'); }
{ const v=valid(); v.connectors[0].mechanism='java_jni'; rejects(() => validateRegistry(v), 'unsupported'); }
{ const v=valid(); v.connectors[0].enabled='true'; rejects(() => validateRegistry(v), 'must be boolean'); }
process.stdout.write('FFI_CONNECTOR_REGISTRY_CHECK_PASS: strict envelope, duplicate keys, bounded paths and closed mechanisms\n');
