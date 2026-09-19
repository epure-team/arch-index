#!/usr/bin/env node
'use strict';
const assert=require('assert'); const crypto=require('crypto'); const {assemble}=require('./ffi-connector-sidecars.js');
const registry={schema_version:1,connectors:[
  {id:'ocaml',mechanism:'ocaml_c_primitive',version:1,enabled:true,source_roots:['src'],build_targets:['src/lib:demo'],artifact_roots:['_build/default/src/lib']},
  {id:'callback',mechanism:'callback_registration',version:1,enabled:true,source_roots:['src'],build_targets:['src/lib:demo'],artifact_roots:['_build/default/src/lib']}
]};
const sidecars={ocaml:{records:[{external:{path:'src/api.ml'},availability:'RESOLVED_STRICT',witnesses:[{target:{dune_path:'src/lib/dune',name:'demo'},artefact:{path:'_build/default/src/lib/libdemo_stubs.a'}}]},{external:{path:'other/api.ml'},witnesses:[]}]},rust:{endpoints:[]}};
const x=assemble(registry,'a'.repeat(64),sidecars); assert.equal(x.connectors[0].records.length,1); assert.equal(x.connectors[0].records[0].availability,'RESOLVED_STRICT'); assert.equal(x.connectors[1].status,'FRONTIER'); assert.equal(x.record_digest,crypto.createHash('sha256').update(JSON.stringify(x.connectors)).digest('hex')); process.stdout.write('FFI_CONNECTOR_SIDECARS_CHECK_PASS: explicit registry scopes sidecars and callbacks remain frontier\n');
