#!/usr/bin/env node
'use strict';
const cp=require('child_process'),crypto=require('crypto'),path=require('path');
const root=process.argv[2]||'/home/mathias/dev/tezos/tezos';
function read(file){const r=cp.spawnSync(process.execPath,[path.join(__dirname,file),root],{encoding:'utf8',maxBuffer:64*1024*1024});if(r.status)return {status:'NOT_ANALYSED',reason:'sidecar_unavailable'};try{return {status:'ANALYSED',value:JSON.parse(r.stdout)}}catch(_){return {status:'NOT_ANALYSED',reason:'invalid_sidecar_output'}}}
const census=read('../ffi-boundary-census/census.js'),build=read('../ffi-build-attribution/attribution.js'),ocaml=read('../ffi-ocaml-c-resolution/resolution.js'),rust=read('../ffi-c-rust-callbacks/c-rust.js');
const x={schema_version:1,analysis:'ffi_integration_qualification',root:path.resolve(root),scope:'read-only FFI evidence report; no SQLite write, graph edge, reachability change or MUST claim',components:{census,build,ocaml_c:ocaml,rust_archive:rust}};
const v=k=>x.components[k].value; x.summary={ocaml_c_strict:v('ocaml_c')?.summary.resolved_strict||0,rust_archive_endpoints:v('rust_archive')?.summary.endpoints||0,callback_frontiers:v('rust_archive')?.summary.callbacks||0,retained_ffi_frontiers:(v('ocaml_c')?.summary.may_top||0)+(v('rust_archive')?.endpoints.filter(e=>e.availability==='MAY_TOP').length||0)};x.report_digest=crypto.createHash('sha256').update(JSON.stringify(x.components)).digest('hex');process.stdout.write(JSON.stringify(x,null,2)+'\n');
