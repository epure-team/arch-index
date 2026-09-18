#!/usr/bin/env node
'use strict';
const cp = require('child_process'); const crypto = require('crypto'); const path = require('path');
const root = process.argv[2] || '/home/mathias/dev/tezos/tezos'; const script = path.join(__dirname, 'resolution.js');
function fail(m) { process.stderr.write(`CHECK3_ASSERTION: ${m}\n`); process.exit(1); }
function run(args) { const r=cp.spawnSync(process.execPath,[script,...args],{encoding:'utf8',maxBuffer:64*1024*1024}); if(r.status!==0){process.stderr.write(r.stderr);process.stderr.write('CHECK3_SETUP: resolver launch failed\n');process.exit(2);} return r.stdout; }
if (process.argv[3] === '--test-control=assertion') fail('injected assertion');
if (process.argv[3] === '--test-control=setup') { process.stderr.write('CHECK3_SETUP: injected setup failure\n'); process.exit(2); }
run(['--self-test']); let x; try { x=JSON.parse(run([root])); } catch(e) { process.stderr.write(`CHECK3_SETUP: invalid JSON: ${e.message}\n`); process.exit(2); }
if(x.schema_version!==1||x.analysis!=='ffi_ocaml_c_resolution'||!Array.isArray(x.records)) fail('wrong envelope');
let resolved=0, top=0; for(const row of x.records){if(!row.external||!['RESOLVED_STRICT','MAY_TOP'].includes(row.availability)||!Array.isArray(row.witnesses))fail('bad record'); if(row.availability==='RESOLVED_STRICT'){resolved++;if(row.witnesses.length!==1||row.top_reason!==null)fail('bad strict result');const w=row.witnesses[0];if(w.definition.symbol!==row.external.symbol||w.artefact.symbol!==row.external.symbol||!w.source_mirror.identical)fail('incomplete witness');}else{top++;if(!row.top_reason)fail('top without reason');}}
if(resolved!==x.summary.resolved_strict||top!==x.summary.may_top||resolved+top!==x.summary.externals)fail('summary mismatch');
if(crypto.createHash('sha256').update(JSON.stringify(x.records)).digest('hex')!==x.record_digest)fail('digest mismatch');
process.stdout.write(`CHECK3_PASS: ${resolved} strict OCaml-C bindings, ${top} retained FFI frontiers; no graph edge inferred\n`);
